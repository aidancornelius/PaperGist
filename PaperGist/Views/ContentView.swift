//
// ContentView.swift
// PaperGist
//
// Root view that manages authentication state and layout.
// Shows setup screen for unauthenticated users, and library view for authenticated users.
// Handles iPad split view vs iPhone single-column layout.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import SwiftData
import Combine

/// Root view that adapts to authentication state and device layout
struct ContentView: View {
    @StateObject private var oauthService = ZoteroOAuthService()
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showNotificationOnboarding = false

    var body: some View {
        Group {
            if oauthService.isAuthenticated {
                if horizontalSizeClass == .regular {
                    // iPad split view layout
                    SplitViewContainer(oauthService: oauthService)
                } else {
                    // iPhone single-column layout
                    LibraryView(oauthService: oauthService)
                }
            } else {
                SetupView(oauthService: oauthService)
            }
        }
        .onChange(of: oauthService.isAuthenticated) { oldValue, newValue in
            // When user successfully authenticates, check if they need to see notification onboarding
            if !oldValue && newValue && !appSettings.hasSeenNotificationOnboarding {
                showNotificationOnboarding = true
            }
        }
        .sheet(isPresented: $showNotificationOnboarding) {
            NotificationOnboardingView {
                appSettings.hasSeenNotificationOnboarding = true
                showNotificationOnboarding = false
            }
        }
    }
}

// MARK: - Split View Container for iPad

