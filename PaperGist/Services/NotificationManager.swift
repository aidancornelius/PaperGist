// NotificationManager.swift
// PaperGist
//
// Manages local notifications for batch job events including completion, failures,
// and cancellations. Implements rate limiting to prevent notification spam.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import UserNotifications
import OSLog

/// Manages local notifications for batch job completion
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorised = false
    private let notificationCenter = UNUserNotificationCenter.current()

    private var lastNotificationTime: [String: Date] = [:]
    private let minimumNotificationInterval: TimeInterval = 5.0

    override private init() {
        super.init()
    }

    // MARK: - Rate Limiting

    /// Checks if enough time has passed since last notification of this type
    private func canSendNotification(category: String) -> Bool {
        guard let lastTime = lastNotificationTime[category] else {
            return true // No previous notification of this type
        }

        let timeSinceLastNotification = Date().timeIntervalSince(lastTime)
        return timeSinceLastNotification >= minimumNotificationInterval
    }

    /// Records that a notification was sent
    private func recordNotificationSent(category: String) {
        lastNotificationTime[category] = Date()
    }

    // MARK: - Permission Management

    /// Requests notification permissions from the user
    func requestAuthorisation() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorised = granted

            if !granted {
                AppLogger.notifications.warning("Notification permissions denied")
            }
        } catch {
            AppLogger.notifications.error("Failed to request notification permissions: \(error.localizedDescription)")
            isAuthorised = false
        }
    }

    /// Checks current notification authorisation status
    func checkAuthorisationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        isAuthorised = settings.authorizationStatus == .authorized
    }

    // MARK: - Notification Sending

    /// Sends a notification when batch job completes successfully
    func sendBatchCompletionNotification(successCount: Int, totalCount: Int, failedCount: Int) async {
        guard isAuthorised else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Batch summarisation complete"

        if failedCount == 0 {
            content.body = "Successfully summarised all \(successCount) papers"
        } else if successCount == 0 {
            content.body = "Failed to summarise all \(totalCount) papers"
        } else {
            content.body = "Successfully summarised \(successCount) of \(totalCount) papers"
        }

        content.sound = .default
        content.categoryIdentifier = "BATCH_COMPLETION"

        // Add badge count (number of completed jobs)
        content.badge = 1

        // Deliver immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            AppLogger.notifications.error("Failed to send batch completion notification: \(error.localizedDescription)")
        }
    }

    /// Sends a notification when batch job fails
    func sendBatchFailureNotification(errorMessage: String) async {
        guard isAuthorised else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Batch summarisation failed"
        content.body = errorMessage
        content.sound = .default
        content.categoryIdentifier = "BATCH_FAILURE"

        // Deliver immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            AppLogger.notifications.error("Failed to send notification: \(error.localizedDescription)")
        }
    }

    /// Sends a notification when batch job is cancelled
    func sendBatchCancellationNotification(processedCount: Int, totalCount: Int) async {
        guard isAuthorised else {
            return
        }

        // Rate limiting check
        let category = "BATCH_CANCELLED"
        guard canSendNotification(category: category) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Batch summarisation cancelled"
        content.body = "Cancelled after processing \(processedCount) of \(totalCount) papers"
        content.sound = .default
        content.categoryIdentifier = category

        // Deliver immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            recordNotificationSent(category: category)
        } catch {
            AppLogger.notifications.error("Failed to send notification: \(error.localizedDescription)")
        }
    }

    /// Sends a notification when batch job is paused/interrupted
    func sendBatchPausedNotification(processedCount: Int, totalCount: Int) async {
        guard isAuthorised else {
            return
        }

        // Rate limiting check
        let category = "BATCH_PAUSED"
        guard canSendNotification(category: category) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Batch summarisation paused"

        // Handle singular/plural for papers
        let papersWord = totalCount == 1 ? "paper" : "papers"
        let remainingCount = totalCount - processedCount

        if remainingCount > 0 {
            content.body = "Paused with \(remainingCount) \(papersWord) remaining. Will resume when you return to the app."
        } else {
            content.body = "Paused after processing \(processedCount) \(papersWord). Will resume when you return to the app."
        }

        content.sound = .default
        content.categoryIdentifier = category

        // Deliver immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            recordNotificationSent(category: category)
        } catch {
            AppLogger.notifications.error("Failed to send notification: \(error.localizedDescription)")
        }
    }

    /// Clears all delivered notifications
    func clearAllNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
    }

    /// Clears badge count
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Called when app is in foreground and notification is delivered
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notification even when app is in foreground
        return [.banner, .sound, .badge]
    }

    /// Called when user taps on notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let categoryIdentifier = response.notification.request.content.categoryIdentifier

        // Handle different notification categories
        // Note: Navigation would need to be implemented via a notification/deep link system
        // For now, just acknowledge the tap without crashing
        switch categoryIdentifier {
        case "BATCH_COMPLETION", "BATCH_FAILURE", "BATCH_CANCELLED", "BATCH_PAUSED":
            break
        default:
            break
        }

        // The app will become active when the notification is tapped
        // Any restored jobs will automatically be shown in the UI
    }
}
