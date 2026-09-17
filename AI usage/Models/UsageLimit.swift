import Foundation

struct UsageLimit: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let usedFraction: Double
    let resetsAt: Date?
}

struct LimitSelection: Equatable, Sendable {
    let providerID: String
    let limitID: String
}

enum ProviderState: Equatable, Sendable {
    case loading
    case connected(limits: [UsageLimit], asOf: Date)
    case disconnected(message: String)
}
