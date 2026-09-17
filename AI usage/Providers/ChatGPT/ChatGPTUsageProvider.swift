import Foundation

final class ChatGPTUsageProvider: UsageProvider {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    let id = "chatgpt"
    let displayName = "ChatGPT"

    private let credentialsSource: any CodexCredentialsSource
    private let transport: Transport

    init(
        credentialsSource: any CodexCredentialsSource = CodexAuthFileCredentialsSource(),
        transport: @escaping Transport = ChatGPTUsageProvider.urlSessionTransport
    ) {
        self.credentialsSource = credentialsSource
        self.transport = transport
    }

    func fetchLimits() async throws -> [UsageLimit] {
        let credentials: CodexCredentials
        do {
            credentials = try await credentialsSource.load()
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.notConnected("Couldn’t read Codex credentials")
        }

        if let expiresAt = credentials.expiresAt,
           expiresAt < Date.now.addingTimeInterval(-60) {
            throw UsageProviderError.notConnected(
                "Codex session expired — run codex to refresh it"
            )
        }

        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(credentials.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        if let accountId = credentials.accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("AI-usage/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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
                "ChatGPT rejected the saved credentials — sign in to Codex again"
            )
        default:
            throw UsageProviderError.fetchFailed(
                "ChatGPT usage service returned HTTP \(response.statusCode)"
            )
        }

        do {
            let usageResponse = try JSONDecoder().decode(ChatGPTUsageResponse.self, from: data)
            guard usageResponse.hasRecognizedPayload else {
                throw UsageProviderError.fetchFailed(
                    "Unexpected response from ChatGPT usage service"
                )
            }

            return usageResponse.toUsageLimits()
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.fetchFailed(
                "Unexpected response from ChatGPT usage service"
            )
        }
    }

    static func urlSessionTransport(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageProviderError.fetchFailed(
                "Unexpected response from ChatGPT usage service"
            )
        }

        return (data, httpResponse)
    }
}
