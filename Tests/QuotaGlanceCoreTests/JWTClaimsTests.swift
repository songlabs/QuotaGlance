import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("JWT claims")
struct JWTClaimsTests {
    @Test("Codex account ID uses the official nested auth claim")
    func nestedChatGPTAccountID() throws {
        let token = try jwt(payload: [
            "email": "test@example.com",
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "workspace-123",
                "chatgpt_plan_type": "plus",
            ],
        ])

        #expect(JWTClaims.chatGPTAccountID(in: token) == "workspace-123")
    }

    @Test("Missing Codex account ID returns nil")
    func missingChatGPTAccountID() throws {
        let token = try jwt(payload: ["email": "test@example.com"])

        #expect(JWTClaims.chatGPTAccountID(in: token) == nil)
    }

    @Test("Top-level Codex account ID remains a fallback")
    func topLevelChatGPTAccountID() throws {
        let token = try jwt(payload: ["chatgpt_account_id": "legacy-123"])

        #expect(JWTClaims.chatGPTAccountID(in: token) == "legacy-123")
    }

    @Test("Official nested Codex account ID takes priority")
    func nestedChatGPTAccountIDTakesPriority() throws {
        let token = try jwt(payload: [
            "chatgpt_account_id": "legacy",
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "official",
            ],
        ])

        #expect(JWTClaims.chatGPTAccountID(in: token) == "official")
    }

    @Test("Display name is preferred over username and email")
    func accountDisplayName() throws {
        let token = try jwt(payload: [
            "email": "person@example.com",
            "preferred_username": "person",
            "name": "Example Person",
        ])

        #expect(JWTClaims.accountDisplayName(in: token) == "Example Person")
    }

    @Test("Namespaced profile and top-level email are readable fallbacks")
    func accountDisplayNameFallbacks() throws {
        let profileToken = try jwt(payload: [
            "email": "person@example.com",
            "https://api.openai.com/profile": ["preferred_username": "profile-person"],
        ])
        let emailToken = try jwt(payload: ["email": " person@example.com "])

        #expect(JWTClaims.accountDisplayName(in: profileToken) == "profile-person")
        #expect(JWTClaims.accountDisplayName(in: emailToken) == "person@example.com")
    }

    private func jwt(payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let encodedPayload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encodedPayload).signature"
    }
}