/// Split view layout for iPad with sidebar library and detail pane
struct SplitViewContainer: View {
    @ObservedObject var oauthService: ZoteroOAuthService
    @State private var selectedItemKey: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar: Library list
            LibrarySidebarView(
                oauthService: oauthService,
                selectedItemKey: $selectedItemKey
            )
        } detail: {
            // Detail: Item detail view or placeholder
            if let itemKey = selectedItemKey {
                ItemDetailContainer(
                    itemKey: itemKey,
                    oauthService: oauthService
                )
            } else {
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Select a paper")
                .font(.titleSourceSans)

            Text("Choose a paper from your library to view details and summaries")
                .font(.subheadlineSourceSans)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Library Sidebar View

/// Sidebar view for iPad split view showing library list and controls
struct LibrarySidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var oauthService: ZoteroOAuthService
    @Binding var selectedItemKey: String?

    @StateObject private var viewModel: LibraryViewModelWrapper
    @State private var selectedItems = Set<String>()
    @State private var isSelectionMode = false
    @State private var showSettings = false
    @State private var showJobProgress = false
    @State private var currentJob: SummaryJob?
    @State private var jobManager: JobManager?
    @State private var showSummariseAllConfirmation = false
    @State private var showAppleIntelligenceUnavailableAlert = false
    @Environment(\.scenePhase) private var scenePhase

    init(oauthService: ZoteroOAuthService, selectedItemKey: Binding<String?>) {
        self.oauthService = oauthService
        self._selectedItemKey = selectedItemKey
        _viewModel = StateObject(wrappedValue: LibraryViewModelWrapper())
    }

    var body: some View {
        Group {
            if let vm = viewModel.vm {
                if vm.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(vm.loadingMessage)
                            .font(.subheadlineSourceSans)
                            .foregroundStyle(.secondary)
                    }
                } else if vm.items.isEmpty && !vm.isSyncing {
                    emptyState(vm: vm)
                } else {
                    itemListContent(vm: vm)
                }
            } else {
                ProgressView("Initialising...")
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let vm = viewModel.vm, !vm.items.isEmpty {
                    Button(isSelectionMode ? "Cancel" : "Select") {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedItems.removeAll()
                        }
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Color.terracotta)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task {
                            await viewModel.vm?.fetchLibrary(force: true)
                        }
                    } label: {
                        Label("Refresh library", systemImage: "arrow.clockwise")
                            .font(.bodySourceSans)
                    }
                    .disabled(viewModel.vm?.isSyncing ?? true)

                    Button {
                        showSummariseAllConfirmation = true
                    } label: {
                        Label("Summarise all unsummarised (\(viewModel.vm?.unsummarisedCount ?? 0))", systemImage: "sparkles")
                            .font(.bodySourceSans)
                    }
                    .disabled((viewModel.vm?.unsummarisedCount ?? 0) == 0 || !(viewModel.vm?.hasCompletedFullSync ?? false))

                    Divider()

                    Button(role: .destructive) {
                        oauthService.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.bodySourceSans)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.terracotta)
                }
            }
        }
        .searchable(text: .init(
            get: { viewModel.vm?.searchText ?? "" },
            set: { viewModel.vm?.updateSearch($0) }
        ), prompt: "Search papers")
        .safeAreaInset(edge: .top, spacing: 0) {
            // Floating sync progress pill
            if let vm = viewModel.vm, vm.isSyncing, let progress = vm.syncProgress {
                syncProgressPill(progress: progress)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.vm?.errorMessage != nil },
            set: { if !$0 { viewModel.vm?.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.vm?.errorMessage = nil
            }
        } message: {
            if let error = viewModel.vm?.errorMessage {
                Text(error)
            }
        }
        .onAppear {
            if viewModel.vm == nil {
                let zoteroService = ZoteroService(oauthService: oauthService)
                viewModel.vm = LibraryViewModel(zoteroService: zoteroService, modelContext: modelContext)

                // Initialize JobManager
                let summarisationService = SummarisationService(
                    zoteroService: zoteroService,
                    modelContext: modelContext
                )
                Task { @MainActor in
                    let manager = JobManager(
                        modelContext: modelContext,
                        summarisationService: summarisationService,
                        liveActivityManager: LiveActivityManager.shared
                    )

                    // Set callback to update unsummarised count when jobs complete
                    manager.onJobCompleted = { [weak vm = viewModel.vm] in
                        vm?.updateUnsummarisedCount()
                    }

                    jobManager = manager

                    // Restore any incomplete jobs from previous session
                    let restoredCount = await jobManager?.restoreIncompleteJobs() ?? 0
                    if restoredCount > 0 {
                        // Show the most recent restored job
                        if let mostRecentJob = jobManager?.findIncompleteJobs().first {
                            currentJob = mostRecentJob
                        }
                    }
                }
            }
        }
        .task {
            guard let vm = viewModel.vm else { return }
            vm.loadItemsFromDatabase()

            // Always refresh library on launch to check for new items
            await vm.fetchLibrary()
        }
        .sheet(isPresented: $showSettings) {
            if let vm = viewModel.vm {
                SettingsView(oauthService: oauthService, libraryViewModel: vm)
            }
        }
        .sheet(isPresented: $showJobProgress) {
            if let job = currentJob, let manager = jobManager {
                JobProgressView(job: job, jobManager: JobManagerAdapter(manager: manager))
            }
        }
        .alert("Summarise whole library", isPresented: $showSummariseAllConfirmation) {
            Button("Summarise \(viewModel.vm?.unsummarisedCount ?? 0) papers", role: .destructive) {
                startSummariseAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will start summarising all unsummarised papers in your library (\(viewModel.vm?.unsummarisedCount ?? 0) papers). This may take a considerable amount of time and device resources.")
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Pause jobs when app goes to background
            if newPhase == .background {
                Task { @MainActor in
                    await jobManager?.pauseAllJobs(sendNotifications: true)
                }
            }
        }
        .alert("On-device AI unavailable", isPresented: $showAppleIntelligenceUnavailableAlert) {
            Button("Learn more") {
                if let url = URL(string: "https://www.apple.com/au/apple-intelligence/") {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Foundation Models require iOS 26 or later on iPhone 16 Pro or newer. Visit apple.com/apple-intelligence for compatible devices.")
        }
    }

    @ViewBuilder
    private func emptyState(vm: LibraryViewModel) -> some View {
        LibraryEmptyStateView(viewModel: vm)
    }

    @ViewBuilder
    private func itemListContent(vm: LibraryViewModel) -> some View {
        VStack(spacing: 0) {
            // Selection toolbar
            if isSelectionMode {
                selectionToolbar
            }

            // Items list
            List(selection: isSelectionMode ? $selectedItems : .constant(Set<String>())) {
                ForEach(vm.items, id: \.key) { item in
                    if isSelectionMode {
                        ItemRow(item: item, isSelected: selectedItems.contains(item.key))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(item.key)
                            }
                            .onAppear {
                                if vm.shouldLoadMore(currentItem: item) {
                                    vm.loadNextPage()
                                }
                            }
                    } else {
                        Button {
                            selectedItemKey = item.key
                        } label: {
                            ItemRow(item: item, isSelected: selectedItemKey == item.key)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedItemKey == item.key ? Color.accentColor.opacity(0.1) : nil
                        )
                        .onAppear {
                            if vm.shouldLoadMore(currentItem: item) {
                                vm.loadNextPage()
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func syncProgressPill(progress: SyncProgress) -> some View {
        SyncProgressPill(progress: progress, style: .compact)
    }

    private var selectionToolbar: some View {
        SelectionToolbar(
            selectedCount: selectedItems.count,
            totalCount: viewModel.vm?.items.count ?? 0,
            eligibleCount: eligibleItemsCount,
            onSelectAll: { selectAll() },
            onDeselectAll: { selectedItems.removeAll() },
            onSummariseSelected: { startBatchSummarisation() }
        )
    }

    private var eligibleItemsCount: Int {
        guard let vm = viewModel.vm else { return 0 }
        return BatchSummarisationHelper.eligibleItemsCount(
            selectedItems: selectedItems,
            items: vm.items
        )
    }

    private func toggleSelection(_ key: String) {
        if selectedItems.contains(key) {
            selectedItems.remove(key)
        } else {
            selectedItems.insert(key)
        }
    }

    private func selectAll() {
        guard let vm = viewModel.vm else { return }
        selectedItems = Set(vm.items.map { $0.key })
    }

    private func startSummariseAll() {
        guard let manager = jobManager else { return }

        BatchSummarisationHelper.startSummariseAll(
            jobManager: manager,
            modelContext: modelContext,
            onJobCreated: { job in
                currentJob = job
                showJobProgress = true
            },
            onError: { errorMessage in
                viewModel.vm?.errorMessage = errorMessage
            },
            onAppleIntelligenceUnavailable: {
                showAppleIntelligenceUnavailableAlert = true
            }
        )
    }

    private func startBatchSummarisation() {
        guard let vm = viewModel.vm, let manager = jobManager else { return }

        BatchSummarisationHelper.startBatchSummarisation(
            selectedItems: selectedItems,
            items: vm.items,
            jobManager: manager,
            modelContext: modelContext,
            onJobCreated: { job in
                currentJob = job
                showJobProgress = true
                isSelectionMode = false
                selectedItems.removeAll()
            },
            onError: { errorMessage in
                viewModel.vm?.errorMessage = errorMessage
            },
            onAppleIntelligenceUnavailable: {
                showAppleIntelligenceUnavailableAlert = true
            }
        )
    }
}

// MARK: - Item Detail Container

/// Container that queries and displays a specific item by key
/// Used in iPad split view to show selected item details
struct ItemDetailContainer: View {
    @Environment(\.modelContext) private var modelContext
    let itemKey: String
    let oauthService: ZoteroOAuthService

    @Query private var items: [ZoteroItem]

    init(itemKey: String, oauthService: ZoteroOAuthService) {
        self.itemKey = itemKey
        self.oauthService = oauthService

        // Query for the specific item
        _items = Query(filter: #Predicate<ZoteroItem> { item in
            item.key == itemKey
        })
    }

    var body: some View {
        if let item = items.first {
            ItemDetailView(item: item, oauthService: oauthService)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                Text("Paper not found")
                    .font(.titleSourceSans)

                Text("This paper could not be loaded")
                    .font(.subheadlineSourceSans)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ZoteroItem.self, ProcessedItem.self, SummaryJob.self])
}
