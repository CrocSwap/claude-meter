# UI specification

This is the visual contract. Every pixel-level decision in the app is here. If you find yourself making a visual decision not covered by this doc, ask before implementing — odds are the decision was made deliberately and just isn't written down yet.

## Display modes

Three menu bar display modes, user-selectable. Default is vessel mode tracking the 5h window.

1. **Vessel mode** (default) — vertical pill gauge, fills bottom-up with utilization
2. **Pacing mode** — speedometer arc, sweeps up to the 100% apex then continues into a red zone for dead time
3. **Numeric mode** — plain percentage text or pace label, no graphical gauge

The selected window (5h or 7d) is orthogonal to the mode. Default window is 5h.

## Vessel mode (default)

A vertical rounded pill gauge representing utilization 0-100%.

**Geometry:**
- Drawn into the 22×22 status item button area
- Outer pill: ~5px wide × 13px tall, 1px stroke, 2px corner radius, vertically centered
- Inner fill: rounded rect inside the outer pill, bottom-anchored, height proportional to utilization

**Color states:**
- **Below 85% utilization** — render as a **template image** (pure black on transparent), set `image.isTemplate = true`. macOS auto-tints based on light/dark mode and any system tinting.
- **85% and above** — render as a **non-template image** in red `#D63838` (light mode) or `#E85555` (dark mode). Set `image.isTemplate = false`.

The transition at 85% is binary. There is no amber or gradient state. Fill level alone carries the warning in the 60-85% range; color is reserved for "act now."

**Implementation note:** programmatically render via `CGContext` rather than shipping static assets. The fill level changes continuously, and the template/non-template swap is just a flag plus a fill color change. No `@1x/@2x/@3x` raster pipeline needed.

## Pacing mode

A semicircular arc, opening upward, that traces from a left endpoint up to the apex (100% pace) and continues down the right side into a dead-time zone.

**Geometry:**
- Drawn into the 22×14 effective area (slightly shorter vertically than the vessel)
- Arc radius ~8px, centered horizontally at x=11
- Background arc: light gray track, 1px stroke, 25% opacity
- Foreground fill: 2px stroke, rounded line caps
- Center dot at apex: 0.8px radius normally, grows to 1.2px when exactly on pace

**Fill behavior:**
- Below 100% pace — fill arcs from left endpoint toward apex, length proportional to pace ratio
- At ~100% pace — fill reaches apex, center dot becomes prominent
- Above 100% pace — fill continues from apex down the right side, length proportional to projected dead time (capped visually at 3 days; numeric label keeps showing actual magnitude)

**Color states:**
- **Below 100% (under-pace and on-pace)** — template image (auto-tinted)
- **Above 100%, dead time under 1 day** — terracotta `#B5563D` for the dead-time portion only; the 0-100% portion remains template
- **Above 100%, dead time over 1 day** — red `#D63838` (light) / `#E85555` (dark) for the dead-time portion

The 0-100% portion of the arc never changes color. Only the dead-time extension does.

**Numeric label** (always shown adjacent to the arc):
- Below 10% utilization (confidence gate): `—` or hide entirely
- 10-95% pace: `42% pace`
- 95-105% pace: `on pace`
- Above 105% pace, under 1 day dead time: `+10h` (terracotta text)
- Above 105% pace, over 1 day dead time: `+2d` (red text)

## Numeric mode

Plain text only. No graphical element.

**Format:**
- Default (vessel-mode equivalent): `42%` — current utilization for the selected window
- Pacing-mode equivalent: same as the pacing-mode label format above (`42% pace`, `on pace`, `+10h`)

**Color:**
- Default text color (system label color, auto-tinted)
- Above 85% utilization OR over-pace with dead time: red `#D63838` (light) / `#E85555` (dark)

## The 7d ambient warning dot

Across all three modes, when the menu bar is showing one window's data, the *other* window's warning state is communicated by a small dot in the upper-right of the gauge area.

**Geometry:**
- 6px diameter circle
- Positioned at top-right of the gauge bounds, with ~2px offset (slight overflow is acceptable; this is meant to read as a notification badge)

**Visibility rules:**
- **Absent** — other window has confidence under 10%, or projects within on-pace band, or projects under-pace
- **Terracotta** `#B5563D` — other window projects 6h to 1d dead time
- **Red** `#D63838` (light) / `#E85555` (dark) — other window projects over 1d dead time

