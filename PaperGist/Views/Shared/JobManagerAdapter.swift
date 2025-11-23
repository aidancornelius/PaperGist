//
// JobManagerAdapter.swift
// PaperGist
//
// Adapter that wraps JobManager to conform to the JobManaging protocol.
// Bridges between JobProgressView and the concrete JobManager implementation.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import OSLog

/// Adapts JobManager to JobManaging protocol for use in views
@MainActor
class JobManagerAdapter: JobManaging {
    private let manager: PaperGist.JobManager

    init(manager: PaperGist.JobManager) {
        self.manager = manager
    }

    func pauseJob(_ job: SummaryJob) {
        Task { @MainActor in
            await manager.pauseJob(job)
        }
    }

    func resumeJob(_ job: SummaryJob) {
        Task { @MainActor in
            try? await manager.resumeJob(job)
        }
    }

    func cancelJob(_ job: SummaryJob) {
        Task { @MainActor in
            await manager.cancelJob(job)
        }
    }

    func retryFailedItems(_ job: SummaryJob) {
        Task { @MainActor in
            do {
                try await manager.retryFailedItems(job)
            } catch {
                AppLogger.jobs.error("Failed to retry failed items: \(error.localizedDescription)")
            }
        }
    }
}
