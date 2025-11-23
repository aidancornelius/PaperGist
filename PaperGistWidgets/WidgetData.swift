//
//  WidgetData.swift
//  PaperGist
//
//  Shared data model and provider for widget content.
//  Stores summary statistics and recent items in App Group container
//  for access by WidgetKit extensions.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Shared data model for widgets.
/// Stored in App Group container for access by WidgetKit extensions.
struct WidgetData: Codable {
    var totalSummaries: Int
    var recentSummaries: [RecentSummary]
    var lastUpdated: Date
    var activeBatchJobs: Int

    /// A recently processed paper summary
    struct RecentSummary: Codable, Identifiable {
        var id: String
        var title: String
        var authors: String
        var year: String?
        var processedDate: Date
    }

    static let `default` = WidgetData(
        totalSummaries: 0,
        recentSummaries: [],
        lastUpdated: Date(),
        activeBatchJobs: 0
    )
}

/// Manages reading and writing widget data to the shared App Group container
final class WidgetDataProvider: @unchecked Sendable {
    static let shared = WidgetDataProvider()

    private let appGroupID = "group.com.cornelius-bell.PaperGist"
    private let widgetDataKey = "widgetData"

    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private init() {}

    /// Updates widget data and triggers a widget refresh.
    /// Call this whenever summary data changes in the main app.
    func updateWidgetData(
        totalSummaries: Int,
        recentSummaries: [WidgetData.RecentSummary],
        activeBatchJobs: Int
    ) {
        let data = WidgetData(
            totalSummaries: totalSummaries,
            recentSummaries: Array(recentSummaries.prefix(5)),
            lastUpdated: Date(),
            activeBatchJobs: activeBatchJobs
        )

        saveWidgetData(data)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Saves widget data to shared container
    private func saveWidgetData(_ data: WidgetData) {
        guard let defaults = userDefaults else {
            return
        }

        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: widgetDataKey)
        } catch {
            // Silent fail - widgets don't have error reporting
        }
    }

    /// Loads widget data from shared container
    func loadWidgetData() -> WidgetData {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: widgetDataKey) else {
            return .default
        }

        do {
            return try JSONDecoder().decode(WidgetData.self, from: data)
        } catch {
            return .default
        }
    }
}
