# AGENTS.md — Claude Meter

A macOS menu bar app that displays Claude subscription usage (5-hour and 7-day windows) like a battery gauge. Open source, single-binary install, zero-config for end users.

## North star

A user installs via Homebrew, launches once, and forever after has ambient awareness of their Claude usage in the menu bar. The app is invisible until they need it. If a user has to think about this app after install, we failed.

## Hard product constraints

These are not negotiable. Push back if a request would violate them.

- **macOS only, native.** SwiftUI + AppKit menu bar APIs. No Electron, no web views, no Python runtime.
- **Single signed binary.** Ships as a `.app` inside a `.dmg`, distributed via Homebrew cask and GitHub Releases. No installer wizards.
- **Minimal first-run config.** A single "Sign in with Anthropic" click triggers OAuth 2.0 + PKCE in a system-managed browser session (`ASWebAuthenticationSession`); tokens are stored in claude-meter's own Keychain entry. After first sign-in, subsequent launches are silent. No settings screen.
- **Tiny resource footprint.** Idle RAM under 50MB. CPU under 0.1% when idle. The app polls on a slow cadence; it is not a real-time dashboard.
- **Graceful degradation.** If the API endpoint changes, auth breaks, or network is offline, the menu bar shows a clear error state — never a crash, never a misleading number.
- **No telemetry, no analytics.** Network calls limited to (a) Anthropic's OAuth endpoints during sign-in and refresh, and (b) `api.anthropic.com` for usage queries. No third-party services. This is a personal utility. Treat user data accordingly.

## Tech stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI with `MenuBarExtra` (macOS 13+). AppKit fallbacks where SwiftUI menu bar APIs are insufficient.
- **Concurrency:** Swift structured concurrency (`async/await`, actors). No GCD callbacks.
- **HTTP:** `URLSession` only. No Alamofire or third-party HTTP libraries.
- **Keychain:** Direct Security.framework calls. No KeychainAccess or wrappers — the dependency surface stays minimal.
- **Build:** Xcode project committed to repo. SPM for any (rare) dependencies.
- **Min macOS:** 14.0 (Sonoma). Gives us `MenuBarExtra` and the `@Observable` macro for SwiftUI state. Sonoma has been out long enough that it covers a strong majority of active Macs; if a future v1.x needs to drop to 13, the only blocker would be `@Observable` (replaceable with `ObservableObject` + `@Published`).

Do not add dependencies without explicit approval. Every line of third-party code is a future maintenance liability.

## v1 scope

In scope:
- Menu bar icon + percentage display (the higher of 5h/7d, with a subtle indicator of which window is the binding constraint)
- Click reveals a popover with: 5h bar + reset countdown, 7d bar + reset countdown, last-updated timestamp, manual refresh button, quit option
- Color thresholds: green <60%, amber 60–85%, red >85%
- Polls every 60s, faster (15s) when popover is open
- First-run OAuth 2.0 + PKCE sign-in via `ASWebAuthenticationSession`; tokens stored in claude-meter's own Keychain entry; automatic refresh on expiry
- Launch at login (off by default, toggleable from popover)

Explicitly out of scope for v1:
- Per-surface attribution (Cowork vs Code vs Chat) — the API doesn't expose this
- Predictive "you'll hit cap in X hours" — save for v1.1
- Notifications/alerts at thresholds — save for v1.1
- Historical graphs/sparklines — save for v1.1
- Per-task burn logging — save for v2 if at all
- Windows/Linux support — never, unless someone forks

If a request expands scope, push back and ask whether it should be a v1.1 issue instead.

## API contract

**Endpoint:** `GET https://api.anthropic.com/api/oauth/usage`

**Headers:**
```
Accept: application/json, text/plain, */*
Content-Type: application/json
Authorization: Bearer <oauth_token>
anthropic-beta: oauth-2025-04-20
User-Agent: claude-meter/<version> (macOS)
```

**Response shape (current, subject to change):**
```json
{
  "five_hour": { "utilization": 0.42, "resets_at": "2026-04-30T18:00:00Z" },
  "seven_day": { "utilization": 0.18, "resets_at": "2026-05-03T00:00:00Z" }
}
```

**Important:** This endpoint is unofficial. Treat the response shape as untrusted:
- Both windows may be `null` independently — handle each absent.
- `utilization` may be a fraction (0.0–1.0) or percentage (0–100) — verify by inspection on first integration and pin a parser.
- `resets_at` may be ISO 8601 string or Unix epoch — same.
- New fields may appear; ignore unknown fields gracefully.
- The endpoint may return 401 on auth failure, 404 if removed, 5xx on Anthropic-side issues. Handle each distinctly.

**Auth flow:** claude-meter performs its own OAuth 2.0 sign-in (Authorization Code grant + PKCE) on first launch. Access and refresh tokens are stored in the macOS Keychain under a service we own (`dev.claudemeter.oauth`). claude-meter reads from and writes to its own Keychain entry only — it does not touch any other app's Keychain items.

The flow:

1. On launch, if no valid token is stored, the popover shows a "Sign in with Anthropic" button and nothing else.
2. Clicking it opens `ASWebAuthenticationSession` to Anthropic's authorization endpoint with a PKCE code challenge. The user sees Anthropic's own domain in a system-managed browser session; claude-meter never sees the password.
3. After successful auth, Anthropic redirects to `claude-meter://oauth/callback?code=...`. The app exchanges the code (plus the PKCE verifier it generated in step 2) for an access + refresh token pair at Anthropic's token endpoint.
4. Tokens go into Keychain. The menu bar starts updating.
5. When the access token expires, `OAuthClient` uses the refresh token to get a new pair transparently. If refresh fails (refresh token expired or revoked), the Keychain entry is cleared and the popover returns to the sign-in state.

