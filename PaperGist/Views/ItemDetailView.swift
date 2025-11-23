//
// ItemDetailView.swift
// PaperGist
//
// Detail view for a single library item showing metadata, summary status, and actions.
// Handles summarisation, export to Markdown/PDF, and PDF thumbnail generation.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

/// Displays comprehensive details and summary status for a single library item
struct ItemDetailView: View {
    let item: ZoteroItem
    let oauthService: ZoteroOAuthService

    @Environment(\.modelContext) private var modelContext
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var summarisationService: SummarisationService?
    @State private var pdfThumbnail: UIImage?
    @State private var exportItem: ExportItem?
    @State private var showShareSheet = false
    @State private var showAppleIntelligenceUnavailableAlert = false

    // Query configured to fetch only jobs for this specific item
    @Query private var jobs: [ItemSummaryJob]

    /// Active job for this item (if any)
    private var itemJob: ItemSummaryJob? {
        jobs.first
    }

    init(item: ZoteroItem, oauthService: ZoteroOAuthService) {
        self.item = item
        self.oauthService = oauthService

        // Configure @Query with predicate to only fetch jobs for this item
        let itemKey = item.key
        _jobs = Query(filter: #Predicate<ItemSummaryJob> { job in
            job.itemKey == itemKey
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Paper metadata
                paperMetadataSection

                Divider()

                // Summary section
                summarySection
            }
            .padding()
        }
        .navigationTitle("Paper details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
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
        .sheet(isPresented: $showShareSheet) {
            if let exportItem = exportItem {
                ShareSheet(items: [exportItem.url])
            }
        }
        .task {
            if summarisationService == nil {
                let zoteroService = ZoteroService(oauthService: oauthService)
                summarisationService = SummarisationService(
                    zoteroService: zoteroService,
                    modelContext: modelContext
                )
            }

            // Load PDF thumbnail if available
            if item.hasAttachment && pdfThumbnail == nil {
                await loadPDFThumbnail()
            }
        }
    }

    // MARK: - Paper Metadata Section

    private var paperMetadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // PDF Thumbnail (if available)
            if let thumbnail = pdfThumbnail {
                HStack {
                    Spacer()
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 150, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                    Spacer()
                }
                .padding(.bottom, 8)
            }

            Text(item.title)
                .font(.titleSourceSans)

            HStack {
                Image(systemName: "person.2")
                    .foregroundStyle(.secondary)
                Text(item.creatorSummary)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadlineSourceSans)

