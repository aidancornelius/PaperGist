// ZoteroService.swift
// PaperGist
//
// Handles all Zotero API operations including fetching library items, downloading
// PDF attachments, and creating notes. Supports both user and group libraries with
// incremental sync capabilities.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import CryptoKit
import OSLog

/// Handles all Zotero API operations
final class ZoteroService: @unchecked Sendable {
    private let baseURL = "https://api.zotero.org"
    private let oauthService: ZoteroOAuthService

    init(oauthService: ZoteroOAuthService) {
        self.oauthService = oauthService
    }

    // MARK: - Library Operations

    /// Tests API access by fetching user keys
    func testAPIAccess() async throws {
        guard let credentials = oauthService.getCredentials() else {
            throw ZoteroError.notAuthenticated
        }

        let endpoint = "/keys/current"
        let components = URLComponents(string: baseURL + endpoint)!
        guard let url = components.url else {
            throw ZoteroError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.setValue(credentials.accessTokenSecret, forHTTPHeaderField: "Zotero-API-Key")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ZoteroError.requestFailed
        }
    }

    /// Fetches items from a library with support for pagination and incremental sync
    /// - Parameters:
    ///   - limit: Maximum items per page (max 100)
    ///   - start: Pagination offset
    ///   - libraryType: "user" or "group"
    ///   - libraryID: Library identifier
    ///   - since: Library version for incremental sync (only fetch items modified since this version)
    /// - Returns: Items, total count, and current library version
    func fetchItems(limit: Int = 100, start: Int = 0, libraryType: String? = nil, libraryID: String? = nil, since: Int? = nil) async throws -> (items: [ZoteroAPIItem], totalCount: Int?, libraryVersion: Int?) {
        guard let credentials = oauthService.getCredentials() else {
            throw ZoteroError.notAuthenticated
        }

        let libID = libraryID ?? credentials.userID
        let libraryPath = buildLibraryPath(libraryType: libraryType, libraryID: libID, credentials: credentials)
        let endpoint = "\(libraryPath)/items"
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(min(limit, 100))"), // Zotero API max is 100
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "include", value: "data")
        ]

        if start > 0 {
            queryItems.append(URLQueryItem(name: "start", value: "\(start)"))
        }

        if let since = since {
            queryItems.append(URLQueryItem(name: "since", value: "\(since)"))
        }

        return try await makeAuthenticatedRequestWithTotal(
            endpoint: endpoint,
            queryItems: queryItems,
            credentials: credentials
        )
    }

    /// Fetches child items (attachments, notes) for a specific item
    /// - Parameters:
    ///   - itemKey: The item key
    ///   - libraryType: "user" or "group" (defaults to "user")
    ///   - libraryID: The library ID (defaults to user's ID for user libraries)
    func fetchChildren(itemKey: String, libraryType: String? = nil, libraryID: String? = nil) async throws -> [ZoteroAPIItem] {
        guard let credentials = oauthService.getCredentials() else {
            throw ZoteroError.notAuthenticated
        }

        let libID = libraryID ?? credentials.userID
        let libraryPath = buildLibraryPath(libraryType: libraryType, libraryID: libID, credentials: credentials)
        let endpoint = "\(libraryPath)/items/\(itemKey)/children"

        return try await makeAuthenticatedRequest(
            endpoint: endpoint,
            queryItems: [],
            credentials: credentials
        )
    }

    /// Downloads a PDF attachment
    ///
    /// Handles redirects to S3 storage and saves the file to a temporary location.
    ///
    /// - Parameters:
    ///   - itemKey: Parent item key
    ///   - attachmentKey: Attachment key
    ///   - libraryType: "user" or "group"
    ///   - libraryID: Library identifier
    /// - Returns: URL to the downloaded PDF file in the temp directory
    func downloadPDF(itemKey: String, attachmentKey: String, libraryType: String? = nil, libraryID: String? = nil) async throws -> URL {
        guard let credentials = oauthService.getCredentials() else {
            throw ZoteroError.notAuthenticated
        }

        let libID = libraryID ?? credentials.userID
        let libraryPath = buildLibraryPath(libraryType: libraryType, libraryID: libID, credentials: credentials)
        let endpoint = "\(libraryPath)/items/\(attachmentKey)/file"

        var components = URLComponents(string: baseURL + endpoint)!
        components.queryItems = []

        guard let url = components.url else {
            throw ZoteroError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.setValue(credentials.accessTokenSecret, forHTTPHeaderField: "Zotero-API-Key")

        let (tempURL, response) = try await URLSession.shared.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ZoteroError.invalidResponse
        }

        // Zotero API redirects to S3 for actual file download
        if httpResponse.statusCode == 302,
           let locationHeader = httpResponse.value(forHTTPHeaderField: "Location"),
           let redirectURL = URL(string: locationHeader) {
            try? FileManager.default.removeItem(at: tempURL)

            let (downloadedURL, _) = try await URLSession.shared.download(from: redirectURL)
            return try moveToTempFile(from: downloadedURL, key: attachmentKey)
        }

        guard httpResponse.statusCode == 200 else {
            // Clean up the temporary file
            try? FileManager.default.removeItem(at: tempURL)
            throw ZoteroError.downloadFailed(httpResponse.statusCode)
        }

        return try moveToTempFile(from: tempURL, key: attachmentKey)
    }

    /// Creates a child note for an item
    ///
    /// Uploads HTML-formatted note content to Zotero as a child note of the specified item.
    ///
    /// - Parameters:
    ///   - itemKey: Parent item key
    ///   - content: Note content in HTML format
    ///   - addTag: Whether to add the #ai-summary tag
    ///   - libraryType: "user" or "group"
    ///   - libraryID: Library identifier
    /// - Returns: The created note's key
    func createNote(itemKey: String, content: String, addTag: Bool, libraryType: String? = nil, libraryID: String? = nil) async throws -> String {
        guard let credentials = oauthService.getCredentials() else {
            throw ZoteroError.notAuthenticated
        }

        let libID = libraryID ?? credentials.userID
        let libraryPath = buildLibraryPath(libraryType: libraryType, libraryID: libID, credentials: credentials)
        let endpoint = "\(libraryPath)/items"

        var tags: [[String: Any]] = []
        if addTag {
            tags.append(["tag": "#ai-summary"])
        }

        let noteData: [String: Any] = [
            "itemType": "note",
            "parentItem": itemKey,
            "note": content,
            "tags": tags
        ]

        let payload: [[String: Any]] = [noteData]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        let components = URLComponents(string: baseURL + endpoint)!
        guard let url = components.url else {
            throw ZoteroError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.accessTokenSecret, forHTTPHeaderField: "Zotero-API-Key")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ZoteroError.uploadFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? [String: String],
              let noteKey = success.values.first else {
            throw ZoteroError.invalidResponse
        }

        return noteKey
    }

    // MARK: - Private Helpers

    /// Builds the library path for API requests
    private func buildLibraryPath(libraryType: String?, libraryID: String, credentials: ZoteroOAuthCredentials) -> String {
        if libraryType == "group" {
            return "/groups/\(libraryID)"
        } else {
            return "/users/\(credentials.userID)"
        }
    }

    private func makeAuthenticatedRequest<T: Decodable>(
        endpoint: String,
        queryItems: [URLQueryItem],
        credentials: ZoteroOAuthCredentials
    ) async throws -> T {
        var components = URLComponents(string: baseURL + endpoint)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw ZoteroError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.setValue(credentials.accessTokenSecret, forHTTPHeaderField: "Zotero-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.network.error("Zotero API Error: Invalid response type")
            throw ZoteroError.requestFailed
        }

        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            AppLogger.network.error("Zotero API Error: Status \(httpResponse.statusCode), URL: \(url), Response: \(responseBody)")
            throw ZoteroError.requestFailed
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            AppLogger.network.error("Zotero API decoding error: \(error.localizedDescription)")
            throw ZoteroError.decodingFailed
        }
    }

    private func makeAuthenticatedRequestWithTotal<T: Decodable>(
        endpoint: String,
        queryItems: [URLQueryItem],
        credentials: ZoteroOAuthCredentials
    ) async throws -> (items: T, totalCount: Int?, libraryVersion: Int?) {
        var components = URLComponents(string: baseURL + endpoint)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw ZoteroError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.setValue(credentials.accessTokenSecret, forHTTPHeaderField: "Zotero-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.network.error("Zotero API Error: Invalid response type")
            throw ZoteroError.requestFailed
        }

        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            AppLogger.network.error("Zotero API Error: Status \(httpResponse.statusCode), URL: \(url), Response: \(responseBody)")
            throw ZoteroError.requestFailed
        }

        let totalCount: Int?
        if let totalResultsHeader = httpResponse.value(forHTTPHeaderField: "Total-Results") {
            totalCount = Int(totalResultsHeader)
        } else {
            totalCount = nil
        }

        // Track library version for incremental sync
        let libraryVersion: Int?
        if let versionHeader = httpResponse.value(forHTTPHeaderField: "Last-Modified-Version") {
            libraryVersion = Int(versionHeader)
        } else {
            libraryVersion = nil
        }

        do {
            let decoder = JSONDecoder()
            let items = try decoder.decode(T.self, from: data)
            return (items, totalCount, libraryVersion)
        } catch {
            AppLogger.network.error("Zotero API decoding error: \(error.localizedDescription)")
            throw ZoteroError.decodingFailed
        }
    }

    /// Moves a downloaded file to a permanent temporary location
    ///
    /// Note: This app uses API key authentication (via OAuth access token secret)
    /// rather than full OAuth 1.0a signing for each request.
    private func moveToTempFile(from sourceURL: URL, key: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(key).pdf")

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        // Move the downloaded file to the named location
        try FileManager.default.moveItem(at: sourceURL, to: fileURL)

        return fileURL
    }
}

// MARK: - Errors

enum ZoteroError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case requestFailed
    case decodingFailed
    case downloadFailed(Int)
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Zotero"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from Zotero"
        case .requestFailed:
            return "Request failed"
        case .decodingFailed:
            return "Failed to decode response"
        case .downloadFailed(let code):
            return "Download failed with status code: \(code)"
        case .uploadFailed:
            return "Failed to upload note to Zotero"
        }
    }
}
