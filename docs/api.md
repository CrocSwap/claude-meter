# API: `/api/oauth/usage`

This document pins the empirically observed shape of the usage endpoint and how `claude-meter` parses it. **Re-verify after every Anthropic-side change** to the OAuth scheme — the endpoint is unofficial and may shift.

## Last verified

- Date: 2026-04-30
- `anthropic-beta: oauth-2025-04-20`
- Probed via a token with scopes `user:inference user:file_upload user:profile`.

## Request

```
GET https://api.anthropic.com/api/oauth/usage
```

| Header | Value |
|--------|-------|
| `Accept` | `application/json, text/plain, */*` |
| `Content-Type` | `application/json` |
| `Authorization` | `Bearer <opaque-108-char-access-token>` |
| `anthropic-beta` | `oauth-2025-04-20` |
| `User-Agent` | `claude-meter/<version> (macOS)` |

## Auth requirements

- **Scope: `user:profile`** is required. A token without it returns:
  ```json
  {"type":"error","error":{"type":"permission_error","message":"OAuth token does not meet scope requirement user:profile",...}}
  ```
  with HTTP 403. This is the only documented scope requirement we've observed; any additional scopes (`user:inference`, `user:file_upload`) are unrelated to this endpoint.

- An expired or revoked token returns HTTP 401 with `type: authentication_error`. `OAuthClient` handles this with a forced refresh-and-retry.

## Response shape

Observed body (2026-04-30, real values redacted to `…` where appropriate):

```json
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
```

## Field reference

### `five_hour`, `seven_day` (the v1 surface)

Both follow the same shape. Either may be `null` (whole window absent), and `resets_at` within a present window may also be `null`.

| Field | Type | Notes |
|-------|------|-------|
| `utilization` | `Double` | Percentage 0.0–100.0. **Not a fraction.** |
| `resets_at` | `String?` (ISO 8601) | Format: `YYYY-MM-DDThh:mm:ss.ffffff+00:00`. Microsecond precision, always UTC offset `+00:00`. May be `null` even when the window object is present (observed for `seven_day_omelette` at 0% util). |

### Other windows (out of v1 scope, may surface in v1.1)

| Field | Likely meaning | Action in v1 |
|-------|---------------|--------------|
| `seven_day_opus` | 7-day Opus-specific quota | Ignore |
| `seven_day_sonnet` | 7-day Sonnet-specific quota | Ignore |
| `seven_day_oauth_apps` | 7-day quota for third-party OAuth apps (like us) | Ignore |
| `seven_day_cowork` | 7-day Cowork (desktop's coding agent) usage | Ignore |
| `seven_day_omelette` | Internal codename — purpose unclear | Ignore |
| `tangelo` | Internal codename — purpose unclear | Ignore |
| `iguana_necktie` | Internal codename — purpose unclear | Ignore |
| `omelette_promotional` | Promotional bucket | Ignore |

### `extra_usage`

The pay-as-you-go credit bucket Pro/Max users can opt into:

```
{
  "is_enabled": Bool,
  "monthly_limit": Int,         # presumably USD cents or whole-dollar units; verify before using
  "used_credits": Double,
  "utilization": Double?,       # null when monthly_limit is 0 / not set
  "currency": "USD"
}
```

Out of scope per AGENTS.md:168 ("not a billing or cost tracker"). Ignore in v1.

## Edge cases the parser must handle

1. **Whole window is `null`.** `five_hour: null` or `seven_day: null` are both valid. The popover shows the bar in a "no data" state for that window — not an error.
2. **`resets_at` is `null` inside a present window.** Surface as "resets unknown"; do not try to format a `nil` date.
3. **Both windows are `null` simultaneously.** Treat as "data unavailable" — distinct from auth/network errors. Show an info-state, not a red error.
4. **Unknown top-level fields.** Anthropic adds new windows (`iguana_necktie` and friends). Parser MUST ignore unknown keys gracefully; never fail on them.
5. **`utilization` exactly `100.0` or above.** Cap the visual bar at 100%; treat anything `>= 100` as "at limit". Do not assert utilization is `<= 100`.
6. **HTTP errors:**
   - `401`: force a refresh, retry once. If still 401, clear tokens and return to sign-in.
   - `403`: scope mismatch — surface "claude-meter needs to be re-authorized" and re-run the OAuth flow.
   - `404`: endpoint removed; show "claude-meter needs an update."
   - `5xx`: transient; honor exponential backoff in `UsagePoller`.
   - Network failure: keep last known snapshot, mark stale in popover.

## Parser strategy

```swift
struct UsageWindow: Decodable {
    let utilization: Double
    let resetsAt: Date?
    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct UsageSnapshot: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
```

- Decode only the two fields we use. All other top-level keys are silently ignored by `JSONDecoder` — we get free forward-compatibility.
- Configure `JSONDecoder.dateDecodingStrategy = .iso8601` with a formatter that accepts microseconds and `+00:00`, since `.iso8601` default doesn't accept fractional seconds. Use a custom `DateFormatter` or `ISO8601DateFormatter` with `.withFractionalSeconds`.

## Re-verification

```sh
# 1. Confirm endpoint still 200s with our planned scope.
curl -sS -i -H "Authorization: Bearer <token>" \
     -H "anthropic-beta: oauth-2025-04-20" \
     -H "User-Agent: claude-meter-probe/0.0 (macOS)" \
     https://api.anthropic.com/api/oauth/usage

# 2. Confirm shape of five_hour and seven_day still matches above.
# 3. Update this doc with any new fields seen — and confirm parser still
#    ignores them silently in a unit test.
```

If the shape changes meaningfully (new required fields, different units, different date format), update the parser and bump claude-meter's minor version with a changelog note.
