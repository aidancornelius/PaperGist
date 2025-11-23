// JobManager.swift
// PaperGist
//
// Manages batch processing of multiple summarisation jobs. Handles job lifecycle,
// progress tracking, pause/resume functionality, and error recovery.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftData
import OSLog

// MARK: - Job Manager Errors

enum JobManagerError: LocalizedError {
    case jobNotFound
    case jobAlreadyRunning
    case jobCancelled
    case invalidJobState

    var errorDescription: String? {
        switch self {
        case .jobNotFound:
            return "Job not found"
        case .jobAlreadyRunning:
            return "Job is already running"
        case .jobCancelled:
            return "Job was cancelled"
        case .invalidJobState:
            return "Job is in an invalid state for this operation"
        }
    }
}

// MARK: - Task Storage Actor

/// Thread-safe storage for tracking active background tasks by job ID
private actor TaskStorage {
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    func setTask(_ task: Task<Void, Never>, for id: UUID) {
        activeTasks[id] = task
    }

    func getTask(for id: UUID) -> Task<Void, Never>? {
        return activeTasks[id]
    }

    func removeTask(for id: UUID) {
        activeTasks.removeValue(forKey: id)
    }

    func hasTask(for id: UUID) -> Bool {
        return activeTasks[id] != nil
    }

    func getAllTaskIDs() -> [UUID] {
        return Array(activeTasks.keys)
    }
}

// MARK: - Job Manager

/// Manages batch processing of multiple items
///
/// Coordinates the execution of summarisation jobs, handling progress updates,
/// Live Activity integration, and error recovery. Jobs can be paused, resumed,
/// and retried. This class is NOT @MainActor and runs background tasks off the
/// main thread.
final class JobManager: @unchecked Sendable {
    private let modelContext: ModelContext
    private let summarisationService: SummarisationService
    private let liveActivityManager: LiveActivityManager
    private let taskStorage = TaskStorage()

    var onJobCompleted: (@MainActor () -> Void)?

    init(modelContext: ModelContext, summarisationService: SummarisationService, liveActivityManager: LiveActivityManager) {
        self.modelContext = modelContext
        self.summarisationService = summarisationService
        self.liveActivityManager = liveActivityManager
    }

    // MARK: - Public API

    /// Starts a new batch job to process multiple items
    /// - Parameter items: Array of ZoteroItems to process
    /// - Returns: The job ID (UUID)
    /// - Note: Processes items sequentially with error handling
    @MainActor
    func startBatchJob(items: [ZoteroItem]) async throws -> UUID {
        // Extract item keys for cross-isolation boundary
        let itemKeys = items.map { $0.key }

        // Create job record on main actor
        let job = createJob(itemKeys: itemKeys, totalCount: items.count)
        let jobID = job.id

        // Start background processing task
        let task = Task.detached { [weak self] in
            guard let self = self else { return }
            await self.processJob(jobID: jobID, itemKeys: itemKeys)
        }

        // Track the task
        await taskStorage.setTask(task, for: jobID)

        return jobID
    }

    /// Starts a new batch job to process multiple items by their keys
    /// - Parameters:
    ///   - itemKeys: Array of item keys to process
    /// - Returns: The job ID (UUID)
    /// - Note: Processes items sequentially with error handling
    @MainActor
    func startBatchJob(itemKeys: [String]) async throws -> UUID {
        // Create job record on main actor
        let job = createJob(itemKeys: itemKeys, totalCount: itemKeys.count)
        let jobID = job.id

        // Start background processing task
        let task = Task.detached { [weak self] in
            guard let self = self else { return }
            await self.processJob(jobID: jobID, itemKeys: itemKeys)
        }

        // Track the task
        await taskStorage.setTask(task, for: jobID)

        return jobID
    }

