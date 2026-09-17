import Foundation
import Observation

@Observable
final class UsageStore {
    let providers: [any UsageProvider]

    private(set) var providerStates: [String: ProviderState]
    private(set) var selection: LimitSelection?
    private(set) var isRefreshing = false

    private let defaults: UserDefaults
    private var autoRefreshTask: Task<Void, Never>?

    init(providers: [any UsageProvider], defaults: UserDefaults) {
        self.providers = providers
        self.defaults = defaults
        providerStates = Dictionary(
            uniqueKeysWithValues: providers.map { ($0.id, ProviderState.loading) }
        )

        if let providerID = defaults.string(forKey: DefaultsKey.selectedProviderID),
           let limitID = defaults.string(forKey: DefaultsKey.selectedLimitID) {
            selection = LimitSelection(providerID: providerID, limitID: limitID)
        }
    }

    var menuBarText: String {
        guard let selection,
              case let .connected(limits, _) = providerStates[selection.providerID],
              let limit = limits.first(where: { $0.id == selection.limitID }),
              limit.usedFraction.isFinite else {
            return "—"
        }

        let clampedFraction = min(max(limit.usedFraction, 0), 1)
        return "\(Int((clampedFraction * 100).rounded()))%"
    }

    func select(providerID: String, limitID: String) {
        selection = LimitSelection(providerID: providerID, limitID: limitID)
        defaults.set(providerID, forKey: DefaultsKey.selectedProviderID)
        defaults.set(limitID, forKey: DefaultsKey.selectedLimitID)
    }

    func refreshAll() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        for provider in providers {
            do {
                let limits = try await provider.fetchLimits()
                providerStates[provider.id] = .connected(limits: limits, asOf: .now)
            } catch {
                providerStates[provider.id] = .disconnected(message: message(for: error))
            }
        }

        selectFirstAvailableLimitIfNeeded()
    }

    func startAutoRefresh(interval: Duration = .seconds(300)) {
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.refreshAll()

                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func selectFirstAvailableLimitIfNeeded() {
        guard selection == nil else { return }

        for provider in providers {
            guard case let .connected(limits, _) = providerStates[provider.id],
                  let firstLimit = limits.first else {
                continue
            }

            select(providerID: provider.id, limitID: firstLimit.id)
            return
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case let UsageProviderError.notConnected(message),
             let UsageProviderError.fetchFailed(message):
            return message
        default:
            return error.localizedDescription
        }
    }
}

private enum DefaultsKey {
    static let selectedProviderID = "selectedProviderID"
    static let selectedLimitID = "selectedLimitID"
}
