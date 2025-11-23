// LiveActivityManager.swift
// PaperGist
//
// Manages Live Activities for batch job progress tracking. Handles the complete
// lifecycle of Live Activities including creation, updates, and dismissal.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@preconcurrency import ActivityKit
import SwiftData
import OSLog

/// Manages Live Activities for batch job progress tracking
@MainActor
final class LiveActivityManager {
    // MARK: - Properties

    private var activeActivities: [UUID: Activity<SummaryJobActivityAttributes>] = [:]
    static let shared = LiveActivityManager()

    // MARK: - Initialisation

    nonisolated private init() {
    }

    // MARK: - Public API

    /// Starts a Live Activity for a batch job
    /// - Parameter job: The SummaryJob to create an activity for
    /// - Returns: The created Activity instance, or nil if creation failed
    /// - Throws: ActivityKit errors if the activity cannot be started
    func startActivity(for job: SummaryJob) async throws -> Activity<SummaryJobActivityAttributes>? {
        AppLogger.jobs.info("startActivity called for job \(job.id)")

        // Check if Live Activities are supported
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            AppLogger.jobs.warning("Live Activities are not enabled in system settings")
            return nil
        }

        AppLogger.jobs.info("Live Activities are enabled")

        // Check if activity already exists for this job and is still active
        if let existing = activeActivities[job.id] {
            AppLogger.jobs.info("Found existing activity for job \(job.id), checking state...")
            // Verify the activity is still active (not ended or dismissed)
            if existing.activityState == .active {
                AppLogger.jobs.info("Activity already exists and is active for job \(job.id), returning existing")
                return existing
            } else {
                // Activity is stale (ended/dismissed), remove it and create a new one
                AppLogger.jobs.info("Existing activity for job \(job.id) is no longer active, removing and creating new one")
                activeActivities.removeValue(forKey: job.id)
            }
        } else {
            AppLogger.jobs.info("No existing activity found for job \(job.id)")
        }

        // Create initial state
        let initialState = SummaryJobActivityAttributes.ContentState(
            totalItems: job.totalItems,
            processedItems: job.processedItems,
            failedItems: job.failedItemKeys.count,
            currentItemTitle: job.progressMessage ?? "Starting...",
            status: job.status.rawValue,
            progressMessage: job.progressMessage
        )

        // Create attributes
        let attributes = SummaryJobActivityAttributes(
            jobID: job.id.uuidString,
            jobName: "Batch summarisation"
        )

        do {
            AppLogger.jobs.info("Requesting new Live Activity from system...")
            // Request the activity
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )

            AppLogger.jobs.info("Live Activity created successfully, ID: \(activity.id)")

            // Store reference
            activeActivities[job.id] = activity

