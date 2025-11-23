//
// BatchSummarisationHelper.swift
// PaperGist
//
// Helper functions for starting batch summarisation jobs.
// Handles querying eligible items and creating batch jobs.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import SwiftData
import OSLog

/// Utilities for batch summarisation operations
struct BatchSummarisationHelper {

    /// Gets the count of all unsummarised items from the database
    static func allUnsummarisedCount(modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<ZoteroItem>(
            predicate: #Predicate { item in
                item.hasAttachment && !item.hasSummary
            }
        )
        return (try? modelContext.fetch(descriptor))?.count ?? 0
    }

    /// Gets the count of eligible items from selected items
    static func eligibleItemsCount(
        selectedItems: Set<String>,
        items: [ZoteroItem]
    ) -> Int {
        return items.filter { item in
            selectedItems.contains(item.key) && item.hasAttachment && !item.hasSummary
        }.count
    }

    /// Starts a batch summarisation job for all unsummarised items in the library
    @MainActor
    static func startSummariseAll(
        jobManager: JobManager,
        modelContext: ModelContext,
        onJobCreated: @escaping (SummaryJob) -> Void,
        onError: @escaping (String) -> Void,
        onAppleIntelligenceUnavailable: @escaping () -> Void
    ) {
        // Check Foundation Models availability first
        guard AIService.isAppleIntelligenceAvailable() else {
            onAppleIntelligenceUnavailable()
            return
        }

        // Query database directly for ALL unsummarised items, not just paginated ones
        let descriptor = FetchDescriptor<ZoteroItem>(
            predicate: #Predicate { item in
                item.hasAttachment && !item.hasSummary
            }
        )

        guard let itemsToSummarise = try? modelContext.fetch(descriptor) else {
            AppLogger.general.error("Failed to fetch items from database for batch summarisation")
            return
        }

        guard !itemsToSummarise.isEmpty else {
            return
        }

        // Start batch job in background
        Task {
            do {
                let jobId = try await jobManager.startBatchJob(items: itemsToSummarise)

                // Fetch the job and update UI on main actor
                await MainActor.run {
                    // Fetch job by ID
                    let descriptor = FetchDescriptor<SummaryJob>(
                        predicate: #Predicate { $0.id == jobId }
                    )
                    if let job = try? modelContext.fetch(descriptor).first {
                        onJobCreated(job)
                    }
                }

            } catch {
                AppLogger.jobs.error("Failed to start batch job: \(error.localizedDescription)")
                await MainActor.run {
                    onError("Failed to start batch job: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Starts a batch summarisation job for selected items
    @MainActor
    static func startBatchSummarisation(
        selectedItems: Set<String>,
        items: [ZoteroItem],
        jobManager: JobManager,
        modelContext: ModelContext,
        onJobCreated: @escaping (SummaryJob) -> Void,
        onError: @escaping (String) -> Void,
        onAppleIntelligenceUnavailable: @escaping () -> Void
    ) {
        // Check Foundation Models availability first
        guard AIService.isAppleIntelligenceAvailable() else {
            onAppleIntelligenceUnavailable()
            return
        }

        // Filter selected items that have attachments and no summary
        let itemsToSummarise = items.filter { item in
            selectedItems.contains(item.key) && item.hasAttachment && !item.hasSummary
        }

        guard !itemsToSummarise.isEmpty else {
            return
        }

        // Start batch job in background
        Task {
            do {
                let jobId = try await jobManager.startBatchJob(items: itemsToSummarise)

                // Fetch the job and update UI on main actor
                await MainActor.run {
                    // Fetch job by ID
                    let descriptor = FetchDescriptor<SummaryJob>(
                        predicate: #Predicate { $0.id == jobId }
                    )
                    if let job = try? modelContext.fetch(descriptor).first {
                        onJobCreated(job)
                    }
                }

            } catch {
                AppLogger.jobs.error("Failed to start batch job: \(error.localizedDescription)")
                await MainActor.run {
                    onError("Failed to start batch job: \(error.localizedDescription)")
                }
            }
        }
    }
}
