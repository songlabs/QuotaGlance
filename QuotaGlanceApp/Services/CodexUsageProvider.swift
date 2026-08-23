import Foundation
import QuotaGlanceCore

@MainActor
final class CodexUsageProvider: UsageProvider {
    let provider = AIProvider.codex

    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let authorizationEndpoint = URL(string: "https://auth.openai.com/oauth/authorize")!
    private let tokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let scopes = "openid profile email offline_access api.connectors.read api.connectors.invoke"

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

    var isConnected: Bool { credentials.contains(provider) }

    func connect() async throws {
        let pkce = try OAuthPKCE.make()
        let state = try OAuthPKCE.state()
        var redirectURI = ""

        let callback = try await oauthSession.authorize(
            expectedState: state,
            preferredPorts: [1455, 1457]
        ) { [self] port in
            redirectURI = "http://localhost:\(port)/auth/callback"
            var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "scope", value: scopes),
                URLQueryItem(name: "code_challenge", value: pkce.challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "id_token_add_organizations", value: "true"),
                URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "originator", value: "quotaglance"),
            ]
            return components.url!
        }

        let code = try authorizationCode(from: callback)
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormURLEncoder.data([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": pkce.verifier,
        ])

        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else { throw map(status: response.statusCode) }
        let token: CodexTokenResponse
        do {
            token = try JSONDecoder().decode(CodexTokenResponse.self, from: data)
        } catch {
            throw UsageProviderError.schemaChanged
        }

        let accountID = JWTClaims.chatGPTAccountID(in: token.idToken)
        guard accountID != nil else { throw UsageProviderError.schemaChanged }
        try credentials.save(OAuthCredential(
            provider: provider,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: JWTClaims.expiration(in: token.accessToken) ?? Date().addingTimeInterval(3_600),
            accountID: accountID,
            scopes: scopes.split(separator: " ").map(String.init)
        ))
    }

    func disconnect() async throws {
        try credentials.delete(provider)
    }

    func refreshUsage() async throws -> UsageSnapshot {
        guard var credential = try credentials.load(provider) else {
            throw UsageProviderError.noAccount
        }
        if credential.expiresAt <= Date().addingTimeInterval(60) {
            credential = try await refresh(credential)
        }

        do {
            return try await requestUsage(credential)
        } catch UsageProviderError.rejected(statusCode: 401) {
            let refreshed = try await refresh(credential)
            return try await requestUsage(refreshed)
        }
    }

    private func requestUsage(_ credential: OAuthCredential) async throws -> UsageSnapshot {
        guard let accountID = credential.accountID else { throw UsageProviderError.noAccount }
        var request = URLRequest(url: usageEndpoint)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("QuotaGlance/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else { throw map(status: response.statusCode) }
        return try UsageResponseDecoder.decodeCodex(data)
    }

    private func refresh(_ credential: OAuthCredential) async throws -> OAuthCredential {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CodexRefreshRequest(
            clientID: clientID,
            grantType: "refresh_token",
            refreshToken: credential.refreshToken
        ))

        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else {
            if response.statusCode == 400 || response.statusCode == 401 {
                throw UsageProviderError.tokenExpired
            }
            throw map(status: response.statusCode)
        }

        let token: CodexRefreshResponse
        do {
            token = try JSONDecoder().decode(CodexRefreshResponse.self, from: data)
        } catch {
            throw UsageProviderError.schemaChanged
        }
        let accessToken = token.accessToken ?? credential.accessToken
        let idToken = token.idToken
        let refreshed = credential.replacing(
            accessToken: accessToken,
            refreshToken: token.refreshToken,
            expiresAt: JWTClaims.expiration(in: accessToken) ?? Date().addingTimeInterval(3_600),
            accountID: idToken.flatMap { JWTClaims.chatGPTAccountID(in: $0) }
        )
        try credentials.save(refreshed)
        return refreshed
    }

    private func authorizationCode(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        if let error = items?.first(where: { $0.name == "error" })?.value {
            throw UsageProviderError.oauthUnavailable("OpenAI authorization failed: \(error)")
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
        status == 401 ? .rejected(statusCode: 401) : .rejected(statusCode: status)
    }
}

private struct CodexTokenResponse: Decodable {
    let idToken: String
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct CodexRefreshRequest: Encodable {
    let clientID: String
    let grantType: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
    }
}

private struct CodexRefreshResponse: Decodable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
