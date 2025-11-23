// WidgetIntegration.swift
// PaperGist
//
// Convenience helper for updating widgets from anywhere in the app.
// Wraps WidgetUpdateService for simple integration.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftData

/// Helper to update widgets from anywhere in the app
@MainActor
struct WidgetUpdater {
    let modelContext: ModelContext

    func updateWidgets() {
        let widgetService = WidgetUpdateService(modelContext: modelContext)
        widgetService.updateWidgets()
    }
}

// Integration points:
//
// 1. After library sync completes
// 2. After a summary is processed
// 3. When app enters background
