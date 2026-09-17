import Foundation
import Testing
@testable import AI_usage

@MainActor
struct ChatGPTUsageProviderTests {
    @Test
    func credentialsParserReadsFakeTokenAccountAndJWTExpiry() throws {
        let data = Data(
            """
            {
              "auth_mode": "chatgpt",
              "OPENAI_API_KEY": null,
              "tokens": {
                "id_token": "FAKE-ID-TOKEN",
                "access_token": "\(Self.futureJWT)",
                "refresh_token": "FAKE-REFRESH",
                "account_id": "acct-FAKE"
              },
              "last_refresh": "2026-07-19T02:02:49.553909Z"
            }
            """.utf8
        )

        let credentials = try CodexAuthFileCredentialsSource.parseCredentials(data)

        #expect(credentials.accessToken == Self.futureJWT)
        #expect(credentials.accountId == "acct-FAKE")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 4_102_444_800))
    }

    @Test
    func JWTExpiryDecodeIsBestEffortAndUsesEpochSeconds() {
        #expect(
            CodexAuthFileCredentialsSource.expiry(fromJWT: Self.futureJWT)
                == Date(timeIntervalSince1970: 4_102_444_800)
        )
        #expect(
            CodexAuthFileCredentialsSource.expiry(fromJWT: Self.expiredJWT)
                == Date(timeIntervalSince1970: 1_600_000_000)
        )
        #expect(CodexAuthFileCredentialsSource.expiry(fromJWT: "not-a-jwt") == nil)
        #expect(CodexAuthFileCredentialsSource.expiry(fromJWT: "a.%%%invalid%%%.b") == nil)
    }

    @Test
    func credentialsParserExplainsAPIKeyOnlySignIns() {
        let payloads = [
            #"{"auth_mode":"chatgpt","OPENAI_API_KEY":"sk-FAKE","tokens":null}"#,
            #"{"auth_mode":"apikey","OPENAI_API_KEY":null,"tokens":null}"#,
        ]

        for payload in payloads {
            do {
                _ = try CodexAuthFileCredentialsSource.parseCredentials(Data(payload.utf8))
                Issue.record("Expected an API-key-only sign-in to be rejected")
            } catch let error as UsageProviderError {
                #expect(
                    error == .notConnected(
                        "Codex is signed in with an API key — sign in with ChatGPT to see plan limits"
                    )
                )
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test
    func credentialsParserDistinguishesSignedOutFromMalformedData() {
        let signedOutPayloads = [
            #"{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":null}"#,
            #"{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{}}"#,
            #"{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"access_token":""}}"#,
        ]

        for payload in signedOutPayloads {
            do {
                _ = try CodexAuthFileCredentialsSource.parseCredentials(Data(payload.utf8))
                Issue.record("Expected signed-out credentials to be rejected")
            } catch let error as UsageProviderError {
                #expect(error == .notConnected("Not signed in to Codex"))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }

        do {
            _ = try CodexAuthFileCredentialsSource.parseCredentials(Data("not-json".utf8))
            Issue.record("Expected malformed credentials to be rejected")
        } catch let error as UsageProviderError {
            #expect(
                error == .notConnected(
                    "Codex credentials are malformed — sign in to Codex again"
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func credentialsSourceReportsAMissingAuthFileAsSignedOut() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = CodexAuthFileCredentialsSource(
            authFileURL: temporaryDirectory.appending(path: "missing.json")
        )

        do {
            _ = try await source.load()
            Issue.record("Expected a missing auth file to be rejected")
        } catch let error as UsageProviderError {
            #expect(error == .notConnected("Not signed in to Codex"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func credentialsSourceReadsTheAuthFileFreshOnEveryLoad() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let authFile = temporaryDirectory.appending(path: "auth.json")
        let source = CodexAuthFileCredentialsSource(authFileURL: authFile)

        try writeCredentials(accessToken: "first-not-a-jwt", to: authFile)
        let first = try await source.load()

        try writeCredentials(accessToken: "second-not-a-jwt", to: authFile)
        let second = try await source.load()

        #expect(first.accessToken == "first-not-a-jwt")
        #expect(second.accessToken == "second-not-a-jwt")
        #expect(first.expiresAt == nil)
        #expect(second.expiresAt == nil)
    }

    @Test
    func fetchUsesSavedCredentialsAndBuildsTheExpectedRequest() async throws {
        let transport = ChatGPTTransportSpy(
            outcomes: [.response(statusCode: 200, body: Self.successBody)]
        )
        let provider = makeProvider(transport: transport)

        let limits = try await provider.fetchLimits()

        #expect(limits.map(\.id) == ["primary"])
        #expect(limits.map(\.usedFraction) == [0.15])
        #expect(transport.requests.count == 1)

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://chatgpt.com/backend-api/wham/usage"
        )
        #expect(request.timeoutInterval == 15)
        #expect(
            request.value(forHTTPHeaderField: "Authorization")
                == "Bearer access-FAKE"
        )
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-FAKE")
        #expect(request.value(forHTTPHeaderField: "originator") == "codex_cli_rs")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "AI-usage/1.0")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test
    func fetchOmitsTheAccountHeaderWhenNoAccountIsStored() async throws {
        let transport = ChatGPTTransportSpy(
            outcomes: [.response(statusCode: 200, body: Self.successBody)]
        )
        let provider = ChatGPTUsageProvider(
            credentialsSource: StubCodexCredentialsSource(
                result: .success(
                    CodexCredentials(
                        accessToken: "access-FAKE",
                        accountId: nil,
                        expiresAt: nil
                    )
                )
            ),
            transport: transport.send
        )

        _ = try await provider.fetchLimits()

        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
    }

    @Test
    func unparseableJWTStillLetsTheServerAuthorizeTheRequest() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let authFile = temporaryDirectory.appending(path: "auth.json")
        try writeCredentials(accessToken: "not-a-jwt", to: authFile)
        let transport = ChatGPTTransportSpy(
            outcomes: [.response(statusCode: 200, body: Self.successBody)]
        )
        let provider = ChatGPTUsageProvider(
            credentialsSource: CodexAuthFileCredentialsSource(authFileURL: authFile),
            transport: transport.send
        )

        let limits = try await provider.fetchLimits()

        #expect(limits.map(\.id) == ["primary"])
        #expect(transport.requests.count == 1)
        #expect(
            transport.requests.first?.value(forHTTPHeaderField: "Authorization")
                == "Bearer not-a-jwt"
        )
    }

    @Test
    func expiredCredentialsDoNotCallTheNetwork() async {
        let transport = ChatGPTTransportSpy(outcomes: [])
        let provider = ChatGPTUsageProvider(
            credentialsSource: StubCodexCredentialsSource(
                result: .success(
                    CodexCredentials(
                        accessToken: Self.expiredJWT,
                        accountId: "acct-FAKE",
                        expiresAt: Date(timeIntervalSince1970: 1_600_000_000)
                    )
                )
            ),
            transport: transport.send
        )

        do {
            _ = try await provider.fetchLimits()
            Issue.record("Expected expired credentials to be rejected")
        } catch let error as UsageProviderError {
            #expect(
                error == .notConnected(
                    "Codex session expired — run codex to refresh it"
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(transport.requests.isEmpty)
    }

    @Test
    func signedOutCredentialsSourceSurfacesDisconnectedWithoutANetworkCall() async {
        let transport = ChatGPTTransportSpy(outcomes: [])
        let provider = ChatGPTUsageProvider(
            credentialsSource: StubCodexCredentialsSource(
                result: .failure(.notConnected("Not signed in to Codex"))
            ),
            transport: transport.send
        )

        do {
            _ = try await provider.fetchLimits()
            Issue.record("Expected signed-out credentials to be rejected")
        } catch let error as UsageProviderError {
            #expect(error == .notConnected("Not signed in to Codex"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(transport.requests.isEmpty)
    }

    @Test
    func authenticationResponsesSurfaceDisconnected() async {
        for statusCode in [401, 403] {
            let transport = ChatGPTTransportSpy(
                outcomes: [
                    .response(
                        statusCode: statusCode,
                        body: Data(
                            #"{"error":{"message":"Incorrect API key provided: FAKE","type":"invalid_request_error"}}"#.utf8
                        )
                    ),
                ]
            )
            let provider = makeProvider(transport: transport)

            do {
                _ = try await provider.fetchLimits()
                Issue.record("Expected HTTP \(statusCode) to disconnect the provider")
            } catch let error as UsageProviderError {
                #expect(
                    error == .notConnected(
                        "ChatGPT rejected the saved credentials — sign in to Codex again"
                    )
                )
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test
    func serverFailureIncludesTheHTTPStatus() async {
        let transport = ChatGPTTransportSpy(
            outcomes: [.response(statusCode: 500, body: Data())]
        )
        let provider = makeProvider(transport: transport)

        do {
            _ = try await provider.fetchLimits()
            Issue.record("Expected HTTP 500 to fail")
        } catch let error as UsageProviderError {
            #expect(error == .fetchFailed("ChatGPT usage service returned HTTP 500"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func transportFailureSurfacesAsANetworkError() async {
        let transport = ChatGPTTransportSpy(
            outcomes: [.failure(URLError(.notConnectedToInternet))]
        )
        let provider = makeProvider(transport: transport)

        do {
            _ = try await provider.fetchLimits()
            Issue.record("Expected the transport to fail")
        } catch let error as UsageProviderError {
            #expect(error == .fetchFailed("Network error — check your connection"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func unexpectedSuccessResponsesSurfaceAsAServiceError() async {
        for body in ["not-json", "{}", #"{"credits":{"has_credits":false}}"#] {
            let transport = ChatGPTTransportSpy(
                outcomes: [.response(statusCode: 200, body: Data(body.utf8))]
            )
            let provider = makeProvider(transport: transport)

            do {
                _ = try await provider.fetchLimits()
                Issue.record("Expected invalid response data to fail")
            } catch let error as UsageProviderError {
                #expect(
                    error == .fetchFailed(
                        "Unexpected response from ChatGPT usage service"
                    )
                )
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test
    func recognizedEmptySuccessResponseReturnsNoLimits() async throws {
        let transport = ChatGPTTransportSpy(
            outcomes: [
                .response(
                    statusCode: 200,
                    body: Data(#"{"additional_rate_limits":[]}"#.utf8)
                ),
            ]
        )
        let provider = makeProvider(transport: transport)

        let limits = try await provider.fetchLimits()

        #expect(limits.isEmpty)
    }

    @Test
    func failedRefreshClearsPreviouslyFetchedChatGPTLimits() async {
        let transport = ChatGPTTransportSpy(
            outcomes: [
                .response(statusCode: 200, body: Self.successBody),
                .failure(URLError(.timedOut)),
            ]
        )
        let provider = makeProvider(transport: transport)
        let defaults = ChatGPTProviderTestDefaults()
        defer { defaults.remove() }
        let store = UsageStore(providers: [provider], defaults: defaults.defaults)
        store.select(providerID: provider.id, limitID: "primary")

        await store.refreshAll()
        #expect(store.menuBarText == "15%")

        await store.refreshAll()

        #expect(
            store.providerStates[provider.id]
                == .disconnected(message: "Network error — check your connection")
        )
        #expect(store.menuBarText == "—")
    }

    private func makeProvider(transport: ChatGPTTransportSpy) -> ChatGPTUsageProvider {
        ChatGPTUsageProvider(
            credentialsSource: StubCodexCredentialsSource(
                result: .success(
                    CodexCredentials(
                        accessToken: "access-FAKE",
                        accountId: "acct-FAKE",
                        expiresAt: .distantFuture
                    )
                )
            ),
            transport: transport.send
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ChatGPTUsageProviderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func writeCredentials(accessToken: String, to url: URL) throws {
        try Data(
            """
            {
              "auth_mode": "chatgpt",
              "OPENAI_API_KEY": null,
              "tokens": {
                "access_token": "\(accessToken)",
                "account_id": "acct-FAKE"
              }
            }
            """.utf8
        ).write(to: url)
    }

    static let futureJWT = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQxMDI0NDQ4MDAsImh0dHBzOi8vYXBpLm9wZW5haS5jb20vYXV0aCI6eyJjaGF0Z3B0X3BsYW5fdHlwZSI6InByb2xpdGUiLCJjaGF0Z3B0X2FjY291bnRfaWQiOiJhY2N0LUZBS0UifX0.FAKESIG"
    static let expiredJWT = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2MDAwMDAwMDB9.FAKESIG"
    static let successBody = Data(
        #"{"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":15,"limit_window_seconds":604800,"reset_at":1785024392},"secondary_window":null},"code_review_rate_limit":null,"additional_rate_limits":[]}"#.utf8
    )
}

@MainActor
private struct StubCodexCredentialsSource: CodexCredentialsSource {
    let result: Result<CodexCredentials, UsageProviderError>

    func load() async throws -> CodexCredentials {
        try result.get()
    }
}

@MainActor
private final class ChatGPTTransportSpy {
    enum Outcome {
        case response(statusCode: Int, body: Data)
        case failure(URLError)
    }

    private var outcomes: [Outcome]
    private(set) var requests: [URLRequest] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !outcomes.isEmpty else {
            throw URLError(.unknown)
        }

        switch outcomes.removeFirst() {
        case let .response(statusCode, body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, response)
        case let .failure(error):
            throw error
        }
    }
}

private struct ChatGPTProviderTestDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "ChatGPTUsageProviderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
