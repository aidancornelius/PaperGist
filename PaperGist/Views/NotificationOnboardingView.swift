//
// NotificationOnboardingView.swift
// PaperGist
//
// Onboarding screen shown after first authentication to request notification permissions.
// Explains benefits of notifications for batch job completion alerts.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// Post-authentication onboarding for notification permissions
struct NotificationOnboardingView: View {
    let onComplete: () -> Void

    @State private var isRequestingPermission = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    Spacer()
                        .frame(height: 20)

                    // Icon
                    Image(systemName: "bell.badge")
                        .font(.system(size: 80))
                        .foregroundStyle(Color.terracotta)
                        .padding(.bottom, 8)

                    VStack(spacing: 20) {
                        Text("Stay updated on your summaries")
                            .font(.largeTitleSourceSans)
                            .multilineTextAlignment(.center)

                        Text("PaperGist can notify you when batch summarisations complete")
                            .font(.title2SourceSans)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        VStack(alignment: .leading, spacing: 20) {
                            NotificationFeatureRow(
                                icon: "checkmark.circle",
                                title: "Know when jobs finish",
                                description: "Get notified when batch summarisation completes, even if the app is in the background"
                            )

                            NotificationFeatureRow(
                                icon: "clock",
                                title: "Save time",
                                description: "No need to keep checking back, the app will let you know when your summaries are ready"
                            )

                            NotificationFeatureRow(
                                icon: "hand.raised",
                                title: "You're in control",
                                description: "You can change notification settings at any time in iOS Settings"
                            )
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    }

                    VStack(spacing: 16) {
                        Button {
                            requestNotifications()
                        } label: {
                            HStack {
                                if isRequestingPermission {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "bell")
                                }

                                Text(isRequestingPermission ? "Requesting..." : "Enable notifications")
                                    .font(.bodySourceSans)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.terracotta)
                        .disabled(isRequestingPermission)
                        .controlSize(.large)

                        Button {
                            onComplete()
                        } label: {
                            Text("Not now")
                                .font(.bodySourceSans)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                        .frame(height: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
    }

    private func requestNotifications() {
        isRequestingPermission = true

        Task {
            await NotificationManager.shared.requestAuthorisation()
            isRequestingPermission = false
            onComplete()
        }
    }
}

// MARK: - Notification Feature Row Component

/// Feature row explaining notification benefits
struct NotificationFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.terracotta)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadlineMediumSourceSans)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadlineSourceSans)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NotificationOnboardingView(onComplete: {})
}
