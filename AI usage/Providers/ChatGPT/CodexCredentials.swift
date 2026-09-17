import Foundation

struct CodexCredentials: Equatable {
    let accessToken: String
    let accountId: String?
    let expiresAt: Date?
}

protocol CodexCredentialsSource {
    func load() async throws -> CodexCredentials
}

struct CodexAuthFileCredentialsSource: CodexCredentialsSource {
    private let authFileURL: URL

    init(
        authFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex/auth.json")
    ) {
        self.authFileURL = authFileURL
    }

    func load() async throws -> CodexCredentials {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw UsageProviderError.notConnected("Not signed in to Codex")
        }

        do {
            return try Self.parseCredentials(Data(contentsOf: authFileURL))
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.notConnected(
                "Couldn’t read Codex credentials — sign in to Codex again"
            )
        }
    }

    static func parseCredentials(_ data: Data) throws -> CodexCredentials {
        let envelope: CredentialsEnvelope
        do {
            envelope = try JSONDecoder().decode(CredentialsEnvelope.self, from: data)
        } catch {
            throw UsageProviderError.notConnected(
                "Codex credentials are malformed — sign in to Codex again"
            )
        }

        guard envelope.authMode == "chatgpt",
              let tokens = envelope.tokens,
              let accessToken = tokens.accessToken,
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if envelope.authMode == "apikey"
                || !(envelope.openAIAPIKey?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                throw UsageProviderError.notConnected(
                    "Codex is signed in with an API key — sign in with ChatGPT to see plan limits"
                )
            }

            throw UsageProviderError.notConnected("Not signed in to Codex")
        }

        let accountId = tokens.accountId?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return CodexCredentials(
            accessToken: accessToken,
            accountId: accountId?.isEmpty == false ? accountId : nil,
            expiresAt: expiry(fromJWT: accessToken)
        )
    }

    static func expiry(fromJWT token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count > 1 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONDecoder().decode(JWTClaims.self, from: data) else {
            return nil
        }

        return Date(timeIntervalSince1970: claims.exp)
    }
}

private struct CredentialsEnvelope: Decodable {
    let authMode: String?
    let openAIAPIKey: String?
    let tokens: CodexTokens?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case openAIAPIKey = "OPENAI_API_KEY"
        case tokens
    }
}

private struct CodexTokens: Decodable {
    let accessToken: String?
    let accountId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountId = "account_id"
    }
}

private struct JWTClaims: Decodable {
    let exp: Double
}
