// PDFTextExtractor.swift
// PaperGist
//
// Extracts text content from PDF files using PDFKit. Validates text quality
// and detects scanned PDFs with insufficient extractable text.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PDFKit
import Foundation
import UIKit
import OSLog

enum PDFExtractionError: LocalizedError {
    case invalidPDF
    case insufficientText
    case extractionFailed
    case scannedPDF

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "Could not open PDF file"
        case .insufficientText:
            return "Could not extract enough text from PDF (may be scanned images)"
        case .extractionFailed:
            return "Text extraction failed"
        case .scannedPDF:
            return "This appears to be a scanned PDF with minimal extractable text. Consider using OCR or accessing the original digital version."
        }
    }
}

final class PDFTextExtractor {

    /// Extracts text from a PDF file with progress updates
    /// - Parameters:
    ///   - pdfURL: URL to the PDF file
    ///   - progressHandler: Called with progress (0.0-1.0) and status message
    /// - Returns: Extracted text as a single string
    func extractText(
        from pdfURL: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> String {
        // Check cancellation before starting
        try Task.checkCancellation()

        // Load PDF document
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw PDFExtractionError.invalidPDF
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw PDFExtractionError.invalidPDF
        }

        var fullText = ""

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()

            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            guard let pageText = page.string else { continue }

            fullText += pageText + "\n\n"

            let progress = Double(pageIndex + 1) / Double(pageCount)
            progressHandler(progress, "Extracting page \(pageIndex + 1) of \(pageCount)...")

            await Task.yield()
        }

        try Task.checkCancellation()

        fullText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard fullText.count > 100 else {
            throw PDFExtractionError.insufficientText
        }

        // Detect scanned PDFs by checking text density
        let expectedCharsPerPage = 2000
        let expectedTotalChars = pageCount * expectedCharsPerPage
        let textRatio = Double(fullText.count) / Double(expectedTotalChars)

        if textRatio < 0.1 {
            AppLogger.general.warning("Low text ratio detected in PDF: \(String(format: "%.2f%%", textRatio * 100)), extracted \(fullText.count) chars from \(pageCount) pages (expected ~\(expectedTotalChars))")
            throw PDFExtractionError.scannedPDF
        }

        return fullText
    }

    /// Generates a thumbnail image from the first page of a PDF
    /// - Parameters:
    ///   - url: URL to the PDF file
    ///   - size: Desired size of the thumbnail (default: 200x280)
    /// - Returns: UIImage thumbnail, or nil if generation fails
    func generateThumbnail(from url: URL, size: CGSize = CGSize(width: 200, height: 280)) -> UIImage? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else {
            return nil
        }

        return page.thumbnail(of: size, for: .cropBox)
    }
}
