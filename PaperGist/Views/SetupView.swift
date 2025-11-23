//
// SetupView.swift
// PaperGist
//
// Initial setup and onboarding screen shown to unauthenticated users.
// Explains app features and initiates Zotero OAuth flow.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// Welcome and authentication screen for new users
struct SetupView: View {
    @ObservedObject var oauthService: ZoteroOAuthService

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var showAppleIntelligenceWarning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    Spacer()
                        .frame(height: 20)

                    // App icon/logo placeholder
                    Image(systemName: "text.line.3.summary")
                        .font(.system(size: 80))
                        .foregroundStyle(Color.terracotta)
                        .padding(.bottom, 8)

                    VStack(spacing: 20) {
                        Text("Welcome to PaperGist")
                            .font(.largeTitleSourceSans)

                        Text("AI-powered summaries for your research library")
                            .font(.title2SourceSans)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        VStack(alignment: .leading, spacing: 20) {
                            FeatureRow(
                                icon: "sparkles",
                                title: "Intelligent summaries",
                                description: "Automatically summarise research papers using on-device Apple Intelligence"
                            )

                            FeatureRow(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Seamless Zotero sync",
                                description: "Download PDFs, generate summaries, and sync them back to your Zotero library"
                            )

                            FeatureRow(
                                icon: "lock.shield",
                                title: "Private and secure",
                                description: "All processing happens on your device. No data is sent to third parties."
                            )
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)

                        // Privacy policy link
                        Link(destination: URL(string: "https://aidan.cornelius-bell.com/privacy-policy/apps/")!) {
                            HStack(spacing: 4) {
                                Text("Privacy policy")
                                    .font(.captionSourceSans)
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption2)
                            }
                            .foregroundStyle(Color.terracotta)
                        }
                        .padding(.top, 8)
                    }

                    VStack(spacing: 20) {
                        // Apple Intelligence availability warning
                        if !AIService.isAppleIntelligenceAvailable() {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .imageScale(.large)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Apple Intelligence unavailable")
                                        .font(.subheadlineSourceSans)
                                        .fontWeight(.semibold)

                                    Text("This app requires iOS 26 or later on an iPhone 16 Pro or newer to function.")
                                        .font(.caption2SourceSans)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            authenticate()
                        } label: {
                            HStack {
                                if isAuthenticating {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "person.badge.key")
                                }

                                Text(isAuthenticating ? "Connecting..." : "Connect to Zotero")
                                    .font(.bodySourceSans)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.terracotta)
                        .disabled(isAuthenticating)
                        .controlSize(.large)

                        Text("You'll be redirected to Zotero to authorise PaperGist")
                            .font(.captionSourceSans)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                        .frame(height: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .alert("Authentication error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    private func authenticate() {
        isAuthenticating = true
        errorMessage = nil

        Task {
            do {
                try await oauthService.authenticate()
            } catch {
                errorMessage = error.localizedDescription
            }

            isAuthenticating = false
        }
    }
}

// MARK: - Feature Row Component

/// Reusable row for displaying app features during onboarding
struct FeatureRow: View {
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
    SetupView(oauthService: ZoteroOAuthService())
}
