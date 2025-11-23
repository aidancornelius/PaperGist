//
//  Font+SourceSans.swift
//  PaperGist
//
//  Font extension providing Source Sans 3 typography for the app.
//  Includes weight variants and semantic text styles.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

extension Font {
    // MARK: - Source Sans 3 Font Family

    /// Regular weight Source Sans 3
    static func sourceSans(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Regular", size: size)
    }

    /// Light weight Source Sans 3
    static func sourceSansLight(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Light", size: size)
    }

    /// Extra Light weight Source Sans 3
    static func sourceSansExtraLight(_ size: CGFloat) -> Font {
        .custom("SourceSans3-ExtraLight", size: size)
    }

    /// Medium weight Source Sans 3
    static func sourceSansMedium(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Medium", size: size)
    }

    /// Semi Bold weight Source Sans 3
    static func sourceSansSemiBold(_ size: CGFloat) -> Font {
        .custom("SourceSans3-SemiBold", size: size)
    }

    /// Bold weight Source Sans 3
    static func sourceSansBold(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Bold", size: size)
    }

    /// Extra Bold weight Source Sans 3
    static func sourceSansExtraBold(_ size: CGFloat) -> Font {
        .custom("SourceSans3-ExtraBold", size: size)
    }

    /// Black weight Source Sans 3
    static func sourceSansBlack(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Black", size: size)
    }

    // MARK: - Italic Variants

    /// Italic Source Sans 3
    static func sourceSansItalic(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Italic", size: size)
    }

    /// Light Italic Source Sans 3
    static func sourceSansLightItalic(_ size: CGFloat) -> Font {
        .custom("SourceSans3-LightItalic", size: size)
    }

    /// Medium Italic Source Sans 3
    static func sourceSansMediumItalic(_ size: CGFloat) -> Font {
        .custom("SourceSans3-MediumItalic", size: size)
    }

    /// Semi Bold Italic Source Sans 3
    static func sourceSansSemiBoldItalic(_ size: CGFloat) -> Font {
        .custom("SourceSans3-SemiBoldItalic", size: size)
    }

    /// Bold Italic Source Sans 3
    static func sourceSansBoldItalic(_ size: CGFloat) -> Font {
        .custom("SourceSans3-BoldItalic", size: size)
    }

    // MARK: - Semantic Text Styles

    /// Large title at 34pt bold
    static var largeTitleSourceSans: Font {
        .sourceSansBold(34)
    }

    /// Title at 22pt bold
    static var titleSourceSans: Font {
        .sourceSansBold(22)
    }

    /// Title 2 at 20pt bold
    static var title2SourceSans: Font {
        .sourceSansBold(20)
    }

    /// Headline at 17pt bold
    static var headlineSourceSans: Font {
        .sourceSansBold(17)
    }

    /// Body at 17pt regular
    static var bodySourceSans: Font {
        .sourceSans(17)
    }

    /// Body at 17pt medium
    static var bodyMediumSourceSans: Font {
        .sourceSansMedium(17)
    }

    /// Subheadline at 15pt regular
    static var subheadlineSourceSans: Font {
        .sourceSans(15)
    }

    /// Subheadline at 15pt medium
    static var subheadlineMediumSourceSans: Font {
        .sourceSansMedium(15)
    }

    /// Callout at 15pt bold
    static var calloutSourceSans: Font {
        .sourceSansBold(15)
    }

    /// Caption at 13pt regular
    static var captionSourceSans: Font {
        .sourceSans(13)
    }

    /// Caption 2 at 11pt regular
    static var caption2SourceSans: Font {
        .sourceSans(11)
    }
}
