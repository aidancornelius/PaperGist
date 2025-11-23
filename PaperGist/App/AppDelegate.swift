//
//  AppDelegate.swift
//  PaperGist
//
//  Handles app lifecycle events and manages background task registration.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import UIKit
import BackgroundTasks
import OSLog

/// Application delegate managing lifecycle events and background task scheduling
class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - App launch

    /// Registers background task handlers and schedules the initial background refresh
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundTaskManager.shared.registerBackgroundTasks()

        Task {
            await BackgroundTaskManager.shared.scheduleBackgroundTask()
        }

        return true
    }

    // MARK: - Background refresh

    /// Legacy background fetch method - reports new data available
    /// Actual background work is handled by BGTaskScheduler
    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(.newData)
    }

    // MARK: - Scene lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        return configuration
    }

    // MARK: - App state transitions

    /// Schedules background tasks when the app moves to the background
    func applicationDidEnterBackground(_ application: UIApplication) {
        Task {
            await BackgroundTaskManager.shared.scheduleBackgroundTask()
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }
}
