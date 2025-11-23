//
//  AppLogger.swift
//  PaperGist
//
//  Centralised logging using Apple's unified logging system.
//  Organises logs by category for filtering in Console.app.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import Foundation
import OSLog

/// Categorised loggers for different app subsystems
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.cornelius-bell.PaperGist"

    // MARK: - Logger categories

    static let auth = Logger(subsystem: subsystem, category: "Authentication")
    static let sync = Logger(subsystem: subsystem, category: "Sync")
    static let ai = Logger(subsystem: subsystem, category: "AI")
    static let jobs = Logger(subsystem: subsystem, category: "Jobs")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let general = Logger(subsystem: subsystem, category: "General")
}
