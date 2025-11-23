//
//  SummaryJob.swift
//  PaperGist
//
//  Represents a batch summarisation job tracking progress across multiple items.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import Foundation
import SwiftData

/// Batch job for processing multiple items through the summarisation pipeline
@Model
final class SummaryJob: Identifiable {
    var id: UUID
    var createdDate: Date
    var status: JobStatus
    var totalItems: Int
    var processedItems: Int
    var failedItemKeys: [String]
    var currentBatchIndex: Int
    var itemKeys: [String]
    var progress: Double
    var progressMessage: String?
    var completedAt: Date?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        createdDate: Date = Date(),
        status: JobStatus = .queued,
        totalItems: Int = 0,
        processedItems: Int = 0,
        failedItemKeys: [String] = [],
        currentBatchIndex: Int = 0,
        itemKeys: [String] = [],
        progress: Double = 0.0,
        progressMessage: String? = nil,
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.createdDate = createdDate
        self.status = status
        self.totalItems = totalItems
        self.processedItems = processedItems
        self.failedItemKeys = failedItemKeys
        self.currentBatchIndex = currentBatchIndex
        self.itemKeys = itemKeys
        self.progress = progress
        self.progressMessage = progressMessage
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }
}

/// Job execution state
enum JobStatus: String, Codable {
    case queued
    case processing
    case paused
    case completed
    case failed
    case cancelled
}

extension SummaryJob {
    /// Progress as a ratio of processed items to total (0.0-1.0)
    var calculatedProgress: Double {
        guard totalItems > 0 else { return 0.0 }
        return Double(processedItems) / Double(totalItems)
    }

    /// Items yet to be processed
    var remainingItems: Int {
        totalItems - processedItems
    }

    /// Successfully processed items (excluding failures)
    var successfulItems: Int {
        processedItems - failedItemKeys.count
    }

    /// Whether the job can be resumed from its current state
    var canResume: Bool {
        status == .paused || status == .failed
    }

    /// Whether the job is currently running or queued
    var isActive: Bool {
        status == .processing || status == .queued
    }
}
