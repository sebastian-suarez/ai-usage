import Foundation

final class ClaudeUsageProvider: UsageProvider {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    let id = "claude"
    let displayName = "Claude"

    private let credentialsSource: any ClaudeCredentialsSource
    private let transport: Transport

    init(
        credentialsSource: any ClaudeCredentialsSource = KeychainClaudeCredentialsSource(),
        transport: @escaping Transport = ClaudeUsageProvider.urlSessionTransport
    ) {
        self.credentialsSource = credentialsSource
        self.transport = transport
    }

    func fetchLimits() async throws -> [UsageLimit] {
        let credentials: ClaudeCredentials
        do {
            credentials = try await credentialsSource.load()
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.notConnected("Couldn’t read Claude Code credentials")
        }

        if let expiresAt = credentials.expiresAt,
           expiresAt < Date.now.addingTimeInterval(-60) {
            throw UsageProviderError.notConnected(
                "Claude Code session expired — open Claude Code to refresh it"
            )
        }

        var request = URLRequest(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("AI-usage/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.fetchFailed("Network error — check your connection")
        }

        switch response.statusCode {
        case 200:
            break
        case 401, 403:
            throw UsageProviderError.notConnected(
                "Claude rejected the saved credentials — sign in to Claude Code again"
            )
        default:
            throw UsageProviderError.fetchFailed(
                "Claude usage service returned HTTP \(response.statusCode)"
            )
        }

        do {
            let usageResponse = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
            guard usageResponse.hasRecognizedPayload else {
                throw UsageProviderError.fetchFailed(
                    "Unexpected response from Claude usage service"
                )
            }

            return usageResponse.toUsageLimits()
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.fetchFailed(
                "Unexpected response from Claude usage service"
            )
        }
    }

    static func urlSessionTransport(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageProviderError.fetchFailed(
                "Unexpected response from Claude usage service"
            )
        }

        return (data, httpResponse)
    }
}
