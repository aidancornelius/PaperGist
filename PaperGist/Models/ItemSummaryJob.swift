//
//  ItemSummaryJob.swift
//  PaperGist
//
//  Tracks progress for individual item summarisation.
//  Used for real-time UI updates during processing.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import Foundation
import SwiftData

/// Individual item job tracking detailed progress through summarisation stages
@Model
final class ItemSummaryJob {
    var id: UUID
    var itemKey: String
    var status: SummaryStatus
    var progress: Double
    var progressMessage: String
    var createdAt: Date
    var completedAt: Date?
    var errorMessage: String?

    init(
        itemKey: String,
        status: SummaryStatus = .pending,
        progress: Double = 0.0,
        progressMessage: String = "Initialising..."
    ) {
        self.id = UUID()
        self.itemKey = itemKey
        self.status = status
        self.progress = progress
        self.progressMessage = progressMessage
        self.createdAt = Date()
    }
}

// MARK: - Summary status

/// Processing state for individual item summarisation
enum SummaryStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
    case cancelled
}
