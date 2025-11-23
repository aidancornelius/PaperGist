//
//  String+OAuth.swift
//  PaperGist
//
//  String extension for OAuth 1.0a percent encoding.
//
//  Created by Aidan Cornelius-Bell on 15/01/2025.
//  Licensed under the Mozilla Public License 2.0
//

import Foundation

extension String {
    /// Percent encodes string per OAuth 1.0a RFC 5849
    /// Unreserved characters: ALPHA / DIGIT / "-" / "." / "_" / "~"
    func percentEncoded() -> String {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? self
    }
}
