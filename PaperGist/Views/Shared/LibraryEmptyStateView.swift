//
// LibraryEmptyStateView.swift
// PaperGist
//
// Empty state view shown when library has no items or search returns no results.
// Provides contextual messaging and sync action.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// Empty state for library with no items or no search results
struct LibraryEmptyStateView: View {
    let viewModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: viewModel.searchText.isEmpty ? "doc.text.magnifyingglass" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(viewModel.searchText.isEmpty ? "No papers found" : "No matching papers")
                .font(.titleSourceSans)

            Text(viewModel.searchText.isEmpty
                ? "Sync your library from Zotero to get started"
                : "Try a different search term")
                .font(.subheadlineSourceSans)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if viewModel.searchText.isEmpty && !viewModel.isSyncing {
                Button("Sync library") {
                    Task {
                        await viewModel.fetchLibrary(force: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.terracotta)
            }
        }
        .padding()
    }
}