    /// Pauses a running job
    /// - Parameter job: The job to pause
    /// - Parameter sendNotification: Whether to send a notification (default true)
    @MainActor
    func pauseJob(_ job: SummaryJob, sendNotification: Bool = true) async {
        // Only pause if currently processing
        guard job.status == .processing else { return }

        let processedCount = job.processedItems
        let totalCount = job.totalItems

        job.status = .paused
        job.progressMessage = "Job paused"
        try? modelContext.save()

        // Cancel the active task
        if let task = await taskStorage.getTask(for: job.id) {
            task.cancel()
            await taskStorage.removeTask(for: job.id)
        }

        // End Live Activity when paused - use immediate dismissal so it can be recreated on resume
        await liveActivityManager.endActivity(for: job, dismissalPolicy: .immediate)

        // Send notification if requested
        if sendNotification {
            Task {
                await NotificationManager.shared.sendBatchPausedNotification(
                    processedCount: processedCount,
                    totalCount: totalCount
                )
            }
        }
    }

    /// Resumes a paused or interrupted job
    /// - Parameter job: The job to resume
    /// - Parameter allowProcessing: Allow resuming jobs in .processing state (for restoration after app restart)
    @MainActor
    func resumeJob(_ job: SummaryJob, allowProcessing: Bool = false) async throws {
        // Validate job can be resumed
        guard job.canResume || (allowProcessing && job.status == .processing) else {
            throw JobManagerError.invalidJobState
        }

        // Check if job is already running
        let isRunning = await taskStorage.hasTask(for: job.id)

        guard !isRunning else {
            throw JobManagerError.jobAlreadyRunning
        }

        // Get items to resume from
        let itemKeys = job.itemKeys
        let startIndex = job.currentBatchIndex
        let jobID = job.id

        // Update job status
        job.status = .processing
        job.progressMessage = "Resuming job..."
        try? modelContext.save()

        AppLogger.jobs.info("Attempting to restart Live Activity for resumed job \(job.id)")

        // Restart Live Activity immediately and await it
        do {
            let activity = try await liveActivityManager.startActivity(for: job)
            if activity != nil {
                AppLogger.jobs.info("Live Activity successfully restarted for resumed job \(job.id)")
            } else {
                AppLogger.jobs.warning("Live Activity could not be restarted (might be disabled in system settings)")
            }
        } catch {
            AppLogger.jobs.error("Failed to restart Live Activity on resume: \(error.localizedDescription)")
        }

        // Start processing from where we left off
        let task = Task.detached { [weak self] in
            guard let self = self else { return }
            await self.processJob(jobID: jobID, itemKeys: itemKeys, startIndex: startIndex)
        }

        // Track the task
        await taskStorage.setTask(task, for: jobID)
    }

    /// Cancels a running job
    /// - Parameter job: The job to cancel
    @MainActor
    func cancelJob(_ job: SummaryJob) async {
        let processedCount = job.processedItems
        let totalCount = job.totalItems

        job.status = .cancelled
        job.progressMessage = "Job cancelled"
        job.completedAt = Date()
        try? modelContext.save()

        // Cancel the active task
        if let task = await taskStorage.getTask(for: job.id) {
            task.cancel()
            await taskStorage.removeTask(for: job.id)
        }

        // End Live Activity
        await liveActivityManager.endActivity(for: job)

        // Send notification
        Task {
            await NotificationManager.shared.sendBatchCancellationNotification(
                processedCount: processedCount,
                totalCount: totalCount
            )
        }
    }

    /// Retries processing failed items from a job
    /// - Parameter job: The job with failed items to retry
    @MainActor
    func retryFailedItems(_ job: SummaryJob) async throws {
        // Get failed keys
        let failedKeys = job.failedItemKeys
        guard !failedKeys.isEmpty else {
            AppLogger.jobs.warning("No failed items to retry for job \(job.id)")
            return
        }

        // Check if job is already running
        let isRunning = await taskStorage.hasTask(for: job.id)
        guard !isRunning else {
            throw JobManagerError.jobAlreadyRunning
        }

        // Store the current processed count (we'll build on top of successful items)
        let previousSuccessfulCount = job.successfulItems
        let jobID = job.id

        // Reset job state for retry
        job.failedItemKeys.removeAll()
        job.status = .processing
        job.totalItems = previousSuccessfulCount + failedKeys.count
        job.currentBatchIndex = previousSuccessfulCount
        job.progressMessage = "Retrying failed items..."
        job.completedAt = nil
        job.errorMessage = nil
        try? modelContext.save()

        // Restart Live Activity immediately and await it
        do {
            let activity = try await liveActivityManager.startActivity(for: job)
            if activity != nil {
                AppLogger.jobs.info("Live Activity restarted for retry job \(job.id)")
            } else {
                AppLogger.jobs.warning("Live Activity could not be restarted (might be disabled)")
            }
        } catch {
            AppLogger.jobs.error("Failed to restart Live Activity on retry: \(error.localizedDescription)")
        }

        // Start processing failed items
        // IMPORTANT: Pass startIndex: 0 because we're passing a filtered list of only failed keys
        let task = Task.detached { [weak self] in
            guard let self = self else { return }
            await self.processJob(jobID: jobID, itemKeys: failedKeys, startIndex: 0)
        }

        // Track the task
        await taskStorage.setTask(task, for: jobID)
    }

