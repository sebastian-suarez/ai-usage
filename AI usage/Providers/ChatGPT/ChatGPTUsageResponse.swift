import Foundation

struct ChatGPTUsageResponse: Decodable {
    let planType: String?
    let rateLimit: RateLimit?
    let codeReviewRateLimit: RateLimit?
    let additionalRateLimits: [NamedRateLimit]?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case codeReviewRateLimit = "code_review_rate_limit"
        case additionalRateLimits = "additional_rate_limits"
    }

    var hasRecognizedPayload: Bool {
        planType != nil
            || rateLimit != nil
            || codeReviewRateLimit != nil
            || additionalRateLimits != nil
    }

    func toUsageLimits(now: Date = .now) -> [UsageLimit] {
        var limits: [UsageLimit] = []

        if let rateLimit {
            if let primaryWindow = rateLimit.primaryWindow {
                limits.append(
                    Self.usageLimit(
                        for: primaryWindow,
                        id: "primary",
                        name: Self.durationName(
                            seconds: primaryWindow.limitWindowSeconds,
                            fallback: "Primary limit"
                        ),
                        now: now
                    )
                )
            }

            if let secondaryWindow = rateLimit.secondaryWindow {
                limits.append(
                    Self.usageLimit(
                        for: secondaryWindow,
                        id: "secondary",
                        name: Self.durationName(
                            seconds: secondaryWindow.limitWindowSeconds,
                            fallback: "Secondary limit"
                        ),
                        now: now
                    )
                )
            }
        }

        if let codeReviewRateLimit {
            if let primaryWindow = codeReviewRateLimit.primaryWindow {
                limits.append(
                    Self.usageLimit(
                        for: primaryWindow,
                        id: "code_review",
                        name: "Code review",
                        now: now
                    )
                )
            }

            if let secondaryWindow = codeReviewRateLimit.secondaryWindow {
                limits.append(
                    Self.usageLimit(
                        for: secondaryWindow,
                        id: "code_review:secondary",
                        name: "Code review (secondary)",
                        now: now
                    )
                )
            }
        }

        for (index, namedLimit) in (additionalRateLimits ?? []).enumerated() {
            guard let rateLimit = namedLimit.rateLimit else { continue }

            let identity = Self.identity(for: namedLimit, at: index)
            if let primaryWindow = rateLimit.primaryWindow {
                limits.append(
                    Self.usageLimit(
                        for: primaryWindow,
                        id: identity.id,
                        name: identity.name,
                        now: now
                    )
                )
            }

            if let secondaryWindow = rateLimit.secondaryWindow {
                limits.append(
                    Self.usageLimit(
                        for: secondaryWindow,
                        id: "\(identity.id):secondary",
                        name: "\(identity.name) (secondary)",
                        now: now
                    )
                )
            }
        }

        return limits
    }

    private static func usageLimit(
        for window: Window,
        id: String,
        name: String,
        now: Date
    ) -> UsageLimit {
        let resetsAt: Date?
        if let resetAt = window.resetAt {
            resetsAt = Date(timeIntervalSince1970: resetAt)
        } else if let resetAfterSeconds = window.resetAfterSeconds {
            resetsAt = now.addingTimeInterval(resetAfterSeconds)
        } else {
            resetsAt = nil
        }

        return UsageLimit(
            id: id,
            name: name,
            usedFraction: min(max(window.usedPercent / 100, 0), 1),
            resetsAt: resetsAt
        )
    }

    private static func durationName(seconds: Double?, fallback: String) -> String {
        guard let seconds, seconds > 0 else { return fallback }

        if seconds < 86_400 {
            guard let hours = roundedInteger(seconds / 3_600) else {
                return fallback
            }
            return "Session (\(hours)h)"
        }

        guard let days = roundedInteger(seconds / 86_400) else {
            return fallback
        }
        switch days {
        case 1:
            return "Daily"
        case 7:
            return "Weekly"
        case 30, 31:
            return "Monthly"
        default:
            return "\(days)-day"
        }
    }

    private static func roundedInteger(_ value: Double) -> Int? {
        let rounded = value.rounded()
        guard rounded.isFinite,
              rounded >= Double(Int.min),
              rounded < Double(Int.max) else {
            return nil
        }

        return Int(rounded)
    }

    private static func identity(
        for namedLimit: NamedRateLimit,
        at index: Int
    ) -> (id: String, name: String) {
        let limitName = nonEmpty(namedLimit.limitName)
        let meteredFeature = nonEmpty(namedLimit.meteredFeature)

        let key: String
        if let meteredFeature {
            key = meteredFeature
        } else if let limitName {
            key = limitName.lowercased().replacingOccurrences(of: " ", with: "-")
        } else {
            key = "\(index)"
        }

        let name: String
        if let limitName {
            name = limitName
        } else if let meteredFeature {
            name = humanized(meteredFeature)
        } else {
            name = "Limit \(index + 1)"
        }

        return ("feature:\(key)", name)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return value
    }

    private static func humanized(_ value: String) -> String {
        let spaced = value.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}

extension ChatGPTUsageResponse {
    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Double?
        let resetAfterSeconds: Double?
        let resetAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAfterSeconds = "reset_after_seconds"
            case resetAt = "reset_at"
        }
    }

    struct NamedRateLimit: Decodable {
        let limitName: String?
        let meteredFeature: String?
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case meteredFeature = "metered_feature"
            case rateLimit = "rate_limit"
        }
    }
}
