//
// LibraryViewModel.swift
// PaperGist
//
// Manages Zotero library synchronisation and local item caching.
// Handles background sync operations and progress tracking for library updates.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import SwiftData
import OSLog

/// Tracks the current state of a library sync operation
struct SyncProgress {
    var itemsFetched: Int = 0
    var itemsProcessed: Int = 0
    var totalItems: Int? = nil // nil until total is known from API
    var currentPhase: String = "Starting sync..."
}

/// Background actor that performs sync operations off the main thread
/// Handles network requests and database operations concurrently
actor LibrarySyncActor {
    private let zoteroService: ZoteroService
    private let modelContainer: ModelContainer

    init(zoteroService: ZoteroService, modelContainer: ModelContainer) {
        self.zoteroService = zoteroService
        self.modelContainer = modelContainer
    }

    /// Syncs library items from Zotero API to local database
    /// Supports incremental sync when sinceVersion is provided
    func performSync(
        sinceVersion: Int?,
        progressHandler: @MainActor @Sendable (SyncProgress) -> Void,
        onBatchSaved: @MainActor @Sendable () -> Void
    ) async throws -> SyncResult {
        // Create background context for SwiftData operations
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false // Manual save control

        // Test API access first
        try await zoteroService.testAPIAccess()

        await progressHandler(SyncProgress(currentPhase: "Fetching library items..."))

        let isIncrementalSync = sinceVersion != nil

        // Fetch all pages from Zotero
        let apiPageSize = 100
        var start = 0
        var hasMore = true
        var totalFetched = 0
        var apiTotalCount: Int? = nil
        var latestLibraryVersion: Int? = nil

        while hasMore {
            // Update progress
            if let total = apiTotalCount {
                let syncType = isIncrementalSync ? "new/updated" : ""
                let progress = SyncProgress(
                    itemsFetched: totalFetched,
                    totalItems: total,
                    currentPhase: "Fetching \(syncType) items \(start + 1)–\(start + apiPageSize)..."
                )
                await progressHandler(progress)
            } else {
                let progress = SyncProgress(
                    itemsFetched: totalFetched,
                    currentPhase: "Fetching items \(start + 1)–\(start + apiPageSize)..."
                )
                await progressHandler(progress)
            }

            // Fetch page from API (network call runs off main actor)
            let result = try await zoteroService.fetchItems(
                limit: apiPageSize,
                start: start,
                since: sinceVersion
            )
            let pageItems = result.items

            // Capture library version
            if let version = result.libraryVersion {
                latestLibraryVersion = version
            }

            // Capture total count from first page
            if apiTotalCount == nil, let total = result.totalCount {
                apiTotalCount = total
                let progress = SyncProgress(
                    itemsFetched: totalFetched,
                    totalItems: total,
                    currentPhase: "Fetching items..."
                )
                await progressHandler(progress)

                // Save total to settings
                await MainActor.run {
                    AppSettings.shared.totalZoteroItems = total
                }
            }

            // Process this batch in background
            _ = try await processBatch(
                pageItems,
                context: context,
                progressHandler: progressHandler,
                currentProgress: totalFetched
            )

            totalFetched += pageItems.count
            start += pageItems.count
            hasMore = pageItems.count == apiPageSize

            // Save batch to database (background context)
            try context.save()

            // Notify main actor to refresh the view with new items
            await onBatchSaved()
        }

        return SyncResult(
            totalFetched: totalFetched,
            libraryVersion: latestLibraryVersion
        )
    }

    private func processBatch(
        _ apiItems: [ZoteroAPIItem],
        context: ModelContext,
        progressHandler: @MainActor @Sendable (SyncProgress) -> Void,
        currentProgress: Int
    ) async throws -> BatchStats {
        var itemsWithPDF = 0
        var itemsWithoutPDF = 0
        var nonDocuments = 0
        var itemsInserted = 0
        var itemsUpdated = 0
        var itemsSkipped = 0
        var itemsProcessed = currentProgress

        for apiItem in apiItems {
            itemsProcessed += 1
            await progressHandler(SyncProgress(
                itemsProcessed: itemsProcessed,
                currentPhase: "Synchronising library items..."
            ))

            // Skip non-document items
            guard isDocumentType(apiItem.data.itemType) else {
                nonDocuments += 1
                continue
            }

            // Check if item already exists and was checked recently (background context)
            let itemKey = apiItem.key
            let descriptor = FetchDescriptor<ZoteroItem>(
                predicate: #Predicate { $0.key == itemKey }
            )

            if let existingItem = try? context.fetch(descriptor).first {
                // Skip if checked within last 24 hours
                let hoursSinceLastCheck = Date().timeIntervalSince(existingItem.lastChecked) / 3600
                if hoursSinceLastCheck < 24 {
                    itemsSkipped += 1
                    continue
                }
            }

            // Fetch children to check for attachments and notes (network call)
            let children = try? await zoteroService.fetchChildren(
                itemKey: apiItem.key,
                libraryType: apiItem.library?.type,
                libraryID: apiItem.library?.id.description
            )

            guard let children = children else { continue }

            let hasAttachment = children.contains {
                $0.data.itemType == "attachment" &&
                $0.data.contentType == "application/pdf"
            }

            // Only include items with PDF attachments
            guard hasAttachment else {
                itemsWithoutPDF += 1
                continue
            }

            itemsWithPDF += 1

            // Check for any existing notes
            let hasNotes = children.contains { $0.data.itemType == "note" }

            // Skip items with notes if setting is enabled
            let skipItemsWithNotes = await MainActor.run { AppSettings.shared.skipItemsWithNotes }
            if skipItemsWithNotes && hasNotes {
                continue
            }

            // Check for existing summary notes with #ai-summary tag
            let hasSummary = children.contains { child in
                guard child.data.itemType == "note" else { return false }

                // Convert to ZoteroNote and check for #ai-summary tag
                if let noteData = try? JSONEncoder().encode(child),
                   let note = try? JSONDecoder().decode(ZoteroNote.self, from: noteData) {
                    return note.hasAISummaryTag()
                }
                return false
            }

            // Convert to local model
            let localItem = apiItem.toZoteroItem(
                hasAttachment: hasAttachment,
                hasSummary: hasSummary
            )

            // Insert or update in background context
            let wasInserted = upsertItem(localItem, context: context)
            if wasInserted {
                itemsInserted += 1
            } else {
                itemsUpdated += 1
            }
        }

        return BatchStats(
            withPDF: itemsWithPDF,
            withoutPDF: itemsWithoutPDF,
            nonDocuments: nonDocuments,
            inserted: itemsInserted,
            updated: itemsUpdated,
            skipped: itemsSkipped
        )
    }

    /// Inserts or updates an item in the database
    /// - Returns: true if inserted, false if updated
    private func upsertItem(_ item: ZoteroItem, context: ModelContext) -> Bool {
        let itemKey = item.key
        let descriptor = FetchDescriptor<ZoteroItem>(
            predicate: #Predicate { $0.key == itemKey }
        )

        if let existingItem = try? context.fetch(descriptor).first {
            // Update existing
            existingItem.title = item.title
            existingItem.itemType = item.itemType
            existingItem.creatorSummary = item.creatorSummary
            existingItem.creators = item.creators
            existingItem.year = item.year
            existingItem.publicationTitle = item.publicationTitle
            existingItem.hasAttachment = item.hasAttachment
            existingItem.hasSummary = item.hasSummary
            existingItem.lastChecked = item.lastChecked
            existingItem.libraryType = item.libraryType
            existingItem.version = item.version
            return false // Updated
        } else {
            // Insert new
            context.insert(item)
            return true // Inserted
        }
    }

    /// Checks if an item type is a document that can have PDFs
    private func isDocumentType(_ itemType: String) -> Bool {
        let documentTypes = [
            "journalArticle",
            "book",
            "bookSection",
            "conferencePaper",
            "report",
            "thesis",
            "manuscript",
            "preprint"
        ]

        return documentTypes.contains(itemType)
    }
}

