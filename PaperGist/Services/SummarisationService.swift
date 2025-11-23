// SummarisationService.swift
// PaperGist
//
// Orchestrates the complete summarisation workflow: downloading PDFs from Zotero,
// extracting text with fallback strategies, generating AI summaries, and uploading
// results back to Zotero. Uses a background worker actor for I/O-heavy operations.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftData
import PDFKit
import OSLog

// MARK: - Errors

enum SummarisationError: LocalizedError {
    case noPDFAttachment
    case pdfDownloadFailed(Int)
    case insufficientText
    case summaryGenerationFailed
    case uploadFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noPDFAttachment:
            return "No PDF attachment found for this item"
        case .pdfDownloadFailed(let statusCode):
            return "Failed to download PDF (HTTP \(statusCode))"
        case .insufficientText:
            return "Insufficient text extracted from PDF to generate summary"
        case .summaryGenerationFailed:
            return "Failed to generate AI summary"
        case .uploadFailed:
            return "Failed to upload summary to Zotero"
        case .cancelled:
            return "Summarisation was cancelled"
        }
    }
}

// MARK: - Background Processing Actor

/// Performs I/O-heavy operations off the main thread
///
/// Handles PDF downloads, text extraction with multiple fallback strategies,
/// and Zotero API uploads. Includes markdown-to-HTML conversion for note formatting.
actor SummarisationBackgroundWorker {
    private let zoteroService: ZoteroService

    init(zoteroService: ZoteroService) {
        self.zoteroService = zoteroService
    }

    /// Downloads PDF attachment for an item (runs on background)
    func downloadPDF(
        itemKey: String,
        libraryType: LibraryType,
        libraryID: String
    ) async throws -> URL {
        try Task.checkCancellation()

        // Find PDF attachment
        let children = try await zoteroService.fetchChildren(
            itemKey: itemKey,
            libraryType: libraryType.rawValue,
            libraryID: libraryID
        )

        guard let attachment = children.first(where: {
            $0.data.itemType == "attachment" &&
            $0.data.contentType == "application/pdf"
        }) else {
            throw SummarisationError.noPDFAttachment
        }

        try Task.checkCancellation()

        // Download the PDF
        let pdfURL = try await zoteroService.downloadPDF(
            itemKey: itemKey,
            attachmentKey: attachment.key,
            libraryType: libraryType.rawValue,
            libraryID: libraryID
        )

        return pdfURL
    }

    /// Extracts text from PDF with multiple fallback strategies
    ///
    /// Attempts full extraction first, then falls back to extracting abstract,
    /// introduction/conclusion, or progressive streaming if initial extraction
    /// yields insufficient text.
    func extractText(pdfURL: URL, progressCallback: @Sendable @escaping (Double, String) -> Void) async throws -> String {
        try Task.checkCancellation()

        let minimumTextThreshold = 500

        do {
            let pdfExtractor = PDFTextExtractor()
            let text = try await pdfExtractor.extractText(from: pdfURL) { progress, message in
                let overallProgress = 0.3 + (progress * 0.2)
                progressCallback(overallProgress, message)
            }

            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SummarisationError.insufficientText
            }

            return text
        } catch let error as PDFExtractionError where error == .scannedPDF {
            AppLogger.ai.warning("Scanned PDF detected, attempting fallback strategies")
        } catch {
            AppLogger.ai.warning("Text extraction failed, attempting fallback strategies: \(error.localizedDescription)")
        }

        // Fallback strategies
        try Task.checkCancellation()

        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw PDFExtractionError.invalidPDF
        }

        let pageCount = pdfDocument.pageCount

        // Memory-efficient extraction: define maximum text to extract to avoid memory bloat
        // Target ~10MB of text maximum (assuming ~2 bytes per character in UTF-16)
        let maxCharacters = 5_000_000

        // Fallback 1: Try to extract abstract from first few pages
        try Task.checkCancellation()
        progressCallback(0.35, "Attempting to extract abstract...")

        // Extract first ~10 pages for abstract/intro/conclusion search (typically sufficient)
        let earlyPagesLimit = min(10, pageCount)
        var earlyPagesText = ""
        for pageIndex in 0..<earlyPagesLimit {
            try Task.checkCancellation()
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            guard let pageText = page.string else { continue }
            earlyPagesText += pageText + "\n\n"

            // Cap early pages text to prevent memory issues
            if earlyPagesText.count > 500_000 {
                break
            }
        }

        earlyPagesText = earlyPagesText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let abstractText = extractSection(from: earlyPagesText, sectionName: "Abstract"),
           abstractText.count >= minimumTextThreshold {
            return abstractText
        }

        // Fallback 2: Try to extract introduction + conclusion
        try Task.checkCancellation()
        progressCallback(0.40, "Attempting to extract introduction and conclusion...")

        let introText = extractSection(from: earlyPagesText, sectionName: "Introduction") ?? ""

        // For conclusion, check last few pages if not in early pages
        var conclusionText = extractSection(from: earlyPagesText, sectionName: "Conclusion") ?? ""

        if conclusionText.isEmpty && pageCount > earlyPagesLimit {
            // Extract last ~5 pages for conclusion
            let lastPagesStart = max(earlyPagesLimit, pageCount - 5)
            var lastPagesText = ""
            for pageIndex in lastPagesStart..<pageCount {
                try Task.checkCancellation()
                guard let page = pdfDocument.page(at: pageIndex) else { continue }
                guard let pageText = page.string else { continue }
                lastPagesText += pageText + "\n\n"

                // Cap last pages text
                if lastPagesText.count > 200_000 {
                    break
                }
            }
            conclusionText = extractSection(from: lastPagesText, sectionName: "Conclusion") ?? ""
        }

        let combinedText = (introText + "\n\n" + conclusionText).trimmingCharacters(in: .whitespacesAndNewlines)

        if combinedText.count >= minimumTextThreshold {
            return combinedText
        }

        // Fallback 3: Extract first portion of document progressively
        try Task.checkCancellation()
        progressCallback(0.45, "Attempting to use first portion of text...")

        // Stream pages until we hit 50% of maxCharacters or run out of pages
        let targetHalfSize = maxCharacters / 2
        var streamedText = ""
        var currentCharCount = 0

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            guard let pageText = page.string else { continue }

            streamedText += pageText + "\n\n"
            currentCharCount = streamedText.count

            // Stop when we have enough text for the 50% fallback
            if currentCharCount >= targetHalfSize {
                break
            }
        }

        streamedText = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if streamedText.count >= minimumTextThreshold {
            return streamedText
        }

        // Fallback 4: Try first 25% of the streamed text
        try Task.checkCancellation()
        progressCallback(0.48, "Attempting to use reduced portion of text...")

        if streamedText.count > minimumTextThreshold * 2 {
            let quarterIndex = streamedText.index(
                streamedText.startIndex,
                offsetBy: streamedText.count / 4,
                limitedBy: streamedText.endIndex
            ) ?? streamedText.endIndex
            let firstQuarter = String(streamedText[..<quarterIndex]).trimmingCharacters(in: .whitespacesAndNewlines)

            if firstQuarter.count >= minimumTextThreshold {
                return firstQuarter
            }
        }

        // All fallbacks failed
        AppLogger.ai.error("All fallback strategies failed - insufficient text")
        throw SummarisationError.insufficientText
    }

    /// Generates AI summary (AIService is @MainActor, async call handles isolation automatically)
    func generateSummary(text: String) async throws -> (summary: String, confidence: Double?) {
        try Task.checkCancellation()

        // AIService is @MainActor, but async calls can cross actor boundaries
        let aiService = AIService()
        let result = try await aiService.summarisePaper(text: text)
        return (summary: result.summary, confidence: result.confidence)
    }

    /// Uploads summary to Zotero (runs on background)
    func uploadToZotero(
        itemKey: String,
        summary: String,
        libraryType: LibraryType,
        libraryID: String,
        addTag: Bool
    ) async throws -> String {
        try Task.checkCancellation()

        let formattedNote = formatSummaryNote(summary)

        do {
            try Task.checkCancellation()

            let noteKey = try await zoteroService.createNote(
                itemKey: itemKey,
                content: formattedNote,
                addTag: addTag,
                libraryType: libraryType.rawValue,
                libraryID: libraryID
            )

            return noteKey
        } catch {
            throw SummarisationError.uploadFailed
        }
    }

    /// Cleans up temporary PDF file
    func cleanupTemporaryPDF(at url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            AppLogger.general.warning("Failed to clean up temporary PDF: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Extracts a section from text based on common header patterns
    private func extractSection(from text: String, sectionName: String) -> String? {
        let patterns = [
            "\(sectionName.uppercased())",
            "\(sectionName.lowercased())",
            "\(sectionName.capitalized)",
            "\\d+\\.?\\s*\(sectionName.uppercased())",
            "\\d+\\.?\\s*\(sectionName.capitalized)"
        ]

        for pattern in patterns {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let startIndex = range.upperBound
                var endIndex = text.endIndex

                if let nextSection = text[startIndex...].range(of: "\\n\\d+\\.?\\s*[A-Z]", options: .regularExpression) {
                    endIndex = nextSection.lowerBound
                }

                let section = String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !section.isEmpty {
                    return section
                }
            }
        }

        return nil
    }

    /// Formats summary note with HTML
    private func formatSummaryNote(_ summary: String) -> String {
        let timestamp = Date().formatted(date: .long, time: .shortened)

        var formattedSummary = summary
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        formattedSummary = convertMarkdownToHTML(formattedSummary)
        formattedSummary = formattedSummary.replacingOccurrences(of: "\n", with: "<br/>")

        return """
        <h1>AI-Generated Summary</h1>
        <p><em>Generated on \(timestamp) by PaperGist</em></p>

        <h2>Summary</h2>
        <p>\(formattedSummary)</p>

        <hr/>
        <p style="font-size: 0.9em; color: #666;">
        This summary was generated using AI and may not capture all nuances of the original paper.
        </p>
        """
    }

    /// Converts markdown to HTML
    private func convertMarkdownToHTML(_ text: String) -> String {
        var result = text

        let lines = result.components(separatedBy: "\n")
        var processedLines: [String] = []
        var inCodeBlock = false
        var codeBlockLines: [String] = []
        var inList = false
        var listItems: [String] = []
        var listType: String? = nil

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCodeBlock {
                    let codeContent = codeBlockLines.joined(separator: "\n")
                    processedLines.append("<pre><code>\(codeContent)</code></pre>")
                    codeBlockLines.removeAll()
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                continue
            }

            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let isUnorderedListItem = trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") || trimmedLine.hasPrefix("+ ")
            let isOrderedListItem = trimmedLine.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil

            if isUnorderedListItem || isOrderedListItem {
                let currentListType = isUnorderedListItem ? "ul" : "ol"

                if inList && listType != currentListType {
                    let listHTML = wrapList(items: listItems, type: listType!)
                    processedLines.append(listHTML)
                    listItems.removeAll()
                }

                inList = true
                listType = currentListType

                let content: String
                if isUnorderedListItem {
                    content = String(trimmedLine.dropFirst(2))
                } else {
                    if let dotRange = trimmedLine.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        content = String(trimmedLine[dotRange.upperBound...])
                    } else {
                        content = trimmedLine
                    }
                }
                listItems.append(content)
            } else {
                if inList {
                    let listHTML = wrapList(items: listItems, type: listType!)
                    processedLines.append(listHTML)
                    listItems.removeAll()
                    inList = false
                    listType = nil
                }

                processedLines.append(line)
            }
        }

        if inList {
            let listHTML = wrapList(items: listItems, type: listType!)
            processedLines.append(listHTML)
        }

        if inCodeBlock {
            let codeContent = codeBlockLines.joined(separator: "\n")
            processedLines.append("<pre><code>\(codeContent)</code></pre>")
        }

        result = processedLines.joined(separator: "\n")

        result = convertHeaders(in: result, level: 6)
        result = convertHeaders(in: result, level: 5)
        result = convertHeaders(in: result, level: 4)
        result = convertHeaders(in: result, level: 3)
        result = convertHeaders(in: result, level: 2)
        result = convertHeaders(in: result, level: 1)

        while let range = result.range(of: #"`([^`]+)`"#, options: .regularExpression) {
            let match = result[range]
            let content = match.dropFirst().dropLast()
            result.replaceSubrange(range, with: "<code>\(content)</code>")
        }

        while let range = result.range(of: #"\*\*([^\*]+)\*\*"#, options: .regularExpression) {
            let match = result[range]
            let content = match.dropFirst(2).dropLast(2)
            result.replaceSubrange(range, with: "<strong>\(content)</strong>")
        }

        while let range = result.range(of: #"(?<!</?strong>)(?<!^)\*([^\*\n]+)\*(?!</?strong>)"#, options: .regularExpression) {
            let match = result[range]
            let content = match.dropFirst().dropLast()
            result.replaceSubrange(range, with: "<em>\(content)</em>")
        }

        while let range = result.range(of: #"\[([^\]]+)\]\(([^\)]+)\)"#, options: .regularExpression) {
            let matchText = result[range]
            let matchString = String(matchText)

            if let linkMatch = matchString.firstMatch(of: /\[([^\]]+)\]\(([^\)]+)\)/) {
                let linkText = String(linkMatch.1)
                let linkURL = String(linkMatch.2)
                result.replaceSubrange(range, with: "<a href=\"\(linkURL)\">\(linkText)</a>")
            }
        }

        while let range = result.range(of: #"~~([^~]+)~~"#, options: .regularExpression) {
            let match = result[range]
            let content = match.dropFirst(2).dropLast(2)
            result.replaceSubrange(range, with: "<del>\(content)</del>")
        }

        let finalLines = result.components(separatedBy: "\n")
        var quotedLines: [String] = []
        var processedFinalLines: [String] = []

        for line in finalLines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                let content = line.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces)
                quotedLines.append(String(content))
            } else {
                if !quotedLines.isEmpty {
                    processedFinalLines.append("<blockquote>\(quotedLines.joined(separator: "<br/>"))</blockquote>")
                    quotedLines.removeAll()
                }
                processedFinalLines.append(line)
            }
        }

        if !quotedLines.isEmpty {
            processedFinalLines.append("<blockquote>\(quotedLines.joined(separator: "<br/>"))</blockquote>")
        }

        result = processedFinalLines.joined(separator: "\n")
        result = result.replacingOccurrences(of: #"(?:^|\n)(?:---|\*\*\*|___)(?:\n|$)"#, with: "\n<hr/>\n", options: .regularExpression)

        return result
    }

    private func convertHeaders(in text: String, level: Int) -> String {
        let hashes = String(repeating: "#", count: level)
        let pattern = "(?:^|\\n)\(hashes) ([^\\n]+)"

        return text.replacingOccurrences(
            of: pattern,
            with: "\n<h\(level)>$1</h\(level)>",
            options: .regularExpression
        )
    }

    private func wrapList(items: [String], type: String) -> String {
        let listItemsHTML = items.map { "<li>\($0)</li>" }.joined(separator: "\n")
        return "<\(type)>\n\(listItemsHTML)\n</\(type)>"
    }
}

