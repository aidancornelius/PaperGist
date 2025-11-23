//
//  SummaryJobLiveActivity.swift
//  PaperGist
//
//  Live Activity for displaying batch summarisation job progress.
//  Displays on lock screen, banner notifications, and Dynamic Island
//  with real-time updates as papers are processed.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity widget for displaying batch job progress.
/// Shows on lock screen and Dynamic Island with real-time updates.
struct SummaryJobLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SummaryJobActivityAttributes.self) { context in
            // Lock Screen/Banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView(context: context)
            }
        }
    }
}

// MARK: - Lock Screen View

/// Lock screen view displaying comprehensive progress information.
/// Shows job name, progress bar, current item, and statistics.
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<SummaryJobActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 20))

                Text(context.attributes.jobName)
                    .font(.headlineSourceSans)

                Spacer()

                Text(statusText)
                    .font(.captionSourceSans)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            ProgressView(value: progressValue) {
                HStack {
                    Text("\(context.state.processedItems)/\(context.state.totalItems) items")
                        .font(.captionSourceSans)

                    Spacer()

                    Text("\(context.state.progressPercentage)%")
                        .font(.captionSourceSans)
                        .fontWeight(.semibold)
                }
            }
            .tint(statusColor)

            // Current item
            if !context.state.isFinished {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.captionSourceSans)
                        .foregroundStyle(.secondary)

                    Text(context.state.currentItemTitle)
                        .font(.captionSourceSans)
                        .lineLimit(1)

                    Spacer()
                }
            }

            // Stats
            HStack(spacing: 16) {
                StatView(
                    icon: "checkmark.circle.fill",
                    value: "\(context.state.successfulItems)",
                    label: "Success",
                    color: .green
                )

                if context.state.failedItems > 0 {
                    StatView(
                        icon: "xmark.circle.fill",
                        value: "\(context.state.failedItems)",
                        label: "Failed",
                        color: .red
                    )
                }

                if !context.state.isFinished {
                    StatView(
                        icon: "clock.fill",
                        value: "\(context.state.totalItems - context.state.processedItems)",
                        label: "Remaining",
                        color: .orange
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .activityBackgroundTint(Color.terracotta.opacity(0.1))
        .activitySystemActionForegroundColor(Color.terracotta)
    }

    // MARK: - Computed Properties

    /// Progress as a fraction from 0.0 to 1.0
    private var progressValue: Double {
        guard context.state.totalItems > 0 else { return 0 }
        return Double(context.state.processedItems) / Double(context.state.totalItems)
    }

    /// SF Symbol name for the current job status
    private var statusIcon: String {
        switch context.state.status {
        case "processing": return "arrow.triangle.2.circlepath"
        case "completed": return "checkmark.circle.fill"
        case "failed": return "exclamationmark.triangle.fill"
        case "cancelled": return "xmark.circle.fill"
        default: return "circle.fill"
        }
    }

    private var statusColor: Color {
        switch context.state.status {
        case "processing": return .terracotta
        case "completed": return context.state.failedItems > 0 ? .orange : .green
        case "failed": return .red
        case "cancelled": return .gray
        default: return .terracotta
        }
    }

    /// Capitalised display text for the current status
    private var statusText: String {
        switch context.state.status {
        case "processing": return "Processing"
        case "completed": return "Completed"
        case "failed": return "Failed"
        case "cancelled": return "Cancelled"
        default: return context.state.status.capitalized
        }
    }
}

// MARK: - Dynamic Island Views

/// Compact leading view showing progress percentage with status icon
struct CompactLeadingView: View {
    let context: ActivityViewContext<SummaryJobActivityAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption2SourceSans)

            Text("\(context.state.progressPercentage)%")
                .font(.caption2SourceSans)
                .fontWeight(.semibold)
        }
        .foregroundStyle(statusColor)
    }

    /// SF Symbol for compact leading display
    private var statusIcon: String {
        switch context.state.status {
        case "processing": return "arrow.triangle.2.circlepath"
        case "completed": return "checkmark.circle.fill"
        case "failed": return "exclamationmark.triangle.fill"
        default: return "circle.fill"
        }
    }

    /// Colour for compact leading icon
    private var statusColor: Color {
        switch context.state.status {
        case "processing": return .terracotta
        case "completed": return context.state.failedItems > 0 ? .orange : .green
        case "failed": return .red
        default: return .terracotta
        }
    }
}

/// Compact trailing view showing processed/total item count
struct CompactTrailingView: View {
    let context: ActivityViewContext<SummaryJobActivityAttributes>

    var body: some View {
        Text("\(context.state.processedItems)/\(context.state.totalItems)")
            .font(.caption2SourceSans)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }
}

/// Minimal view showing a simple status icon
struct MinimalView: View {
    let context: ActivityViewContext<SummaryJobActivityAttributes>

    var body: some View {
        Image(systemName: context.state.isActive ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
            .font(.caption2SourceSans)
            .foregroundStyle(context.state.isActive ? Color.terracotta : .green)
    }
}

/// Expanded leading view showing large status icon and percentage
struct ExpandedLeadingView: View {
    let context: ActivityViewContext<SummaryJobActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: statusIcon)
                .font(.titleSourceSans)
                .foregroundStyle(statusColor)

