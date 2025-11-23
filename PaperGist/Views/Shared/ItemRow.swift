//
// ItemRow.swift
// PaperGist
//
// Reusable list row for displaying library item metadata.
// Shows title, authors, publication, and summary status icon.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// List row displaying a library item's key information
struct ItemRow: View {
    let item: ZoteroItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status icon
            Image(systemName: item.statusIcon)
                .font(.system(size: 20))
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(item.title)
                    .font(.bodyMediumSourceSans)
                    .lineLimit(2)

                // Authors and year
                Text(item.citation)
                    .font(.subheadlineSourceSans)
                    .foregroundStyle(.secondary)

                // Journal/Publication
                if let publication = item.publicationTitle {
                    Text(publication)
                        .font(.captionSourceSans)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.terracotta)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch item.statusIcon {
        case "checkmark.circle.fill":
            return .green
        case "exclamationmark.triangle.fill":
            return .orange
        default:
            return .gray
        }
    }
}
