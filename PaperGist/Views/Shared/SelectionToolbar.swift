//
// SelectionToolbar.swift
// PaperGist
//
// Toolbar shown during multi-select mode for batch operations.
// Displays selection count and provides select/deselect/summarise actions.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// Toolbar for multi-selection and batch summarisation actions
struct SelectionToolbar: View {
    let selectedCount: Int
    let totalCount: Int
    let eligibleCount: Int
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onSummariseSelected: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Row 1: Selection controls
            HStack {
                if selectedCount == 0 {
                    Text("No items selected")
                        .font(.subheadlineSourceSans)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(selectedCount) selected")
                        .font(.subheadlineSourceSans)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onSelectAll()
                } label: {
                    Text("Select all")
                }
                .buttonStyle(.bordered)
                .disabled(selectedCount == totalCount)

                Button {
                    onDeselectAll()
                } label: {
                    Text("Deselect all")
                }
                .buttonStyle(.bordered)
                .disabled(selectedCount == 0)
            }

            // Row 2: Action button
            if selectedCount > 0 {
                Button {
                    onSummariseSelected()
                } label: {
                    Label("Summarise selected (\(eligibleCount))", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.terracotta)
                .disabled(eligibleCount == 0)
                .controlSize(.large)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
}
