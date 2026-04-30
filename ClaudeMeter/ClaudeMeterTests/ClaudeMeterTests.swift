import Foundation
import Testing
@testable import ClaudeMeter

@Suite("UsageSnapshot decoding")
struct UsageSnapshotDecodingTests {

    @Test("Decodes the empirically observed full response")
    func decodesObservedResponse() throws {
        let snapshot = try AnthropicAPI.decoder.decode(UsageSnapshot.self, from: Data(observedResponse.utf8))
        #expect(snapshot.fiveHour?.utilization == 14.0)
        #expect(snapshot.sevenDay?.utilization == 65.0)
        #expect(snapshot.fiveHour?.resetsAt != nil)
        #expect(snapshot.sevenDay?.resetsAt != nil)
    }

    @Test("Both windows null is valid")
    func decodesBothNull() throws {
        let json = #"{"five_hour": null, "seven_day": null}"#
        let snapshot = try AnthropicAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.sevenDay == nil)
    }

    @Test("Window present but resets_at null is valid")
    func decodesNullResetTime() throws {
        let json = #"{"five_hour": {"utilization": 0.0, "resets_at": null}, "seven_day": null}"#
        let snapshot = try AnthropicAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour?.utilization == 0.0)
        #expect(snapshot.fiveHour?.resetsAt == nil)
    }

    @Test("Unknown top-level fields are ignored")
    func ignoresUnknownFields() throws {
        let json = """
        {
          "five_hour": {"utilization": 14.0, "resets_at": "2026-04-30T22:19:59.857928+00:00"},
          "seven_day": {"utilization": 65.0, "resets_at": "2026-05-03T21:59:59.857943+00:00"},
          "future_field_anthropic_invents_next_year": {"utilization": 99.9, "resets_at": null},
          "iguana_necktie": null,
          "extra_usage": {"is_enabled": true, "monthly_limit": 5000}
        }
        """
        let snapshot = try AnthropicAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour?.utilization == 14.0)
        #expect(snapshot.sevenDay?.utilization == 65.0)
    }

    @Test("Utilization above 100 is preserved (caller clamps for display)")
    func utilizationCanExceed100() throws {
        let json = #"{"five_hour": {"utilization": 105.5, "resets_at": "2026-04-30T22:19:59.857928+00:00"}, "seven_day": null}"#
        let snapshot = try AnthropicAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour?.utilization == 105.5)
    }

    @Test("ISO 8601 with microseconds and +00:00 offset parses correctly")
    func parsesMicrosecondISO8601() throws {
        let json = #"{"five_hour": {"utilization": 14.0, "resets_at": "2026-04-30T22:19:59.857928+00:00"}, "seven_day": null}"#
        let snapshot = try AnthropicAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        guard let date = snapshot.fiveHour?.resetsAt else {
            Issue.record("expected non-nil reset date")
            return
        }
        // Sanity check: parsed timestamp matches the ISO 8601 string when re-formatted.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let roundtrip = f.string(from: date)
        // Round-trip won't preserve sub-millisecond precision (Foundation truncates),
        // but the second/minute/hour/day must match.
        #expect(roundtrip.hasPrefix("2026-04-30T22:19:59"))
    }

    @Test("ISO 8601 without fractional seconds also parses")
    func parsesPlainISO8601() throws {
        let json = #"{"five_hour": {"utilization": 14.0, "resets_at": "2026-04-30T22:19:59+00:00"}, "seven_day": null}"#
        let snapshot = try AnthropicAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.fiveHour?.resetsAt != nil)
    }

    @Test("Invalid date string throws decoding error")
    func invalidDateThrows() {
        let json = #"{"five_hour": {"utilization": 14.0, "resets_at": "not-a-date"}, "seven_day": null}"#
        #expect(throws: DecodingError.self) {
            try AnthropicAPI.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        }
    }
}

/// The full body observed from `GET /api/oauth/usage` on 2026-04-30.
/// Pinned here so the parser keeps working as Anthropic adds new top-level fields.
private let observedResponse = """
{
  "five_hour": {
    "utilization": 14.0,
    "resets_at": "2026-04-30T22:19:59.857928+00:00"
  },
  "seven_day": {
    "utilization": 65.0,
    "resets_at": "2026-05-03T21:59:59.857943+00:00"
  },
  "seven_day_oauth_apps": null,
  "seven_day_opus": null,
  "seven_day_sonnet": {
    "utilization": 0.0,
    "resets_at": "2026-05-03T22:00:00.857950+00:00"
  },
  "seven_day_cowork": null,
  "seven_day_omelette": {
    "utilization": 0.0,
    "resets_at": null
  },
  "tangelo": null,
  "iguana_necktie": null,
  "omelette_promotional": null,
  "extra_usage": {
    "is_enabled": true,
    "monthly_limit": 5000,
    "used_credits": 0.0,
    "utilization": null,
    "currency": "USD"
  }
}
"""