The dot is asymmetric: it never indicates under-pace situations. The menu bar surfaces actionable concerns only.

When the user has chosen to display 7d in the menu bar, the dot reflects 5h state. The general rule: dot indicates the *non-displayed* window's warning.

## Popover

The popover opens on click of the menu bar item. It contains the full state across both windows.

**Layout** (vertical stack, ~280px wide):

```
┌─────────────────────────────────────┐
│  5-hour                             │
│  ████████░░░░░░░░░░  42%            │
│  resets in 3:14                     │
│                                     │
│  Weekly                             │
│  ████░░░░░░░░░░░░░░  28%            │
│  resets in 4d                       │
│  ~12h unused at reset               │  ← projection annotation
│                                     │
│  ─────────────────────────────      │
│                                     │
│  [⟳ Refresh]              [⚙]       │
└─────────────────────────────────────┘
```

**Window rows** show:
1. Label (`5-hour` / `Weekly`)
2. Horizontal progress bar with percentage label inline
3. Reset countdown
4. **Optionally:** projection annotation (dead time over-pace, unused capacity under-pace)

**Bar geometry:**
- Width: ~200px
- Height: ~6px
- Corner radius: 3px
- Background track: system tertiary fill color
- Fill: system label color below 85%, red `#D63838` above 85%

**Projection annotation rules** (see `docs/metrics.md` for the full logic):
- Over pace → `locked out ~Xh before reset` or `locked out ~X days` — bold weight, red text if dead time over 1 day
- Under pace → `~X% unused at reset` or `~Xh of capacity unused` — quieter visual weight, secondary text color, suppressible by user setting
- On pace → no annotation rendered (saves vertical space, signals quiet state)
- Below 10% confidence → no annotation rendered

**Annotation placement:**
- Default: 7d row only
- 5h row gets its annotation if 5h is the binding constraint OR if 5h is the user's selected menu bar window

**Footer controls:**
- Refresh button — manual poll trigger, useful for users who want to verify a tick after a heavy task
- Settings gear — opens settings panel (mode, window, launch-at-login, suppress under-pace annotation)
- Last-updated timestamp — small, secondary text, somewhere in the popover footer area

**Error states in the popover:**
- "Sign in via Claude desktop" + button → opens Claude.app via `NSWorkspace`
- "Token expired — open Claude desktop to refresh" + button → opens Claude.app
- "Service unavailable" / "Anthropic services unavailable" → static message, no button
- "Offline" → static message, retry happens automatically
- "Unexpected response. Check for app update." → static message, surfaces a link to the GitHub releases page

In error states, **the bars still show the last known good value** with a subtle question-mark glyph overlay or muted opacity. Don't render zero or empty bars during transient errors — that's misleading.

## Settings panel

Opened via the gear icon in the popover footer. SwiftUI `Form`-based, system-styled.

**Settings to expose:**
- **Display mode:** Vessel / Pacing / Numeric (radio)
- **Tracked window:** 5-hour / Weekly (radio)
- **Show under-pace annotation:** on/off (toggle, default on)
- **Launch at login:** on/off (toggle, default off)

That's it for v1. Resist adding more.

## Typography

The app uses **system fonts only**. No custom typography anywhere — not in the popover, not in settings, not in the menu bar gauge labels. SF Pro at SwiftUI defaults.

The README and any marketing material can use whatever, but those are out of scope for the app itself.

## Animation

**None.**

The popover opens and closes via the system's default `MenuBarExtra` behavior — no custom transitions. The menu bar gauge updates between poll cycles by replacing the rendered image. No tweening, no easing, no fade.

The single exception: the bar fill in the popover may animate its width change between poll cycles using SwiftUI's default `.animation(.default)` to make the update feel less abrupt. Keep duration short (~150ms). If this looks fussy in practice, remove it.

No animation anywhere else. No bouncy popover, no sparkle on tick over, no celebratory anything.

## What the app must never do

- Display marketing copy, taglines, or descriptions of itself
- Show notifications (deferred to v1.2 and opt-in)
- Pop a "rate this app" prompt
- Show a welcome screen, onboarding, or first-launch tutorial
- Display Claude branding, the Anthropic asterisk, or any third-party trademark
- Render the gauge in any color other than what's specified above
- Use emoji in any UI surface
- Make sound

If a feature request would require any of these, it's outside the project's scope. See `docs/backlog.md` for what's deferred and the "probably never" list.
