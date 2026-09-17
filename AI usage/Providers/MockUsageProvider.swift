import Foundation

final class MockUsageProvider: UsageProvider {
    let id: String
    let displayName: String

    private let baseLimits: [UsageLimit]
    private let latency: Duration
    private let jitter: Double
    private let failure: UsageProviderError?

    private(set) var fetchCount = 0

    init(
        id: String,
        displayName: String,
        baseLimits: [UsageLimit],
        latency: Duration = .milliseconds(300),
        jitter: Double = 0.02,
        failure: UsageProviderError? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.baseLimits = baseLimits
        self.latency = latency
        self.jitter = abs(jitter)
        self.failure = failure
    }

    func fetchLimits() async throws -> [UsageLimit] {
        fetchCount += 1

        if latency > .zero {
            try await Task.sleep(for: latency)
        }

        if let failure {
            throw failure
        }

        return baseLimits.map { limit in
            let offset = jitter == 0 ? 0 : Double.random(in: -jitter...jitter)

            return UsageLimit(
                id: limit.id,
                name: limit.name,
                usedFraction: min(max(limit.usedFraction + offset, 0), 1),
                resetsAt: limit.resetsAt
            )
        }
    }
}

extension MockUsageProvider {
    static var claudeSample: MockUsageProvider {
        MockUsageProvider(
            id: "claude",
            displayName: "Claude (sample)",
            baseLimits: [
                UsageLimit(
                    id: "session",
                    name: "Session",
                    usedFraction: 0.62,
                    resetsAt: Date.now.addingTimeInterval(2 * 60 * 60)
                ),
                UsageLimit(
                    id: "weekly",
                    name: "Weekly",
                    usedFraction: 0.34,
                    resetsAt: Date.now.addingTimeInterval(4 * 24 * 60 * 60)
                ),
                UsageLimit(
                    id: "weekly-opus",
                    name: "Weekly Opus",
                    usedFraction: 0.11,
                    resetsAt: Date.now.addingTimeInterval(4 * 24 * 60 * 60)
                ),
            ]
        )
    }

    static var chatGPTSample: MockUsageProvider {
        MockUsageProvider(
            id: "chatgpt",
            displayName: "ChatGPT (sample)",
            baseLimits: [
                UsageLimit(
                    id: "session",
                    name: "Session",
                    usedFraction: 0.45,
                    resetsAt: Date.now.addingTimeInterval(60 * 60)
                ),
                UsageLimit(
                    id: "weekly",
                    name: "Weekly",
                    usedFraction: 0.72,
                    resetsAt: Date.now.addingTimeInterval(3 * 24 * 60 * 60)
                ),
                UsageLimit(
                    id: "deep-research",
                    name: "Deep research",
                    usedFraction: 0.80,
                    resetsAt: nil
                ),
            ]
        )
    }
}