    // MARK: - Private Helpers

    /// Creates a new job record on the main actor
    @MainActor
    private func createJob(itemKeys: [String], totalCount: Int) -> SummaryJob {
        let job = SummaryJob(
            status: .processing,
            totalItems: totalCount,
            itemKeys: itemKeys,
            progressMessage: "Starting batch job..."
        )

        modelContext.insert(job)
        try? modelContext.save()

        // Start Live Activity immediately
        Task {
            do {
                let activity = try await liveActivityManager.startActivity(for: job)
                if activity != nil {
                    AppLogger.jobs.info("Live Activity started for job \(job.id)")
                } else {
                    AppLogger.jobs.warning("Live Activity could not be started (might be disabled)")
                }
            } catch {
                AppLogger.jobs.error("Failed to start Live Activity: \(error.localizedDescription)")
            }
        }

        return job
    }

    /// Main processing loop for a job
    private func processJob(jobID: UUID, itemKeys: [String], startIndex: Int = 0) async {
        // Get remaining keys to process
        let keysToProcess = Array(itemKeys.dropFirst(startIndex))

        for (index, itemKey) in keysToProcess.enumerated() {
            // Check if task was cancelled
            if Task.isCancelled {
                await handleJobCancellation(jobID: jobID)
                return
            }

            // Check if job was paused - fetch job to check status
            let status = await MainActor.run {
                let descriptor = FetchDescriptor<SummaryJob>(
                    predicate: #Predicate { $0.id == jobID }
                )
                guard let job = try? modelContext.fetch(descriptor).first else { return JobStatus.cancelled }
                return job.status
            }

            if status == .paused || status == .cancelled {
                return
            }

            // Calculate actual index in full array
            let actualIndex = startIndex + index

            // Fetch item metadata and update job on MainActor
            let (itemTitle, totalItems) = await MainActor.run {
                // Fetch job
                let jobDescriptor = FetchDescriptor<SummaryJob>(
                    predicate: #Predicate { $0.id == jobID }
                )
                guard let job = try? modelContext.fetch(jobDescriptor).first else {
                    return ("Unknown", 0)
                }

                // Fetch item
                let itemDescriptor = FetchDescriptor<ZoteroItem>(
                    predicate: #Predicate { item in
                        item.key == itemKey
                    }
                )

                guard let item = try? modelContext.fetch(itemDescriptor).first else {
                    return ("Unknown", job.totalItems)
                }

                // Update current position
                updateJobProgress(
                    job,
                    currentIndex: actualIndex,
                    message: "Processing \(item.title)"
                )

                return (item.title, job.totalItems)
            }

            // Process the item (this will re-fetch it on MainActor inside summariseItem)
            do {
                _ = try await processItemByKey(itemKey)

                // Update progress after successful processing
                await incrementProcessedItems(jobID: jobID)
            } catch {
                // Handle individual item failure
                await handleItemFailure(jobID: jobID, itemKey: itemKey, error: error)

                AppLogger.jobs.error("Failed to process item '\(itemTitle)': \(error.localizedDescription)")
            }

            // Save job state regularly for recovery
            await saveJobState(jobID: jobID)
        }

