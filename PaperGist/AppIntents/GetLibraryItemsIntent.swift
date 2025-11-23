//
//  GetLibraryItemsIntent.swift
//  PaperGist
//
//  App intent for retrieving Zotero library items by ID or title search.
//  Returns formatted results without opening the app.
//
//  Created by Aidan Cornelius-Bell on 18/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppIntents
import SwiftData

/// Retrieves library items by ID or title search from the local SwiftData store.
///
/// Supports three search modes:
/// - Search by Zotero item key (itemID)
/// - Search by title using case-insensitive substring matching
/// - Return recently checked items (default, limited to 10)
///
/// Results include item metadata and summary status.
struct GetLibraryItemsIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Get library items"
    nonisolated(unsafe) static var description = IntentDescription("Gets library items by ID or name search")

    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Item ID", description: "The Zotero item key/ID")
    var itemID: String?

    @Parameter(title: "Search name", description: "Search for items by title")
    var searchName: String?

    init() {}

    init(itemID: String? = nil, searchName: String? = nil) {
        self.itemID = itemID
        self.searchName = searchName
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Get library items") {
            \.$itemID
            \.$searchName
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let container = try? ModelContainer(
            for: ZoteroItem.self, ProcessedItem.self, SummaryJob.self, ItemSummaryJob.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        ) else {
            struct DatabaseError: Error {
                let message: String
            }
            throw DatabaseError(message: "Failed to access database")
        }

        let context = ModelContext(container)
        var items: [ZoteroItem] = []

        // Priority: ID search > title search > recent items
        if let itemID = itemID, !itemID.isEmpty {
            let descriptor = FetchDescriptor<ZoteroItem>(
                predicate: #Predicate { item in
                    item.key == itemID
                }
            )
            items = (try? context.fetch(descriptor)) ?? []
        }
        else if let searchName = searchName, !searchName.isEmpty {
            let searchTerm = searchName
            let descriptor = FetchDescriptor<ZoteroItem>(
                predicate: #Predicate { item in
                    item.title.localizedStandardContains(searchTerm)
                }
            )
            items = (try? context.fetch(descriptor)) ?? []
        }
        else {
            // Return recently synced items when no parameters provided
            let descriptor = FetchDescriptor<ZoteroItem>(
                sortBy: [SortDescriptor<ZoteroItem>(\.lastChecked, order: .reverse)]
            )
            items = (try? context.fetch(descriptor))?.prefix(10).map { $0 } ?? []
        }

        guard !items.isEmpty else {
            struct NotFoundError: Error {
                let message: String
            }
            throw NotFoundError(message: "No items found")
        }

        // Format each item with key, title, authors, year, and summary status
        let result = items.map { item in
            var info = "[\(item.key)] \(item.title)"
            if !item.creators.isEmpty {
                info += " - \(item.creators)"
            }
            if let year = item.year {
                info += " (\(year))"
            }
            info += " - Summary: \(item.hasSummary ? "Yes" : "No")"
            return info
        }.joined(separator: "\n\n")

        return .result(
            value: result,
            dialog: "Found \(items.count) item(s)"
        )
    }
}
