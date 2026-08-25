import Foundation
import QuotaGlanceCore

@MainActor
final class ClaudeUsageProvider: UsageProvider {
    let provider = AIProvider.claude

    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let authorizationEndpoint = URL(string: "https://claude.com/cai/oauth/authorize")!
    private let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let scopes = ["user:profile", "user:inference"]

    private let credentials: KeychainCredentialStore
    private let oauthSession: LoopbackOAuthSession
    private let session: URLSession

    init(credentials: KeychainCredentialStore, oauthSession: LoopbackOAuthSession) {
        self.credentials = credentials
        self.oauthSession = oauthSession
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    func isConnected(accountIdentifier: UUID) -> Bool {
        credentials.contains(provider, accountIdentifier: accountIdentifier)
    }

    func connect(accountIdentifier: UUID) async throws -> String? {
        let pkce = try OAuthPKCE.make()
        let state = try OAuthPKCE.state()
        var redirectURI = ""

        let callback = try await oauthSession.authorize(expectedState: state) { [self] port in
            redirectURI = "http://localhost:\(port)/callback"
            var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "code", value: "true"),
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
                URLQueryItem(name: "code_challenge", value: pkce.challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: state),
            ]
            return components.url!
        }

        let code = try authorizationCode(from: callback)
        let payload = ClaudeTokenRequest(
            grantType: "authorization_code",
            code: code,
            redirectURI: redirectURI,
            clientID: clientID,
            codeVerifier: pkce.verifier,
            state: state,
            refreshToken: nil,
            scope: nil
        )
        let token = try await requestToken(payload, refreshing: false)
        guard let refreshToken = token.refreshToken else { throw UsageProviderError.schemaChanged }
        try credentials.save(OAuthCredential(
            provider: provider,
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            accountID: token.account?.uuid,
            scopes: token.scope?.split(separator: " ").map(String.init) ?? scopes
        ), accountIdentifier: accountIdentifier)
        return token.account?.identityLabel
    }

    func disconnect(accountIdentifier: UUID) async throws {
        try credentials.delete(provider, accountIdentifier: accountIdentifier)
    }

    func accountIdentityLabel(accountIdentifier: UUID) async throws -> String? {
        guard let credential = try credentials.load(provider, accountIdentifier: accountIdentifier) else {
            return nil
        }
        return try await refresh(credential, accountIdentifier: accountIdentifier).identityLabel
    }

    func refreshUsage(accountIdentifier: UUID) async throws -> UsageSnapshot {
        guard var credential = try credentials.load(provider, accountIdentifier: accountIdentifier) else {
            throw UsageProviderError.noAccount
        }
        if credential.expiresAt <= Date().addingTimeInterval(60) {
            credential = try await refresh(credential, accountIdentifier: accountIdentifier).credential
        }

        do {
            return try await requestUsage(credential)
        } catch UsageProviderError.rejected(statusCode: 401) {
            let refreshed = try await refresh(credential, accountIdentifier: accountIdentifier).credential
            return try await requestUsage(refreshed)
        }
    }

    private func requestUsage(_ credential: OAuthCredential) async throws -> UsageSnapshot {
        var request = URLRequest(url: usageEndpoint)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("QuotaGlance/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else { throw map(status: response.statusCode) }
        return try UsageResponseDecoder.decodeClaude(data)
    }

    private func refresh(
        _ credential: OAuthCredential,
        accountIdentifier: UUID
    ) async throws -> (credential: OAuthCredential, identityLabel: String?) {
        let token = try await requestToken(ClaudeTokenRequest(
            grantType: "refresh_token",
            code: nil,
            redirectURI: nil,
            clientID: clientID,
            codeVerifier: nil,
            state: nil,
            refreshToken: credential.refreshToken,
            scope: credential.scopes.joined(separator: " ")
        ), refreshing: true)
        let refreshed = credential.replacing(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            accountID: token.account?.uuid,
            scopes: token.scope?.split(separator: " ").map(String.init)
        )
        try credentials.save(refreshed, accountIdentifier: accountIdentifier)
        return (refreshed, token.account?.identityLabel)
    }

    private func requestToken(_ payload: ClaudeTokenRequest, refreshing: Bool) async throws -> ClaudeTokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else {
            if refreshing && (response.statusCode == 400 || response.statusCode == 401) {
                throw UsageProviderError.tokenExpired
            }
            throw map(status: response.statusCode)
        }
        do {
            return try JSONDecoder().decode(ClaudeTokenResponse.self, from: data)
        } catch {
            throw UsageProviderError.schemaChanged
        }
    }

    private func authorizationCode(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        if let error = items?.first(where: { $0.name == "error" })?.value {
            throw UsageProviderError.oauthUnavailable("Claude authorization failed: \(error)")
        }
        guard let code = items?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw UsageProviderError.invalidOAuthCallback
        }
        return code
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw UsageProviderError.network }
            return (data, response)
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.network
        }
    }

    private func map(status: Int) -> UsageProviderError {
        .rejected(statusCode: status)
    }
}

private struct ClaudeTokenRequest: Encodable {
    let grantType: String
    let code: String?
    let redirectURI: String?
    let clientID: String
    let codeVerifier: String?
    let state: String?
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case code
        case redirectURI = "redirect_uri"
        case clientID = "client_id"
        case codeVerifier = "code_verifier"
        case state
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct ClaudeTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let scope: String?
    let account: ClaudeOAuthAccount?
    let organization: ClaudeOAuthOrganization?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case account
        case organization
    }
}
