# Brand specification

This doc covers the project's identity — colors, icon, voice, and the rules that govern marketing surfaces (README, GitHub social preview, any future website). The app itself is almost entirely system-styled; brand decisions show up in marketing, not in the running app.

## Concept

> Claude Meter is a battery indicator for your Claude usage. Install it once, look at it when you wonder, otherwise forget it exists.

That sentence is the north star. Every brand decision passes through it. If a choice would make the user *think about* the app rather than just *use* the data, the choice is wrong.

What this means in practice:

- **Invisibility, not minimalism.** Minimalism is an aesthetic; invisibility is a behavior. The app disappears into the user's existing workflow. The product is in service of the task; the task is not in service of the product.
- **No personality.** The app does not have a sense of humor. There are no clever error messages, no easter eggs, no mascot, no voice. The product does not need to entertain you.
- **No marketing language.** Words like "beautifully crafted," "thoughtfully designed," "delightful," "powerful" are banned in all surfaces. The product should not need to tell you it is good.
- **Quiet at rest, loud only when needed.** This applies to the app (monochrome gauge until critical) and the marketing (one screenshot beats a marketing banner).

## Test for any decision

> Would a battery indicator do this?

A battery indicator has no launch screen, no rating prompt, no logo on its menu bar icon, no marketing tagline, no onboarding flow. If the answer is "no, a battery indicator wouldn't do this," neither should Claude Meter.

## Reference points

