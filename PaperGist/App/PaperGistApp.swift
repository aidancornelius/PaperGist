//
//  PaperGistApp.swift
//  PaperGist
//
//  Main application entry point for PaperGist - an iOS app for AI-powered
//  summarisation of academic papers from Zotero libraries.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct PaperGistApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let modelContainer: ModelContainer
    @StateObject private var notificationManager = NotificationManager.shared

    init() {
        do {
            modelContainer = try ModelContainer(
                for: ZoteroItem.self, ProcessedItem.self, SummaryJob.self, ItemSummaryJob.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            )
        } catch {
            fatalError("Failed to initialise model container: \(error)")
        }

        setupNotifications()
        configureNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .font(.bodySourceSans)
        }
    }

    /// Configures the notification manager as the UNUserNotificationCenter delegate
    private func setupNotifications() {
        Task { @MainActor in
            UNUserNotificationCenter.current().delegate = NotificationManager.shared
        }
    }

    /// Applies Source Sans font to all navigation bars throughout the app
    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()

        let largeTitleFont = UIFont(name: "SourceSans3-Bold", size: 34) ?? UIFont.boldSystemFont(ofSize: 34)
        appearance.largeTitleTextAttributes = [.font: largeTitleFont]

        let titleFont = UIFont(name: "SourceSans3-SemiBold", size: 17) ?? UIFont.boldSystemFont(ofSize: 17)
        appearance.titleTextAttributes = [.font: titleFont]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
}
