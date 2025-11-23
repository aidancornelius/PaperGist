//
// SettingsView.swift
// PaperGist
//
// Comprehensive settings screen for account, library, summarisation, and app configuration.
// Manages notifications, tips, custom prompts, and library statistics.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import SwiftData
import StoreKit
import UserNotifications

/// Main settings screen with all app configuration options
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var oauthService: ZoteroOAuthService
    @ObservedObject var libraryViewModel: LibraryViewModel

    @State private var showResetPromptConfirmation = false
    @State private var customPromptText: String = ""
    @State private var showSignOutConfirmation = false
    @State private var showClearLibraryConfirmation = false
    @State private var statistics: LibraryStatistics?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequestingNotifications = false

    // Queries used for live statistics updates
    @Query private var allItems: [ZoteroItem]
    @Query private var allSummaries: [ProcessedItem]
    @Query private var allJobs: [SummaryJob]

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                librarySection
                statisticsSection
                generalSection
                notificationsSection
                summarisationSection
                batchProcessingSection
                supportSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                customPromptText = settings.customPrompt ?? AppSettings.defaultPrompt
                loadStatistics()
                checkNotificationStatus()
            }
            .onChange(of: allItems.count) { _, _ in
                loadStatistics()
            }
            .onChange(of: allSummaries.count) { _, _ in
                loadStatistics()
            }
            .onChange(of: allJobs.count) { _, _ in
                loadStatistics()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // Re-check notification status when app becomes active
                // (in case user changed permissions in iOS Settings)
                if newPhase == .active {
                    checkNotificationStatus()
                }
            }
            // Aggressively refresh statistics every second
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    loadStatistics()
                }
            }
            .confirmationDialog(
                "Delete downloaded attachments?",
                isPresented: $showClearLibraryConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear and re-sync", role: .destructive) {
                    clearLocalLibrary()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all downloaded items and summaries from this device only. Your Zotero library will not be affected. The next sync will download everything again.")
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            if oauthService.isAuthenticated, let user = oauthService.currentUser {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.terracotta)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName ?? user.username)
                                .font(.headlineSourceSans)
                            Text("User ID: \(user.userID)")
                                .font(.captionSourceSans)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button(role: .destructive, action: {
                        showSignOutConfirmation = true
                    }) {
                        Label("Sign out", systemImage: "arrow.right.square")
                            .foregroundStyle(Color.terracotta)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "person.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not signed in")
                            .font(.headlineSourceSans)
                        Text("Sign in to sync your Zotero library")
                            .font(.captionSourceSans)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Account")
                .font(.calloutSourceSans)
        } footer: {
            if oauthService.isAuthenticated {
                Text("Signed in with Zotero account")
                    .font(.captionSourceSans)
            }
        }
        .alert("Sign out of Zotero?", isPresented: $showSignOutConfirmation) {
            Button("Sign out", role: .destructive) {
                oauthService.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to sign in again to sync your library.")
        }
    }

    // MARK: - Library Section

    private var librarySection: some View {
        Section {
            if let stats = statistics {
                if let totalInZotero = settings.totalZoteroItems {
                    HStack {
                        Label("Total in Zotero", systemImage: "cloud")
                            .foregroundStyle(Color.terracotta)
                        Spacer()
                        Text("\(totalInZotero) items")
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                    }
                }

                HStack {
                    Label("Downloaded to app", systemImage: "arrow.down.circle")
                        .foregroundStyle(Color.terracotta)
                    Spacer()
                    Text("\(stats.totalItems) items")
                        .foregroundStyle(.secondary)
                }

                // Show sync progress if currently syncing
                if libraryViewModel.isSyncing, let progress = libraryViewModel.syncProgress {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Sync status", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Color.terracotta)
                            Spacer()
                            if let total = progress.totalItems {
                                Text("\(progress.itemsFetched)/\(total)")
                                    .foregroundStyle(.secondary)
                                    .font(.captionSourceSans)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let total = progress.totalItems {
                                ProgressView(value: Double(progress.itemsFetched), total: Double(total))
                                    .tint(.terracotta)
                            } else {
                                ProgressView()
                                    .tint(.terracotta)
                            }

                            Text(progress.currentPhase)
                                .font(.captionSourceSans)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button(role: .destructive) {
                    showClearLibraryConfirmation = true
                } label: {
                    HStack {
                        Label("Clear local library", systemImage: "trash")
                            .foregroundStyle(Color.terracotta)
                        Spacer()
                    }
                }
                .disabled(libraryViewModel.isSyncing)
            } else {
                HStack {
                    Label("Library items", systemImage: "book.closed")
                        .foregroundStyle(Color.terracotta)
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text("Library")
                .font(.calloutSourceSans)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let totalInZotero = settings.totalZoteroItems, let stats = statistics, totalInZotero > stats.totalItems {
                    Text("Only documents with PDF attachments are downloaded.")
                        .font(.captionSourceSans)
                }
                Text("Syncs items from your Zotero library only. Files stored via WebDAV or Local Zotero file storage are not synced.")
                    .font(.captionSourceSans)
            }
        }
    }

    // MARK: - Statistics Section

    private var statisticsSection: some View {
        Section {
            if let stats = statistics {
                HStack {
                    Label("Summaries generated", systemImage: "doc.text.fill")
                        .foregroundStyle(Color.terracotta)
                    Spacer()
                    Text("\(stats.summariesGenerated)")
                        .foregroundStyle(.secondary)
                        .fontWeight(.semibold)
                }

                HStack {
                    Label("Uploaded to Zotero", systemImage: "cloud.fill")
                        .foregroundStyle(Color.terracotta)
                    Spacer()
                    Text("\(stats.summariesUploaded)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Local only", systemImage: "iphone")
                        .foregroundStyle(Color.terracotta)
                    Spacer()
                    Text("\(stats.summariesLocal)")
                        .foregroundStyle(.secondary)
                }
                if stats.summariesGenerated > 0 && stats.averageConfidence > 0 {
                    HStack {
                        Label("Average confidence", systemImage: "chart.bar")
                            .foregroundStyle(Color.terracotta)
                        Spacer()
                        Text(String(format: "%.1f%%", stats.averageConfidence * 100))
                            .foregroundStyle(.secondary)
                    }
                }
                if stats.totalJobs > 0 {
                    HStack {
                        Label("Batch jobs run", systemImage: "rectangle.stack")
                            .foregroundStyle(Color.terracotta)
                        Spacer()
                        Text("\(stats.totalJobs)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Items processed", systemImage: "checkmark.circle")
                            .foregroundStyle(Color.terracotta)
                        Spacer()
                        Text("\(stats.totalItemsProcessed)")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    Label("Loading statistics...", systemImage: "chart.bar")
                        .foregroundStyle(Color.terracotta)
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text("Statistics")
                .font(.calloutSourceSans)
        } footer: {
            Text("Usage analytics for your library.")
                .font(.captionSourceSans)
        }
    }

    // MARK: - Support Section

    private var supportSection: some View {
        Section {
            Button {
                requestReview()
            } label: {
                Label("Rate PaperGist", systemImage: "star.fill")
                    .foregroundStyle(Color.terracotta)
            }

            TipProductRow(
                productId: "com.papergist.tip.small",
                iconName: "cup.and.saucer",
                title: "Small tip"
            )

            TipProductRow(
                productId: "com.papergist.tip.medium",
                iconName: "mug",
                title: "Medium tip"
            )

            TipProductRow(
                productId: "com.papergist.tip.large",
                iconName: "takeoutbag.and.cup.and.straw",
                title: "Large tip"
            )
        } header: {
            Text("Support development")
                .font(.calloutSourceSans)
        } footer: {
            Text("Tips help support ongoing development and maintenance of PaperGist.")
                .font(.captionSourceSans)
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: notificationStatusIcon)
                        .foregroundStyle(notificationStatusColor)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notification status")
                            .font(.bodySourceSans)
                        Text(notificationStatusText)
                            .font(.captionSourceSans)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)

                // Show button based on status
                if notificationStatus == .notDetermined || notificationStatus == .denied {
                    if notificationStatus == .notDetermined {
                        Button {
                            requestNotificationPermission()
                        } label: {
                            HStack {
                                if isRequestingNotifications {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "bell")
                                }

                                Text(isRequestingNotifications ? "Requesting..." : "Enable notifications")
                                    .font(.bodySourceSans)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.terracotta)
                        .disabled(isRequestingNotifications)
                    } else {
                        // Status is denied - need to open Settings
                        Button {
                            openAppSettings()
                        } label: {
                            HStack {
                                Image(systemName: "gearshape")
                                Text("Open settings")
                                    .font(.bodySourceSans)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.terracotta)
                    }
                }
            }
        } header: {
            Text("Notifications")
                .font(.calloutSourceSans)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if notificationStatus == .authorized {
                    Text("You'll receive notifications when batch summarisations complete.")
                        .font(.captionSourceSans)
                } else if notificationStatus == .denied {
                    Text("Notifications are disabled. To enable them, go to Settings > PaperGist > Notifications.")
                        .font(.captionSourceSans)
                } else {
                    Text("Get notified when batch summarisations complete, even when the app is in the background.")
                        .font(.captionSourceSans)
                }
            }
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        Section {
            Toggle(isOn: $settings.skipItemsWithNotes) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skip items with existing notes")
                        .font(.bodySourceSans)
                    Text("Items with any notes will be skipped during synchronisation")
                        .font(.captionSourceSans)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.terracotta)

            Toggle(isOn: $settings.autoUploadToZotero) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-upload summaries to Zotero")
                        .font(.bodySourceSans)
                    Text("Automatically upload generated summaries as notes")
                        .font(.captionSourceSans)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.terracotta)

            Toggle(isOn: $settings.addAISummaryTag) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add #ai-summary tag")
                        .font(.bodySourceSans)
                    Text("Tag items with #ai-summary after summarisation")
                        .font(.captionSourceSans)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.terracotta)
        } header: {
            Text("General")
                .font(.calloutSourceSans)
        }
    }

    // MARK: - Summarisation Section

    private var summarisationSection: some View {
        Section {
            // Summary length picker
            Picker("Summary length", selection: $settings.summaryLength) {
                ForEach(SummaryLength.allCases) { length in
                    Text(length.displayName).tag(length)
                }
            }
            .tint(.terracotta)

            // Custom prompt toggle and editor
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { settings.customPrompt != nil },
                    set: { isCustom in
                        if isCustom {
                            settings.customPrompt = customPromptText
                        } else {
                            settings.customPrompt = nil
                            customPromptText = AppSettings.defaultPrompt
                        }
                    }
                )) {
                    Text("Use custom prompt")
                }
                .tint(.terracotta)

                if settings.customPrompt != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom prompt")
                            .font(.captionSourceSans)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $customPromptText)
                            .frame(minHeight: 200)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .onChange(of: customPromptText) { oldValue, newValue in
                                settings.customPrompt = newValue
                            }

                        HStack {
                            Text("\(customPromptText.count) characters")
                                .font(.caption2SourceSans)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Reset to default") {
                                showResetPromptConfirmation = true
                            }
                            .font(.captionSourceSans)
                            .foregroundStyle(Color.terracotta)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            // Info about default prompt
            if settings.customPrompt == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Using default prompt")
                        .font(.captionSourceSans)
                        .foregroundStyle(.secondary)
                    Text("The default prompt focuses on research questions, methodology, key findings, and conclusions.")
                        .font(.captionSourceSans)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Summarisation")
                .font(.calloutSourceSans)
        } footer: {
            if settings.summaryLength != .medium {
                Text("Custom summary length: \(settings.summaryLength.wordCount).")
                    .font(.captionSourceSans)
            }
        }
        .confirmationDialog(
            "Reset prompt to default?",
            isPresented: $showResetPromptConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset to default", role: .destructive) {
                settings.resetToDefaultPrompt()
                customPromptText = AppSettings.defaultPrompt
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will discard your custom prompt and restore the default prompt.")
        }
    }

    // MARK: - Batch Processing Section

    private var batchProcessingSection: some View {
        Section {
            HStack {
                Text("Batch size")
                Spacer()
                Stepper("\(settings.batchSize)", value: $settings.batchSize, in: 1...50)
                    .labelsHidden()
                Text("\(settings.batchSize)")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 30, alignment: .trailing)
            }

            Toggle(isOn: $settings.backgroundSyncEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Background synchronisation")
                        .font(.bodySourceSans)
                    Text("Allow library and summary sync in background")
                        .font(.captionSourceSans)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.terracotta)
            .onChange(of: settings.backgroundSyncEnabled) { oldValue, newValue in
                // Schedule or cancel background tasks based on setting
                if newValue {
                    Task {
                        await BackgroundTaskManager.shared.scheduleBackgroundTask()
                    }
                } else {
                    BackgroundTaskManager.shared.cancelScheduledTasks()
                }
            }
        } header: {
            Text("Batch processing")
                .font(.calloutSourceSans)
        } footer: {
            Text("Batch size controls how many items are processed at once. Lower values reduce memory usage but may take longer.")
                .font(.captionSourceSans)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            Text("PaperGist made with ❤︎ on Kaurna Country by Aidan Cornelius-Bell.")
                .font(.captionSourceSans)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } header: {
            Text("About")
                .font(.calloutSourceSans)
        }
    }

    // MARK: - Notification Helpers

    private var notificationStatusIcon: String {
        switch notificationStatus {
        case .authorized:
            return "bell.badge.fill"
        case .denied:
            return "bell.slash.fill"
        case .notDetermined:
            return "bell.badge"
        case .provisional, .ephemeral:
            return "bell.badge"
        @unknown default:
            return "bell.badge"
        }
    }

    private var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized:
            return .terracotta
        case .denied:
            return .red
        case .notDetermined:
            return .terracotta
        case .provisional, .ephemeral:
            return .terracotta
        @unknown default:
            return .gray
        }
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized:
            return "Enabled"
        case .denied:
            return "Disabled"
        case .notDetermined:
            return "Not enabled"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }

    private func checkNotificationStatus() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            await MainActor.run {
                notificationStatus = settings.authorizationStatus
            }
        }
    }

    private func requestNotificationPermission() {
        isRequestingNotifications = true

        Task {
            await NotificationManager.shared.requestAuthorisation()
            // Re-check status after request
            await checkNotificationStatus()
            await MainActor.run {
                isRequestingNotifications = false
            }
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func loadStatistics() {
        Task {
            let stats = await calculateStatistics()
            await MainActor.run {
                self.statistics = stats
            }
        }
    }

    private func calculateStatistics() async -> LibraryStatistics {
        await MainActor.run {
            // Fetch library items
            let itemDescriptor = FetchDescriptor<ZoteroItem>()
            let items = (try? modelContext.fetch(itemDescriptor)) ?? []

            let userLibraryCount = items.filter { $0.libraryType == .user }.count
            let groupLibraryCount = items.filter { $0.libraryType == .group }.count

            // Fetch processed items (summaries)
            let summaryDescriptor = FetchDescriptor<ProcessedItem>()
            let summaries = (try? modelContext.fetch(summaryDescriptor)) ?? []

            let summariesGenerated = summaries.count
            let summariesUploaded = summaries.filter { $0.status == .uploaded }.count
            let summariesLocal = summaries.filter { $0.status == .local }.count

            // Calculate average confidence
            let summariesWithConfidence = summaries.filter { $0.confidence != nil }
            let averageConfidence: Double
            if summariesWithConfidence.isEmpty {
                averageConfidence = 0.0
            } else {
                let totalConfidence = summariesWithConfidence.reduce(0.0) { $0 + ($1.confidence ?? 0.0) }
                averageConfidence = totalConfidence / Double(summariesWithConfidence.count)
            }

            // Fetch batch jobs
            let jobDescriptor = FetchDescriptor<SummaryJob>()
            let jobs = (try? modelContext.fetch(jobDescriptor)) ?? []

            let totalJobs = jobs.count
            let totalItemsProcessed = jobs.reduce(0) { $0 + $1.processedItems }

            return LibraryStatistics(
                totalItems: items.count,
                userLibraryCount: userLibraryCount,
                groupLibraryCount: groupLibraryCount,
                summariesGenerated: summariesGenerated,
                summariesUploaded: summariesUploaded,
                summariesLocal: summariesLocal,
                averageConfidence: averageConfidence,
                totalJobs: totalJobs,
                totalItemsProcessed: totalItemsProcessed
            )
        }
    }

    private func requestReview() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            AppStore.requestReview(in: windowScene)
        }
    }

    private func clearLocalLibrary() {
        // Delete all ZoteroItems
        let itemDescriptor = FetchDescriptor<ZoteroItem>()
        if let items = try? modelContext.fetch(itemDescriptor) {
            for item in items {
                modelContext.delete(item)
            }
        }

        // Delete all ProcessedItems (summaries)
        let summaryDescriptor = FetchDescriptor<ProcessedItem>()
        if let summaries = try? modelContext.fetch(summaryDescriptor) {
            for summary in summaries {
                modelContext.delete(summary)
            }
        }

        // Delete all SummaryJobs
        let jobDescriptor = FetchDescriptor<SummaryJob>()
        if let jobs = try? modelContext.fetch(jobDescriptor) {
            for job in jobs {
                modelContext.delete(job)
            }
        }

        // Save changes
        try? modelContext.save()

        // Refresh statistics
        loadStatistics()

        // Trigger a new sync
        Task {
            await libraryViewModel.fetchLibrary(force: true)
        }
    }
}

// MARK: - Supporting Types

/// Aggregated statistics about library and summarisation usage
struct LibraryStatistics {
    let totalItems: Int
    let userLibraryCount: Int
    let groupLibraryCount: Int
    let summariesGenerated: Int
    let summariesUploaded: Int
    let summariesLocal: Int
    let averageConfidence: Double
    let totalJobs: Int
    let totalItemsProcessed: Int
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ZoteroItem.self, ProcessedItem.self, SummaryJob.self, configurations: config)
    let context = ModelContext(container)
    let zoteroService = ZoteroService(oauthService: ZoteroOAuthService())
    let vm = LibraryViewModel(zoteroService: zoteroService, modelContext: context)

    return SettingsView(oauthService: ZoteroOAuthService(), libraryViewModel: vm)
        .modelContainer(container)
}
