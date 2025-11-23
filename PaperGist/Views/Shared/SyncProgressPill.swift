//
// SyncProgressPill.swift
// PaperGist
//
// Floating progress indicator shown during library synchronisation.
// Supports compact (iPad) and detailed (iPhone) display styles.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// Floating pill showing sync progress with adaptive styling
struct SyncProgressPill: View {
    let progress: SyncProgress
    let style: Style

    enum Style {
        case compact  // iPad version
        case detailed // iPhone version
    }

    var body: some View {
        Group {
            switch style {
            case .compact:
                compactStyle
            case .detailed:
                detailedStyle
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private var compactStyle: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(progress.currentPhase)
                    .font(.subheadlineMediumSourceSans)
                    .lineLimit(1)

                if progress.itemsFetched > 0 {
                    Text("\(progress.itemsFetched) fetched, \(progress.itemsProcessed) processed")
                        .font(.captionSourceSans)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var detailedStyle: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(progress.currentPhase)
                            .font(.subheadlineMediumSourceSans)
                            .lineLimit(1)

                        Spacer()

                        if let total = progress.totalItems {
                            Text("\(progress.itemsFetched)/\(total)")
                                .font(.captionSourceSans)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    if let total = progress.totalItems {
                        ProgressView(value: Double(progress.itemsFetched), total: Double(total))
                            .progressViewStyle(.linear)
                            .tint(.terracotta)
                    }
                }
            }
        }
    }
}