            if let year = item.year {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text(year)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadlineSourceSans)
            }

            if let publication = item.publicationTitle {
                HStack {
                    Image(systemName: "book.closed")
                        .foregroundStyle(.secondary)
                    Text(publication)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadlineSourceSans)
            }

            // Attachment status
            HStack {
                Image(systemName: item.hasAttachment ? "paperclip" : "paperclip.slash")
                    .foregroundStyle(item.hasAttachment ? .green : .orange)
                Text(item.hasAttachment ? "PDF attached" : "No PDF")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadlineSourceSans)
        }
    }

    // MARK: - Summary Section

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.headlineSourceSans)

            // Priority 1: Check if there's an active job
            if let job = itemJob, job.status == .processing || job.status == .pending {
                // Show real-time progress from job
                progressView(for: job)
            } else if let job = itemJob, job.status == .failed {
                // Show error state from job
                failedView(for: job)
            } else if let summary = item.summary, summary.status == .local || summary.status == .uploaded {
                // Show completed summary
                completedSummaryView(summary)
            } else if let summary = item.summary, summary.status == .failed {
                // Show error state from ProcessedItem (fallback if job not found)
                failedView(summary)
            } else {
                // Show summarise button
                summariseButton
            }
        }
    }

    private func completedSummaryView(_ processedItem: ProcessedItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Timestamp
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Summarised \(processedItem.processedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.captionSourceSans)
                    .foregroundStyle(.secondary)

                if let confidence = processedItem.confidence {
                    Spacer()
                    Text(String(format: "%.0f%% confidence", confidence * 100))
                        .font(.captionSourceSans)
                        .foregroundStyle(.secondary)
                }
            }

            // Scrollable summary content
            ScrollView {
                Text(.init(processedItem.summaryText))
                    .font(.bodySourceSans)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Action buttons
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Re-summarise button (secondary style)
                    Button {
                        summarise()
                    } label: {
                        Label("Re-summarise", systemImage: "arrow.clockwise")
                            .font(.subheadlineSourceSans)
                    }
                    .buttonStyle(.bordered)
                    .disabled(itemJob?.status == .processing || itemJob?.status == .pending)

                    // View in Zotero deep link
                    // Format: zotero://select/items/LIBRARYTYPE_LIBRARYID_ITEMKEY
                    // Where LIBRARYTYPE is 0 for user libraries, 1 for group libraries
                    let libraryTypeCode = item.libraryType == .user ? "0" : "1"
                    let zoteroURL = "zotero://select/items/\(libraryTypeCode)_\(item.libraryID)_\(item.key)"

                    if let url = URL(string: zoteroURL) {
                        Link(destination: url) {
                            Label("View in Zotero", systemImage: "arrow.up.forward.app")
                                .font(.subheadlineSourceSans)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Export buttons
                HStack(spacing: 12) {
                    // Export as Markdown
                    Button {
                        exportAsMarkdown(processedItem)
                    } label: {
                        Label("Export Markdown", systemImage: "doc.text")
                            .font(.subheadlineSourceSans)
                    }
                    .buttonStyle(.bordered)

                    // Export as PDF
                    Button {
                        exportAsPDF(processedItem)
                    } label: {
                        Label("Export PDF", systemImage: "doc.richtext")
                            .font(.subheadlineSourceSans)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func progressView(for job: ItemSummaryJob?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let job = job {
                // Show detailed progress from job
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView(value: job.progress, total: 1.0)
                            .progressViewStyle(.linear)

                        Text("\(Int(job.progress * 100))%")
                            .font(.captionSourceSans)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.terracotta)
                        Text(job.progressMessage)
                            .font(.subheadlineMediumSourceSans)
                    }
                }
            } else {
                // Fallback generic progress
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Summarising...")
                        .font(.subheadlineSourceSans)
                }

                Text("Processing PDF and generating summary")
                    .font(.captionSourceSans)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Shared failure view for both ItemSummaryJob and ProcessedItem
    private func failureView(errorMessage: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Summarisation failed")
                    .font(.subheadlineMediumSourceSans)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.captionSourceSans)
                    .foregroundStyle(.secondary)
            }

            Button {
                summarise()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(.terracotta)
            .disabled(itemJob?.status == .processing || itemJob?.status == .pending)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Failed view for ItemSummaryJob
    private func failedView(for job: ItemSummaryJob) -> some View {
        failureView(errorMessage: job.errorMessage)
    }

    // Failed view for ProcessedItem (fallback)
    private func failedView(_ processedItem: ProcessedItem) -> some View {
        failureView(errorMessage: processedItem.errorMessage)
    }

    private var summariseButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This paper has not been summarised yet")
                .font(.subheadlineSourceSans)
                .foregroundStyle(.secondary)

            Button {
                summarise()
            } label: {
                Label("Summarise with AI", systemImage: "sparkles")
                    .font(.bodySourceSans)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.terracotta)
            .controlSize(.large)
            .disabled(!item.hasAttachment || itemJob?.status == .processing || itemJob?.status == .pending)

            if !item.hasAttachment {
                Text("PDF attachment required for summarisation")
                    .font(.captionSourceSans)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Actions

    private func summarise() {
        // Check Foundation Models availability first
        guard AIService.isAppleIntelligenceAvailable() else {
            showAppleIntelligenceUnavailableAlert = true
            return
        }

        guard let service = summarisationService else {
            errorMessage = "Summarisation service not initialized"
            showError = true
            return
        }

        // Start task on MainActor to access item, then pass to background service
        Task { @MainActor in
            // Capture item on main actor before async boundary
            let itemToSummarise = item
            do {
                try await service.summariseItem(itemToSummarise)
            } catch {
                // Error is already captured in ItemSummaryJob.errorMessage and logged in service
            }
        }
    }

    // MARK: - Export Functions

    /// Generates Markdown content for the summary
    private func generateMarkdownContent(_ processedItem: ProcessedItem) -> String {
        var markdown = ""

        // Title
        markdown += "# \(item.title)\n\n"

        // Metadata
        markdown += "## Metadata\n\n"
        markdown += "- **Authors:** \(item.creatorSummary)\n"
        if let year = item.year {
            markdown += "- **Year:** \(year)\n"
        }
        if let publication = item.publicationTitle {
            markdown += "- **Publication:** \(publication)\n"
        }
        markdown += "- **Item type:** \(item.itemType)\n"
        markdown += "\n"

        // Summary section
        markdown += "## Summary\n\n"
        markdown += processedItem.summaryText
        markdown += "\n\n"

        // Footer
        markdown += "---\n\n"
        markdown += "*Generated on \(processedItem.processedAt.formatted(date: .long, time: .shortened)) using Apple Intelligence*\n"
        if let confidence = processedItem.confidence {
            markdown += "\n*Confidence: \(String(format: "%.1f%%", confidence * 100))*\n"
        }

        return markdown
    }

    /// Generates HTML content for PDF export
    private func generateHTMLContent(_ processedItem: ProcessedItem) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
                    line-height: 1.6;
                    max-width: 800px;
                    margin: 40px auto;
                    padding: 0 20px;
                    color: #333;
                }
                h1 {
                    color: #1a1a1a;
                    border-bottom: 2px solid #B66969;
                    padding-bottom: 10px;
                    margin-bottom: 30px;
                }
                h2 {
                    color: #2c3e50;
                    margin-top: 30px;
                    margin-bottom: 15px;
                }
                .metadata {
                    background-color: #f5f5f5;
                    padding: 15px;
                    border-radius: 8px;
                    margin-bottom: 30px;
                }
                .metadata p {
                    margin: 8px 0;
                }
                .metadata strong {
                    color: #555;
                }
                .summary {
                    text-align: justify;
                    margin: 20px 0;
                }
                .footer {
                    margin-top: 40px;
                    padding-top: 20px;
                    border-top: 1px solid #ddd;
                    font-size: 0.9em;
                    color: #666;
                    font-style: italic;
                }
            </style>
        </head>
        <body>
            <h1>\(item.title.htmlEscaped)</h1>

            <div class="metadata">
                <h2>Metadata</h2>
                <p><strong>Authors:</strong> \(item.creatorSummary.htmlEscaped)</p>
        """

        if let year = item.year {
            html += "<p><strong>Year:</strong> \(year.htmlEscaped)</p>\n"
        }
        if let publication = item.publicationTitle {
            html += "<p><strong>Publication:</strong> \(publication.htmlEscaped)</p>\n"
        }
        html += "<p><strong>Item type:</strong> \(item.itemType.htmlEscaped)</p>\n"

        html += """
            </div>

            <h2>Summary</h2>
            <div class="summary">
                \(processedItem.summaryText.htmlEscaped.replacingOccurrences(of: "\n", with: "<br>"))
            </div>

            <div class="footer">
                <p>Generated on \(processedItem.processedAt.formatted(date: .long, time: .shortened)) using Apple Intelligence</p>
        """

        if let confidence = processedItem.confidence {
            html += "<p>Confidence: \(String(format: "%.1f%%", confidence * 100))</p>\n"
        }

        html += """
            </div>
        </body>
        </html>
        """

        return html
    }

    /// Exports summary as Markdown
    private func exportAsMarkdown(_ processedItem: ProcessedItem) {
        let markdown = generateMarkdownContent(processedItem)
        let fileName = sanitiseFilename(item.title) + ".md"

        // Create temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try markdown.write(to: tempURL, atomically: true, encoding: .utf8)
            exportItem = ExportItem(url: tempURL, type: .markdown)
            showShareSheet = true
        } catch {
            errorMessage = "Failed to create Markdown file: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Exports summary as PDF
    private func exportAsPDF(_ processedItem: ProcessedItem) {
        let html = generateHTMLContent(processedItem)
        let fileName = sanitiseFilename(item.title) + ".pdf"

        // Create temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            // Create PDF from HTML
            guard let pdfData = createPDFData(from: html) else {
                throw NSError(domain: "ItemDetailView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate PDF"])
            }

            try pdfData.write(to: tempURL)
            exportItem = ExportItem(url: tempURL, type: .pdf)
            showShareSheet = true
        } catch {
            errorMessage = "Failed to create PDF file: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Creates PDF data from HTML string
    private func createPDFData(from html: String) -> Data? {
        let printFormatter = UIMarkupTextPrintFormatter(markupText: html)
        let printRenderer = UIPrintPageRenderer()
        printRenderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)

        // Set page size (A4)
        let pageSize = CGSize(width: 595.2, height: 841.8) // A4 in points
        let pageMargins = UIEdgeInsets(top: 72, left: 72, bottom: 72, right: 72) // 1 inch margins
        let printableRect = CGRect(
            x: pageMargins.left,
            y: pageMargins.top,
            width: pageSize.width - pageMargins.left - pageMargins.right,
            height: pageSize.height - pageMargins.top - pageMargins.bottom
        )
        let paperRect = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)

        printRenderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
        printRenderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")

        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, paperRect, nil)

        for i in 0..<printRenderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            printRenderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }

        UIGraphicsEndPDFContext()
        return pdfData as Data
    }

    /// Sanitises filename by removing invalid characters
    private func sanitiseFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    /// Loads the PDF thumbnail asynchronously
    private func loadPDFThumbnail() async {
        guard summarisationService != nil else { return }

        // Download PDF temporarily
        let zoteroService = ZoteroService(oauthService: oauthService)
        var pdfURL: URL?

        // Cleanup on exit
        defer {
            if let url = pdfURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        do {
            // Find PDF attachment
            let children = try await zoteroService.fetchChildren(
                itemKey: item.key,
                libraryType: item.libraryType.rawValue,
                libraryID: item.libraryID
            )

            guard let attachment = children.first(where: {
                $0.data.itemType == "attachment" &&
                $0.data.contentType == "application/pdf"
            }) else {
                return
            }

            // Download the PDF
            pdfURL = try await zoteroService.downloadPDF(
                itemKey: item.key,
                attachmentKey: attachment.key,
                libraryType: item.libraryType.rawValue,
                libraryID: item.libraryID
            )

            // Generate thumbnail
            let extractor = PDFTextExtractor()
            if let thumbnail = await MainActor.run(body: {
                extractor.generateThumbnail(from: pdfURL!, size: CGSize(width: 150, height: 210))
            }) {
                await MainActor.run {
                    pdfThumbnail = thumbnail
                }
            }
        } catch {
            // Silently fail - just don't show thumbnail
        }
    }
}

// MARK: - Supporting Types

/// Temporary file reference for sharing exported summaries
struct ExportItem {
    let url: URL
    let type: ExportType

    enum ExportType {
        case markdown
        case pdf
    }
}

/// UIKit share sheet wrapped for SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

/// HTML escaping for safe insertion into HTML templates
extension String {
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - Previews

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: ZoteroItem.self,
        ProcessedItem.self,
        ItemSummaryJob.self,
        configurations: config
    )

    let sampleItem = ZoteroItem(
        key: "TEST123",
        title: "Sample research paper",
        itemType: "journalArticle",
        creatorSummary: "Smith et al.",
        year: "2024",
        publicationTitle: "Journal of AI Research",
        hasAttachment: true,
        hasSummary: false,
        libraryID: "test",
        version: 1
    )

    let oauthService = ZoteroOAuthService()

    NavigationStack {
        ItemDetailView(item: sampleItem, oauthService: oauthService)
    }
    .modelContainer(container)
}

// MARK: - Preview with Summary

#Preview("With Summary") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: ZoteroItem.self,
        ProcessedItem.self,
        ItemSummaryJob.self,
        configurations: config
    )

    let sampleItem = ZoteroItem(
        key: "TEST456",
        title: "Sample research paper with summary",
        itemType: "journalArticle",
        creatorSummary: "Jones et al.",
        year: "2024",
        publicationTitle: "Nature",
        hasAttachment: true,
        hasSummary: true,
        libraryID: "test",
        version: 1
    )

    let summary = ProcessedItem(
        itemKey: "TEST456",
        summaryText: "This paper presents a comprehensive analysis of machine learning techniques applied to natural language processing. The authors demonstrate significant improvements in model performance through novel architectural innovations.",
        processedAt: Date(),
        confidence: 0.92,
        wordCount: 250,
        status: .uploaded
    )

    let _ = {
        sampleItem.summary = summary
        container.mainContext.insert(sampleItem)
        container.mainContext.insert(summary)
    }()

    let oauthService = ZoteroOAuthService()

    return NavigationStack {
        ItemDetailView(item: sampleItem, oauthService: oauthService)
    }
    .modelContainer(container)
}
