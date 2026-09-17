import Foundation
import Testing
@testable import AI_usage

@MainActor
struct ClaudeUsageProviderTests {
    @Test
    func credentialsParserReadsFakeTokenAndMillisecondExpiry() throws {
        let data = Data(
            #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-FAKE","refreshToken":"sk-ant-ort01-FAKE","expiresAt":1784443682444,"refreshTokenExpiresAt":1799995682444,"scopes":["user:inference","user:profile"],"subscriptionType":"max","rateLimitTier":"default"}}"#.utf8
        )

        let credentials = try KeychainClaudeCredentialsSource.parseCredentials(data)

        #expect(credentials.accessToken == "sk-ant-oat01-FAKE")
        #expect(
            abs((credentials.expiresAt?.timeIntervalSince1970 ?? 0) - 1_784_443_682.444)
                < 0.000_001
        )
    }

    @Test
    func credentialsParserRejectsMissingOrMalformedOAuthData() {
        let invalidPayloads = [
            Data(#"{"unrelated":true}"#.utf8),
            Data("not-json".utf8),
        ]

        for payload in invalidPayloads {
            do {
                _ = try KeychainClaudeCredentialsSource.parseCredentials(payload)
                Issue.record("Expected malformed credentials to be rejected")
            } catch let error as UsageProviderError {
                #expect(
                    error == .notConnected(
                        "Claude Code credentials are malformed — sign in again"
                    )
                )
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test
    func credentialsSourceFallsBackToTheCredentialsFile() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let credentialsFile = temporaryDirectory.appending(path: ".credentials.json")
        try Data(
            #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-FAKE","expiresAt":1784443682444}}"#.utf8
        ).write(to: credentialsFile)
        let source = KeychainClaudeCredentialsSource(
            credentialsFileURL: credentialsFile,
            securityExecutableURL: URL(fileURLWithPath: "/usr/bin/false"),
            securityArguments: [],
            keychainTimeout: 1
        )

        let credentials = try await source.load()

        #expect(credentials.accessToken == "sk-ant-oat01-FAKE")
    }

    @Test
    func unavailableKeychainWithoutFallbackHasAClearError() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = KeychainClaudeCredentialsSource(
            credentialsFileURL: temporaryDirectory.appending(path: "missing.json"),
            securityExecutableURL: URL(fileURLWithPath: "/usr/bin/false"),
            securityArguments: [],
            keychainTimeout: 1
        )

        do {
            _ = try await source.load()
            Issue.record("Expected unavailable Keychain access to fail")
        } catch let error as UsageProviderError {
            #expect(error == .notConnected("Couldn’t access Claude Code credentials"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func stalledKeychainLookupTimesOut() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = KeychainClaudeCredentialsSource(
            credentialsFileURL: temporaryDirectory.appending(path: "missing.json"),
            securityExecutableURL: URL(fileURLWithPath: "/bin/sleep"),
            securityArguments: ["5"],
            keychainTimeout: 0.01
        )
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            _ = try await source.load()
            Issue.record("Expected the stalled lookup to time out")
        } catch let error as UsageProviderError {
            #expect(error == .notConnected("Couldn’t access Claude Code credentials"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(startedAt.duration(to: clock.now) < .seconds(2))
    }

    @Test
    func fetchUsesSavedCredentialsAndBuildsTheExpectedRequest() async throws {
        let transport = ClaudeTransportSpy(
            outcomes: [
                .response(
                    statusCode: 200,
                    body: Data(
                        #"{"limits":[{"kind":"session","percent":15,"resets_at":null}]}"#.utf8
                    )
                ),
            ]
        )
        let provider = makeProvider(transport: transport)

        let limits = try await provider.fetchLimits()

        #expect(limits.map(\.id) == ["session"])
        #expect(limits.map(\.usedFraction) == [0.15])
        #expect(transport.requests.count == 1)

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.timeoutInterval == 15)
        #expect(
            request.value(forHTTPHeaderField: "Authorization")
                == "Bearer sk-ant-oat01-FAKE"
        )
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "AI-usage/1.0")
    }

    @Test
    func expiredCredentialsDoNotCallTheNetwork() async {
        let transport = ClaudeTransportSpy(outcomes: [])
        let provider = ClaudeUsageProvider(
            credentialsSource: StubClaudeCredentialsSource(
                result: .success(
                    ClaudeCredentials(
                        accessToken: "sk-ant-oat01-FAKE",
                        expiresAt: .distantPast
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
                    "Claude Code session expired — open Claude Code to refresh it"
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(transport.requests.isEmpty)
    }

    @Test
    func signedOutCredentialsSourceSurfacesDisconnectedWithoutANetworkCall() async {
        let transport = ClaudeTransportSpy(outcomes: [])
        let provider = ClaudeUsageProvider(
            credentialsSource: StubClaudeCredentialsSource(
                result: .failure(.notConnected("Not signed in to Claude Code"))
            ),
            transport: transport.send
        )

        do {
            _ = try await provider.fetchLimits()
            Issue.record("Expected signed-out credentials to be rejected")
        } catch let error as UsageProviderError {
            #expect(error == .notConnected("Not signed in to Claude Code"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(transport.requests.isEmpty)
    }

    @Test
    func authenticationResponsesSurfaceDisconnected() async {
        for statusCode in [401, 403] {
            let transport = ClaudeTransportSpy(
                outcomes: [
                    .response(
                        statusCode: statusCode,
                        body: Data(
                            #"{"type":"error","error":{"type":"authentication_error","message":"Invalid bearer token"}}"#.utf8
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
                        "Claude rejected the saved credentials — sign in to Claude Code again"
                    )
                )
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test
    func serverFailureIncludesTheHTTPStatus() async {
        let transport = ClaudeTransportSpy(
            outcomes: [.response(statusCode: 500, body: Data())]
        )
        let provider = makeProvider(transport: transport)

        do {
            _ = try await provider.fetchLimits()
            Issue.record("Expected HTTP 500 to fail")
        } catch let error as UsageProviderError {
            #expect(error == .fetchFailed("Claude usage service returned HTTP 500"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func transportFailureSurfacesAsANetworkError() async {
        let transport = ClaudeTransportSpy(
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
        for body in ["not-json", "{}"] {
            let transport = ClaudeTransportSpy(
                outcomes: [.response(statusCode: 200, body: Data(body.utf8))]
            )
            let provider = makeProvider(transport: transport)

            do {
                _ = try await provider.fetchLimits()
                Issue.record("Expected invalid response data to fail")
            } catch let error as UsageProviderError {
                #expect(
                    error == .fetchFailed("Unexpected response from Claude usage service")
                )
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test
    func failedRefreshClearsPreviouslyFetchedClaudeLimits() async {
        let transport = ClaudeTransportSpy(
            outcomes: [
                .response(
                    statusCode: 200,
                    body: Data(
                        #"{"limits":[{"kind":"session","percent":25,"resets_at":null}]}"#.utf8
                    )
                ),
                .failure(URLError(.timedOut)),
            ]
        )
        let provider = makeProvider(transport: transport)
        let defaults = ProviderTestDefaults()
        defer { defaults.remove() }
        let store = UsageStore(providers: [provider], defaults: defaults.defaults)
        store.select(providerID: provider.id, limitID: "session")

        await store.refreshAll()
        #expect(store.menuBarText == "25%")

        await store.refreshAll()

        #expect(
            store.providerStates[provider.id]
                == .disconnected(message: "Network error — check your connection")
        )
        #expect(store.menuBarText == "—")
    }

    private func makeProvider(transport: ClaudeTransportSpy) -> ClaudeUsageProvider {
        ClaudeUsageProvider(
            credentialsSource: StubClaudeCredentialsSource(
                result: .success(
                    ClaudeCredentials(
                        accessToken: "sk-ant-oat01-FAKE",
                        expiresAt: .distantFuture
                    )
                )
            ),
            transport: transport.send
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ClaudeUsageProviderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

@MainActor
private struct StubClaudeCredentialsSource: ClaudeCredentialsSource {
    let result: Result<ClaudeCredentials, UsageProviderError>

    func load() async throws -> ClaudeCredentials {
        try result.get()
    }
}

@MainActor
private final class ClaudeTransportSpy {
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

private struct ProviderTestDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "ClaudeUsageProviderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
