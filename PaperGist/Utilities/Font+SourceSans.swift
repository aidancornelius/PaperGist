//
//  Font+SourceSans.swift
//  PaperGist
//
//  SwiftUI font extensions for Source Sans 3.
//  Provides weight variants and semantic text styles.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import SwiftUI

extension Font {
    // MARK: - Source Sans 3 weights

    static func sourceSans(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Regular", size: size)
    }

    static func sourceSansLight(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Light", size: size)
    }

    static func sourceSansExtraLight(_ size: CGFloat) -> Font {
        .custom("SourceSans3-ExtraLight", size: size)
    }

    static func sourceSansMedium(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Medium", size: size)
    }

    static func sourceSansSemiBold(_ size: CGFloat) -> Font {
        .custom("SourceSans3-SemiBold", size: size)
    }

    static func sourceSansBold(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Bold", size: size)
    }

    static func sourceSansExtraBold(_ size: CGFloat) -> Font {
        .custom("SourceSans3-ExtraBold", size: size)
    }

    static func sourceSansBlack(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Black", size: size)
    }

    // MARK: - Italic variants

    static func sourceSansItalic(_ size: CGFloat) -> Font {
        .custom("SourceSans3-Italic", size: size)
    }

    static func sourceSansLightItalic(_ size: CGFloat) -> Font {
        .custom("SourceSans3-LightItalic", size: size)
    }

    static func sourceSansMediumItalic(_ size: CGFloat) -> Font {
        .custom("SourceSans3-MediumItalic", size: size)
    }

    static func sourceSansSemiBoldItalic(_ size: CGFloat) -> Font {
        .custom("SourceSans3-SemiBoldItalic", size: size)
    }

    static func sourceSansBoldItalic(_ size: CGFloat) -> Font {
        .custom("SourceSans3-BoldItalic", size: size)
    }

    // MARK: - Semantic text styles

    static var largeTitleSourceSans: Font {
        .sourceSansBold(34)
    }

    static var titleSourceSans: Font {
        .sourceSansBold(22)
    }

    static var title2SourceSans: Font {
        .sourceSansBold(20)
    }

    static var headlineSourceSans: Font {
        .sourceSansBold(17)
    }

    static var bodySourceSans: Font {
        .sourceSans(17)
    }

    static var bodyMediumSourceSans: Font {
        .sourceSansMedium(17)
    }

    static var subheadlineSourceSans: Font {
        .sourceSans(15)
    }

    static var subheadlineMediumSourceSans: Font {
        .sourceSansMedium(15)
    }

    static var calloutSourceSans: Font {
        .sourceSansBold(17)
    }

    static var captionSourceSans: Font {
        .sourceSans(13)
    }

    static var caption2SourceSans: Font {
        .sourceSans(11)
    }
}
