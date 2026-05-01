# UI specification

This is the visual contract. Every pixel-level decision in the app is here. If you find yourself making a visual decision not covered by this doc, ask before implementing — odds are the decision was made deliberately and just isn't written down yet.

## Menu bar

The menu bar surface is a single composited image (`MenuBarLabel` snapshots a SwiftUI view tree into an `NSImage` via `ImageRenderer`). `MenuBarExtra` collapses any multi-element label down to its first child image, so we composite everything we want shown into one view and snapshot it.

What appears in the menu bar is controlled by three popover toggles, persisted in `AppSettings`:

- **Show Usage** — renders `VesselGauge`, the vertical pill.
- **Show Pacing** — renders `PacingArc`, the speedometer-style upward arc.
- **Show %** — renders a small numeric label adjacent to each visible gauge.

At least one of Show Usage / Show Pacing must remain on; both `AppSettings` and the popover's checkbox bindings defend that invariant.

The menu bar always reflects the **tracked window** (`AppSettings.trackedWindow`, default `.fiveHour`). The non-tracked window's severity is encoded as the warning dot. There is no separate "display mode" — the gauges aren't mutually exclusive.

### VesselGauge

Vertical rounded pill displaying *remaining* capacity (battery-style). Fills bottom-up with `100 − utilization`, so a fresh window is full and the pill drains as the user burns through tokens. Inversion happens in the display layer — the `utilization` input remains in API space (0 = fresh, 100 = locked out).

**Geometry:**
- Outer pill: 9px wide × 16px tall, 1.25px stroke, 3px corner radius
- Inner fill: 6px wide rounded rect, 1.5px corner radius, 2px inset on each side, bottom-anchored
- A floor of 1.75px on the rendered fill height keeps near-empty pills visually distinct from fully-empty ones
- Optional `ClaudeMark` splatter overlaid at the bottom-right corner, ~8px, poking out 1.5px past the pill. Suppressed when the menu bar shows vessel + pacing side by side, since the pacing arc carries its own splatter on the right.

### PacingArc

Speedometer-style arc opening upward. Conceptually distinct from the popover's radial gauges: the menu-bar arc puts the on-pace target at three-quarters along the visible sweep, with the final quarter as over-pace runway. Anything past 100% pace just keeps filling the runway until it clamps at the splatter clearance.

**Geometry:**
- Drawn into a 22×14 canvas
- Arc radius 8px, centered horizontally
- Background track: 1px stroke at 25% opacity
- Foreground fill: 2px stroke, rounded line cap
- The visible sweep stops 12° short of the right endpoint to leave room for the brand splatter
- Target dot at the 75% landing: 0.8px radius normally, 1.2px when the projection's `outcome == .onPace`
- `ClaudeMark` overlaid at the bottom-right corner, ~8px

The arc fill is single-color throughout — over-pace doesn't change the color, only extends the fill length until it hits the clearance clamp. The color decision happens at the gauge level (see "Color trigger" below).

### Warning dot

When the **non-tracked** window has a problem, a small dot appears in the upper-right of the gauge area. Drawn as a 5px diameter circle in `MenuBarLabel`, with a separate `WarningDot` view that mirrors the same severity logic for use elsewhere.

| Severity | Trigger | Color |
|---|---|---|
| Absent | non-tracked pace ratio ≤ 1.10, or no projection available | — |
| Terracotta | `1.10 < paceRatio ≤ 1.30` | `#B5563D` (light) / `#C8654D` (dark) |
| Red | `paceRatio > 1.30` | `#D63838` (light) / `#E85555` (dark) |

The dot is asymmetric — it never indicates under-pace. The menu bar surfaces actionable concerns only.

### Percent labels

When **Show %** is on, a 10px monospaced-digit label sits to the right of each visible gauge:

- Next to the vessel: **remaining** capacity, e.g. `58%`. Counts down with the pill.
- Next to the pacing arc: **pace ratio** as a percent, e.g. `94%`, `118%`. No "on pace"/"+10h" conditional text — always a raw percent so the label width stays predictable.

Both labels render in the appearance-aware mono color (white in dark mode, black in light mode) so they survive the non-template render path the gauge uses.

### Color trigger

The gauge body (both vessel and pacing arc) is **monochrome** until the tracked window's projected pace ratio exceeds **110%**, at which point both flip to `criticalRed`. Utilization alone never drives the color — a fresh window burning fast goes red even at low utilization, and a slow-burning window stays monochrome even at 90% utilization.

