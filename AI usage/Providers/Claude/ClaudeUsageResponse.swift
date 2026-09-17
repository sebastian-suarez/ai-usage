import Foundation

struct ClaudeUsageResponse: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let limits: [Limit]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case limits
    }

    var hasRecognizedPayload: Bool {
        limits != nil
            || fiveHour != nil
            || sevenDay != nil
            || sevenDayOpus != nil
            || sevenDaySonnet != nil
    }

    func toUsageLimits() -> [UsageLimit] {
        if let limits, !limits.isEmpty {
            return limits.map { limit in
                let identity = Self.identity(for: limit)

                return UsageLimit(
                    id: identity.id,
                    name: identity.name,
                    usedFraction: Self.usedFraction(from: limit.percent),
                    resetsAt: Self.parseResetDate(limit.resetsAt)
                )
            }
        }

        return [
            fallbackLimit(
                window: fiveHour,
                id: "session",
                name: "Session"
            ),
            fallbackLimit(
                window: sevenDay,
                id: "weekly_all",
                name: "Weekly (all models)"
            ),
            fallbackLimit(
                window: sevenDayOpus,
                id: "weekly_opus",
                name: "Weekly (Opus)"
            ),
            fallbackLimit(
                window: sevenDaySonnet,
                id: "weekly_sonnet",
                name: "Weekly (Sonnet)"
            ),
        ].compactMap { $0 }
    }

    static func parseResetDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        return try? Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            .parse(value)
    }

    private func fallbackLimit(
        window: UsageWindow?,
        id: String,
        name: String
    ) -> UsageLimit? {
        guard let window else { return nil }

        return UsageLimit(
            id: id,
            name: name,
            usedFraction: Self.usedFraction(from: window.utilization),
            resetsAt: Self.parseResetDate(window.resetsAt)
        )
    }

    private static func identity(for limit: Limit) -> (id: String, name: String) {
        switch limit.kind {
        case "session":
            return ("session", "Session")
        case "weekly_all":
            return ("weekly_all", "Weekly (all models)")
        case "weekly_scoped":
            guard let modelName = limit.scope?.model?.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !modelName.isEmpty else {
                return (limit.kind, humanized(limit.kind))
            }

            return ("weekly_scoped:\(modelName.lowercased())", "Weekly (\(modelName))")
        default:
            return (limit.kind, humanized(limit.kind))
        }
    }

    private static func humanized(_ kind: String) -> String {
        let spaced = kind.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    private static func usedFraction(from percent: Double) -> Double {
        min(max(percent / 100, 0), 1)
    }
}

extension ClaudeUsageResponse {
    struct UsageWindow: Decodable {
        let utilization: Double
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    struct Limit: Decodable {
        let kind: String
        let percent: Double
        let resetsAt: String?
        let scope: Scope?

        enum CodingKeys: String, CodingKey {
            case kind
            case percent
            case resetsAt = "resets_at"
            case scope
        }
    }

    struct Scope: Decodable {
        let model: Model?
    }

    struct Model: Decodable {
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }
}