            return activity

        } catch {
            AppLogger.jobs.error("Failed to start Live Activity: \(error.localizedDescription)")
            throw error
        }
    }

    /// Updates the Live Activity for a job with current progress
    /// - Parameter job: The SummaryJob to update
    func updateActivity(for job: SummaryJob) async {
        guard let activity = activeActivities[job.id] else {
            AppLogger.jobs.warning("No active activity found for job \(job.id)")
            return
        }

        // Check if activity is still active
        guard activity.activityState == .active else {
            AppLogger.jobs.warning("Activity for job \(job.id) is no longer active, cannot update")
            activeActivities.removeValue(forKey: job.id)
            return
        }

        // Create updated state
        let updatedState = SummaryJobActivityAttributes.ContentState(
            totalItems: job.totalItems,
            processedItems: job.processedItems,
            failedItems: job.failedItemKeys.count,
            currentItemTitle: job.progressMessage ?? "Processing...",
            status: job.status.rawValue,
            progressMessage: job.progressMessage
        )

        // Update the activity
        await activity.update(
            .init(
                state: updatedState,
                staleDate: nil
            )
        )
    }

    /// Ends the Live Activity for a completed/failed/cancelled job
    /// - Parameters:
    ///   - job: The SummaryJob to end the activity for
    ///   - dismissalPolicy: When to dismiss the activity (default: after 4 hours)
    func endActivity(for job: SummaryJob, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        AppLogger.jobs.info("endActivity called for job \(job.id), dismissalPolicy: \(dismissalPolicy == .immediate ? "immediate" : "default")")

        guard let activity = activeActivities[job.id] else {
            AppLogger.jobs.warning("No active activity found for job \(job.id)")
            return
        }

        // Create final state based on job status
        let finalState: SummaryJobActivityAttributes.ContentState

        switch job.status {
        case .completed:
            finalState = .completed(
                totalItems: job.totalItems,
                successfulItems: job.successfulItems,
                failedItems: job.failedItemKeys.count
            )

        case .failed:
            finalState = .failed(
                totalItems: job.totalItems,
                processedItems: job.processedItems,
                failedItems: job.failedItemKeys.count,
                error: job.errorMessage ?? "Job failed"
            )

        case .cancelled:
            finalState = .cancelled(
                totalItems: job.totalItems,
                processedItems: job.processedItems,
                failedItems: job.failedItemKeys.count
            )

        default:
            // For other states, just use current state
            finalState = SummaryJobActivityAttributes.ContentState(
                totalItems: job.totalItems,
                processedItems: job.processedItems,
                failedItems: job.failedItemKeys.count,
                currentItemTitle: job.progressMessage ?? "Finished",
                status: job.status.rawValue,
                progressMessage: job.progressMessage
            )
        }

        // End the activity with final state
        await activity.end(
            .init(state: finalState, staleDate: nil),
            dismissalPolicy: dismissalPolicy
        )

        AppLogger.jobs.info("Live Activity ended for job \(job.id)")

        // Remove from tracking after ending completes
        activeActivities.removeValue(forKey: job.id)
    }

    /// Ends all active Live Activities
    /// Useful for cleanup or when the app is terminating
    func endAllActivities() async {
        for (_, activity) in activeActivities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        activeActivities.removeAll()
    }

    /// Checks if an activity is currently active for a job
    /// - Parameter jobID: The job UUID to check
    /// - Returns: True if an activity exists for this job
    func hasActiveActivity(for jobID: UUID) -> Bool {
        return activeActivities[jobID] != nil
    }

    /// Gets the current activity for a job
    /// - Parameter jobID: The job UUID
    /// - Returns: The Activity instance if one exists
    func getActivity(for jobID: UUID) -> Activity<SummaryJobActivityAttributes>? {
        return activeActivities[jobID]
    }

    /// Cleans up finished activities
    /// Useful to remove references to activities that have already ended
    func cleanupFinishedActivities() {
        let finishedJobIDs = activeActivities.filter { _, activity in
            activity.activityState == .ended || activity.activityState == .dismissed
        }.map { $0.key }

        for jobID in finishedJobIDs {
            activeActivities.removeValue(forKey: jobID)
        }
    }
}

// MARK: - Helper Methods

extension LiveActivityManager {
    /// Creates a content state from a SummaryJob
    /// - Parameter job: The job to create state from
    /// - Returns: ContentState representing the job's current state
    private func createContentState(from job: SummaryJob) -> SummaryJobActivityAttributes.ContentState {
        return SummaryJobActivityAttributes.ContentState(
            totalItems: job.totalItems,
            processedItems: job.processedItems,
            failedItems: job.failedItemKeys.count,
            currentItemTitle: job.progressMessage ?? "Processing...",
            status: job.status.rawValue,
            progressMessage: job.progressMessage
        )
    }
}

// MARK: - Error Handling

extension LiveActivityManager {
    /// Handles errors that occur during Live Activity operations
    /// - Parameter error: The error that occurred
    private func handleError(_ error: Error) {
        AppLogger.jobs.error("LiveActivityManager error: \(error.localizedDescription)")

        // Log specific ActivityKit errors
        if let activityError = error as? ActivityKit.ActivityAuthorizationError {
            AppLogger.jobs.error("Authorization error: \(String(describing: activityError))")
        }
    }
}
