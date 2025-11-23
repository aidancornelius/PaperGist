// WidgetUpdateService.swift
// PaperGist
//
// Updates widget data when summaries change. Fetches recent summaries and active
// job counts from the database and pushes updates to all widget timelines.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftData
import WidgetKit
import OSLog

/// Service for updating widget data when summaries change
@MainActor
final class WidgetUpdateService {
    private let modelContext: ModelContext
    private let dataProvider = WidgetDataProvider.shared

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Updates widget data from current database state
    ///
    /// Fetches summary counts, recent items, and active batch jobs, then pushes
    /// the data to the widget data provider.
    func updateWidgets() {
        Task { @MainActor in
            do {
                let summaryDescriptor = FetchDescriptor<ProcessedItem>()
                let totalSummaries = try modelContext.fetchCount(summaryDescriptor)

                var recentDescriptor = FetchDescriptor<ProcessedItem>(
                    sortBy: [SortDescriptor(\.processedAt, order: .reverse)]
                )
                recentDescriptor.fetchLimit = 5

                let recentProcessed = try modelContext.fetch(recentDescriptor)

                let recentSummaries: [WidgetData.RecentSummary] = recentProcessed.compactMap { processed in
                    guard let item = processed.item else { return nil }

                    return WidgetData.RecentSummary(
                        id: item.key,
                        title: item.title,
                        authors: item.creatorSummary,
                        year: item.year,
                        processedDate: processed.processedAt
                    )
                }

                // Count active batch jobs - just count all for now since predicate macros don't support enum comparisons well
                let allJobsDescriptor = FetchDescriptor<SummaryJob>()
                let allJobs = try modelContext.fetch(allJobsDescriptor)
                let activeBatchJobs = allJobs.filter { job in
                    job.status == .processing || job.status == .queued
                }.count

                // Update widget data
                dataProvider.updateWidgetData(
                    totalSummaries: totalSummaries,
                    recentSummaries: recentSummaries,
                    activeBatchJobs: activeBatchJobs
                )
            } catch {
                AppLogger.general.error("Failed to update widget data: \(error.localizedDescription)")
            }
        }
    }

    /// Reloads all widget timelines
    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
