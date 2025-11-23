//
//  SummaryStatsWidget.swift
//  PaperGist
//
//  Widget displaying summary statistics and active job counts.
//  Supports small and medium sizes showing total summaries and
//  current processing status.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import WidgetKit
import SwiftUI

/// Home screen widget showing summary statistics
struct SummaryStatsWidget: Widget {
    let kind: String = "SummaryStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummaryStatsProvider()) { entry in
            SummaryStatsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Summary statistics")
        .description("View your library summary counts at a glance")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline Provider

struct SummaryStatsProvider: TimelineProvider {
    typealias Entry = SummaryStatsEntry

    func placeholder(in context: Context) -> SummaryStatsEntry {
        SummaryStatsEntry(
            date: Date(),
            totalSummaries: 42,
            activeBatchJobs: 1
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryStatsEntry) -> Void) {
        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryStatsEntry>) -> Void) {
        let entry = createEntry()

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func createEntry() -> SummaryStatsEntry {
        let dataProvider = WidgetDataProvider.shared
        let data = dataProvider.loadWidgetData()

        return SummaryStatsEntry(
            date: Date(),
            totalSummaries: data.totalSummaries,
            activeBatchJobs: data.activeBatchJobs
        )
    }
}

// MARK: - Entry

struct SummaryStatsEntry: TimelineEntry {
    let date: Date
    let totalSummaries: Int
    let activeBatchJobs: Int
}

// MARK: - Widget View

struct SummaryStatsWidgetView: View {
    let entry: SummaryStatsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget

/// Compact view for small widget size
struct SmallWidgetView: View {
    let entry: SummaryStatsEntry

    var body: some View {
        VStack(spacing: 8) {
            // App icon/title
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.headlineSourceSans)
                    .foregroundStyle(Color.terracotta)

                Text("PaperGist")
                    .font(.headlineSourceSans)
                    .fontWeight(.semibold)

                Spacer()
            }

            Spacer()

            // Main stat
            VStack(spacing: 4) {
                Text("\(entry.totalSummaries)")
                    .font(.sourceSansBold(36))
                    .foregroundStyle(.primary)

                Text("Summaries")
                    .font(.subheadlineSourceSans)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Active jobs indicator
            if entry.activeBatchJobs > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2SourceSans)
                        .foregroundStyle(Color.terracotta)

                    Text("\(entry.activeBatchJobs) active")
                        .font(.caption2SourceSans)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - Medium Widget

/// Expanded view for medium widget size with additional stats
struct MediumWidgetView: View {
    let entry: SummaryStatsEntry

    var body: some View {
        HStack(spacing: 20) {
            // Left side - Main stat
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.terracotta)

                    Text("PaperGist")
                        .font(.headlineSourceSans)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.totalSummaries)")
                        .font(.sourceSansBold(40))
                        .foregroundStyle(.primary)

                    Text("Summaries")
                        .font(.subheadlineSourceSans)
                        .foregroundStyle(.secondary)
                }

                if entry.activeBatchJobs > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.captionSourceSans)
                            .foregroundStyle(Color.terracotta)

                        Text("\(entry.activeBatchJobs) job\(entry.activeBatchJobs == 1 ? "" : "s") active")
                            .font(.captionSourceSans)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Right side - Quick stats
            VStack(alignment: .leading, spacing: 12) {
                StatRow(
                    icon: "checkmark.circle.fill",
                    label: "Total",
                    value: "\(entry.totalSummaries)",
                    color: .green
                )

                if entry.activeBatchJobs > 0 {
                    StatRow(
                        icon: "arrow.triangle.2.circlepath",
                        label: "Processing",
                        value: "\(entry.activeBatchJobs)",
                        color: .terracotta
                    )
                } else {
                    StatRow(
                        icon: "checkmark.circle",
                        label: "All done",
                        value: "",
                        color: .gray
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }
}

// MARK: - Helper Views

/// Single stat row with icon and label
struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.captionSourceSans)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2SourceSans)
                    .foregroundStyle(.secondary)

                if !value.isEmpty {
                    Text(value)
                        .font(.captionSourceSans)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    SummaryStatsWidget()
} timeline: {
    SummaryStatsEntry(
        date: Date(),
        totalSummaries: 42,
        activeBatchJobs: 0
    )
    SummaryStatsEntry(
        date: Date(),
        totalSummaries: 45,
        activeBatchJobs: 1
    )
}

#Preview(as: .systemMedium) {
    SummaryStatsWidget()
} timeline: {
    SummaryStatsEntry(
        date: Date(),
        totalSummaries: 42,
        activeBatchJobs: 0
    )
    SummaryStatsEntry(
        date: Date(),
        totalSummaries: 45,
        activeBatchJobs: 2
    )
}