**Yes, this aesthetic:**
- iStat Menus in its quietest configuration
- The macOS battery indicator itself
- Tot before it added features
- Finicky (you forget it exists, that's the win)

**No, not this aesthetic:**
- Raycast (too much personality, performs its design)
- Arc (the opposite of invisible by design)
- Linear (beautiful but performs beauty)
- Most "indie Mac app" preciousness

## Palette

The full palette is small. Six colors, plus their dark-mode variants where applicable.

| Role | Light | Dark | Where used |
|---|---|---|---|
| **Terracotta** (primary accent) | `#B5563D` | `#C8654D` | Marketing surfaces; warning dot; pacing-mode dead-time arc; app icon background |
| **Cream** (neutral surface) | `#F4E8DD` | `#F4E8DD` | App icon vessel |
| **Deep terracotta** (icon depth) | `#8A3F2C` | `#8A3F2C` | App icon vessel fill |
| **Critical red** | `#D63838` | `#E85555` | Menu-bar gauge color when pace ratio exceeds 110%; popover bar fill when ≤20% capacity remains; popover radial-gauge red zone (110–150%); pacing-status burnout line |
| **Usage green** | `#34C759` | `#30D158` | Popover bar fill when >40% capacity remains; popover radial-gauge under-utilized zone (<85% pace) |
| **Usage yellow** | `#FFCC00` | `#FFD60A` | Popover bar fill when 20–40% capacity remains |
| **Pacing amber** | `#D97706` | `#F59E0B` | Popover radial-gauge on-target zone (85–110% pace) |
| Standard label | system | system | All other text in the app |
| Standard fill | system | system | Bar tracks, default gauge fill |

**The menu bar gauge uses minimal color.** It renders monochrome (auto-tinted to match the system label color) until the tracked window's pace ratio crosses 110%, at which point both the vessel and the pacing arc flip to critical red. The non-tracked window's status surfaces as a small terracotta or red dot above the gauge.

**The popover uses more color** because it has the room: green/yellow/red usage bars (40%/20% remaining cutoffs) and a green/amber/red radial pacing dial (85%/110% pace cutoffs). Terracotta only appears in the running app as the menu-bar warning dot.

**Marketing surfaces use terracotta heavily.** Repo header, social preview card, README accent, future website if any.

## Why terracotta and not Anthropic coral

Adjacent to Anthropic's palette without being parasitic on it. The proximity signals "this is in the Claude ecosystem"; the distinction signals "this is not an Anthropic product." Using Anthropic's actual coral would create both legal and trust issues — a third-party utility should not appear to claim affiliation.

If Anthropic ever rebrands, our color does not suddenly look stale. We're in their neighborhood, not their house.

## App icon

A vessel — cream pill on a terracotta field, with a deep terracotta fill at 50% inside the pill. The fill is static; the icon is not dynamic.

**Specifications:**
- Square canvas with macOS-standard squircle corner radius (~22% of icon size as a starting approximation; refine to Apple's superellipse for the final asset using Apple's icon template)
- Solid terracotta `#B5563D` background, full canvas
- Centered vertical pill, cream `#F4E8DD`
  - ~32% of canvas width
  - ~70% of canvas height
  - Rounded ends (radius = half the pill's width)
- Inside the pill, lower 50% filled with deep terracotta `#8A3F2C`, with a flat horizontal boundary
- No text, no logo, no asterisk, no ornament
- Source size: 1024×1024
- Exported as `.icns` covering all macOS sizes (16, 32, 64, 128, 256, 512, 1024)

**Why 50% fill, not 70%:** 70% reads as a current-state claim ("you're at 70% right now"), which is wrong because the icon is static. 50% reads as a measuring vessel without any specific state implication. Neutral framing.

**At small sizes** (16×16, 32×32) the fill detail may not survive compression. That is acceptable — the icon's identity holds even when reduced to "cream pill on terracotta." The fill is a bonus at large sizes, not load-bearing.

**Never:**
- Use Anthropic's asterisk
- Use any Claude branding
- Add text or numbers to the icon
- Use any color outside the locked palette

## Menu bar glyph

The menu bar gauge is **not the app icon**. It is a programmatically composited SwiftUI view snapshotted into an `NSImage` on every store update (see `docs/ui.md` for full geometry). The gauge body draws in the system label color until the tracked window's pace ratio crosses 110%, at which point it flips to critical red. The non-tracked window's projected severity surfaces as a small dot in the upper-right — terracotta from 110–130% pace, red beyond. No cream, no deep terracotta, no other brand color appears in the menu bar — it is a system UI element first and a brand surface a distant second.

Resist any urge to bring the icon's vessel shape into the menu bar. The icon is the *project's* identity; the gauge is the *app's* function. They are different surfaces with different jobs.

## Typography

**The app uses system fonts only.** SF Pro at SwiftUI defaults, no exceptions, no overrides.

**Marketing surfaces** can use system fonts or a single carefully-chosen alternative. If a website is ever built, lean toward Inter or system fonts rather than display faces. Custom typography on marketing surfaces draws attention to itself, which is the opposite of what we want.

The README on GitHub renders in GitHub's defaults; do not try to override.

## Voice and copy

For the README, GitHub repo description, social preview, future website:

**Yes:**
- Plain factual descriptions of what the app does
- Honest caveats (the API is unofficial, this could break)
- "What it is not" framing to pre-empt scope-creep requests
- Single screenshots that show the actual product

**No:**
- Adjectives describing the app's quality ("beautifully designed," "powerful," "delightful")
- Mission statements or grand framing
- "Your Claude companion" / "Your usage assistant" / any anthropomorphizing
- Emoji in headings or body copy
- Animated GIFs that draw attention rather than informing
- Comparisons to other tools that imply ours is better

The standard for any line of marketing copy: would this exist if the writer had no marketing instinct, only an instinct to inform? If the line is doing emotional or persuasive work, it goes.

## Marketing assets — checklist

When the project ships, these are needed:

- **App icon** — `.icns` bundle, all sizes
- **GitHub social preview card** — 1280×640 image, used by GitHub when the repo URL is shared. Contains: app icon at large size on left, project name in system font, one-line description, terracotta accent. No tagline beyond the one-line description.
- **README hero image** — single screenshot of menu bar + open popover at near-actual size. Light mode by default; optionally a side-by-side light/dark comparison further down the README.
- **Threshold ramp comparison** — small image showing the gauge at 14%, 42%, 73%, 94%. Optional but useful for the README.
- **Homebrew cask icon** — same `.icns` as the app
- **Optional: GIF showing popover open + a percentage tick** — 3-5 seconds, under 2MB. Captures the ambient nature of the app better than static images. Place immediately under the H1 in the README if used.

**Never use:**
- Stock photography
- Illustrations of people using the app
- A "logo lockup" with the project name and icon together (the icon is the logo; no wordmark needed)
- A custom typeface for the project name

## What "doing this well" looks like

A user lands on the GitHub repo from a tweet. Within 3 seconds they see: the app icon, a one-line description ("battery indicator for Claude usage"), and a screenshot of the menu bar with the popover open. They understand the product. Within 30 seconds they have decided whether to install it or close the tab. The README does not try to argue them into installing — it tells them what the thing is and lets them decide.

If the README is doing more than that, it is doing too much.
