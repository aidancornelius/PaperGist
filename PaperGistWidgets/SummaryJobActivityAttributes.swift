//
//  SummaryJobActivityAttributes.swift
//  PaperGist
//
//  Activity attributes and content state for batch job Live Activities.
//  Defines the static attributes and dynamic state that updates during
//  the job's lifetime.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import ActivityKit

/// Activity attributes for Live Activities displaying batch job progress.
/// The static attributes never change; ContentState is updated as work progresses.
struct SummaryJobActivityAttributes: ActivityAttributes {
    /// Dynamic content state that updates as the job progresses.
    /// Updated via ActivityKit as each item is processed.
    public struct ContentState: Codable, Hashable {
        /// Total number of items to process in the batch
        var totalItems: Int

        /// Number of items that have been processed so far
        var processedItems: Int

        /// Number of items that failed during processing
        var failedItems: Int

        /// Title of the item currently being processed
        var currentItemTitle: String

        /// Current job status: processing, completed, failed, cancelled, or paused
        var status: String

        /// Optional progress message shown to user
        var progressMessage: String?

        /// Progress percentage from 0 to 100
        var progressPercentage: Int {
            guard totalItems > 0 else { return 0 }
            return Int((Double(processedItems) / Double(totalItems)) * 100)
        }

        /// Number of successfully processed items
        var successfulItems: Int {
            processedItems - failedItems
        }

        /// Whether the job is currently active
        var isActive: Bool {
            status == "processing"
        }

        /// Whether the job has finished (completed, failed, or cancelled)
        var isFinished: Bool {
            status == "completed" || status == "failed" || status == "cancelled"
        }
    }

    // MARK: - Static Attributes

    /// Unique identifier for this batch job.
    /// Never changes during the Live Activity's lifetime.
    var jobID: String

    /// Display name shown to user
    var jobName: String
}

// MARK: - Convenience Initializers

extension SummaryJobActivityAttributes.ContentState {
    /// Creates initial state when starting a job
    static func initial(totalItems: Int) -> Self {
        SummaryJobActivityAttributes.ContentState(
            totalItems: totalItems,
            processedItems: 0,
            failedItems: 0,
            currentItemTitle: "Starting...",
            status: "processing",
            progressMessage: "Initialising batch job..."
        )
    }

    /// Creates completed state
    static func completed(totalItems: Int, successfulItems: Int, failedItems: Int) -> Self {
        SummaryJobActivityAttributes.ContentState(
            totalItems: totalItems,
            processedItems: totalItems,
            failedItems: failedItems,
            currentItemTitle: "All items processed",
            status: "completed",
            progressMessage: failedItems > 0
                ? "Completed with \(successfulItems) succeeded, \(failedItems) failed"
                : "All items processed successfully"
        )
    }

    /// Creates failed state
    static func failed(totalItems: Int, processedItems: Int, failedItems: Int, error: String) -> Self {
        SummaryJobActivityAttributes.ContentState(
            totalItems: totalItems,
            processedItems: processedItems,
            failedItems: failedItems,
            currentItemTitle: "Job failed",
            status: "failed",
            progressMessage: error
        )
    }

    /// Creates cancelled state
    static func cancelled(totalItems: Int, processedItems: Int, failedItems: Int) -> Self {
        SummaryJobActivityAttributes.ContentState(
            totalItems: totalItems,
            processedItems: processedItems,
            failedItems: failedItems,
            currentItemTitle: "Job cancelled",
            status: "cancelled",
            progressMessage: "Cancelled by user"
        )
    }
}
