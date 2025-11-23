//
// JobProgressView.swift
// PaperGist
//
// Displays real-time progress for batch summarisation jobs.
// Shows statistics, progress bar, failed items, and job control actions.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import SwiftData

/// Real-time progress view for batch summarisation jobs
struct JobProgressView: View {
    @Bindable var job: SummaryJob
    let jobManager: JobManaging?

    @State private var isFailedItemsExpanded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    init(job: SummaryJob, jobManager: JobManaging? = nil) {
        self.job = job
        self.jobManager = jobManager
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    combinedProgressSection

                    if !job.failedItemKeys.isEmpty {
                        failedItemsSection
                    }

                    if let errorMessage = job.errorMessage {
                        errorMessageSection(errorMessage)
                    }
                }
                .padding()
            }
            .navigationTitle("Batch job progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    actionMenu
                }
            }
            .interactiveDismissDisabled(job.status == .processing || job.status == .paused)
        }
    }

    // MARK: - Combined Progress Section

    private var combinedProgressSection: some View {
        VStack(spacing: 20) {
            // Status badge and timestamp
            HStack {
                statusBadge
                Spacer()
                Label {
                    if let completedAt = job.completedAt {
                        Text("Completed \(completedAt, style: .relative)")
                            .font(.subheadlineSourceSans)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(job.createdDate, style: .relative)
                            .font(.subheadlineSourceSans)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: job.completedAt != nil ? "checkmark.circle" : "clock")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Progress bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Int(job.progress * 100))%")
                        .font(.titleSourceSans)
                    Spacer()
                    Text("\(job.processedItems) of \(job.totalItems)")
                        .font(.subheadlineSourceSans)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(height: 12)

                        // Progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(progressGradient)
                            .frame(width: geometry.size.width * job.progress, height: 12)
                            .animation(.easeInOut(duration: 0.3), value: job.progress)
                    }
                }
                .frame(height: 12)
            }

            // Current progress message
            if let progressMessage = job.progressMessage, !progressMessage.isEmpty {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressMessage)
                        .font(.subheadlineSourceSans)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            // Estimated time remaining (if processing and has some progress)
            if job.status == .processing && job.processedItems > 0 {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                        .font(.captionSourceSans)
                    Text(estimatedTimeRemaining)
                        .font(.captionSourceSans)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            Divider()

            // Statistics
            HStack(spacing: 16) {
                statisticCard(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    label: "Successful",
                    value: "\(job.successfulItems)"
                )

                statisticCard(
                    icon: "xmark.circle.fill",
                    color: .red,
                    label: "Failed",
                    value: "\(job.failedItemKeys.count)"
                )

                statisticCard(
                    icon: "circle",
                    color: .gray,
                    label: "Remaining",
                    value: "\(job.remainingItems)"
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.headlineSourceSans)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch job.status {
        case .queued:
            return .terracotta
        case .processing:
            return .terracotta
        case .paused:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .gray
        }
    }

    private var statusText: String {
        switch job.status {
        case .queued:
            return "Queued"
        case .processing:
            return "Processing"
        case .paused:
            return "Paused"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }


    private var progressGradient: LinearGradient {
        switch job.status {
        case .completed:
            return LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        case .failed, .cancelled:
            return LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        case .paused:
            return LinearGradient(colors: [.orange, .orange.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [.terracotta, .terracotta.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        }
    }

    private var estimatedTimeRemaining: String {
        guard job.processedItems > 0, job.remainingItems > 0 else {
            return "Calculating..."
        }

        let elapsedTime = Date().timeIntervalSince(job.createdDate)
        let timePerItem = elapsedTime / Double(job.processedItems)
        let estimatedRemaining = timePerItem * Double(job.remainingItems)

        return "Est. \(formatDuration(estimatedRemaining)) remaining"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let hours = minutes / 60

        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }


    private func statisticCard(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)

            Text(value)
                .font(.title2SourceSans)

            Text(label)
                .font(.captionSourceSans)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Failed items section

    private var failedItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isFailedItemsExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isFailedItemsExpanded ? "chevron.down" : "chevron.right")
                        .font(.captionSourceSans)
                        .foregroundStyle(.secondary)

                    Text("Failed items (\(job.failedItemKeys.count))")
                        .font(.headlineSourceSans)
                        .foregroundStyle(.primary)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isFailedItemsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(job.failedItemKeys, id: \.self) { itemKey in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.captionSourceSans)
                                .foregroundStyle(.red)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(getItemTitle(for: itemKey))
                                    .font(.subheadlineSourceSans)
                                    .foregroundStyle(.primary)

                                Text("Processing error")
                                    .font(.captionSourceSans)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - Error message section

    private func errorMessageSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Error")
                    .font(.headlineSourceSans)
                    .foregroundStyle(.red)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Text(message)
                .font(.subheadlineSourceSans)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }


    // MARK: - Action menu

    @ViewBuilder
    private var actionMenu: some View {
        if job.status == .processing || job.status == .paused {
            Menu {
                if job.status == .processing {
                    Button {
                        pauseJob()
                    } label: {
                        Label("Pause", systemImage: "pause")
                    }
                } else if job.status == .paused {
                    Button {
                        resumeJob()
                    } label: {
                        Label("Resume", systemImage: "play")
                    }
                }

                Button(role: .destructive) {
                    cancelJob()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Color.terracotta)
            }
        } else if job.status == .completed && !job.failedItemKeys.isEmpty {
            Menu {
                Button {
                    retryFailedItems()
                } label: {
                    Label("Retry failed items", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Color.terracotta)
            }
        }
    }

    // MARK: - Helper Methods

    /// Gets the item title for a given item key
    private func getItemTitle(for itemKey: String) -> String {
        let descriptor = FetchDescriptor<ZoteroItem>(
            predicate: #Predicate { item in
                item.key == itemKey
            }
        )

        guard let item = try? modelContext.fetch(descriptor).first else {
            return itemKey // Fallback to showing key if item not found
        }

        return item.title
    }

    // MARK: - Actions

    private func pauseJob() {
        jobManager?.pauseJob(job)
    }

    private func resumeJob() {
        jobManager?.resumeJob(job)
    }

    private func cancelJob() {
        jobManager?.cancelJob(job)
    }

    private func retryFailedItems() {
        jobManager?.retryFailedItems(job)
    }
}

// MARK: - JobManager protocol

/// Protocol for job control operations used by this view
@MainActor
protocol JobManaging {
    func pauseJob(_ job: SummaryJob)
    func resumeJob(_ job: SummaryJob)
    func cancelJob(_ job: SummaryJob)
    func retryFailedItems(_ job: SummaryJob)
}

// MARK: - Preview

#Preview("Processing") {
    let job = SummaryJob(
        status: .processing,
        totalItems: 20,
        processedItems: 7,
        failedItemKeys: ["sample-paper-1"],
        itemKeys: Array(repeating: "item", count: 20),
        progress: 0.35,
        progressMessage: "Generating summary...",
        errorMessage: nil
    )

    JobProgressView(job: job, jobManager: nil)
}

#Preview("Completed with failures") {
    let job = SummaryJob(
        status: .completed,
        totalItems: 20,
        processedItems: 20,
        failedItemKeys: ["paper-1", "paper-2", "paper-3"],
        itemKeys: Array(repeating: "item", count: 20),
        progress: 1.0,
        progressMessage: nil,
        completedAt: Date(),
        errorMessage: nil
    )

    JobProgressView(job: job, jobManager: nil)
}

#Preview("Failed") {
    let job = SummaryJob(
        status: .failed,
        totalItems: 20,
        processedItems: 5,
        failedItemKeys: ["paper-1", "paper-2"],
        itemKeys: Array(repeating: "item", count: 20),
        progress: 0.25,
        progressMessage: nil,
        errorMessage: "Unable to connect to API service"
    )

    JobProgressView(job: job, jobManager: nil)
}

#Preview("Paused") {
    let job = SummaryJob(
        status: .paused,
        totalItems: 15,
        processedItems: 8,
        failedItemKeys: ["paper-1"],
        itemKeys: Array(repeating: "item", count: 15),
        progress: 0.53,
        progressMessage: "Paused by user",
        errorMessage: nil
    )

    JobProgressView(job: job, jobManager: nil)
}
