import Foundation
import Testing
@testable import AI_usage

@MainActor
struct UsageStoreTests {
    @Test
    func selectionPersistsAndRestores() {
        let isolatedDefaults = IsolatedDefaults()
        defer { isolatedDefaults.remove() }

        let store = UsageStore(providers: [], defaults: isolatedDefaults.defaults)
        store.select(providerID: "claude", limitID: "weekly")

        #expect(isolatedDefaults.defaults.string(forKey: "selectedProviderID") == "claude")
        #expect(isolatedDefaults.defaults.string(forKey: "selectedLimitID") == "weekly")

        let restoredStore = UsageStore(providers: [], defaults: isolatedDefaults.defaults)
        #expect(
            restoredStore.selection == LimitSelection(
                providerID: "claude",
                limitID: "weekly"
            )
        )
    }

    @Test
    func refreshConnectsProviderAndFormatsSelectedLimit() async {
        let isolatedDefaults = IsolatedDefaults()
        defer { isolatedDefaults.remove() }

        let provider = SequencedUsageProvider(
            id: "test",
            results: [
                .success([
                    UsageLimit(id: "standard", name: "Standard", usedFraction: 0.73, resetsAt: nil),
                    UsageLimit(id: "over", name: "Over", usedFraction: 1.4, resetsAt: nil),
                ]),
            ]
        )
        let store = UsageStore(providers: [provider], defaults: isolatedDefaults.defaults)
        store.select(providerID: provider.id, limitID: "standard")
        let beforeRefresh = Date.now

        await store.refreshAll()

        let afterRefresh = Date.now
        guard case let .connected(limits, asOf)? = store.providerStates[provider.id] else {
            Issue.record("Expected the provider to be connected")
            return
        }

        #expect(limits.count == 2)
        #expect(asOf >= beforeRefresh)
        #expect(asOf <= afterRefresh)
        #expect(store.menuBarText == "73%")

        store.select(providerID: provider.id, limitID: "over")
        #expect(store.menuBarText == "100%")
    }

    @Test
    func unavailableUsageShowsDash() async {
        let isolatedDefaults = IsolatedDefaults()
        defer { isolatedDefaults.remove() }

        let provider = SequencedUsageProvider(
            id: "test",
            results: [.failure(.notConnected("Sign in required"))]
        )
        let store = UsageStore(providers: [provider], defaults: isolatedDefaults.defaults)

        #expect(store.menuBarText == "—")

        store.select(providerID: provider.id, limitID: "session")
        #expect(store.menuBarText == "—")

        await store.refreshAll()

        #expect(store.providerStates[provider.id] == .disconnected(message: "Sign in required"))
        #expect(store.menuBarText == "—")
    }

    @Test
    func failedRefreshDiscardsPriorLimitsWithoutAffectingOtherProviders() async {
        let isolatedDefaults = IsolatedDefaults()
        defer { isolatedDefaults.remove() }

        let staleLimit = UsageLimit(
            id: "session",
            name: "Session",
            usedFraction: 0.5,
            resetsAt: nil
        )
        let failingProvider = SequencedUsageProvider(
            id: "failing",
            results: [
                .success([staleLimit]),
                .failure(.fetchFailed("Refresh failed")),
            ]
        )
        let connectedProvider = MockUsageProvider(
            id: "connected",
            displayName: "Connected",
            baseLimits: [staleLimit],
            latency: .zero,
            jitter: 0
        )
        let store = UsageStore(
            providers: [failingProvider, connectedProvider],
            defaults: isolatedDefaults.defaults
        )
        store.select(providerID: failingProvider.id, limitID: staleLimit.id)

        await store.refreshAll()
        #expect(store.menuBarText == "50%")

        await store.refreshAll()

        #expect(
            store.providerStates[failingProvider.id] == .disconnected(message: "Refresh failed")
        )
        #expect(store.menuBarText == "—")

        guard case .connected? = store.providerStates[connectedProvider.id] else {
            Issue.record("Expected the other provider to remain connected")
            return
        }
    }

    @Test
    func firstRefreshSelectsFirstLimitOfFirstConnectedProvider() async {
        let isolatedDefaults = IsolatedDefaults()
        defer { isolatedDefaults.remove() }

        let unavailableProvider = SequencedUsageProvider(
            id: "unavailable",
            results: [.failure(.notConnected("Unavailable"))]
        )
        let connectedProvider = MockUsageProvider(
            id: "connected",
            displayName: "Connected",
            baseLimits: [
                UsageLimit(id: "first", name: "First", usedFraction: 0.2, resetsAt: nil),
                UsageLimit(id: "second", name: "Second", usedFraction: 0.4, resetsAt: nil),
            ],
            latency: .zero,
            jitter: 0
        )
        let store = UsageStore(
            providers: [unavailableProvider, connectedProvider],
            defaults: isolatedDefaults.defaults
        )

        await store.refreshAll()

        #expect(
            store.selection == LimitSelection(
                providerID: connectedProvider.id,
                limitID: "first"
            )
        )
        #expect(store.menuBarText == "20%")
    }

    @Test
    func autoRefreshFetchesPeriodically() async {
        let isolatedDefaults = IsolatedDefaults()
        defer { isolatedDefaults.remove() }

        let provider = MockUsageProvider(
            id: "test",
            displayName: "Test",
            baseLimits: [],
            latency: .zero,
            jitter: 0
        )
        let store = UsageStore(providers: [provider], defaults: isolatedDefaults.defaults)
        defer { store.stopAutoRefresh() }

        store.startAutoRefresh(interval: .milliseconds(10))

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while provider.fetchCount < 2, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(provider.fetchCount >= 2)
    }

    @Test
    func connectedStateExposesEveryLimitIncludingUnknownResetTimes() async {
        let isolatedDefaults = IsolatedDefaults()
        defer { isolatedDefaults.remove() }

        let knownReset = Date.now.addingTimeInterval(60 * 60)
        let provider = MockUsageProvider(
            id: "test",
            displayName: "Test",
            baseLimits: [
                UsageLimit(id: "known", name: "Known", usedFraction: 0.2, resetsAt: knownReset),
                UsageLimit(id: "unknown", name: "Unknown", usedFraction: 0.4, resetsAt: nil),
            ],
            latency: .zero,
            jitter: 0
        )
        let store = UsageStore(providers: [provider], defaults: isolatedDefaults.defaults)

        await store.refreshAll()

        guard case let .connected(limits, _)? = store.providerStates[provider.id] else {
            Issue.record("Expected the provider to be connected")
            return
        }

        #expect(limits.map(\.id) == ["known", "unknown"])
        #expect(limits.first(where: { $0.id == "known" })?.resetsAt == knownReset)
        #expect(limits.first(where: { $0.id == "unknown" })?.resetsAt == nil)
    }
}

@MainActor
private final class SequencedUsageProvider: UsageProvider {
    let id: String
    let displayName: String

    private var results: [Result<[UsageLimit], UsageProviderError>]

    init(
        id: String,
        displayName: String = "Test",
        results: [Result<[UsageLimit], UsageProviderError>]
    ) {
        self.id = id
        self.displayName = displayName
        self.results = results
    }

    func fetchLimits() async throws -> [UsageLimit] {
        guard !results.isEmpty else {
            throw UsageProviderError.fetchFailed("No result configured")
        }

        return try results.removeFirst().get()
    }
}

private struct IsolatedDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "AIUsageTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
