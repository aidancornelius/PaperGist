// ZoteroOAuthService.swift
// PaperGist
//
// Handles OAuth 1.0a authentication flow with Zotero API. Manages the three-legged
// OAuth process: request token, user authorisation via web browser, and access
// token exchange. Stores credentials securely in the keychain.
//
// Created by Aidan Cornelius-Bell on 15/01/2025.
// Copyright © 2025 Aidan Cornelius-Bell. All rights reserved.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import AuthenticationServices
import CryptoKit
import OSLog

/// Handles OAuth 1.0a authentication with Zotero
@MainActor
final class ZoteroOAuthService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: ZoteroUser?

    nonisolated(unsafe) private let keychainService = KeychainService()

    private let requestTokenURL = URL(string: "https://www.zotero.org/oauth/request")!
    private let authorizeURL = URL(string: "https://www.zotero.org/oauth/authorize")!
    private let accessTokenURL = URL(string: "https://www.zotero.org/oauth/access")!

    private var webAuthSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        loadCredentials()
    }

    // MARK: - Public Methods

    /// Initiates the OAuth flow
    ///
    /// Performs the three-step OAuth 1.0a dance: obtains a request token, prompts
    /// the user to authorise in their browser, then exchanges the verifier for an
    /// access token. Includes automatic retry logic for first-launch race conditions.
    func authenticate() async throws {
        let requestToken = try await getRequestToken()

        // Automatic retry for first-launch race condition in ASWebAuthenticationSession
        let verifier: String
        do {
            verifier = try await authorizeUser(requestToken: requestToken)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            AppLogger.auth.warning("Auth session cancelled (likely first-launch race condition), retrying...")
            try await Task.sleep(for: .milliseconds(500))
            verifier = try await authorizeUser(requestToken: requestToken)
        }

        let credentials = try await getAccessToken(requestToken: requestToken, verifier: verifier)

        try saveCredentials(credentials)
        try await fetchUserInfo()

        isAuthenticated = true
    }

    /// Signs out the current user and clears all credentials
    @MainActor
    func signOut() {
        keychainService.delete(key: "zotero_credentials")

        isAuthenticated = false
        currentUser = nil

        AppSettings.shared.lastLibraryVersion = nil
    }

    /// Returns the stored credentials if available
    nonisolated func getCredentials() -> ZoteroOAuthCredentials? {
        guard let data = keychainService.load(key: "zotero_credentials"),
              let credentials = try? JSONDecoder().decode(ZoteroOAuthCredentials.self, from: data) else {
            return nil
        }
        return credentials
    }

    // MARK: - Private Methods

    private func loadCredentials() {
        if let credentials = getCredentials() {
            isAuthenticated = true
            currentUser = ZoteroUser(
                userID: credentials.userID,
                username: credentials.username,
                displayName: nil
            )
        }
    }

    private func saveCredentials(_ credentials: ZoteroOAuthCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        keychainService.save(key: "zotero_credentials", data: data)
    }

    /// Step 1: Get request token from Zotero
    private func getRequestToken() async throws -> OAuthToken {
        var request = URLRequest(url: requestTokenURL)
        request.httpMethod = "POST"

        let oauthParams = [
            "oauth_callback": ZoteroConfig.callbackURL,
            "oauth_consumer_key": ZoteroConfig.consumerKey,
            "oauth_nonce": generateNonce(),
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": String(Int(Date().timeIntervalSince1970)),
            "oauth_version": "1.0"
        ]

        let signature = generateSignature(
            method: "POST",
            url: requestTokenURL,
            parameters: oauthParams,
            tokenSecret: nil
        )

        var signedParams = oauthParams
        signedParams["oauth_signature"] = signature

        let authHeader = createAuthorizationHeader(signedParams)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.auth.error("OAuth request token failed: Invalid response type")
            throw OAuthError.requestTokenFailed
        }

        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            AppLogger.auth.error("OAuth request token failed: Status \(httpResponse.statusCode), Response: \(responseBody)")
            throw OAuthError.requestTokenFailed
        }

        return try parseTokenResponse(data)
    }

    /// Step 2: Authorize user via web browser
    private func authorizeUser(requestToken: OAuthToken) async throws -> String {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "oauth_token", value: requestToken.token),
            URLQueryItem(name: "name", value: "PaperGist"),
            URLQueryItem(name: "library_access", value: "1"),
            URLQueryItem(name: "notes_access", value: "1"),
            URLQueryItem(name: "write_access", value: "1"),
            URLQueryItem(name: "all_groups", value: "read")
        ]

        let authURL = components.url!

        return try await withCheckedThrowingContinuation { continuation in
            webAuthSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "papergist"
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let verifier = components.queryItems?.first(where: { $0.name == "oauth_verifier" })?.value else {
                    continuation.resume(throwing: OAuthError.invalidCallback)
                    return
                }

                continuation.resume(returning: verifier)
            }

            webAuthSession?.presentationContextProvider = self
            webAuthSession?.prefersEphemeralWebBrowserSession = true
            webAuthSession?.start()
        }
    }

    /// Step 3: Exchange request token for access token
    private func getAccessToken(requestToken: OAuthToken, verifier: String) async throws -> ZoteroOAuthCredentials {
        var request = URLRequest(url: accessTokenURL)
        request.httpMethod = "POST"

        let oauthParams = [
            "oauth_consumer_key": ZoteroConfig.consumerKey,
            "oauth_nonce": generateNonce(),
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": String(Int(Date().timeIntervalSince1970)),
            "oauth_token": requestToken.token,
            "oauth_verifier": verifier,
            "oauth_version": "1.0"
        ]

        let signature = generateSignature(
            method: "POST",
            url: accessTokenURL,
            parameters: oauthParams,
            tokenSecret: requestToken.secret
        )

        var signedParams = oauthParams
        signedParams["oauth_signature"] = signature

        request.setValue(createAuthorizationHeader(signedParams), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.accessTokenFailed
        }

        return try parseAccessTokenResponse(data)
    }

    /// Fetch user information from Zotero API
    private func fetchUserInfo() async throws {
        guard let credentials = getCredentials() else {
            throw OAuthError.noCredentials
        }

        currentUser = ZoteroUser(
            userID: credentials.userID,
            username: credentials.username,
            displayName: nil
        )
    }

    // MARK: - OAuth Helpers

    private func generateNonce() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private func generateSignature(
        method: String,
        url: URL,
        parameters: [String: String],
        tokenSecret: String?
    ) -> String {
        // Create base string
        let sortedParams = parameters.sorted { $0.key < $1.key }
        let paramString = sortedParams
            .map { "\($0.key)=\($0.value.percentEncoded())" }
            .joined(separator: "&")

        let baseString = [
            method.uppercased(),
            url.absoluteString.percentEncoded(),
            paramString.percentEncoded()
        ].joined(separator: "&")

        // Create signing key
        let signingKey = [
            ZoteroConfig.consumerSecret.percentEncoded(),
            (tokenSecret ?? "").percentEncoded()
        ].joined(separator: "&")

        // Generate HMAC-SHA1 signature
        let signature = hmacSHA1(message: baseString, key: signingKey)
        return signature.base64EncodedString()
    }

    private func hmacSHA1(message: String, key: String) -> Data {
        let keyData = key.data(using: .utf8)!
        let messageData = message.data(using: .utf8)!

        let key = SymmetricKey(data: keyData)
        let signature = HMAC<Insecure.SHA1>.authenticationCode(for: messageData, using: key)

        return Data(signature)
    }

    private func createAuthorizationHeader(_ params: [String: String]) -> String {
        let sortedParams = params.sorted { $0.key < $1.key }
        let paramString = sortedParams
            .map { "\($0.key)=\"\($0.value.percentEncoded())\"" }
            .joined(separator: ", ")

        return "OAuth \(paramString)"
    }

    private func parseTokenResponse(_ data: Data) throws -> OAuthToken {
        guard let string = String(data: data, encoding: .utf8) else {
            throw OAuthError.invalidResponse
        }

        let params = parseQueryString(string)

        guard let token = params["oauth_token"],
              let secret = params["oauth_token_secret"] else {
            throw OAuthError.invalidResponse
        }

        return OAuthToken(token: token, secret: secret)
    }

    private func parseAccessTokenResponse(_ data: Data) throws -> ZoteroOAuthCredentials {
        guard let string = String(data: data, encoding: .utf8) else {
            throw OAuthError.invalidResponse
        }

        let params = parseQueryString(string)

        guard let token = params["oauth_token"],
              let secret = params["oauth_token_secret"],
              let userID = params["userID"],
              let username = params["username"] else {
            throw OAuthError.invalidResponse
        }

        // Note: Sensitive data logging removed for security
        // TODO: Add proper secure logging for production
        // Successfully received: Token, Secret (API Key), UserID, Username

        return ZoteroOAuthCredentials(
            accessToken: token,
            accessTokenSecret: secret,
            userID: userID,
            username: username
        )
    }

    private func parseQueryString(_ query: String) -> [String: String] {
        var params = [String: String]()

        for param in query.components(separatedBy: "&") {
            let parts = param.components(separatedBy: "=")
            if parts.count == 2 {
                params[parts[0]] = parts[1].removingPercentEncoding
            }
        }

        return params
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension ZoteroOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            fatalError("No active window scene found for authentication")
        }
        return ASPresentationAnchor(windowScene: windowScene)
    }
}

// MARK: - Supporting Types

struct OAuthToken {
    let token: String
    let secret: String
}

enum OAuthError: LocalizedError {
    case requestTokenFailed
    case accessTokenFailed
    case invalidCallback
    case invalidResponse
    case noCredentials

    var errorDescription: String? {
        switch self {
        case .requestTokenFailed:
            return "Failed to get request token from Zotero"
        case .accessTokenFailed:
            return "Failed to get access token from Zotero"
        case .invalidCallback:
            return "Invalid OAuth callback"
        case .invalidResponse:
            return "Invalid response from Zotero"
        case .noCredentials:
            return "No stored credentials found"
        }
    }
}

