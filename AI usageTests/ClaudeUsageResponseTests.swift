import Foundation
import Testing
@testable import AI_usage

@MainActor
struct ClaudeUsageResponseTests {
    @Test
    func capturedResponseMapsEveryLimitInServerOrder() throws {
        let response = try JSONDecoder().decode(
            ClaudeUsageResponse.self,
            from: Data(Self.capturedResponse.utf8)
        )

        let limits = response.toUsageLimits()
        try #require(limits.count == 3)

        #expect(limits.map(\.id) == ["session", "weekly_all", "weekly_scoped:fable"])
        #expect(
            limits.map(\.name) == [
                "Session",
                "Weekly (all models)",
                "Weekly (Fable)",
            ]
        )
        #expect(limits.map(\.usedFraction) == [0.15, 0.48, 0.81])
        #expect(
            abs((limits[0].resetsAt?.timeIntervalSince1970 ?? 0) - 1_784_432_399.570750)
                < 0.000_001
        )
        #expect(
            abs((limits[1].resetsAt?.timeIntervalSince1970 ?? 0) - 1_784_818_799.570774)
                < 0.000_001
        )
        #expect(
            abs((limits[2].resetsAt?.timeIntervalSince1970 ?? 0) - 1_784_818_799.571131)
                < 0.000_001
        )
    }

    @Test
    func unknownKindsAreKeptAndPercentagesAreClamped() throws {
        let response = try decode(
            """
            {
              "limits": [
                {"kind":"monthly_special","percent":5,"resets_at":null},
                {"kind":"below_zero","percent":-10,"resets_at":null},
                {"kind":"above_one_hundred","percent":150,"resets_at":null}
              ]
            }
            """
        )

        let limits = response.toUsageLimits()

        #expect(limits.map(\.id) == ["monthly_special", "below_zero", "above_one_hundred"])
        #expect(limits.map(\.name) == ["Monthly special", "Below zero", "Above one hundred"])
        #expect(limits.map(\.usedFraction) == [0.05, 0, 1])
    }

    @Test
    func scopedWeeklyLimitWithoutAModelFallsBackToItsKind() throws {
        let response = try decode(
            """
            {"limits":[{"kind":"weekly_scoped","percent":30,"scope":null}]}
            """
        )

        let limits = response.toUsageLimits()

        #expect(limits.map(\.id) == ["weekly_scoped"])
        #expect(limits.map(\.name) == ["Weekly scoped"])
        #expect(limits.map(\.usedFraction) == [0.3])
    }

    @Test
    func emptyLimitsArrayFallsBackToEveryKnownLegacyWindow() throws {
        let response = try decode(
            """
            {
              "five_hour":{"utilization":15,"resets_at":"2026-07-19T03:39:59Z"},
              "seven_day":{"utilization":48,"resets_at":null},
              "seven_day_opus":{"utilization":25,"resets_at":null},
              "seven_day_sonnet":{"utilization":125,"resets_at":null},
              "limits":[]
            }
            """
        )

        let limits = response.toUsageLimits()

        #expect(limits.map(\.id) == ["session", "weekly_all", "weekly_opus", "weekly_sonnet"])
        #expect(
            limits.map(\.name) == [
                "Session",
                "Weekly (all models)",
                "Weekly (Opus)",
                "Weekly (Sonnet)",
            ]
        )
        #expect(limits.map(\.usedFraction) == [0.15, 0.48, 0.25, 1])
    }

    @Test
    func absentLimitsArrayAlsoUsesLegacyWindows() throws {
        let response = try decode(
            """
            {
              "five_hour":{"utilization":10,"resets_at":null},
              "seven_day":{"utilization":20,"resets_at":null}
            }
            """
        )

        #expect(response.toUsageLimits().map(\.id) == ["session", "weekly_all"])
    }

    @Test
    func resetParserAcceptsFractionalAndFractionlessTimestamps() {
        let fractional = ClaudeUsageResponse.parseResetDate(
            "2026-07-19T03:39:59.570750+00:00"
        )
        let fractionlessOffset = ClaudeUsageResponse.parseResetDate(
            "2026-07-19T03:39:59+00:00"
        )
        let fractionlessZulu = ClaudeUsageResponse.parseResetDate(
            "2026-07-19T03:39:59Z"
        )

        #expect(
            abs((fractional?.timeIntervalSince1970 ?? 0) - 1_784_432_399.570750)
                < 0.000_001
        )
        #expect(fractionlessOffset == Date(timeIntervalSince1970: 1_784_432_399))
        #expect(fractionlessZulu == Date(timeIntervalSince1970: 1_784_432_399))
        #expect(ClaudeUsageResponse.parseResetDate("not-a-timestamp") == nil)
        #expect(ClaudeUsageResponse.parseResetDate(nil) == nil)
    }

    @Test
    func malformedResetTimeDoesNotDropTheLimit() throws {
        let response = try decode(
            """
            {"limits":[{"kind":"session","percent":12,"resets_at":"soon"}]}
            """
        )

        let limits = response.toUsageLimits()

        #expect(limits.count == 1)
        #expect(limits[0].resetsAt == nil)
    }

    private func decode(_ json: String) throws -> ClaudeUsageResponse {
        try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(json.utf8))
    }

    static let capturedResponse = #"{"five_hour":{"utilization":15.0,"resets_at":"2026-07-19T03:39:59.570750+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null},"seven_day":{"utilization":48.0,"resets_at":"2026-07-23T14:59:59.570774+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null},"seven_day_oauth_apps":null,"seven_day_opus":null,"seven_day_sonnet":null,"seven_day_cowork":null,"seven_day_omelette":null,"tangelo":null,"iguana_necktie":null,"omelette_promotional":null,"nimbus_quill":null,"cinder_cove":null,"amber_ladder":null,"extra_usage":{"is_enabled":true,"monthly_limit":null,"used_credits":40843.0,"utilization":null,"currency":"USD","decimal_places":2,"disabled_reason":null,"daily":null,"weekly":null},"limits":[{"kind":"session","group":"session","percent":15,"severity":"normal","resets_at":"2026-07-19T03:39:59.570750+00:00","scope":null,"is_active":false},{"kind":"weekly_all","group":"weekly","percent":48,"severity":"normal","resets_at":"2026-07-23T14:59:59.570774+00:00","scope":null,"is_active":false},{"kind":"weekly_scoped","group":"weekly","percent":81,"severity":"warning","resets_at":"2026-07-23T14:59:59.571131+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true}],"spend":{"used":{"amount_minor":40843,"currency":"USD","exponent":2},"limit":null,"percent":0,"severity":"normal","enabled":true,"disabled_reason":null,"cap":null,"balance":null,"auto_reload":null,"disclaimer":"Usage credits cover you when you hit your plan limits. [Learn more](https://support.claude.com/articles/12429409)","can_purchase_credits":false,"can_toggle":false},"member_dashboard_available":false}"#
}
