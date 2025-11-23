//
//  ZoteroAPIModels.swift
//  PaperGist
//
//  Codable models for Zotero API responses.
//  Includes helpers for converting API data to local models.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import Foundation

// MARK: - API response models

/// Response structure for Zotero library items
struct ZoteroAPIItem: Codable {
    let key: String
    let version: Int
    let library: Library?
    let data: ItemData

    struct Library: Codable {
        let type: String
        let id: Int
        let name: String
    }

    struct ItemData: Codable {
        let key: String
        let version: Int
        let itemType: String
        let title: String?
        let creators: [Creator]?
        let abstractNote: String?
        let publicationTitle: String?
        let date: String?
        let extra: String?
        let tags: [Tag]?

        // Attachment-specific fields (only present when itemType == "attachment")
        let contentType: String?
        let filename: String?
        let linkMode: String?
        let parentItem: String?

        // Note-specific fields (only present when itemType == "note")
        let note: String?
    }

    struct Creator: Codable {
        let creatorType: String?
        let firstName: String?
        let lastName: String?
        let name: String?
    }

    struct Tag: Codable {
        let tag: String
        let type: Int?
    }
}

struct ZoteroAttachment: Codable {
    let key: String
    let version: Int
    let data: AttachmentData

    struct AttachmentData: Codable {
        let key: String
        let itemType: String
        let linkMode: String
        let title: String
        let contentType: String?
        let filename: String?
    }
}

struct ZoteroNote: Codable {
    let key: String
    let version: Int
    let data: NoteData

    struct NoteData: Codable {
        let key: String
        let itemType: String
        let note: String
        let tags: [ZoteroAPIItem.Tag]?
        let parentItem: String?
    }
}

// MARK: - OAuth models

/// Stored OAuth credentials for Zotero API access
struct ZoteroOAuthCredentials: Codable {
    let accessToken: String
    let accessTokenSecret: String
    let userID: String
    let username: String
}

/// User profile data from Zotero
struct ZoteroUser: Codable {
    let userID: String
    let username: String
    let displayName: String?
}

// MARK: - Helper extensions

extension ZoteroAPIItem {
    /// Converts API response to local ZoteroItem model
    func toZoteroItem(hasAttachment: Bool, hasSummary: Bool) -> ZoteroItem {
        let apiCreators = data.creators ?? []
        let creatorSummary = formatCreators(apiCreators)
        let year = extractYear(from: data.date)

        // Convert API creators to local Creator models
        let localCreators: [PaperGist.Creator] = apiCreators.map { apiCreator in
            PaperGist.Creator(
                creatorType: apiCreator.creatorType ?? "author",
                firstName: apiCreator.firstName,
                lastName: apiCreator.lastName,
                name: apiCreator.name
            )
        }

        // Determine library type
        let libraryType: LibraryType
        if let libType = library?.type {
            libraryType = LibraryType(rawValue: libType) ?? .user
        } else {
            libraryType = .user
        }

        return ZoteroItem(
            key: key,
            title: data.title ?? "Untitled",
            itemType: data.itemType,
            creatorSummary: creatorSummary,
            creators: localCreators,
            year: year,
            publicationTitle: data.publicationTitle,
            hasAttachment: hasAttachment,
            hasSummary: hasSummary,
            libraryID: library?.id.description ?? "unknown",
            libraryType: libraryType,
            version: version
        )
    }

    private func formatCreators(_ creators: [ZoteroAPIItem.Creator]) -> String {
        guard !creators.isEmpty else { return "Unknown" }

        let firstCreator = creators[0]
        let lastName = firstCreator.lastName ?? firstCreator.name ?? "Unknown"

        if creators.count == 1 {
            return lastName
        } else if creators.count == 2 {
            let secondLastName = creators[1].lastName ?? creators[1].name ?? "Unknown"
            return "\(lastName) & \(secondLastName)"
        } else {
            return "\(lastName) et al."
        }
    }

    private func extractYear(from dateString: String?) -> String? {
        guard let dateString = dateString else { return nil }

        let yearPattern = #"(19|20)\d{2}"#
        if let regex = try? NSRegularExpression(pattern: yearPattern),
           let match = regex.firstMatch(in: dateString, range: NSRange(dateString.startIndex..., in: dateString)),
           let range = Range(match.range, in: dateString) {
            return String(dateString[range])
        }

        return nil
    }
}

extension ZoteroNote {
    /// Whether this note has the AI-generated summary tag
    func hasAISummaryTag() -> Bool {
        data.tags?.contains { $0.tag == "#ai-summary" } ?? false
    }
}
