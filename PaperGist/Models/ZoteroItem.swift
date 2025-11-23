//
//  ZoteroItem.swift
//  PaperGist
//
//  Local representation of Zotero library items.
//  Synced from the Zotero API with relationship to ProcessedItem summaries.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import Foundation
import SwiftData

// MARK: - Supporting types

enum LibraryType: String, Codable {
    case user
    case group
}

struct Creator: Codable {
    var creatorType: String
    var firstName: String?
    var lastName: String?
    var name: String?

    init(creatorType: String, firstName: String? = nil, lastName: String? = nil, name: String? = nil) {
        self.creatorType = creatorType
        self.firstName = firstName
        self.lastName = lastName
        self.name = name
    }
}

// MARK: - ZoteroItem

/// Local cache of a Zotero library item with sync metadata
@Model
final class ZoteroItem {
    var key: String
    var title: String
    var itemType: String
    var creatorSummary: String
    var creators: [Creator]
    var year: String?
    var publicationTitle: String?
    var hasAttachment: Bool
    var hasSummary: Bool
    var lastChecked: Date
    var libraryID: String
    var libraryType: LibraryType
    var version: Int

    var summary: ProcessedItem?

    init(
        key: String,
        title: String,
        itemType: String,
        creatorSummary: String,
        creators: [Creator] = [],
        year: String? = nil,
        publicationTitle: String? = nil,
        hasAttachment: Bool,
        hasSummary: Bool,
        lastChecked: Date = Date(),
        libraryID: String,
        libraryType: LibraryType = .user,
        version: Int = 0
    ) {
        self.key = key
        self.title = title
        self.itemType = itemType
        self.creatorSummary = creatorSummary
        self.creators = creators
        self.year = year
        self.publicationTitle = publicationTitle
        self.hasAttachment = hasAttachment
        self.hasSummary = hasSummary
        self.lastChecked = lastChecked
        self.libraryID = libraryID
        self.libraryType = libraryType
        self.version = version
    }
}

extension ZoteroItem {
    /// Formatted citation (e.g., "Smith et al. (2024)")
    var citation: String {
        if let year = year {
            return "\(creatorSummary) (\(year))"
        }
        return creatorSummary
    }

    /// SF Symbol name for item status indicator
    var statusIcon: String {
        if hasSummary {
            return "checkmark.circle.fill"
        } else if summary != nil && summary?.status == .failed {
            return "exclamationmark.triangle.fill"
        }
        return "circle"
    }

    /// Colour name for item status indicator
    var statusColor: String {
        if hasSummary {
            return "green"
        } else if summary != nil && summary?.status == .failed {
            return "orange"
        }
        return "gray"
    }
}
