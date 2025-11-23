//
//  OpenLibraryItemIntent.swift
//  PaperGist
//
//  App intent for opening the app and navigating to a specific library item.
//
//  Created by Aidan Cornelius-Bell on 18/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppIntents
import SwiftData

/// Opens PaperGist and navigates to a specific library item by its Zotero key.
///
/// Validates that the item exists before launching the app. The app is responsible
/// for handling the actual navigation once opened (potentially via URL scheme).
struct OpenLibraryItemIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Open library item"
    nonisolated(unsafe) static var description = IntentDescription("Opens PaperGist to a specific library item by ID")

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(title: "Item ID", description: "The Zotero item key/ID to open")
    var itemID: String

    init() {
        self.itemID = ""
    }

    init(itemID: String) {
        self.itemID = itemID
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Open item \(\.$itemID)")
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

        let descriptor = FetchDescriptor<ZoteroItem>(
            predicate: #Predicate { item in
                item.key == itemID
            }
        )

        guard let items = try? context.fetch(descriptor),
              let item = items.first else {
            struct NotFoundError: Error {
                let message: String
            }
            throw NotFoundError(message: "Item not found: \(itemID)")
        }

        // App opens automatically due to openAppWhenRun = true
        // Navigation to the specific item can be handled via URL scheme or app state
        return .result(
            dialog: "Opening \(item.title) in PaperGist"
        )
    }
}
