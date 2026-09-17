import Foundation
import Testing
@testable import AI_usage

@MainActor
struct MockUsageProviderTests {
    @Test
    func returnsConfiguredLimitsWithStableIDs() async throws {
        let limits = [
            UsageLimit(id: "session", name: "Session", usedFraction: 0.25, resetsAt: nil),
            UsageLimit(id: "weekly", name: "Weekly", usedFraction: 0.75, resetsAt: .now),
        ]
        let provider = MockUsageProvider(
            id: "test",
            displayName: "Test",
            baseLimits: limits,
            latency: .zero,
            jitter: 0
        )

        let firstFetch = try await provider.fetchLimits()
        let secondFetch = try await provider.fetchLimits()

        #expect(firstFetch.map(\.id) == ["session", "weekly"])
        #expect(secondFetch.map(\.id) == ["session", "weekly"])
        #expect(firstFetch == limits)
        #expect(secondFetch == limits)
    }

    @Test
    func clampsJitteredFractionsToDisplayRange() async throws {
        let provider = MockUsageProvider(
            id: "test",
            displayName: "Test",
            baseLimits: [
                UsageLimit(id: "low", name: "Low", usedFraction: -1, resetsAt: nil),
                UsageLimit(id: "high", name: "High", usedFraction: 2, resetsAt: nil),
            ],
            latency: .zero,
            jitter: 0.5
        )

        let limits = try await provider.fetchLimits()

        #expect(limits.allSatisfy { (0...1).contains($0.usedFraction) })
    }

    @Test
    func throwsConfiguredFailure() async {
        let expectedError = UsageProviderError.fetchFailed("Unavailable")
        let provider = MockUsageProvider(
            id: "test",
            displayName: "Test",
            baseLimits: [],
            latency: .zero,
            jitter: 0,
            failure: expectedError
        )

        do {
            _ = try await provider.fetchLimits()
            Issue.record("Expected the configured failure")
        } catch let error as UsageProviderError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func incrementsFetchCountForEveryAttempt() async throws {
        let provider = MockUsageProvider(
            id: "test",
            displayName: "Test",
            baseLimits: [],
            latency: .zero,
            jitter: 0
        )

        _ = try await provider.fetchLimits()
        _ = try await provider.fetchLimits()

        #expect(provider.fetchCount == 2)
    }
}
