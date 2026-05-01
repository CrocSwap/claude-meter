# Post-v1 backlog

These are deferred from v1 to keep the initial release tight. Each entry is structured so it can be lifted into a GitHub issue with minimal editing. Order is rough priority — top items deliver more value per unit of work.

The bar for promoting any of these into v1.x is: **does this make the gauge more useful, without expanding what the app *is*?** If it would turn Claude Meter into a productivity tool, an analytics dashboard, or a coach, it doesn't belong here.

---

## Closed in v1

Items that originally lived here and shipped as part of the initial release:

- **Predictive reset / pacing.** Originally v1.1; promoted into v1. Single-snapshot linear extrapolation of the current burn rate to compute pace ratio, projected dead time, and unused capacity. See `docs/metrics.md` for the spec and `Services/Projector.swift` for the implementation. (EWMA smoothing and a sample buffer were considered and dropped in favor of the simpler always-fresh-from-snapshot approach.)
- **Granular menu-bar visibility.** Three independent toggles in the popover — Show Usage (vessel gauge), Show Pacing (speedometer arc), Show % (percent label next to each visible gauge). At least one of usage/pacing must remain on; the toggles defend that invariant. Replaces the original "vessel / pacing / numeric" mode picker.
- **Two-window popover dial.** A `RadialPacingGauge` for each window (Session and Weekly) plus a single shared status sentence — under-utilized / on-target / burnout — driven off both pace ratios. Replaces the per-bar projection annotation that originally lived here.
- **Pace-ratio-driven color.** The menu-bar gauge body flips to critical red when the tracked window's pace ratio exceeds 110% (not when utilization crosses 85%). The non-tracked window's severity shows as a small dot — terracotta from 110–130% pace, red beyond.
- **Settings panel.** Standard `Settings` scene (⌘,) opened from the popover gear. Public surface is just Launch-at-login. A hidden ⌥⌘⇧D-gated debug section overrides every value the menu bar and popover read so we can preview visual states without burning real quota.
- **Launch at login.** `LaunchAtLogin.swift` wraps `SMAppService.mainApp`; toggle lives in the settings panel.
- **Brand identity icon.** Procedurally rendered from `assets/icon.svg` via `tools/render-icon.swift` into the macOS AppIcon set.

---

## v1.1 — threshold notifications

**Problem.** Ambient awareness only works if you're actually looking at the menu bar. A user who's heads-down in Cowork won't notice they crossed 90% until they hit the wall.

**Approach.** Native `UNUserNotificationCenter` notifications at user-configurable thresholds. Defaults: 80% and 95% on whichever window is binding. One notification per threshold per window per reset cycle (no spam).

**Settings.** Add a "Notifications" section to the popover with toggles for each threshold and a master off switch. Default: master switch off — user opts in. We do not push notifications on someone who didn't ask for them.

**Edge cases.**
- User crosses 80% → 95% in a single poll cycle: fire both, in order
- Window resets and user re-crosses threshold: fire again, that's correct behavior
- App launched while already past threshold: do not retroactively notify (prevents notification storm on first install)

**Out of scope.** Custom notification messages, sounds beyond system default, integration with Focus modes.

---

## v1.2 — sparkline / mini history

**Problem.** A static percentage doesn't show *trajectory*. A sparkline of the last 24 hours immediately tells you whether usage is climbing fast, plateauing, or already declining toward reset.

**Approach.** Reuse the rolling buffer from v1.1. Render a tiny SVG sparkline (~120×24px) inside the popover beneath each window. No axes, no labels, no interactivity — pure shape recognition. The current point is a small filled dot.

**Visual.** Single line at `--color-text-secondary` opacity, current dot at the threshold color. Resets show as a vertical drop. Buffer covers last 24h for the 5-hour window, last 7 days for the weekly window.

**Out of scope.** Zoom, hover tooltips, time axis, comparing to previous periods. This is a glance-and-go indicator, not a chart.

---

## v1.3 — auto-update

**Problem.** Users have to manually download new releases when the API endpoint inevitably shifts.

**Approach.** [Sparkle 2](https://sparkle-project.org) is the canonical macOS auto-update framework. Adds one dependency, but it's the right call given that this app's value depends on the API integration staying current. Configure for delta updates to keep download size small. Updates check on launch and every 24 hours.

**Caveats.** Auto-update requires signed builds, which means the release workflow needs full signing/notarization. If signing isn't set up, ship without auto-update and document the manual upgrade path.

**Out of scope.** Auto-update for unsigned builds (impossible to do safely), beta channels, in-app changelog viewer.

---

## v1.4 — per-surface attribution (only if API exposes it)

**Problem.** Heavy Cowork users want to know how much of their burn came from Cowork vs Code vs Chat. The current API doesn't expose this — usage is account-aggregate.

**Approach.** *Wait and see.* If Anthropic adds per-surface fields to the OAuth usage endpoint, surface them in the popover as a small breakdown beneath the totals. Until then, no client-side hack — there's no reliable way to attribute without instrumentation we don't have.

**Why this is in the backlog at all.** To prevent it from being filed as a bug. Users will ask for it; the answer is "the API doesn't tell us, and we're not guessing."

---

## Probably-never list

These have come up but are outside the project's scope. Documented here so they get a fast "no" rather than reopening the discussion every six months.

- **Windows / Linux ports.** Different APIs, different distribution stories, different communities. Fork-friendly; not core-roadmap.
- **iOS companion app.** Battery-style indicators don't translate to a phone where you'd have to open the app to see them. The Settings page on claude.ai already serves this need on mobile.
- **Per-task burn logging / session attribution.** Requires hooks into Claude Code, Cowork, etc. that we don't have and can't reliably build. The polling-delta approach has too much noise (memory updates, scheduled tasks, etc.) to be trustworthy.
- **Quota optimization tips, "you've used X% — try doing Y".** Coach behavior. Not what this app is.
- **Cost estimation for API users.** Different audience, different data source, different product. Fork it if you want it.
- **Web dashboard / cloud sync.** No. This is a local-first utility with zero account system. Adding any cloud component compromises the security and simplicity story.
