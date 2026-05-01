# Architecture

The app is small enough that the architecture is also small. Three actors, a few views, no clever patterns. Resist any urge to introduce protocols, dependency injection containers, or coordinators — there are not enough moving parts to justify them.

## Status

The actor structure (`UsageStore`, `UsagePoller`), `AnthropicAPI`, `TokenReader`, and `LaunchAtLogin` are implemented. `Projector`, `AppSettings`, `DisplayMode`, and the gauge subfolder are pending v1 work — described here as the target shape so they land in the right places.

## Module layout

```
ClaudeMeter/
  ClaudeMeterApp.swift          # @main, MenuBarExtra setup, launch-at-login
  Models/
    UsageSnapshot.swift         # struct: holds 5h + 7d state and timestamp
    UsageWindow.swift           # struct: utilization, resetsAt
    Projection.swift            # struct: signed dead-time/unused-capacity (v1, pending)
    DisplayMode.swift           # enum: vessel, pacing, numeric (v1, pending)
    AppError.swift              # wraps TokenReader.ReadError + AnthropicAPI.APIError
  Services/
    UsageStore.swift            # @MainActor @Observable: source of truth + sample buffer
    UsagePoller.swift           # actor: timer + API calls + backoff
    AnthropicAPI.swift          # async fns: parse response, classify errors
    TokenReader.swift           # decrypts Claude desktop's locally-cached OAuth token
    Projector.swift             # pure fns: EWMA smoothing, projection math (v1, pending)
    LaunchAtLogin.swift         # SMAppService wrapper for the popover toggle
  Views/
    MenuBarLabel.swift          # the gauge, observes store
    Gauges/                     # v1, pending
      VesselGauge.swift         # vertical pill, default mode
      PacingArc.swift           # speedometer arc, opt-in mode
      NumericLabel.swift        # plain text, opt-in mode
    Popover/
      UsagePopover.swift        # main popover container
      UsageBar.swift            # one row per window (5h, 7d), with progress bar
      ProjectionAnnotation.swift # the dead-time/unused-capacity line (v1, pending)
  Settings/
    AppSettings.swift           # @AppStorage wrapper for user prefs (v1, pending)
docs/                            # all the specs that aren't code
.github/workflows/release.yml    # CI for signed releases
```

## Actor boundaries

Three actors, kept small and single-purpose:

**`UsageStore`** is the source of truth. `@MainActor @Observable` so SwiftUI views observe it directly via the Observation macros. Holds the current `UsageSnapshot`, timestamp of last successful fetch, current error state, and the sample buffer used for projections. **Views read from this and only from this.** Never let a view call the API directly.

**`UsagePoller`** owns the timer. On each tick: read the OAuth token via `TokenReader`, call `AnthropicAPI.fetchUsage()`, on success update the store, on failure record the error in the store and apply exponential backoff (capped at 5 minutes). The poller does not interpret data; it just moves bytes from the network to the store.

**Pure functions** (not actors) for the rest:
- `AnthropicAPI` — given a token, return a parsed `UsageSnapshot` or throw a typed `APIError`
- `TokenReader` — decrypts Claude desktop's locally-cached OAuth token; see `docs/auth.md` for the full protocol
- `Projector` — given a sample buffer and current snapshot, return a `Projection`

The pure-function rule matters because these are the parts that need unit tests. Actors are for managing state; tests don't need state.

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

- **Unit tests:** `AnthropicAPI` parsers (the most likely thing to break when the API changes), `TokenReader` pure helpers (decrypt, selectToken), `Projector` math (signed projections, EWMA, confidence gating)
- **Snapshot tests:** the gauge and popover views at common states (0%, 50%, 95%, error, no-token, all three display modes)
- **Manual smoke tests:** see `docs/testing.md` (to be written when the app exists). Cold launch, token missing, network offline, 401, 500, both windows null, individual windows null

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
