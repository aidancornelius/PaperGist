//
//  PaperGistAppIntents.swift
//  PaperGist
//
//  Defines the app shortcuts available to Siri and iOS system integration.
//
//  Created by Aidan Cornelius-Bell on 18/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppIntents

/// Provides app shortcuts for Siri and system integration.
///
/// Defines natural language phrases that users can speak to trigger intents,
/// making PaperGist's core functionality accessible via voice commands and shortcuts.
struct PaperGistAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Search and retrieve library items by ID or title
        AppShortcut(
            intent: GetLibraryItemsIntent(),
            phrases: [
                "Get my \(.applicationName) library items",
                "Show papers in \(.applicationName)",
                "Search \(.applicationName) library"
            ],
            shortTitle: "Get library items",
            systemImageName: "books.vertical"
        )

        // Navigate directly to a specific item in the app
        AppShortcut(
            intent: OpenLibraryItemIntent(),
            phrases: [
                "Open item in \(.applicationName)",
                "Show library item in \(.applicationName)"
            ],
            shortTitle: "Open library item",
            systemImageName: "arrow.up.forward.app"
        )

        // Trigger summarisation for specific items
        AppShortcut(
            intent: SummariseItemsIntent(),
            phrases: [
                "Summarise papers in \(.applicationName)",
                "Summarise items in \(.applicationName)"
            ],
            shortTitle: "Summarise items",
            systemImageName: "sparkles"
        )

        // Start a batch job to process all unsummarised papers
        AppShortcut(
            intent: StartBatchJobIntent(),
            phrases: [
                "Start batch job in \(.applicationName)",
                "Summarise all papers in \(.applicationName)",
                "Process all unsummarised papers in \(.applicationName)"
            ],
            shortTitle: "Start batch job",
            systemImageName: "square.stack.3d.up"
        )
    }
}
