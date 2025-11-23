//
//  WidgetData.swift
//  PaperGist
//
//  Manages data sharing between the app and home screen widgets.
//  Stores recent summaries and job status in the App Group container.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import Foundation
import OSLog
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Data model shared with widgets via App Group container
struct WidgetData: Codable {
    var totalSummaries: Int
    var recentSummaries: [RecentSummary]
    var lastUpdated: Date
    var activeBatchJobs: Int

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

/// Manages widget data persistence in App Group shared container
final class WidgetDataProvider: @unchecked Sendable {
    static let shared = WidgetDataProvider()

    private let appGroupID = "group.com.cornelius-bell.PaperGist"
    private let widgetDataKey = "widgetData"

    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private init() {}

    /// Updates widget data and triggers widget timeline reload
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

    private func saveWidgetData(_ data: WidgetData) {
        guard let defaults = userDefaults else {
            AppLogger.general.error("Failed to access App Group UserDefaults for widget data")
            return
        }

        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: widgetDataKey)
        } catch {
            AppLogger.general.error("Failed to encode widget data: \(error.localizedDescription)")
        }
    }

    /// Loads current widget data from shared container
    func loadWidgetData() -> WidgetData {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: widgetDataKey) else {
            return .default
        }

        do {
            return try JSONDecoder().decode(WidgetData.self, from: data)
        } catch {
            AppLogger.general.error("Failed to decode widget data: \(error.localizedDescription)")
            return .default
        }
    }
}
