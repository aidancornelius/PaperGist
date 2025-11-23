// AIService.swift
// PaperGist
//
// Provides on-device AI summarisation using Apple's Foundation Models framework.
// Handles text generation, confidence parsing, and model availability checks.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import FoundationModels
import OSLog

enum AIError: LocalizedError {
    case modelNotAvailable
    case generationFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "On-device AI is not available on this device"
        case .generationFailed:
            return "Failed to generate summary"
        case .invalidResponse:
            return "Received invalid response from AI service"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotAvailable:
            return "Foundation Models require iOS 26 or later on iPhone 16 Pro or newer. Visit apple.com/apple-intelligence for compatible devices."
        default:
            return nil
        }
    }
}

@MainActor
final class AIService {

    /// Result type for AI summary generation
    struct SummaryResult {
        let summary: String
        let confidence: Double?
    }

    /// Checks if Foundation Models are available on this device
    /// - Returns: True if the model is available, false otherwise
    static func isAppleIntelligenceAvailable() -> Bool {
        let model = SystemLanguageModel.default
        return model.isAvailable
    }

    /// Throws an error if Foundation Models are not available
    static func checkAppleIntelligenceAvailability() throws {
        guard isAppleIntelligenceAvailable() else {
            throw AIError.modelNotAvailable
        }
    }

    /// Generates a summary of academic paper text using on-device Foundation Models
    /// - Parameters:
    ///   - text: The full text extracted from the PDF
    ///   - customPrompt: Optional custom prompt to override default and AppSettings
    /// - Returns: A SummaryResult containing the summary text and optional confidence score (0.0-1.0)
    func summarisePaper(text: String, customPrompt: String? = nil) async throws -> SummaryResult {
        // Truncate to ~10k characters to stay within model context limits
        let truncatedText = String(text.prefix(10000))

        // Use custom prompt if provided, otherwise use AppSettings active prompt
        let instructions = customPrompt ?? AppSettings.shared.activePrompt

        let userPrompt = """
        Please summarise this academic paper:

        \(truncatedText)
        """

        do {
            let response = try await generateWithFoundationModels(
                instructions: instructions,
                prompt: userPrompt
            )

            guard !response.isEmpty else {
                throw AIError.invalidResponse
            }

            let (summary, confidence) = parseConfidence(from: response)

            return SummaryResult(summary: summary, confidence: confidence)

        } catch {
            AppLogger.ai.error("Foundation Models generation failed: \(error.localizedDescription)")
            throw AIError.generationFailed
        }
    }

    /// Parses the confidence score from the AI response
    ///
    /// Looks for a "Confidence: X.XX" pattern in the response and extracts it,
    /// removing the confidence line from the final summary text.
    ///
    /// - Parameter response: The raw AI response text
    /// - Returns: A tuple containing the summary text (with confidence line removed) and optional confidence score
    private func parseConfidence(from response: String) -> (summary: String, confidence: Double?) {
        let pattern = "Confidence:\\s*(\\d+\\.\\d+)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
              let confidenceRange = Range(match.range(at: 1), in: response),
              let confidence = Double(response[confidenceRange]) else {
            return (response.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let summaryWithoutConfidence = regex.stringByReplacingMatches(
            in: response,
            options: [],
            range: NSRange(response.startIndex..., in: response),
            withTemplate: ""
        )

        let cleanedSummary = summaryWithoutConfidence.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clamp confidence to valid range
        let validatedConfidence = min(max(confidence, 0.0), 1.0)

        return (cleanedSummary, validatedConfidence)
    }

    /// Generates text using Foundation Models
    ///
    /// Configures a language model session with the provided instructions and generates
    /// a response using a low temperature for consistent outputs.
    ///
    /// - Parameters:
    ///   - instructions: System instructions for the model
    ///   - prompt: User prompt to respond to
    /// - Returns: The generated response content
    private func generateWithFoundationModels(
        instructions: String,
        prompt: String
    ) async throws -> String {
        let model = SystemLanguageModel.default

        guard model.isAvailable else {
            throw AIError.modelNotAvailable
        }

        let session = LanguageModelSession(
            model: model,
            instructions: instructions
        )

        let options = GenerationOptions(
            temperature: 0.3,
            maximumResponseTokens: AppSettings.shared.summaryLength.maxTokens
        )

        let response = try await session.respond(
            to: prompt,
            options: options
        )

        return response.content
    }
}
