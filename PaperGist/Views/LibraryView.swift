//
// LibraryView.swift
// PaperGist
//
// Main library view for iPhone showing list of papers with search, selection, and batch actions.
// Handles job management, sync progress, and navigation to item details.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import SwiftData
import Combine

/// Main library list view for iPhone layout
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var oauthService: ZoteroOAuthService
    @StateObject private var viewModel: LibraryViewModelWrapper

    @State private var selectedItems = Set<String>()
    @State private var isSelectionMode = false
    @State private var showSettings = false
    @State private var currentJob: SummaryJob?
    @State private var jobManager: JobManager?
    @State private var showSummariseAllConfirmation = false
    @State private var showAppleIntelligenceUnavailableAlert = false
    @Environment(\.scenePhase) private var scenePhase

    init(oauthService: ZoteroOAuthService) {
        self.oauthService = oauthService
        _viewModel = StateObject(wrappedValue: LibraryViewModelWrapper())
    }

    @ViewBuilder
    private var mainContent: some View {
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
                    LibraryEmptyStateView(viewModel: vm)
                } else {
                    itemListContent(vm: vm)
                }
            } else {
                ProgressView("Initialising...")
            }
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
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
                            Label("Summarise whole library", systemImage: "sparkles")
                                .font(.bodySourceSans)
                        }
                        .disabled((viewModel.vm?.unsummarisedCount ?? 0) == 0)

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
                    SyncProgressPill(progress: progress, style: .detailed)
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
            .sheet(item: $currentJob) { job in
                if let manager = jobManager {
                    JobProgressView(job: job, jobManager: JobManagerAdapter(manager: manager))
                        .presentationDetents([.medium, .large])
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                        .interactiveDismissDisabled(job.status == .processing || job.status == .paused)
                        .onDisappear {
                            // If job is still processing or paused, keep reference so it re-appears
                            if job.status != .processing && job.status != .paused {
                                currentJob = nil
                            }
                        }
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

                // Re-show job progress if there's an incomplete job when app becomes active
                if newPhase == .active {
                    Task { @MainActor in
                        // If there's no current job shown but there are incomplete jobs, show the most recent one
                        if currentJob == nil, let manager = jobManager {
                            let incompleteJobs = manager.findIncompleteJobs()
                            if let mostRecentJob = incompleteJobs.first {
                                currentJob = mostRecentJob
                            }
                        }
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
                Text("Foundation Models require iOS 26 or later on iPhone 16 Pro or newer.\n\nYou can check compatible devices on Apple's website.")
            }
        }
    }

    @ViewBuilder
    private func itemListContent(vm: LibraryViewModel) -> some View {
        VStack(spacing: 0) {
            // Selection toolbar
            if isSelectionMode {
                SelectionToolbar(
                    selectedCount: selectedItems.count,
                    totalCount: vm.items.count,
                    eligibleCount: eligibleItemsCount,
                    onSelectAll: { selectAll() },
                    onDeselectAll: { selectedItems.removeAll() },
                    onSummariseSelected: { startBatchSummarisation() }
                )
            }

            // Items list
            List(selection: isSelectionMode ? $selectedItems : .constant(Set<String>())) {
                ForEach(Array(vm.items.enumerated()), id: \.element.key) { index, item in
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
                            .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                    } else {
                        NavigationLink {
                            ItemDetailView(item: item, oauthService: oauthService)
                        } label: {
                            ItemRow(item: item, isSelected: false)
                        }
                        .onAppear {
                            if vm.shouldLoadMore(currentItem: item) {
                                vm.loadNextPage()
                            }
                        }
                        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
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

/// Wrapper that propagates LibraryViewModel changes to SwiftUI
/// Required because @StateObject needs to observe nested changes
@MainActor
class LibraryViewModelWrapper: ObservableObject {
    @Published var vm: LibraryViewModel? {
        didSet {
            // Cancel previous observation
            cancellable?.cancel()
            // Observe new viewModel's objectWillChange
            if let vm = vm {
                cancellable = vm.objectWillChange.sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
            }
        }
    }

    private var cancellable: AnyCancellable?

    init() {}
}

#Preview {
    LibraryView(oauthService: ZoteroOAuthService())
        .modelContainer(for: [ZoteroItem.self, ProcessedItem.self, SummaryJob.self])
}
