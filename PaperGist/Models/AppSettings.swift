//
//  AppSettings.swift
//  PaperGist
//
//  App-wide user preferences and configuration stored in UserDefaults.
//  Manages summarisation settings, library sync preferences, and onboarding state.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import Foundation

/// Application settings and user preferences stored in UserDefaults
@MainActor
final class AppSettings: ObservableObject {
    /// Singleton instance safe for background access via MainActor.run
    static let shared = MainActor.assumeIsolated {
        AppSettings()
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let skipItemsWithNotes = "skipItemsWithNotes"
        static let autoUploadToZotero = "autoUploadToZotero"
        static let addAISummaryTag = "addAISummaryTag"
        static let customPrompt = "customPrompt"
        static let summaryLength = "summaryLength"
        static let batchSize = "batchSize"
        static let backgroundSyncEnabled = "backgroundSyncEnabled"
        static let totalZoteroItems = "totalZoteroItems"
        static let lastLibraryVersion = "lastLibraryVersion"
        static let hasSeenNotificationOnboarding = "hasSeenNotificationOnboarding"
    }

    // MARK: - Default values

    /// Default system prompt for AI summarisation across all academic disciplines
    static let defaultPrompt = """
    You are an academic research assistant. Your task is to summarise research papers concisely and accurately across all disciplines.

    FORMATTING REQUIREMENTS:
    - Use sentence case for all headings (e.g., "Main argument", not "Main Argument")
    - Structure the summary with 3-4 clear subheadings using bold markdown (e.g., **Main argument**, **Key concepts**)
    - Choose headings appropriate to the paper's discipline and type
    - Use bullet points for lists where appropriate
    - Keep paragraphs concise and well-separated
    - Use consistent, appropriate tense

    CONTENT STRUCTURE:
    Adapt your summary structure to the paper type. Use appropriate headings from these examples:

    For empirical research: **Research question**, **Methodology**, **Key findings**, **Implications**

    For theoretical/conceptual papers: **Central argument**, **Theoretical framework**, **Key concepts**, **Contributions**

    For literature reviews: **Scope**, **Main themes**, **Key debates**, **Synthesis**

    For philosophy/critical theory: **Main argument**, **Philosophical framework**, **Key claims**, **Implications**

    For historical/interpretive work: **Topic and context**, **Approach**, **Main argument**, **Significance**

    Choose the most relevant structure for the paper. Each section should be substantive and informative.

    Keep the summary to 200-300 words total. Use clear, professional academic language.

    After the summary, on a new line, include a confidence score indicating how well the summary captures the paper's content.
    Format: "Confidence: X.XX" where X.XX is a number between 0.00 and 1.00.
    """

    // MARK: - General settings

    /// Skips items that already have notes during library sync
    @Published var skipItemsWithNotes: Bool {
        didSet {
            defaults.set(skipItemsWithNotes, forKey: Keys.skipItemsWithNotes)
        }
    }

    /// Automatically uploads generated summaries to Zotero as notes
    @Published var autoUploadToZotero: Bool {
        didSet {
            defaults.set(autoUploadToZotero, forKey: Keys.autoUploadToZotero)
        }
    }

    /// Tags items with #ai-summary after summarisation
    @Published var addAISummaryTag: Bool {
        didSet {
            defaults.set(addAISummaryTag, forKey: Keys.addAISummaryTag)
        }
    }

    // MARK: - Summarisation settings

    /// Custom system prompt for AI summarisation (nil uses default)
    @Published var customPrompt: String? {
        didSet {
            defaults.set(customPrompt, forKey: Keys.customPrompt)
        }
    }

    /// Target length for generated summaries
    @Published var summaryLength: SummaryLength {
        didSet {
            defaults.set(summaryLength.rawValue, forKey: Keys.summaryLength)
        }
    }

    // MARK: - Batch processing settings

    /// Maximum items to process in a single batch job (clamped 1-50)
    @Published var batchSize: Int {
        didSet {
            let clamped = min(max(batchSize, 1), 50)
            if clamped != batchSize {
                batchSize = clamped
            }
            defaults.set(batchSize, forKey: Keys.batchSize)
        }
    }

    /// Enables background library sync and summarisation
    @Published var backgroundSyncEnabled: Bool {
        didSet {
            defaults.set(backgroundSyncEnabled, forKey: Keys.backgroundSyncEnabled)
        }
    }

    // MARK: - Library statistics

    /// Total items in Zotero library (from most recent API response)
    @Published var totalZoteroItems: Int? {
        didSet {
            if let total = totalZoteroItems {
                defaults.set(total, forKey: Keys.totalZoteroItems)
            } else {
                defaults.removeObject(forKey: Keys.totalZoteroItems)
            }
        }
    }

    /// Library version number for incremental sync
    @Published var lastLibraryVersion: Int? {
        didSet {
            if let version = lastLibraryVersion {
                defaults.set(version, forKey: Keys.lastLibraryVersion)
            } else {
                defaults.removeObject(forKey: Keys.lastLibraryVersion)
            }
        }
    }

    // MARK: - Onboarding

    /// Whether the user has completed notification permission onboarding
    @Published var hasSeenNotificationOnboarding: Bool {
        didSet {
            defaults.set(hasSeenNotificationOnboarding, forKey: Keys.hasSeenNotificationOnboarding)
        }
    }

    private init() {
        self.skipItemsWithNotes = defaults.bool(forKey: Keys.skipItemsWithNotes)
        self.autoUploadToZotero = defaults.object(forKey: Keys.autoUploadToZotero) as? Bool ?? true
        self.addAISummaryTag = defaults.object(forKey: Keys.addAISummaryTag) as? Bool ?? true
        self.customPrompt = defaults.string(forKey: Keys.customPrompt)

        let lengthRawValue = defaults.string(forKey: Keys.summaryLength) ?? SummaryLength.medium.rawValue
        self.summaryLength = SummaryLength(rawValue: lengthRawValue) ?? .medium

        self.batchSize = defaults.object(forKey: Keys.batchSize) as? Int ?? 10
        self.backgroundSyncEnabled = defaults.bool(forKey: Keys.backgroundSyncEnabled)
        self.totalZoteroItems = defaults.object(forKey: Keys.totalZoteroItems) as? Int
        self.lastLibraryVersion = defaults.object(forKey: Keys.lastLibraryVersion) as? Int
        self.hasSeenNotificationOnboarding = defaults.bool(forKey: Keys.hasSeenNotificationOnboarding)
    }

    /// Clears the custom prompt and reverts to the default
    func resetToDefaultPrompt() {
        customPrompt = nil
    }

    /// Returns the currently active prompt (custom or default)
    var activePrompt: String {
        customPrompt ?? Self.defaultPrompt
    }
}

// MARK: - Summary length

/// Target word count ranges for generated summaries
enum SummaryLength: String, CaseIterable, Identifiable {
    case short = "short"
    case medium = "medium"
    case long = "long"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short: return "Short (100-150 words)"
        case .medium: return "Medium (200-300 words)"
        case .long: return "Long (400-500 words)"
        }
    }

    var wordCount: String {
        switch self {
        case .short: return "100-150 words"
        case .medium: return "200-300 words"
        case .long: return "400-500 words"
        }
    }

    var maxTokens: Int {
        switch self {
        case .short: return 250
        case .medium: return 500
        case .long: return 750
        }
    }
}
