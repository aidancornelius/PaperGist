// BackgroundTaskManager.swift
// PaperGist
//
// Manages background task scheduling and execution using BGTaskScheduler.
// Handles periodic background processing of unsummarised items when the app
// is not active.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import BackgroundTasks
import SwiftData
import OSLog

/// Manages background task scheduling and execution using BGTaskScheduler
final class BackgroundTaskManager: @unchecked Sendable {
    static let shared = BackgroundTaskManager()

    // Task identifier must match Info.plist entry
    private let taskIdentifier = "com.cornelius-bell.PaperGist.summarize"

    // Minimum interval between background refreshes (15 minutes)
    private let minimumBackgroundInterval: TimeInterval = 15 * 60

    private init() {}

    // MARK: - Registration

    /// Registers background task handlers with BGTaskScheduler
    ///
    /// Must be called early in app launch (from AppDelegate) before the app
    /// finishes launching to ensure the system can deliver background tasks.
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self else { return }

            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            // BGAppRefreshTask isn't Sendable but we need to use it in an async context.
            // Safe to capture since we use it synchronously before any races can occur.
            nonisolated(unsafe) let task = refreshTask
            Task { @Sendable in
                await self.handleBackgroundTask(task)
            }
        }
    }

    // MARK: - Scheduling

    /// Schedules the next background refresh task
    ///
    /// Only schedules if the user has enabled background sync in settings.
    /// The system will run the task at its discretion, but no earlier than
    /// 15 minutes from now.
    func scheduleBackgroundTask() async {
        let backgroundSyncEnabled = await MainActor.run {
            AppSettings.shared.backgroundSyncEnabled
        }

        guard backgroundSyncEnabled else {
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumBackgroundInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.general.error("Failed to schedule background task: \(error.localizedDescription)")
        }
    }

    /// Cancels all scheduled background tasks
    func cancelScheduledTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    // MARK: - Task Execution

    /// Handles execution of a background refresh task
    /// - Parameter task: The BGAppRefreshTask to handle
    private func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        // Schedule the next background task immediately
        await scheduleBackgroundTask()

        // Set up expiration handler
        var isTaskExpired = false
        task.expirationHandler = {
            isTaskExpired = true
        }

        do {
            // Get model container
            guard let modelContainer = try? ModelContainer(
                for: ZoteroItem.self, ProcessedItem.self, SummaryJob.self, ItemSummaryJob.self
            ) else {
                AppLogger.general.error("Failed to create model container for background task")
                task.setTaskCompleted(success: false)
                return
            }

            // Create all services and job manager on MainActor to avoid data race warnings
            let (jobManager, itemKeysToProcess) = await MainActor.run {
                let modelContext = ModelContext(modelContainer)
                let oauthService = ZoteroOAuthService()
                let zoteroService = ZoteroService(oauthService: oauthService)
                let summarisationService = SummarisationService(
                    zoteroService: zoteroService,
                    modelContext: modelContext
                )
                let jobManager = JobManager(
                    modelContext: modelContext,
                    summarisationService: summarisationService,
                    liveActivityManager: LiveActivityManager.shared
                )

                // Fetch item keys that need summarisation
                let descriptor = FetchDescriptor<ZoteroItem>(
                    predicate: #Predicate { item in
                        !item.hasSummary && item.hasAttachment
                    },
                    sortBy: [SortDescriptor(\.lastChecked, order: .forward)]
                )

                let itemKeys: [String]
                do {
                    let items = try modelContext.fetch(descriptor)
                    itemKeys = items.map { $0.key }
                } catch {
                    AppLogger.general.warning("Failed to fetch unsummarised items: \(error.localizedDescription)")
                    itemKeys = []
                }

                return (jobManager, itemKeys)
            }

            guard !itemKeysToProcess.isEmpty else {
                task.setTaskCompleted(success: true)
                return
            }

            // Check if task expired before starting
            guard !isTaskExpired else {
                task.setTaskCompleted(success: false)
                return
            }

            // Limit batch size for background processing
            let batchSize = await MainActor.run {
                min(AppSettings.shared.batchSize, 5) // Max 5 items in background
            }
            let itemKeysToProcessNow = Array(itemKeysToProcess.prefix(batchSize))

            // Start batch job (returns job ID)
            let jobId = try await jobManager.startBatchJob(itemKeys: itemKeysToProcessNow)

            // Monitor job completion with timeout
            let success = await monitorJobCompletion(
                jobId: jobId,
                modelContainer: modelContainer,
                isExpired: { isTaskExpired }
            )

            task.setTaskCompleted(success: success)

        } catch {
            AppLogger.general.error("Background task failed: \(error.localizedDescription)")
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Private Helpers

    /// Monitors a job until completion or timeout
    /// - Parameters:
    ///   - jobId: The UUID of the SummaryJob to monitor
    ///   - modelContainer: The ModelContainer for creating contexts
    ///   - isExpired: Closure that returns true if task has expired
    /// - Returns: True if job completed successfully, false otherwise
    private func monitorJobCompletion(
        jobId: UUID,
        modelContainer: ModelContainer,
        isExpired: () -> Bool
    ) async -> Bool {

        let maxWaitTime: TimeInterval = 25 * 60 // 25 minutes max (leave 5 min buffer)
        let checkInterval: TimeInterval = 5 // Check every 5 seconds
        let startTime = Date()

        while true {
            // Check if expired
            if isExpired() {
                return false
            }

            // Check timeout
            if Date().timeIntervalSince(startTime) > maxWaitTime {
                return false
            }

            // Fetch current job status
            // Create fresh context for each check to avoid isolation issues
            let status: JobStatus = await MainActor.run {
                let context = ModelContext(modelContainer)
                let descriptor = FetchDescriptor<SummaryJob>(
                    predicate: #Predicate { j in
                        j.id == jobId
                    }
                )

                guard let currentJob = try? context.fetch(descriptor).first else {
                    return .failed
                }

                return currentJob.status
            }

            // Check if job finished
            switch status {
            case .completed:
                return true
            case .failed, .cancelled:
                return false
            case .queued, .processing, .paused:
                // Still running, wait and check again
                try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            }
        }
    }

    // MARK: - Testing Support

    /// Simulates a background task launch for testing
    /// This can be triggered from the debugger console:
    /// e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.cornelius-bell.PaperGist.summarize"]
    func simulateBackgroundTask() async {
        await scheduleBackgroundTask()
    }
}
