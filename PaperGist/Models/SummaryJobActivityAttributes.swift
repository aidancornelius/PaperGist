//
//  SummaryJobActivityAttributes.swift
//  PaperGist
//
//  Live Activity attributes for displaying batch job progress.
//  Used by ActivityKit to show real-time updates on the Lock Screen and Dynamic Island.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import Foundation
import ActivityKit

/// Live Activity data for batch summarisation jobs
struct SummaryJobActivityAttributes: ActivityAttributes {
    /// Dynamic state updated as the job progresses
    public struct ContentState: Codable, Hashable {
        var totalItems: Int
        var processedItems: Int
        var failedItems: Int
        var currentItemTitle: String
        var status: String
        var progressMessage: String?

        /// Progress as percentage (0-100)
        var progressPercentage: Int {
            guard totalItems > 0 else { return 0 }
            return Int((Double(processedItems) / Double(totalItems)) * 100)
        }

        /// Items processed without errors
        var successfulItems: Int {
            processedItems - failedItems
        }

        var isActive: Bool {
            status == "processing"
        }

        var isFinished: Bool {
            status == "completed" || status == "failed" || status == "cancelled"
        }
    }

    // MARK: - Static attributes

    var jobID: String
    var jobName: String
}

// MARK: - Convenience initialisers

extension SummaryJobActivityAttributes.ContentState {
    /// Initial state for a new job
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

    /// Completion state with success/failure counts
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

    /// Failed state with error message
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

    /// User-cancelled state
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
