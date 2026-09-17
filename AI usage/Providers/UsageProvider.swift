protocol UsageProvider {
    var id: String { get }
    var displayName: String { get }
    func fetchLimits() async throws -> [UsageLimit]
}

enum UsageProviderError: Error, Equatable {
    case notConnected(String)
    case fetchFailed(String)
}