/// Result of a completed sync operation
struct SyncResult {
    let totalFetched: Int
    let libraryVersion: Int?
}

/// Statistics from processing a batch of items during sync
struct BatchStats {
    let withPDF: Int
    let withoutPDF: Int
    let nonDocuments: Int
    let inserted: Int
    let updated: Int
    let skipped: Int
}

/// Main view model for the library view
/// Manages library items, search, pagination, and sync state
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var items: [ZoteroItem] = []
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var syncProgress: SyncProgress?
    @Published var loadingMessage = "Loading library..."
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var hasCompletedFullSync = false
    @Published var unsummarisedCount: Int = 0

    private let zoteroService: ZoteroService
    private let modelContext: ModelContext
    private let modelContainer: ModelContainer
    private let settings = AppSettings.shared
    private var currentPage = 0
    private let pageSize = 50
    private var lastSyncTime: Date?
    private var syncActor: LibrarySyncActor?

    init(zoteroService: ZoteroService, modelContext: ModelContext) {
        self.zoteroService = zoteroService
        self.modelContext = modelContext
        self.modelContainer = modelContext.container
        self.syncActor = LibrarySyncActor(
            zoteroService: zoteroService,
            modelContainer: modelContainer
        )
        updateUnsummarisedCount()
    }

    /// Determines if library should auto-refresh based on last sync time
    /// - Returns: true if never synced or last sync was over 5 minutes ago
    func shouldAutoRefresh() -> Bool {
        guard let lastSync = lastSyncTime else {
            return true // Never synced before
        }
        return Date().timeIntervalSince(lastSync) > 300 // 5 minutes
    }

    /// Fetches library items from Zotero and updates local cache
    /// - Parameter force: If true, clears last version to force full sync
    func fetchLibrary(force: Bool = false) async {
        guard !isSyncing else { return }

        // Skip if recently synced (unless forced)
        if !force && !shouldAutoRefresh() {
            return
        }

        // If forcing a full sync, clear the last version to fetch everything
        if force {
            settings.lastLibraryVersion = nil
        }

        isSyncing = true
        errorMessage = nil
        syncProgress = SyncProgress(currentPhase: "Checking API access...")

        // Perform sync in background
        await performBackgroundSync()
    }

    private func performBackgroundSync() async {
        guard let syncActor = syncActor else {
            isSyncing = false
            errorMessage = "Sync actor not initialised"
            return
        }

        do {
            // Get current version for incremental sync
            let sinceVersion = settings.lastLibraryVersion

            // Run sync on background actor (all network and DB work happens off main thread)
            let result = try await syncActor.performSync(
                sinceVersion: sinceVersion,
                progressHandler: { [weak self] progress in
                    // Only UI updates happen on main actor
                    guard let self = self else { return }
                    self.syncProgress = progress
                },
                onBatchSaved: { [weak self] in
                    // Refresh the items list when a batch is saved to show new items incrementally
                    guard let self = self else { return }
                    self.loadItemsFromDatabase()
                }
            )

            // Update UI state on main actor after sync completes
            hasCompletedFullSync = true
            isSyncing = false
            syncProgress = nil
            lastSyncTime = Date()

            // Save library version for next incremental sync
            if let version = result.libraryVersion {
                settings.lastLibraryVersion = version
            }

            // Reload items from database to show updates
            loadItemsFromDatabase()

            // Update widgets after sync
            let widgetService = WidgetUpdateService(modelContext: modelContext)
            widgetService.updateWidgets()

        } catch {
            errorMessage = "Failed to fetch library: \(error.localizedDescription)"
            isSyncing = false
            syncProgress = nil
            AppLogger.sync.error("Error fetching library: \(error.localizedDescription)")
        }
    }

    /// Updates the cached count of unsummarised items
    func updateUnsummarisedCount() {
        let descriptor = FetchDescriptor<ZoteroItem>(
            predicate: #Predicate { item in
                item.hasAttachment && !item.hasSummary
            }
        )
        unsummarisedCount = (try? modelContext.fetch(descriptor))?.count ?? 0
    }

    /// Loads items from local database with pagination
    func loadItemsFromDatabase() {
        currentPage = 0
        loadNextPage()
        updateUnsummarisedCount()
    }

    /// Loads the next page of items
    func loadNextPage() {
        let offset = currentPage * pageSize

        // Create fetch descriptor with sorting
        var descriptor = FetchDescriptor<ZoteroItem>()
        // Manually sort in memory since FetchDescriptor sorting has issues with Bool types
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = offset

        do {
            let pageItems = try modelContext.fetch(descriptor)

            if currentPage == 0 {
                // First page - replace all items
                items = sortAndFilterItems(pageItems)
            } else {
                // Subsequent pages - append items
                items.append(contentsOf: sortAndFilterItems(pageItems))
            }

            if !pageItems.isEmpty {
                currentPage += 1
            }
        } catch {
            errorMessage = "Failed to load items: \(error.localizedDescription)"
        }
    }

    /// Checks if we should load more items (called when near bottom of list)
    func shouldLoadMore(currentItem: ZoteroItem) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else {
            return false
        }
        return index >= items.count - 5 // Load more when within 5 items of the end
    }

    /// Applies search filter and sorting to items
    private func sortAndFilterItems(_ allItems: [ZoteroItem]) -> [ZoteroItem] {
        var filtered = allItems

        // Apply search text filter
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.creatorSummary.localizedCaseInsensitiveContains(searchText) ||
                $0.publicationTitle?.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        // Sort: unsummarised first, then by lastChecked date (newest first)
        return filtered.sorted { item1, item2 in
            // Unsummarised items always come first
            if item1.hasSummary != item2.hasSummary {
                return !item1.hasSummary
            }
            // Within each group, sort by date (newest first)
            return item1.lastChecked > item2.lastChecked
        }
    }

    /// Updates search text and reloads items
    func updateSearch(_ text: String) {
        searchText = text
        loadItemsFromDatabase()
    }
}
