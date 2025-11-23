//
//  RecentSummariesWidget.swift
//  PaperGist
//
//  Widget displaying a list of recently processed paper summaries.
//  Shows paper titles, authors, years, and relative processing times.
//  Supports medium and large sizes.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import WidgetKit
import SwiftUI

/// Home screen widget showing recent summaries
struct RecentSummariesWidget: Widget {
    let kind: String = "RecentSummariesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentSummariesProvider()) { entry in
            RecentSummariesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent summaries")
        .description("View your most recently processed summaries")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Timeline Provider

struct RecentSummariesProvider: TimelineProvider {
    typealias Entry = RecentSummariesEntry

    func placeholder(in context: Context) -> RecentSummariesEntry {
        RecentSummariesEntry(
            date: Date(),
            summaries: [
                .init(
                    id: "1",
                    title: "Understanding Neural Networks in Modern AI",
                    authors: "Smith et al.",
                    year: "2024",
                    processedDate: Date()
                ),
                .init(
                    id: "2",
                    title: "Quantum Computing Applications in Cryptography",
                    authors: "Johnson et al.",
                    year: "2023",
                    processedDate: Date()
                )
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentSummariesEntry) -> Void) {
        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentSummariesEntry>) -> Void) {
        let entry = createEntry()

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func createEntry() -> RecentSummariesEntry {
        let dataProvider = WidgetDataProvider.shared
        let data = dataProvider.loadWidgetData()

        return RecentSummariesEntry(
            date: Date(),
            summaries: data.recentSummaries
        )
    }
}

// MARK: - Entry

struct RecentSummariesEntry: TimelineEntry {
    let date: Date
    let summaries: [WidgetData.RecentSummary]
}

// MARK: - Widget View

struct RecentSummariesWidgetView: View {
    let entry: RecentSummariesEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.headlineSourceSans)
                    .foregroundStyle(Color.terracotta)

                Text("Recent summaries")
                    .font(.headlineSourceSans)
                    .fontWeight(.semibold)

                Spacer()

                if !entry.summaries.isEmpty {
                    Text("\(entry.summaries.count)")
                        .font(.captionSourceSans)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }

            if entry.summaries.isEmpty {
                EmptyStateView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(displayedSummaries) { summary in
                        SummaryRow(summary: summary)

                        if summary.id != displayedSummaries.last?.id {
                            Divider()
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    private var displayedSummaries: [WidgetData.RecentSummary] {
        let maxCount = family == .systemLarge ? 5 : 3
        return Array(entry.summaries.prefix(maxCount))
    }
}

// MARK: - Summary Row

/// Displays a single paper summary with title, authors, year, and date
struct SummaryRow: View {
    let summary: WidgetData.RecentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.title)
                .font(.sourceSansMedium(13))
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                Text(summary.authors)
                    .font(.caption2SourceSans)
                    .foregroundStyle(.secondary)

                if let year = summary.year {
                    Text("(\(year))")
                        .font(.caption2SourceSans)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(relativeDate(from: summary.processedDate))
                    .font(.caption2SourceSans)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func relativeDate(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Empty State

/// Shown when no summaries have been processed yet
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            Text("No summaries yet")
                .font(.captionSourceSans)
                .foregroundStyle(.secondary)

            Text("Process papers in the app to see them here")
                .font(.caption2SourceSans)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview(as: .systemMedium) {
    RecentSummariesWidget()
} timeline: {
    RecentSummariesEntry(
        date: Date(),
        summaries: [
            .init(
                id: "1",
                title: "Understanding Neural Networks in Modern AI Systems",
                authors: "Smith et al.",
                year: "2024",
                processedDate: Date().addingTimeInterval(-3600)
            ),
            .init(
                id: "2",
                title: "Quantum Computing Applications",
                authors: "Johnson et al.",
                year: "2023",
                processedDate: Date().addingTimeInterval(-86400)
            ),
            .init(
                id: "3",
                title: "Machine Learning in Healthcare",
                authors: "Williams et al.",
                year: "2024",
                processedDate: Date().addingTimeInterval(-172800)
            )
        ]
    )
}

#Preview(as: .systemLarge) {
    RecentSummariesWidget()
} timeline: {
    RecentSummariesEntry(
        date: Date(),
        summaries: [
            .init(
                id: "1",
                title: "Understanding Neural Networks in Modern AI Systems",
                authors: "Smith et al.",
                year: "2024",
                processedDate: Date().addingTimeInterval(-3600)
            ),
            .init(
                id: "2",
                title: "Quantum Computing Applications in Cryptography",
                authors: "Johnson et al.",
                year: "2023",
                processedDate: Date().addingTimeInterval(-86400)
            ),
            .init(
                id: "3",
                title: "Machine Learning in Healthcare",
                authors: "Williams et al.",
                year: "2024",
                processedDate: Date().addingTimeInterval(-172800)
            ),
            .init(
                id: "4",
                title: "Climate Change Modelling",
                authors: "Brown et al.",
                year: "2023",
                processedDate: Date().addingTimeInterval(-259200)
            ),
            .init(
                id: "5",
                title: "Renewable Energy Systems",
                authors: "Davis et al.",
                year: "2024",
                processedDate: Date().addingTimeInterval(-345600)
            )
        ]
    )
}

#Preview("Empty State", as: .systemMedium) {
    RecentSummariesWidget()
} timeline: {
    RecentSummariesEntry(
        date: Date(),
        summaries: []
    )
}
