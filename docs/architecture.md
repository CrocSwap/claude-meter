# Architecture

The app is small enough that the architecture is also small. One actor, a couple of stores, a handful of views, no clever patterns. Resist any urge to introduce protocols, dependency injection containers, or coordinators — there are not enough moving parts to justify them.

## Module layout

```
ClaudeMeter/
  ClaudeMeterApp.swift          # @main, MenuBarExtra + Settings scene wiring
  Models/
    UsageSnapshot.swift         # struct: holds 5h + 7d state
    UsageWindow.swift           # struct: utilization, resetsAt
    Projection.swift            # struct: paceRatio + outcome (onPace/over/under)
    DisplayMode.swift           # enum TrackedWindow { fiveHour, sevenDay }
    Threshold.swift             # 4-state bar fill classifier (neutral/normal/warning/critical)
    AppError.swift              # wraps TokenReader.ReadError + AnthropicAPI.APIError
  Services/
    UsageStore.swift            # @MainActor @Observable: source of truth
    UsagePoller.swift           # actor: 60s timer + API calls + backoff
    AnthropicAPI.swift          # async fns: parse response, classify errors
    TokenReader.swift           # decrypts Claude desktop's locally-cached OAuth token
    Projector.swift             # pure fn: linear extrapolation → Projection
    LaunchAtLogin.swift         # SMAppService wrapper used by the settings panel
  Views/
    MenuBarLabel.swift          # composites VesselGauge + PacingArc + warning dot, snapshotted into NSImage
    UsagePopover.swift          # main popover container
    UsageBar.swift              # remaining-capacity bar per window
    Colors.swift                # appearance-aware brand colors
    DurationFormatter.swift     # compact / verbose / coarse human-readable durations
    Gauges/
      VesselGauge.swift         # vertical pill, drains as utilization grows
      PacingArc.swift           # menu-bar speedometer arc (left endpoint → splatter clearance)
      RadialPacingGauge.swift   # popover dial, 0–150% with green/amber/red zones
      NumericLabel.swift        # plain percentage text (currently unused)
      WarningDot.swift          # non-tracked-window severity dot
      ClaudeMark.swift          # 8-rayed splatter mark used as a brand watermark
  Settings/
    AppSettings.swift           # @Observable wrapper for user prefs
    SettingsView.swift          # macOS Settings scene (launch-at-login + hidden debug)
    DebugSettings.swift         # ⌥⌘⇧D-gated value override for previewing visual states
  Resources/
    Assets.xcassets             # AppIcon (rendered from assets/icon.svg) + AccentColor
    Info.plist
assets/icon.svg                  # source of truth for the app icon
tools/render-icon.swift          # rasterizes icon.svg into the AppIcon set
utils/                           # helper scripts (token probe, usage-API probe)
docs/                            # all the specs that aren't code
```

CI for signed releases is not yet wired up; when it lands it'll live at `.github/workflows/release.yml`.

## Actor boundaries

Two stateful actors, plus pure helpers and a couple of `@Observable` settings classes:

**`UsageStore`** is the source of truth. `@MainActor @Observable` so SwiftUI views observe it directly via the Observation macros. Holds the current `UsageSnapshot`, timestamp of last successful fetch, and current error state. **Views read from this and only from this.** Never let a view call the API directly.

**`UsagePoller`** owns the timer. On each tick: read the OAuth token via `TokenReader`, call `AnthropicAPI.fetchUsage()`, on success update the store, on failure record the error in the store and apply exponential backoff (capped at 5 minutes). On HTTP 429 with a `Retry-After` header, the next sleep honors the server's value as a one-shot override. The poller does not interpret data; it just moves bytes from the network to the store.

**Pure helpers** (not actors) for the rest:
- `AnthropicAPI` — given a token, return a parsed `UsageSnapshot` or throw a typed `APIError`
- `TokenReader` — decrypts Claude desktop's locally-cached OAuth token; see `docs/auth.md` for the full protocol
- `Projector` — given a `UsageWindow` and the window's total duration, return a `Projection` (or `nil` when inputs can't yield a meaningful pace ratio)

`AppSettings` and `LaunchAtLogin` are small `@Observable` `@MainActor` classes that own user preferences — `AppSettings` for menu-bar visibility/percent toggles + tracked window, `LaunchAtLogin` for the `SMAppService.mainApp` toggle. `DebugSettings` (a sibling of `AppSettings`) holds the hidden ⌥⌘⇧D override values used to preview visual states without burning real quota.

The pure-helper rule matters because these are the parts that need unit tests. Stateful classes are for managing state; tests don't need state.

`AppError` wraps the two error families the poller can produce (`TokenReader.ReadError` and `AnthropicAPI.APIError`) so `UsageStore` and views render them uniformly.

## Concurrency rules

- All network and Keychain calls are `async`
- Views never `await` directly — they read from observed properties on the store
- The poller is the only thing that triggers network activity
- No `Task { ... }` started from a view body; if a view needs to react to user input, it sends an action to the store/poller

The single mental model: **data flows in one direction.** Poller fetches → Store holds → Views render. Settings flow back the other way (view → store → poller, e.g. "user changed polling interval"), but data never does.

## Dependency rules

- Models depend on nothing (just Foundation)
- Services depend on Models
- Views depend on Models and observe Stores
- `AppSettings` is the only thing allowed to use `@AppStorage` / `UserDefaults`

If a file needs to import something it shouldn't (e.g. a View importing `URLSession`), that's a sign the architecture is being violated. Push the network call back into a service.

## Testing strategy

- **Unit tests:** `AnthropicAPI` parsers (the most likely thing to break when the API changes), `TokenReader` pure helpers (`decrypt`, `selectToken`), `Projector` math (pace ratio, on-pace band, dead-time, unused-fraction).
- **Snapshot tests:** view `#Preview` blocks cover the common states (low/medium/high utilization, no data, error). When the app gets a more formal snapshot pipeline, expand from there.
- **Manual smoke tests:** cold launch, token missing, network offline, 401, 500, both windows null, individual windows null. The hidden ⌥⌘⇧D debug panel in the settings sheet lets you preview every visual state without burning real quota.

No mocking framework. Hand-roll fakes — they're three lines for each protocol you'd otherwise mock.

## Where each doc applies

This doc covers structure. The other docs cover specifications:
- `docs/api.md` — what `AnthropicAPI` does and the empirical shape of `/api/oauth/usage`
- `docs/auth.md` — what `TokenReader` does and the Claude-desktop cache protocol
- `docs/metrics.md` — what `Projector` calculates
- `docs/ui.md` — what the views render
- `docs/brand.md` — colors, icon, voice (mostly relevant to README/marketing, not the app)
- `docs/backlog.md` — features deliberately deferred

Touching code in `Services/`? Read `docs/api.md`, `docs/auth.md`, and `docs/metrics.md`.
Touching code in `Views/`? Read `docs/ui.md`.
Writing the README or building marketing assets? Read `docs/brand.md`.
