//
//  PaperGistWidgets.swift
//  PaperGist
//
//  Widget bundle entry point for PaperGist.
//  Currently only includes Live Activities; standard widgets are disabled.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import WidgetKit
import SwiftUI

@main
struct PaperGistWidgets: WidgetBundle {
    var body: some Widget {
        // Standard widgets disabled - keeping only Live Activity
        // SummaryStatsWidget()
        // RecentSummariesWidget()
        SummaryJobLiveActivity()
    }
}