        // All items processed - finalize job
        await finalizeJob(jobID: jobID)
    }

    /// Updates job progress on main actor
    @MainActor
    private func updateJobProgress(_ job: SummaryJob, currentIndex: Int, message: String) {
        job.currentBatchIndex = currentIndex
        job.progressMessage = message
        job.progress = job.calculatedProgress
        try? modelContext.save()

        // Update Live Activity
        Task {
            await liveActivityManager.updateActivity(for: job)
        }
    }

    /// Increments processed items counter on main actor
    @MainActor
    private func incrementProcessedItems(jobID: UUID) {
        let descriptor = FetchDescriptor<SummaryJob>(
            predicate: #Predicate { $0.id == jobID }
        )
        guard let job = try? modelContext.fetch(descriptor).first else { return }

        job.processedItems += 1
        job.progress = job.calculatedProgress
        try? modelContext.save()

        // Update Live Activity
        Task {
            await liveActivityManager.updateActivity(for: job)
        }
    }

    /// Handles item failure by recording the failed key
    @MainActor
    private func handleItemFailure(jobID: UUID, itemKey: String, error: Error) {
        let descriptor = FetchDescriptor<SummaryJob>(
            predicate: #Predicate { $0.id == jobID }
        )
        guard let job = try? modelContext.fetch(descriptor).first else { return }

        job.failedItemKeys.append(itemKey)
        job.processedItems += 1 // Still count as processed
        job.progress = job.calculatedProgress
        job.progressMessage = "Failed: \(error.localizedDescription)"
        try? modelContext.save()

        // Update Live Activity
        Task {
            await liveActivityManager.updateActivity(for: job)
        }
    }

    /// Saves job state for potential recovery
    @MainActor
    private func saveJobState(jobID: UUID) {
        try? modelContext.save()
    }

    /// Handles job cancellation
    @MainActor
    private func handleJobCancellation(jobID: UUID) {
        let descriptor = FetchDescriptor<SummaryJob>(
            predicate: #Predicate { $0.id == jobID }
        )
        guard let job = try? modelContext.fetch(descriptor).first else { return }
        guard job.status != .cancelled else { return }

        job.status = .cancelled
        job.progressMessage = "Job cancelled by user"
        job.completedAt = Date()
        try? modelContext.save()
    }

    /// Finalizes job after processing all items
    @MainActor
    private func finalizeJob(jobID: UUID) {
        let descriptor = FetchDescriptor<SummaryJob>(
            predicate: #Predicate { $0.id == jobID }
        )
        guard let job = try? modelContext.fetch(descriptor).first else { return }

        // Remove from active tasks
        Task {
            await taskStorage.removeTask(for: jobID)
        }

        let successCount = job.successfulItems
        let failCount = job.failedItemKeys.count
        let totalCount = job.totalItems

        // Determine final status
        if job.failedItemKeys.isEmpty {
            // All succeeded
            job.status = .completed
            job.progressMessage = "All items processed successfully"
        } else if job.failedItemKeys.count == job.totalItems {
            // All failed
            job.status = .failed
            job.progressMessage = "All items failed to process"
            job.errorMessage = "All \(job.totalItems) items failed"
        } else {
            // Partial success
            job.status = .completed
            job.progressMessage = "Completed with \(successCount) succeeded, \(failCount) failed"
        }

        job.completedAt = Date()
        job.progress = 1.0
        try? modelContext.save()

        // End Live Activity
        Task {
            await liveActivityManager.endActivity(for: job)
        }

        // Send notification
        Task {
            if job.status == .completed {
                await NotificationManager.shared.sendBatchCompletionNotification(
                    successCount: successCount,
                    totalCount: totalCount,
                    failedCount: failCount
                )
            } else if job.status == .failed {
                await NotificationManager.shared.sendBatchFailureNotification(
                    errorMessage: job.errorMessage ?? "Unknown error occurred"
                )
            }
        }

        // Update widgets after job completion
        let widgetService = WidgetUpdateService(modelContext: modelContext)
        widgetService.updateWidgets()

        // Notify observers that job completed (e.g., to update counts)
        if let callback = onJobCompleted {
            Task { @MainActor in
                callback()
            }
        }
    }

    /// Processes an item by its key - fetches and summarises it
    @MainActor
    private func processItemByKey(_ itemKey: String) async throws {
        let descriptor = FetchDescriptor<ZoteroItem>(
            predicate: #Predicate { item in
                item.key == itemKey
            }
        )

        guard let item = try? modelContext.fetch(descriptor).first else {
            throw JobManagerError.jobNotFound
        }

        try await summarisationService.summariseItem(item)
    }

    // MARK: - Job Restoration

    /// Finds incomplete jobs that were interrupted (e.g., by app termination)
    /// Returns jobs with status .processing or .queued that don't have active tasks
    @MainActor
    func findIncompleteJobs() -> [SummaryJob] {
        let descriptor = FetchDescriptor<SummaryJob>(
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )

        guard let allJobs = try? modelContext.fetch(descriptor) else {
            return []
        }

        // Filter for incomplete jobs - include paused jobs for restoration
        let incompleteJobs = allJobs.filter { job in
            job.status == .processing || job.status == .queued || job.status == .paused
        }

        return incompleteJobs
    }

    /// Restores all incomplete jobs found in the database
    /// Returns the count of jobs restored
    @MainActor
    func restoreIncompleteJobs() async -> Int {
        let incompleteJobs = findIncompleteJobs()

        guard !incompleteJobs.isEmpty else {
            return 0
        }

        AppLogger.jobs.info("Restoring \(incompleteJobs.count) incomplete job(s)")

        for job in incompleteJobs {
            do {
                // Check if job hasn't already been restored
                let isRunning = await taskStorage.hasTask(for: job.id)
                guard !isRunning else {
                    AppLogger.jobs.warning("Job \(job.id) is already running, skipping restore")
                    continue
                }

                AppLogger.jobs.info("Restoring job \(job.id) with status: \(job.status.rawValue)")
                try await resumeJob(job, allowProcessing: true)
                AppLogger.jobs.info("Successfully restored job \(job.id)")
            } catch {
                AppLogger.jobs.warning("Failed to restore job \(job.id): \(error.localizedDescription)")
            }
        }

        return incompleteJobs.count
    }

    // MARK: - Public Query Methods

    /// Checks if a job is currently running
    func isJobRunning(_ jobID: UUID) async -> Bool {
        return await taskStorage.hasTask(for: jobID)
    }

    /// Gets all active job IDs
    func getActiveJobIDs() async -> [UUID] {
        return await taskStorage.getAllTaskIDs()
    }

    /// Cancels all active jobs
    func cancelAllJobs() async {
        let jobIDs = await getActiveJobIDs()

        // Fetch all jobs and cancel them
        await MainActor.run {
            let descriptor = FetchDescriptor<SummaryJob>(
                predicate: #Predicate { job in
                    jobIDs.contains(job.id)
                }
            )

            if let jobs = try? modelContext.fetch(descriptor) {
                for job in jobs {
                    Task {
                        await cancelJob(job)
                    }
                }
            }
        }
    }

    /// Pauses all active jobs (typically when app backgrounds)
    /// - Parameter sendNotifications: Whether to send notifications for paused jobs
    @MainActor
    func pauseAllJobs(sendNotifications: Bool = true) async {
        let incompleteJobs = findIncompleteJobs()

        guard !incompleteJobs.isEmpty else { return }

        let processingJobs = incompleteJobs.filter { $0.status == .processing }
        guard !processingJobs.isEmpty else { return }

        // Calculate total progress across all jobs
        let totalProcessed = processingJobs.reduce(0) { $0 + $1.processedItems }
        let totalItems = processingJobs.reduce(0) { $0 + $1.totalItems }

        // Pause each job without individual notifications
        for job in processingJobs {
            await pauseJob(job, sendNotification: false)
        }

        // Send a single consolidated notification for all paused jobs
        if sendNotifications {
            Task {
                await NotificationManager.shared.sendBatchPausedNotification(
                    processedCount: totalProcessed,
                    totalCount: totalItems
                )
            }
        }
    }
}