If the API returns 401 with a presumably-valid token, retry once after a forced refresh before surfacing an error.

**Custom URL scheme:** `claude-meter://` is registered in `Info.plist` (`CFBundleURLTypes`). Only the `oauth/callback` host+path is handled; everything else is rejected.

**Open dependency on Anthropic:** this design assumes Anthropic offers a way to register (or otherwise document) a third-party OAuth client and an acceptable redirect URI scheme. If neither is available at v1 implementation time, see `docs/auth.md` for the current state. Do **not** ship a workaround that reuses another Anthropic-developed app's client ID — that's a maintenance and trust hazard.

## Architecture

Four small services. Views are thin and observe the store.

1. **`UsageStore`** (`@MainActor @Observable` class) — holds the latest snapshot, timestamp, and error state. Single source of truth. SwiftUI views observe it directly via the Observation macros.
2. **`UsagePoller`** (actor) — owns the timer, calls `AnthropicAPI`, updates the store. Backs off on errors (exponential, capped at 5 min).
3. **`OAuthClient`** (actor) — runs the PKCE sign-in flow via `ASWebAuthenticationSession`, exchanges codes for tokens, refreshes expiring tokens. Sole writer to `TokenStore`.
4. **`TokenStore`** — Keychain CRUD for our own access + refresh tokens. Generic password item under service `dev.claudemeter.oauth`.

`AnthropicAPI` (URLSession wrapper) asks `OAuthClient` for a current access token before each request and triggers a refresh-and-retry on 401.

The menu bar view observes the store and renders. No business logic in views.

Project structure:
```
ClaudeMeter/
  ClaudeMeterApp.swift          # @main, MenuBarExtra setup, URL scheme handler
  Models/
    UsageSnapshot.swift         # struct holding 5h + 7d state
    UsageWindow.swift           # struct: utilization, resetsAt
    OAuthTokens.swift           # access_token, refresh_token, expires_at
  Services/
    UsagePoller.swift
    UsageStore.swift
    OAuthClient.swift           # PKCE flow, ASWebAuthenticationSession, refresh
    TokenStore.swift            # Keychain wrapper for our access+refresh tokens
    AnthropicAPI.swift          # URLSession wrapper, parsing, 401-retry logic
  Views/
    MenuBarLabel.swift          # the % + icon in the menu bar
    UsagePopover.swift          # the click-to-reveal panel (signed-in state)
    SignInView.swift            # "Sign in with Anthropic" — shown when no token
    UsageBar.swift              # reusable progress bar component
  Resources/
    Assets.xcassets             # icon, app icon
    Info.plist                  # LSUIElement=true, CFBundleURLTypes for claude-meter://
docs/
  auth.md                       # OAuth flow, endpoints, client registration status
  api.md                        # endpoint shape, gotchas
utils/
  README.md                     # what these are and when to re-run
  probe-usage-api.sh            # spot-check /api/oauth/usage
  probe-token-cache.sh          # diagnose Anthropic OAuth changes
  extract-claude-desktop-token.py  # transitional helper, removed once we have our own OAuth
README.md
LICENSE                          # MIT
.github/
  workflows/release.yml         # build, sign, notarize, attach to release
```

## Code style

- Swift API Design Guidelines, full stop. Read them before writing names.
- No force unwraps (`!`) outside of test code or genuinely-impossible-nil cases (and document why with a comment).
- No force casts (`as!`).
- `guard` for early returns; nested `if let` ladders are a smell.
- Prefer `let` everywhere; `var` only when mutation is real.
- Actors for shared mutable state, not locks.
- No `print()` in shipped code. Use `os.Logger` with a subsystem of `dev.claudemeter`.
- Errors are typed (`enum APIError: Error`). No string-throwing.
- Public APIs documented with `///`; internal helpers don't need it unless non-obvious.

## Testing

- Unit tests for parsers (the API response shape is the most likely thing to break).
- Snapshot tests for popover rendering at common usage states (0%, 50%, 95%, error, no-token).
- Manual smoke test checklist in `docs/testing.md` covering: cold launch, token missing, network offline, API 401, API 500, both windows null, 5h null only, 7d null only.
- No mocking framework. Hand-roll fakes — they're three lines.

## Distribution

- **GitHub Releases:** signed + notarized `.dmg` for each tag. CI handles this on tag push.
- **Homebrew cask:** `homebrew-claude-meter` tap, auto-updated by the release workflow.
- **No App Store.** Sandboxing breaks Keychain access patterns we need, and review delays slow iteration.
- Code signing requires Apple Developer ID (handled outside the repo via secrets). If signing isn't available, the build still produces an unsigned binary with a clear warning in the README about the right-click-open workaround.

Versioning: SemVer. v0.x while pre-1.0; bump minor for features, patch for fixes. Tag releases as `v0.1.0`.

## What to do when something is unclear

Ask. The author is one person and prefers a five-minute clarifying exchange over an hour of rework.

Specifically, ask before:
- Adding any dependency
- Changing the API contract assumptions
- Touching anything related to Keychain or signing
- Expanding scope beyond what's listed under "v1 scope"

Don't ask before:
- Renaming for clarity
- Refactoring within a file
- Improving error messages
- Adding tests

## Non-goals worth stating explicitly

- This is not a usage-optimization tool. It does not give advice, it does not nag, it does not gamify.
- This is not a billing or cost tracker for API users. It targets Pro/Max subscribers checking their plan limits.
- This is not a productivity dashboard. Resist every urge to add charts, streaks, or "insights."
- This is not a wrapper around Claude. It does not invoke models, store conversations, or interact with content.

The whole product is "battery percentage, but for Claude usage." If a feature wouldn't fit on a battery icon, it doesn't belong here.

