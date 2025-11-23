//
//  SummariseItemsIntent.swift
//  PaperGist
//
//  App intent for triggering AI summarisation of specific library items by ID.
//
//  Created by Aidan Cornelius-Bell on 18/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppIntents
import SwiftData

/// Triggers summarisation for specific papers identified by their Zotero item keys.
///
/// Accepts a comma-separated list of item IDs, validates they exist in the database,
/// filters out papers that already have summaries, and opens the app to begin
/// the summarisation process for the remaining items.
struct SummariseItemsIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Summarise items"
    nonisolated(unsafe) static var description = IntentDescription("Triggers AI summarisation for specific items by ID")

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(title: "Item IDs", description: "Comma-separated Zotero item keys/IDs")
    var itemIDs: String

    init() {
        self.itemIDs = ""
    }

    init(itemIDs: String) {
        self.itemIDs = itemIDs
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Summarise items \(\.$itemIDs)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
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

        // Parse and clean the comma-separated IDs
        let ids = itemIDs.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }

        guard !ids.isEmpty else {
            struct InvalidInputError: Error {
                let message: String
            }
            throw InvalidInputError(message: "No item IDs provided")
        }

        // Look up each item in the database
        var foundItems: [ZoteroItem] = []
        for id in ids {
            let descriptor = FetchDescriptor<ZoteroItem>(
                predicate: #Predicate { item in
                    item.key == id
                }
            )

            if let items = try? context.fetch(descriptor), let item = items.first {
                foundItems.append(item)
            }
        }

        guard !foundItems.isEmpty else {
            struct NotFoundError: Error {
                let message: String
            }
            throw NotFoundError(message: "No items found with provided IDs")
        }

        // Only process items that don't already have summaries
        let unsummarisedItems = foundItems.filter { !$0.hasSummary }

        if unsummarisedItems.isEmpty {
            return .result(
                dialog: "All \(foundItems.count) item(s) already have summaries"
            )
        }

        // App will handle the actual summarisation process
        // See SummarisationService for the AI processing logic
        return .result(
            dialog: "Opening PaperGist to summarise \(unsummarisedItems.count) item(s)"
        )
    }
}
