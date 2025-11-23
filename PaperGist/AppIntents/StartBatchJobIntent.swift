//
//  StartBatchJobIntent.swift
//  PaperGist
//
//  App intent for initiating a batch summarisation job for all unsummarised papers.
//
//  Created by Aidan Cornelius-Bell on 18/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppIntents
import SwiftData

/// Starts a batch job to summarise all papers in the library that don't have summaries.
///
/// This intent validates that there are unsummarised papers before opening the app.
/// The actual batch job execution is handled by the app's JobManager after launch.
struct StartBatchJobIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Start batch job"
    nonisolated(unsafe) static var description = IntentDescription("Starts a batch job to summarise all unsummarised papers")

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

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

        // Check how many papers need summarising
        let descriptor = FetchDescriptor<ZoteroItem>(
            predicate: #Predicate { item in
                item.hasSummary == false
            }
        )

        let unsummarisedCount = (try? context.fetchCount(descriptor)) ?? 0

        guard unsummarisedCount > 0 else {
            return .result(
                dialog: "All papers in your library already have summaries"
            )
        }

        // App will be opened and should trigger the batch job
        // See JobManager for actual batch processing logic
        return .result(
            dialog: "Opening PaperGist to start batch job for \(unsummarisedCount) paper(s)"
        )
    }
}