            Text("\(context.state.progressPercentage)%")
                .font(.captionSourceSans)
                .fontWeight(.semibold)
        }
    }

    /// SF Symbol for expanded leading display
    private var statusIcon: String {
        switch context.state.status {
        case "processing": return "arrow.triangle.2.circlepath"
        case "completed": return "checkmark.circle.fill"
        case "failed": return "exclamationmark.triangle.fill"
        case "cancelled": return "xmark.circle.fill"
        default: return "circle.fill"
        }
    }

    /// Colour for expanded leading icon
    private var statusColor: Color {
        switch context.state.status {
        case "processing": return .terracotta
        case "completed": return context.state.failedItems > 0 ? .orange : .green
        case "failed": return .red
        case "cancelled": return .gray
        default: return .terracotta
        }
    }
}

/// Expanded trailing view showing item counts and failure stats
struct ExpandedTrailingView: View {
    let context: ActivityViewContext<SummaryJobActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(context.state.processedItems)")
                    .font(.titleSourceSans)
                    .fontWeight(.bold)

                Text("of \(context.state.totalItems)")
                    .font(.caption2SourceSans)
                    .foregroundStyle(.secondary)
            }

            if context.state.failedItems > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2SourceSans)
                        .foregroundStyle(.red)

                    Text("\(context.state.failedItems) failed")
                        .font(.caption2SourceSans)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Expanded bottom view with progress bar, current item, and detailed stats
struct ExpandedBottomView: View {
    let context: ActivityViewContext<SummaryJobActivityAttributes>

    var body: some View {
        VStack(spacing: 8) {
            // Current item
            if !context.state.isFinished {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption2SourceSans)
                        .foregroundStyle(.secondary)

                    Text(context.state.currentItemTitle)
                        .font(.captionSourceSans)
                        .lineLimit(1)

                    Spacer()
                }
            }

            // Progress bar
            ProgressView(value: progressValue)
                .tint(statusColor)

            // Stats row
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2SourceSans)
                        .foregroundStyle(.green)

                    Text("\(context.state.successfulItems)")
                        .font(.caption2SourceSans)
                }

                if context.state.failedItems > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2SourceSans)
                            .foregroundStyle(.red)

                        Text("\(context.state.failedItems)")
                            .font(.caption2SourceSans)
                    }
                }

                Spacer()

                if !context.state.isFinished {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2SourceSans)
                            .foregroundStyle(.orange)

                        Text("\(context.state.totalItems - context.state.processedItems)")
                            .font(.caption2SourceSans)
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Progress fraction for the bottom view progress bar
    private var progressValue: Double {
        guard context.state.totalItems > 0 else { return 0 }
        return Double(context.state.processedItems) / Double(context.state.totalItems)
    }

    /// Colour for bottom view progress bar
    private var statusColor: Color {
        switch context.state.status {
        case "processing": return .terracotta
        case "completed": return context.state.failedItems > 0 ? .orange : .green
        case "failed": return .red
        default: return .terracotta
        }
    }
}

// MARK: - Helper Views

/// Displays a single metric with icon, value, and label
struct StatView: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2SourceSans)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.captionSourceSans)
                    .fontWeight(.semibold)

                Text(label)
                    .font(.caption2SourceSans)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Previews

#Preview("Lock Screen - Processing", as: .content, using: SummaryJobActivityAttributes(
    jobID: "preview-job",
    jobName: "Batch summarisation"
)) {
    SummaryJobLiveActivity()
} contentStates: {
    SummaryJobActivityAttributes.ContentState(
        totalItems: 20,
        processedItems: 7,
        failedItems: 1,
        currentItemTitle: "Understanding Neural Networks in Modern AI",
        status: "processing",
        progressMessage: "Extracting text from PDF..."
    )
}

#Preview("Lock Screen - Completed", as: .content, using: SummaryJobActivityAttributes(
    jobID: "preview-job",
    jobName: "Batch summarisation"
)) {
    SummaryJobLiveActivity()
} contentStates: {
    SummaryJobActivityAttributes.ContentState.completed(
        totalItems: 20,
        successfulItems: 18,
        failedItems: 2
    )
}

#Preview("Dynamic Island - Compact", as: .dynamicIsland(.compact), using: SummaryJobActivityAttributes(
    jobID: "preview-job",
    jobName: "Batch summarisation"
)) {
    SummaryJobLiveActivity()
} contentStates: {
    SummaryJobActivityAttributes.ContentState(
        totalItems: 20,
        processedItems: 7,
        failedItems: 1,
        currentItemTitle: "Understanding Neural Networks in Modern AI",
        status: "processing",
        progressMessage: "Extracting text from PDF..."
    )
}

#Preview("Dynamic Island - Expanded", as: .dynamicIsland(.expanded), using: SummaryJobActivityAttributes(
    jobID: "preview-job",
    jobName: "Batch summarisation"
)) {
    SummaryJobLiveActivity()
} contentStates: {
    SummaryJobActivityAttributes.ContentState(
        totalItems: 20,
        processedItems: 7,
        failedItems: 1,
        currentItemTitle: "Understanding Neural Networks in Modern AI",
        status: "processing",
        progressMessage: "Extracting text from PDF..."
    )
}

#Preview("Dynamic Island - Minimal", as: .dynamicIsland(.minimal), using: SummaryJobActivityAttributes(
    jobID: "preview-job",
    jobName: "Batch summarisation"
)) {
    SummaryJobLiveActivity()
} contentStates: {
    SummaryJobActivityAttributes.ContentState(
        totalItems: 20,
        processedItems: 7,
        failedItems: 1,
        currentItemTitle: "Understanding Neural Networks in Modern AI",
        status: "processing",
        progressMessage: "Extracting text from PDF..."
    )
}
