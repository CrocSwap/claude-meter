# Metrics

Four primitive numbers from the API plus a derived projection. This doc is the source of truth for how each is calculated and when it's surfaced.

## The four primitives

Read directly from the API response (see `docs/api.md`):

- **5h utilization** (%, 0-100) — current 5-hour window
- **7d utilization** (%, 0-100) — current 7-day window
- **5h reset time** — when the 5-hour window rolls over
- **7d reset time** — when the 7-day window rolls over

These are stored in `UsageSnapshot` and updated on every successful poll.

## Reset countdown formatting

For both windows, the time-until-reset is shown to the user. Format depends on magnitude:

- **Under 1 hour:** `47m`
- **1 to 48 hours:** `HH:mm` (e.g. `3:14`, `26:08`)
- **Over 48 hours:** `Xd` rounded to one decimal (e.g. `3.2d`)

The threshold for switching units is firm: do not show `0:47` when `47m` would do, and do not show `72h` when `3d` would do. Different units for different magnitudes is more readable than one consistent unit at all times.

## The projection — pace ratio and dead time

A single derived metric per window: **pace ratio**. Calculated as:

```
expected_utilization = elapsed_in_window / total_window_length
pace_ratio = current_utilization / expected_utilization
```

Below 1.0 means under pace (using subscription slower than would consume full allowance by reset). Above 1.0 means over pace (will exceed allowance before reset).

### Below 100% — express as pace ratio

Display the ratio as a percentage of expected. "75% pace" means burning at three-quarters the rate that would consume your full allowance. The user reads this as "I have headroom."

### Exactly 100% — express as "on pace"

A small band around 1.0 (say, 0.95–1.05) collapses to "on pace" rather than showing a flickering exact ratio. Reading "98% pace" then "102% pace" then "99% pace" as the EWMA wobbles around the boundary is more anxiety than information.

### Above 100% — express as projected dead time

Above the on-pace band, switch units entirely. The user no longer cares about the ratio; they care about consequences. Compute:

```
hours_until_full = (1.0 - current_utilization) / current_burn_rate_per_hour
hours_until_reset = (reset_time - now) in hours
projected_dead_time = max(0, hours_until_reset - hours_until_full)
```

Format dead time using the same convention as the reset countdown: minutes/hours/days based on magnitude.

## Burn rate calculation — EWMA

Burn rate is noisy. A user who just finished a heavy task spikes; an idle user looks like a non-user. Smooth aggressively before projecting.

Use an **exponentially-weighted moving average** of `delta_utilization / delta_time` over the sample buffer. Half-life of roughly 6 hours for the 7d window, 1 hour for the 5h window. The exact constants are tunable; the principle is "smooth enough that single tasks don't dominate, responsive enough that today's pattern shows up."

Sample buffer rules:
- Keep `(timestamp, utilization)` pairs from the last 24 hours per window
- Drop samples older than the buffer window
- Drop pre-reset samples when a reset occurs (the utilization just dropped to zero — including pre-reset samples in the EWMA would falsely suggest negative burn rate)
- Buffer is in-memory only; on app launch, warm up from empty

## Confidence gating

Projections are not always trustworthy. Suppress or de-emphasize when confidence is low.

The gate uses **current utilization** as the confidence proxy. Reasoning: at 1% utilization, any extrapolation is noise; at 10%, you have meaningful data even if the burn pattern is irregular; at 25%, the projection is reliable enough to display normally.

| Utilization | Behavior |
|---|---|
| < 10% | Hide projection entirely. Pacing-mode gauge shows empty arc. Popover shows percentages and reset countdowns only. |
| 10% – 25% | Show projection but with reduced visual weight (lighter color, italicized text). Annotations include a leading `~` to imply approximation. |
| > 25% | Show projection at full weight. |

Additionally, suppress the projection annotation in the popover when:
- The projected end-state is within ±5% of 100% (avoid flicker around the on-pace boundary)
- The sample buffer has fewer than ~5 entries (warmup period)
- The current burn rate is zero or negative (a reset just occurred or the user is idle — extrapolating predicts the user will never hit cap, which is technically true but useless)

## Asymmetric framing in the popover

The popover annotation is asymmetric — different framing for over-pace vs under-pace, because the user cares about different things in each regime.

### Over pace — frame as dead time

```
locked out ~6h before reset
locked out ~2 days
```

This is the actionable framing. The user knows they will hit the wall and how much it will cost them. Format the dead time using the same minutes/hours/days convention.

### Under pace — frame as unused capacity

```
~30% unused at reset
~12h of capacity unused
```

Two valid framings; either is acceptable. The percentage is more concrete for the weekly window (Max users feel "30% of weekly" intuitively); time-based is more concrete when the user is trying to plan additional work.

The under-pace annotation should:
- Only appear after a meaningful portion of the cycle has elapsed (e.g. past ~30% of the window)
- Render in a quieter visual weight than the over-pace annotation
- Be suppressible by user setting (some users only want the warning side)

The over-pace annotation should always be on (it is a load-bearing feature).

### On pace — show nothing

The absence of an annotation is the message. Do not write "you are on pace" — that uses real estate to convey no actionable information. The bare percentage and reset countdown are sufficient.

## Pacing applies to both windows; default surfaces 7d

The same calculation runs for both windows. The popover annotation defaults to showing on the **7d bar** because dead time has more meaningful consequences over longer time horizons (a few hours of 5h lockout is a minor inconvenience; a day of weekly lockout is a real cost).

The 5h projection is available but not surfaced by default. Show it when:
- 5h becomes the binding constraint (its projection is meaningfully worse than 7d's)
- User has explicitly chosen to track 5h in the menu bar (the menu bar's selected window gets the popover annotation)

## Menu bar visibility logic — the dot

The menu bar gauge represents one window (default 5h). The other window's status is encoded as a **small terracotta dot** in the upper-right of the gauge area when the *other* window has a problem.

Dot rules:
- **Absent** — other window is fine, or has insufficient signal (under 10% utilization)
- **Terracotta** (`#B5563D`) — other window has 6h-1d projected dead time
- **Red** (`#D63838`) — other window has over 1d projected dead time

Asymmetric: the dot does **not** appear for under-pace situations. Underutilization is information, not action; the menu bar surfaces actionable concerns only.

## Mode switching changes meaning

The user can configure the menu bar to display:
1. **Vessel mode** (default) — vertical pill gauge encoding utilization 0-100%
2. **Pacing mode** — speedometer arc encoding pace ratio + dead time
3. **Numeric mode** — plain percentage text

The selected window (5h or 7d) is independent of the mode. The dot logic applies in all three modes — it always indicates the *other* window having a problem, regardless of how the primary window is being displayed.