The composited image is rendered with `isTemplate = false` and explicit appearance-aware colors (`monoColor` reads `.colorScheme`). Template rendering would replace those colors with the menu-bar tint and cause text labels to flip from white to black when the gauge flipped red.

### Error state

When `store.lastError` is non-nil and there's no cached snapshot to fall back on, the menu bar shows a single 12pt `exclamationmark.triangle.fill` system glyph in the mono color. No gauge, no dot, no label.

## Popover

Opens on click of the menu bar item. ~280px wide, system-styled.

**Layout** (vertical stack, top to bottom):

```
┌─────────────────────────────────────┐
│  [DEBUG MODE]  ← only in debug      │
│                                     │
│  SESSION                            │
│  ████████████░░░░░░░░  58% left     │
│  resets in 3 hours, 14 minutes      │
│                                     │
│  WEEKLY                             │
│  ███████████░░░░░░░░░  72% left     │
│  resets in 4 days, 6 hours          │
│                                     │
│  ───────────────────────            │
│                                     │
│  PACING                             │
│  ┌───────┐    ┌───────┐             │
│  │ dial  │    │ dial  │             │
│  │ 62%   │    │ 94%   │             │
│  └───────┘    └───────┘             │
│   Session     Weekly                │
│  On target. Maintain token spend.   │
│                                     │
│  ───────────────────────            │
│                                     │
│  Menubar  ◉ Session  ○ Weekly       │
│  ☑ Show Usage in Menubar            │
│  ☐ Show Pacing in Menubar           │
│  ☑ Show % in Menubar                │
│                                     │
│  ───────────────────────            │
│                                     │
│  Updated 12s ago         [⚙]  [⟳]   │
│                                     │
│                  Quit Claude Meter  │
└─────────────────────────────────────┘
```

### Usage bars

`UsageBar` displays *remaining* capacity, battery-style. The bar shrinks as the user burns through the window.

- ~6px tall, 3px corner radius
- Track: secondary fill at 15% opacity
- Fill: four states from `Threshold(utilization:)`:

| State | Trigger | Color |
|---|---|---|
| Neutral | window data missing | `Color.clear` |
| Normal | >40% remaining (`utilization < 60`) | `Color.usageGreen` |
| Warning | 20–40% remaining (`60 ≤ utilization < 80`) | `Color.usageYellow` |
| Critical | ≤20% remaining (`utilization ≥ 80`) | `Color.criticalRed` |

Heading: uppercased label (`SESSION` / `WEEKLY`), caption2 weight semibold, secondary color, 1pt tracking. Right-aligned subhead shows `X% left`. Below the bar, a caption shows `resets in <DurationFormatter.verbose>` or `resets now` / `reset time unavailable` / `no data` for the degraded paths.

### Pacing dials

A `RadialPacingGauge` for each window, rendered side-by-side beneath a small `PACING` section header.

- 110×76 canvas (per dial)
- Stroke width 10
- Three colored zones along an upper semicircle (180°→360°):
  - Green (`usageGreen`) — under-utilized: 0–85% pace
  - Amber (`pacingAmber`) — on-target: 85–110% pace
  - Red (`criticalRed`) — burnout: 110–150% pace
- Needle pivots from a point 14px above the canvas bottom; color matches the zone it points into; runs off the right edge by up to 15° when pace ratio exceeds 150%
- Pivot ring: 4px radius, 1.4px stroke
- Below the dial: `Int(paceRatio × 100)%` in 22pt bold monospaced digits, color-matched to the zone (or secondary when projection is `nil`).

A single status sentence sits beneath both dials (driven by `pacingStatus` in `UsagePopover`):

| Zones | Sentence | Color |
|---|---|---|
| Weekly over | `Weekly limits hitting in X.\nWill lose Y of subscription access` | `criticalRed` |
| Session over (and Weekly not) | `Session limits hitting in X.\nWill lose Y of subscription access` | `criticalRed` |
| Either on-target | `On target. Maintain token spend.` | `usageGreen` |
| Both under | `Under utilized. Use more tokens.` | secondary |
| Otherwise | (no sentence) | — |

`X` is `secondsUntilReset − deadTime`, `Y` is dead time itself, both formatted via `DurationFormatter.coarse`. The status updates live via a 60s `TimelineView` so "limits hitting in X" stays current.

### Menu-bar visibility controls

A small section with the radio + three checkboxes shown in the layout above:

- **Menubar** radio — `Session` / `Weekly`, binds to `settings.trackedWindow`
- **Show Usage in Menubar** — toggle; disabled when it's the only checked option (so the user can't end up with nothing in the menu bar)
- **Show Pacing in Menubar** — toggle; same disable rule
- **Show % in Menubar** — toggle; independent