// MARK: - Summarisation Service

final class SummarisationService: ObservableObject, @unchecked Sendable {
    private let zoteroService: ZoteroService
    private let modelContext: ModelContext
    private let backgroundWorker: SummarisationBackgroundWorker

    /// Cache for active jobs to avoid repeated SwiftData fetches during progress updates
    @MainActor
    private var activeJobsCache: [UUID: ItemSummaryJob] = [:]

    init(zoteroService: ZoteroService, modelContext: ModelContext) {
        self.zoteroService = zoteroService
        self.modelContext = modelContext
        self.backgroundWorker = SummarisationBackgroundWorker(zoteroService: zoteroService)
    }

    // MARK: - Main Entry Point

    /// Main entry point - summarises an item end-to-end
    /// This function starts on @MainActor to accept the item, then delegates heavy I/O to background
    @MainActor
    func summariseItem(_ item: ZoteroItem) async throws {
        // Capture sendable values from item before entering async contexts
        let itemKey = item.key
        let itemTitle = item.title
        let libraryType = item.libraryType
        let libraryID = item.libraryID

        // Check cancellation before starting
        try Task.checkCancellation()

        // Create summary job on main actor
        let jobID = await createJob(itemKey: itemKey)

        var pdfURL: URL?

        // Cleanup: delete temporary PDF file when function exits
        defer {
            if let pdfURL = pdfURL {
                Task { await backgroundWorker.cleanupTemporaryPDF(at: pdfURL) }
            }
        }

        do {
            // Step 1: Download PDF (0.0 - 0.3) - BACKGROUND
            try Task.checkCancellation()
            updateProgress(jobID: jobID, progress: 0.0, message: "Finding PDF attachment...")

            pdfURL = try await backgroundWorker.downloadPDF(
                itemKey: itemKey,
                libraryType: libraryType,
                libraryID: libraryID
            )

            updateProgress(jobID: jobID, progress: 0.3, message: "PDF downloaded")

            // Step 2: Extract text with fallback logic (0.3 - 0.5) - BACKGROUND
            try Task.checkCancellation()
            updateProgress(jobID: jobID, progress: 0.3, message: "Extracting text from PDF...")

            let text = try await backgroundWorker.extractText(pdfURL: pdfURL!) { @Sendable [weak self] progress, message in
                guard let self = self else { return }
                Task { @MainActor in
                    self.updateProgress(jobID: jobID, progress: progress, message: message)
                }
            }

            updateProgress(jobID: jobID, progress: 0.5, message: "Text extracted successfully")

            // Step 3: Generate summary (0.5 - 0.8) - BACKGROUND (but AIService is @MainActor)
            try Task.checkCancellation()
            updateProgress(jobID: jobID, progress: 0.5, message: "Generating summary...")

            let (summary, confidence) = try await backgroundWorker.generateSummary(text: text)

            updateProgress(jobID: jobID, progress: 0.8, message: "Summary generated")

            // Step 4: Upload to Zotero or save locally (0.8 - 1.0)
            try Task.checkCancellation()
            let noteKey: String?
            let status: ProcessingStatus

            // Read app settings on main actor
            let shouldAutoUpload = await MainActor.run { AppSettings.shared.autoUploadToZotero }
            let shouldAddTag = await MainActor.run { AppSettings.shared.addAISummaryTag }

            if shouldAutoUpload {
                updateProgress(jobID: jobID, progress: 0.8, message: "Uploading to Zotero...")
                noteKey = try await backgroundWorker.uploadToZotero(
                    itemKey: itemKey,
                    summary: summary,
                    libraryType: libraryType,
                    libraryID: libraryID,
                    addTag: shouldAddTag
                )
                updateProgress(jobID: jobID, progress: 1.0, message: "Uploaded to Zotero")
                status = .uploaded
            } else {
                updateProgress(jobID: jobID, progress: 0.8, message: "Saving locally...")
                noteKey = nil
                status = .local
            }

            // Step 5: Save locally - MAIN ACTOR for SwiftData
            try Task.checkCancellation()
            updateProgress(jobID: jobID, progress: 1.0, message: "Complete!", status: .completed)

            saveProcessedItem(
                itemKey: itemKey,
                summary: summary,
                confidence: confidence,
                noteKey: noteKey,
                status: status,
                jobID: jobID
            )


        } catch is CancellationError {
            markJobFailed(jobID: jobID, errorMessage: "Cancelled")
            throw SummarisationError.cancelled

        } catch {
            markJobFailed(jobID: jobID, errorMessage: error.localizedDescription)
            AppLogger.ai.error("Failed to summarise '\(itemTitle)': \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Main Actor Database Operations

    /// Creates a new job and returns its ID
    @MainActor
    private func createJob(itemKey: String) -> UUID {
        let job = ItemSummaryJob(itemKey: itemKey, status: .pending)
        modelContext.insert(job)
        try? modelContext.save()

        // Add to cache to avoid repeated fetches during progress updates
        activeJobsCache[job.id] = job

        return job.id
    }

    /// Updates job progress (uses cached reference to avoid repeated SwiftData fetches)
    @MainActor
    private func updateProgress(
        jobID: UUID,
        progress: Double,
        message: String,
        status: SummaryStatus = .processing
    ) {
        // Try to get job from cache first
        let job: ItemSummaryJob?
        if let cachedJob = activeJobsCache[jobID] {
            job = cachedJob
        } else {
            // Fallback to fetching if not in cache (shouldn't happen in normal flow)
            let descriptor = FetchDescriptor<ItemSummaryJob>(
                predicate: #Predicate { $0.id == jobID }
            )
            job = try? modelContext.fetch(descriptor).first
        }

        guard let job = job else { return }

        job.progress = progress
        job.progressMessage = message
        job.status = status
        try? modelContext.save()
    }

    /// Saves the processed item and updates the parent item
    @MainActor
    private func saveProcessedItem(
        itemKey: String,
        summary: String,
        confidence: Double?,
        noteKey: String?,
        status: ProcessingStatus,
        jobID: UUID
    ) {
        // Find and update the job (use cache if available)
        if let job = activeJobsCache[jobID] {
            job.completedAt = Date()
        } else {
            let jobDescriptor = FetchDescriptor<ItemSummaryJob>(
                predicate: #Predicate { $0.id == jobID }
            )
            if let job = try? modelContext.fetch(jobDescriptor).first {
                job.completedAt = Date()
            }
        }

        // Remove from cache now that job is complete
        activeJobsCache.removeValue(forKey: jobID)

        // Create processed item
        let processedItem = ProcessedItem(
            itemKey: itemKey,
            summaryText: summary,
            processedAt: Date(),
            confidence: confidence,
            summaryNoteKey: noteKey,
            wordCount: summary.split(separator: " ").count,
            status: status
        )
        modelContext.insert(processedItem)

        // Find and update the parent item
        let itemDescriptor = FetchDescriptor<ZoteroItem>(
            predicate: #Predicate { $0.key == itemKey }
        )
        if let item = try? modelContext.fetch(itemDescriptor).first {
            item.hasSummary = true
            item.summary = processedItem
        }

        try? modelContext.save()
    }

    /// Marks a job as failed
    @MainActor
    private func markJobFailed(jobID: UUID, errorMessage: String) {
        // Try to get job from cache first
        let job: ItemSummaryJob?
        if let cachedJob = activeJobsCache[jobID] {
            job = cachedJob
        } else {
            let descriptor = FetchDescriptor<ItemSummaryJob>(
                predicate: #Predicate { $0.id == jobID }
            )
            job = try? modelContext.fetch(descriptor).first
        }

        guard let job = job else { return }

        job.status = .failed
        job.errorMessage = errorMessage
        try? modelContext.save()

        // Remove from cache now that job is complete
        activeJobsCache.removeValue(forKey: jobID)
    }
}
