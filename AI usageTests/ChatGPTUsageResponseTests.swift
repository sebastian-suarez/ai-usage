import Foundation
import Testing
@testable import AI_usage

@MainActor
struct ChatGPTUsageResponseTests {
    @Test
    func capturedResponseMapsEveryLimitInServerOrder() throws {
        let response = try decode(Self.capturedResponse)

        let limits = response.toUsageLimits()
        try #require(limits.count == 2)

        #expect(limits.map(\.id) == ["primary", "feature:codex_bengalfox"])
        #expect(limits.map(\.name) == ["Weekly", "GPT-5.3-Codex-Spark"])
        #expect(limits.map(\.usedFraction) == [0.06, 0])
        #expect(limits[0].resetsAt == Date(timeIntervalSince1970: 1_785_024_392))
        #expect(limits[1].resetsAt == Date(timeIntervalSince1970: 1_785_040_089))
    }

    @Test
    func mainWindowsAreNamedByDurationRatherThanPosition() throws {
        let response = try decode(
            """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 45,
                  "limit_window_seconds": 18000
                },
                "secondary_window": {
                  "used_percent": 72,
                  "limit_window_seconds": 604800
                }
              }
            }
            """
        )

        let limits = response.toUsageLimits()

        #expect(limits.map(\.id) == ["primary", "secondary"])
        #expect(limits.map(\.name) == ["Session (5h)", "Weekly"])
        #expect(limits.map(\.usedFraction) == [0.45, 0.72])
    }

    @Test
    func oddAndAbsentDurationsUseStableFallbackNames() throws {
        let oddDuration = try decode(
            """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 20,
                  "limit_window_seconds": 259200
                },
                "secondary_window": null
              }
            }
            """
        )
        let absentDuration = try decode(
            """
            {
              "rate_limit": {
                "primary_window": {"used_percent": 250},
                "secondary_window": {
                  "used_percent": -50,
                  "limit_window_seconds": 0
                }
              }
            }
            """
        )

        #expect(oddDuration.toUsageLimits().map(\.name) == ["3-day"])
        #expect(
            absentDuration.toUsageLimits().map(\.name)
                == ["Primary limit", "Secondary limit"]
        )
        #expect(absentDuration.toUsageLimits().map(\.usedFraction) == [1, 0])
    }

    @Test
    func dailyAndMonthlyDurationsUseFriendlyNames() throws {
        let daily = try decode(
            """
            {
              "rate_limit": {
                "primary_window": {"used_percent": 1, "limit_window_seconds": 86400}
              }
            }
            """
        )
        let monthly = try decode(
            """
            {
              "rate_limit": {
                "primary_window": {"used_percent": 1, "limit_window_seconds": 2678400}
              }
            }
            """
        )

        #expect(daily.toUsageLimits().map(\.name) == ["Daily"])
        #expect(monthly.toUsageLimits().map(\.name) == ["Monthly"])
    }

    @Test
    func extremeDurationFallsBackWithoutOverflowing() throws {
        let response = try decode(
            """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 10,
                  "limit_window_seconds": 1e300
                }
              }
            }
            """
        )

        #expect(response.toUsageLimits().map(\.name) == ["Primary limit"])
    }

    @Test
    func codeReviewAndEveryNamedLimitAreKept() throws {
        let response = try decode(
            """
            {
              "code_review_rate_limit": {
                "primary_window": {"used_percent": 10},
                "secondary_window": {"used_percent": 20}
              },
              "additional_rate_limits": [
                {
                  "limit_name": "",
                  "metered_feature": "codex_foo_bar",
                  "rate_limit": {
                    "primary_window": {"used_percent": 30},
                    "secondary_window": null
                  }
                },
                {
                  "limit_name": "Named limit",
                  "rate_limit": {
                    "primary_window": {"used_percent": 40},
                    "secondary_window": {"used_percent": 50}
                  }
                },
                {
                  "rate_limit": {
                    "primary_window": {"used_percent": 60},
                    "secondary_window": null
                  }
                }
              ]
            }
            """
        )

        let limits = response.toUsageLimits()

        #expect(
            limits.map(\.id) == [
                "code_review",
                "code_review:secondary",
                "feature:codex_foo_bar",
                "feature:named-limit",
                "feature:named-limit:secondary",
                "feature:2",
            ]
        )
        #expect(
            limits.map(\.name) == [
                "Code review",
                "Code review (secondary)",
                "Codex foo bar",
                "Named limit",
                "Named limit (secondary)",
                "Limit 3",
            ]
        )
        #expect(limits.map(\.usedFraction) == [0.1, 0.2, 0.3, 0.4, 0.5, 0.6])
    }

    @Test
    func resetsPreferEpochSecondsThenFallBackToRelativeSeconds() throws {
        let response = try decode(
            """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 10,
                  "reset_at": 1785024392,
                  "reset_after_seconds": 9999
                },
                "secondary_window": {
                  "used_percent": 20,
                  "reset_after_seconds": 3600
                }
              },
              "code_review_rate_limit": {
                "primary_window": {"used_percent": 30},
                "secondary_window": null
              }
            }
            """
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        let limits = response.toUsageLimits(now: now)
        try #require(limits.count == 3)

        #expect(limits[0].resetsAt == Date(timeIntervalSince1970: 1_785_024_392))
        #expect(limits[1].resetsAt == now.addingTimeInterval(3_600))
        #expect(limits[2].resetsAt == nil)
    }

    @Test
    func payloadRecognitionDistinguishesUnknownBodiesFromEmptyKnownOnes() throws {
        let unknown = try decode("{}")
        let emptyRateLimit = try decode(
            #"{"rate_limit":{"primary_window":null,"secondary_window":null}}"#
        )
        let emptyNamedLimits = try decode(#"{"additional_rate_limits":[]}"#)
        let planOnly = try decode(#"{"plan_type":"plus"}"#)

        #expect(!unknown.hasRecognizedPayload)
        #expect(emptyRateLimit.hasRecognizedPayload)
        #expect(emptyNamedLimits.hasRecognizedPayload)
        #expect(planOnly.hasRecognizedPayload)
        #expect(emptyRateLimit.toUsageLimits().isEmpty)
        #expect(emptyNamedLimits.toUsageLimits().isEmpty)
        #expect(planOnly.toUsageLimits().isEmpty)
    }

    private func decode(_ json: String) throws -> ChatGPTUsageResponse {
        try JSONDecoder().decode(ChatGPTUsageResponse.self, from: Data(json.utf8))
    }

    static let capturedResponse = #"{"user_id":"user-FAKE0000000000000000FAKE","account_id":"user-FAKE0000000000000000FAKE","email":"user@example.com","plan_type":"prolite","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":6,"limit_window_seconds":604800,"reset_after_seconds":589104,"reset_at":1785024392},"secondary_window":null},"code_review_rate_limit":null,"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_bengalfox","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":0,"limit_window_seconds":604800,"reset_after_seconds":604800,"reset_at":1785040089},"secondary_window":null}}],"credits":{"has_credits":false,"unlimited":false,"overage_limit_reached":false,"balance":"0","approx_local_messages":[0,0],"approx_cloud_messages":[0,0]},"spend_control":{"reached":false,"individual_limit":null},"rate_limit_reached_type":null,"promo":null,"rate_limit_reset_credits":{"available_count":1,"applicable_available_count":0}}"#
}