### Footer

A 1Hz `TimelineView` runs the "Updated X ago" line via `DurationFormatter.compact` (or "Updated just now" / "Updated 23s ago" for the under-minute range, "Loading…" / "Never refreshed" when no successful poll has happened).

When the most recent poll failed but a cached snapshot is still showing, an `API currently unavailable` line appears in red beneath the timestamp. When `signInMessage` is non-nil (sign-in / scope / token-format errors), it shows in red below that.

To the right: a `gearshape` settings link and an `arrow.clockwise` refresh button, both borderless. A `Quit Claude Meter` button on its own row at the bottom (⌘Q).

### Debug badge

When `settings.debug.enabled` is true, a yellow `DEBUG MODE` capsule appears at the top of the popover. The badge is the only visual difference between debug and production rendering — the gauges and dials read synthesized values from `DebugSettings.syntheticSnapshot` / `syntheticProjection` instead of `UsageStore`.

### Error states in the popover

The bars and dials still render the cached snapshot (or the synthesized debug values). The footer is where errors surface:

- `API currently unavailable` (red) — most recent poll failed with an API error and a cached snapshot is still on screen
- `Open Claude desktop and sign in to enable Claude Meter.` — no token, no config, etc.
- `Open Claude desktop to refresh your sign-in.` — token expired (401 or `noUsableToken`)
- `Allow Keychain access in System Settings → Privacy & Security.` — keychain access denied
- `Claude desktop changed its storage format. Update Claude Meter.` — unsupported `v10` blob, base64 decode fail, or plaintext-not-JSON
- `Couldn't decrypt Claude desktop's sign-in. Update Claude Meter.` — AES decrypt failed
- `Authorization scope changed — Claude Meter may need an update.` — HTTP 403
- `Claude Meter needs an update.` — 404 or response decode failure

Generic API failures (rate limit, network, 5xx) only show the `API currently unavailable` banner — there's nothing for the user to do but wait.

## Settings panel

Opened via the gear icon in the popover footer, or ⌘,. Backed by the `Settings` scene in `ClaudeMeterApp`. Form-styled with `.formStyle(.grouped)`.

Public surface:

- **Startup** section
  - **Launch at login** toggle, switch style — wired to `LaunchAtLogin.setEnabled`

That's it for the public surface. The window is sized at 480×560 normally, and grows to 580×880 once the debug section is revealed.

### Hidden debug section (⌥⌘⇧D)

A second section appears when the user hits ⌥⌘⇧D (or when `debug.enabled` is true on launch). The section overrides every value the menu bar and popover read so a developer can preview every visual state without burning real quota. Persisted to `UserDefaults` so the override survives relaunches.

Per-window controls (5-hour and 7-day):
- Utilization slider (0–100)
- Resets-in number field (minutes)
- Projection picker — `No projection` / `On pace` / `Over pace` / `Under pace`
- Conditional fields: dead-time hours when over-pace; unused-fraction slider when under-pace

Status overrides:
- `Simulate API unavailable` toggle — forces the "API currently unavailable" footer line
- `Last updated X minutes ago` field — drives the "Updated X ago" footer styling

The pace ratio always tracks the synthesized snapshot, so the gauges respond to the Utilization / Resets-in sliders. The projection picker chooses the *outcome* that rides along — it doesn't override the ratio itself.

## Typography

The app uses **system fonts only**. No custom typography anywhere — not in the popover, not in settings, not in the menu bar gauge labels. SF Pro at SwiftUI defaults.

The README and any marketing material can use whatever, but those are out of scope for the app itself.

## Animation

**None.**

The popover opens and closes via the system's default `MenuBarExtra` behavior — no custom transitions. The menu bar gauge updates between poll cycles by re-rendering through `ImageRenderer`. No tweening, no easing, no fade. The only live updates are the popover's `TimelineView`-driven timestamps (footer 1Hz, status sentence 60s).

## What the app must never do

- Display marketing copy, taglines, or descriptions of itself
- Show notifications (deferred to v1.1 and opt-in)
- Pop a "rate this app" prompt
- Show a welcome screen, onboarding, or first-launch tutorial
- Display Claude branding, the Anthropic asterisk, or any third-party trademark beyond the abstract `ClaudeMark` splatter (which is a generic 8-rayed glyph, not Anthropic's actual asterisk)
- Render the gauge in any color other than what's specified above
- Use emoji in any UI surface
- Make sound

If a feature request would require any of these, it's outside the project's scope. See `docs/backlog.md` for what's deferred and the "probably never" list.
