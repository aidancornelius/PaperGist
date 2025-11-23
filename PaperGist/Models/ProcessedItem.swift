//
//  ProcessedItem.swift
//  PaperGist
//
//  Stores completed summaries and their metadata.
//  Links to ZoteroItem and tracks upload status.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import Foundation
import SwiftData

/// A generated summary with metadata and upload tracking
@Model
final class ProcessedItem {
    var itemKey: String
    var summaryText: String

    @Attribute(originalName: "processedDate")
    var processedAt: Date

    var confidence: Double?
    var summaryNoteKey: String?
    var wordCount: Int
    var status: ProcessingStatus
    var errorMessage: String?

    var item: ZoteroItem?

    init(
        itemKey: String,
        summaryText: String,
        processedAt: Date = Date(),
        confidence: Double? = nil,
        summaryNoteKey: String? = nil,
        wordCount: Int = 0,
        status: ProcessingStatus = .local,
        errorMessage: String? = nil
    ) {
        self.itemKey = itemKey
        self.summaryText = summaryText
        self.processedAt = processedAt
        self.confidence = confidence
        self.summaryNoteKey = summaryNoteKey
        self.wordCount = wordCount
        self.status = status
        self.errorMessage = errorMessage
    }
}

/// Summary storage state
enum ProcessingStatus: String, Codable {
    case local
    case uploaded
    case failed
}

extension ProcessedItem {
    /// Formats summary as HTML note for Zotero with metadata footer
    var formattedNote: String {
        var note = summaryText
        note += "\n\n---\n"
        note += "Generated on \(processedAt.formatted(date: .abbreviated, time: .omitted)) using Apple Intelligence"

        if let confidence = confidence {
            note += "\nConfidence: \(String(format: "%.1f%%", confidence * 100))"
        }

        return note
    }
}
