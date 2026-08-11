# Handoff: NosoDeck — iPhone landscape deck (Hardware direction)

## Overview
NosoDeck turns an iPhone docked beside a Mac keyboard into a physical-feeling control deck: a fixed grid of tiles that launch and focus Mac apps, run Shortcuts, and open websites over the local network. This handoff covers the **landscape iPhone experience** and the visual system it is built on ("Hardware", internally direction 2c).

Core interaction: tap a tile → the corresponding app comes to the front on the paired Mac. Tiles reflect live Mac state (running / frontmost) so the deck is glanceable without looking at the Mac.

## About the Design Files
The files in this bundle are **design references authored in HTML**. They are prototypes that communicate intended look, layout, and behaviour — **not production code to copy**.

The task is to **recreate these designs in the target codebase's own environment** using its established patterns. The intended production target is **SwiftUI (iOS 17+) with a companion macOS 14+ menu-bar app**; if you are implementing in a different environment, use that environment's idioms rather than porting the HTML. Do not ship the HTML.

## Fidelity
**High fidelity.** Colours, type, spacing, radii, shadow recipes, and state treatments are final and specified exactly below. Layouts should be recreated faithfully. The one deliberate exception: app icons in the prototypes are monochrome Simple Icons glyphs standing in for real macOS app icons — see **Assets**.

Not yet designed (out of scope for this handoff, flagged on the final deck slide): the macOS menu-bar glyph and popovers in this visual language, light mode, and the final token→asset sheet.

---

## Foundations

### Grid — non-negotiable
- Device target: **iPhone 15 Pro Max landscape, 932×430pt**. Verify on 852×393 (15 Pro) — layouts must not break.
- Horizontal safe-area insets: **34pt each side**. Nothing interactive inside them.
- Deck grid: **4 columns × 2 rows = 8 tiles per page. This is the maximum and does not scale with device size.** Larger devices get larger tiles, never more tiles.
- Gutters **12pt**; vertical padding 16pt top / 14pt bottom inside the safe area.
- Resulting tile size on 932×430: roughly **196×140pt**.
- Pages: **2 free, 8 with Premium.**

### Colour
| Token | Hex | Use |
|---|---|---|
| `void` | `#0a0a0a` | outermost background, device bezel |
| `chassis` | `#111111` | app background |
| `surface` | `#161616` | cards, sheets |
| `surface-raised` | `#1a1a1a` | list rows, panels |
| `keycap` | `linear-gradient(#242424, #191919)` | resting tile fill |
| `keycap-active` | `linear-gradient(#2c2c2c, #202020)` | frontmost tile fill |
| `keycap-pressed` | `#151515` | pressed tile fill |
| `stroke` | `#2f2f2f` | tile border |
| `stroke-subtle` | `#262626` / `#2a2a2a` | dividers, card borders |
| `ink` | `#e8e8e8` | primary text |
| `ink-secondary` | `#c8c8c8` | body copy on cards |
| `ink-muted` | `#8a8a8a` | meta, mono labels |
| `ink-faint` | `#6a6a6a` | timestamps, hints |
| `mint` | `#a4d4c5` | **state only** — running, frontmost, connected, primary confirm |
| `ochre` | `#e8b94a` | **premium only** — gates, upgrade CTA |
| `red` | `#ef4444` | **destructive only** — unpair, delete, disconnected banner |
| `red-ink` | `#ff8080` / `#ff9a9a` | error text on dark |
| `red-bg` | `#1e1414` | disconnected banner fill |

Rules: mint, ochre and red are never decorative. Colour is never the only cue for a state.

### Typography
Two families, one job each. Mixing them inside a single element is a violation.

- **IBM Plex Mono** (production: **SF Mono**) — machine voice: tile legends, status, page numbers, section labels. Always uppercase with positive tracking.
- **Inter** (production: **SF Pro**) — human voice: headings, body copy, buttons, settings labels.

| Role | Font | Size / weight / tracking / leading |
|---|---|---|
| display | Inter | 38–56 / 500 / −1 to −2 / 1.15 |
| title | Inter | 26–32 / 500 / −0.5 to −1 |
| body | Inter | 15–17 / 400 / — / 1.5 |
| body-small | Inter | 13–14 / 400 / — / 1.5 |
| legend (tile) | Plex Mono | 12 / 400 / +1 / 1 · UPPERCASE, one line, truncates |
| meta | Plex Mono | 11–13 / 400 / +1.5 to +2 · UPPERCASE |

Production must use Dynamic Type. Tile legends truncate to one line and never reflow the grid.

### Space, radius, depth
- Spacing scale: **4 · 8 · 12 · 16 · 24 · 34**.
- Radii: `6` badges · `9–10` buttons, rows · `12` **tile (keycap)** · `14–16` cards, sheets · `46` device frame.
- One shadow recipe for every keycap: `inset 0 1px 0 #3a3a3a, 0 3px 0 #050505`. Depth is structural, not atmospheric — no soft ambient shadows anywhere in the UI.

---

## The tile (keycap) — the core component

A keycap is a fixed-bounds rounded rect. **Its bounds never change across states**; only fill, border, shadow, and a 4pt vertical offset vary.

Content, centred, 9pt gap: icon 40×40pt, then legend in mono 12/+1 uppercase.

| State | Fill | Border | Shadow | Extra |
|---|---|---|---|---|
| idle | `keycap` gradient | 1pt `#2f2f2f` | `inset 0 1px 0 #3a3a3a, 0 3px 0 #050505` | — |
| running | idle | idle | idle | mint LED, 8pt circle, top-right inset 11pt, `0 0 8px #a4d4c5` glow |
| frontmost | `keycap-active` | 1pt `mint` | `inset 0 1px 0 #444, 0 0 0 3px rgba(164,212,197,.18), 0 3px 0 #050505` | LED if also running; icon and legend go `#ffffff` |
| pressed | `#151515` | 1pt `#2a2a2a` | `inset 0 3px 8px rgba(0,0,0,.7)` | translateY **+4pt**; icon/legend `#c8c8c8` |
| disconnected | idle | idle | none | whole deck at **38% opacity**, non-interactive |
| shortcut tile | idle | idle | idle | user-chosen emoji at 34pt replaces the icon |
| edit mode | idle | idle | idle | rotate ±0.8–1.5° (alternating), red `−` badge 22pt at top-left, offset −7pt |
| dragging | `#1c1c1c` | 2pt dashed `mint` | `0 12px 26px rgba(0,0,0,.6)` | rotate −3°, scale 1.04, label "DRAGGING" |
| empty slot | none | 2pt dashed `#2f2f2f` | none | `+` glyph + "ADD TILE" in `#6a6a6a` |

Accessibility per tile: `label` = app name, `value` = running / frontmost, `trait` = button. Focus order follows the visual grid, page by page.

---

## Screens

Each screen below maps to a slide in `NosoDeck Landscape Deck.dc.html` and, where noted, an option id in `NosoDeck Landscape.dc.html`.

### S1 · Onboarding (2 steps, no tour, no account)
Skipped entirely if a paired Mac is already known.

**Step 1 — Install on Mac.** Two equal columns, 36pt gap, 24pt vertical padding.
- Left: `STEP 1 / 2` (mono meta) · "Install NosoDeck on your Mac" (Inter 38/500/−1) · body "Same Wi-Fi, that's it — no account, no cable." · button row: **CONTINUE** (48pt tall, radius 12, `ochre` fill, `#1a1300` text, mono 14/+1) and "Already installed" (48pt, 1pt `#2f2f2f` border, `#9a9a9a`) · 2 page pips (22×5pt, radius 3; active `#e8e8e8`, inactive `#333`).
- Right: card radius 16, `linear-gradient(#1c1c1c,#151515)`, 1pt `#2a2a2a`, centring a 132pt white QR square + `nosodeck.app/mac` in mono 12/+1 muted.

**Step 2 — Pair this iPhone.** Same split.
- Left: `STEP 2 / 2` · "Pair this iPhone" · "We find your Mac on the local network and swap a 6-digit PIN." · **FIND MY MAC** (ochre) · pips with the second active.
- Right: the Local Network permission **pre-prompt** card (`surface-raised`, radius 16, 1pt `#2a2a2a`, 26pt padding): mono label `LOCAL NETWORK ACCESS`, then three bolded lines — **Why** "to reach your Mac on this Wi-Fi" / **Without it** "nothing connects at all" / **Degraded path** "none; this one is required" — then an **Allow** button (44pt, radius 10, mint fill, `#0a1a1a` text, Inter 15/600).

Pattern to reuse for every permission: *why · what breaks without it · degraded path*, shown **before** the system prompt. Automation (Shortcuts) and Accessibility (emoji insertion) follow the same card, both with real degraded paths — hide the Shortcuts tab; copy emoji to clipboard instead.

### S2 · Device discovery
Two columns, 1.1fr / 1fr, 28pt gap, 20pt vertical padding.
- Left: mono `CHOOSE YOUR MAC`, then rows (radius 12, `keycap` gradient, 12×14pt padding, **min-height 52pt**, 8pt gap): 34pt icon square `#2c2c2c`, name (Inter 15) + subtitle (Inter 12 muted), trailing element. Paired row gets a mint border and a `PAIRED` pill (mono 11/+1, 1pt mint, radius 6). Unpaired rows get a `›`. Offline rows: `#161616` fill, `#232323` border, **45% opacity**, no chevron.
- Bottom-left: mono `STILL SCANNING…` with a 10pt ring.
- Right: help card — mono `NOTHING FOUND?`, then the three concrete checks ("Mac app running · same Wi-Fi · local network allowed on both") centred, then a **Troubleshoot** button (44pt, 1pt `#3a3a3a`, radius 10).

**The empty state is never blank** — scanning copy plus those three checks.

### S3 · PIN pairing
Two equal columns, vertically centred.
- Left: "Enter the PIN shown on your Mac" (Inter 32/500/−1) · six digit cells **56×74pt**, radius 12, 10pt gap: filled cells use the `keycap` gradient with the digit at 30pt; the active cell is `#202020` with a 2pt mint border and `0 0 0 3px rgba(164,212,197,.16)`; empty cells are `#181818` / 1pt `#262626`. Below, mono `MENU BAR → NOSODECK ICON`.
- Right, stacked 12pt: **error card** (1pt red border) — mono `ERROR`, "Wrong PIN — 2 tries left" in `#ff8080`, plus the rule "Digits shake and clear in place. The flow never resets." **Re-pair card** — mono `IDENTITY CHANGED`, explanatory copy, then **Re-pair** (red fill, white text) and **Cancel** (1pt `#3a3a3a`) side by side, 40pt tall.

Behaviour: wrong PIN shakes the row ~200ms, fires an error haptic, clears digits in place, decrements a **textual** attempt counter. Success fires a success haptic and pushes to the deck after ~250ms.

### S4 · Deck home (primary screen)
Column layout, 16pt top / 14pt bottom padding inside safe area.
- **Top bar** (14pt bottom padding): mint LED 9pt + mono `NORA'S MACBOOK · 12MS` in `#8a8a8a` · spacer · time `09:41` mono 13 `#6a6a6a` · settings button 36×36pt, radius 10, `#1c1c1c`, 1pt `#2c2c2c`.
- **Grid**: 4×2, 12pt gap, fills remaining height. Tiles per the keycap spec.
- **Bottom bar** (12pt top padding, centred): page pips as 22×5pt bars (radius 3), then the ochre `+ PAGE` pill (radius 6, mono 11/+1) when the user is at the free page limit.

Gestures — one per region: tap a tile to launch/focus · swipe down on a tile to quit that app · horizontal swipe to change page · long-press ≥500ms to enter edit mode.

**Connection states.** Reconnecting: deck desaturates and stays on screen behind an amber-bordered banner; never blank the grid. Disconnected: a **red banner** replaces the connection pill — "Disconnected — tiles are inactive until your Mac is back." with an underlined **Retry** — and the deck (including the recents column) drops to 38% opacity and stops accepting taps.

### S5 · Edit mode
Same grid, same bounds. Top bar becomes mono `EDITING PAGE 1` + a **DONE** button (34pt, mint fill, `#0a1a1a`, radius 8, mono 13/+1). Tiles tilt (see keycap table) and gain remove badges; the last slot becomes the dashed **ADD TILE** placeholder. Bottom bar becomes a page strip: `PAGE 1` (1pt mint, mint text) / `PAGE 2` (1pt `#2c2c2c`, `#8a8a8a`) / ochre `+ PAGE`, all 32pt tall radius 8, with the hint `DELETE PAGE CONFIRMS` right-aligned in mono 11.

Deleting a page is a destructive confirm. Reordering is drag-and-drop within and across pages.

### S6 · Add tile
Two columns, 1.35fr / 1fr, 24pt gap.
- Left: segmented control (radius 9, `#1a1a1a`, 1pt `#2a2a2a`, 4pt padding) with **APPS / SHORTCUTS / WEBSITE**, active segment `#e8e8e8` on `#111` text · search field 38pt "⌕ Search apps on your Mac" · results list, rows radius 10, **min-height 46pt**, 7pt gap; selected row gets a mint border and a trailing mint `✓`.
- Right, preview panel (radius 16, `#1a1a1a`, 1pt `#2a2a2a`, 20pt padding): mono `PREVIEW` · a **live 150×112pt keycap** rendering the tile as it will appear · `LABEL` field (38pt, `#141414`, 1pt `#2a2a2a`) · `GOES TO` line showing the destination slot — e.g. "Page 1 · slot 8 of 8" with an ochre "— page full after this" warning · footer **CANCEL** (1pt `#3a3a3a`) and **ADD** (mint) at 44pt.

Because a page only holds 8 tiles, the picker **must** state the destination slot and warn when the page fills. Website tab validates the URL inline (2pt red border + "Needs a valid http(s) address"); **ADD** stays visible but dimmed while invalid — never hidden.

### S7 · Settings
Fits on one screen — **no scrolling in landscape**. Header "Settings" (Inter 26/500) with build number in mono, then a 2-column 16pt grid.
- Left column: **device card** — 40pt icon, name (Inter 16), "● Connected · 12ms" in mint (Inter 13), trailing **UNPAIR** button (36pt, 1pt red, `#ff8080`, mono 12/+1). Below, **DECK** card: "Emoji insertion" toggle (50×28pt track, radius 999; off `#2a2a2a` with `#6a6a6a` knob, on `mint` with `#0a1a1a` knob) with the explainer "Needs Accessibility on the Mac. Off = tiles still launch apps; only typed emoji stops working."; divider; "Keep Mac awake while connected" toggle (on).
- Right column: **premium card** — `linear-gradient(#221c0c,#1a1608)`, 1pt ochre, mono `PREMIUM` in ochre, benefit line "8 pages instead of 2 · recents row · themes", **START FREE TRIAL** (42pt, ochre fill). Below, a plain row list at 46pt each: Restore purchases › · Permissions (trailing "2 of 3 granted") · Help & troubleshooting › · About & privacy ›.

Unpair is a destructive confirm: "Unpair Nora's MacBook Pro?" / "Your deck layout stays on this iPhone. You'll need a new PIN to reconnect." / **Unpair** (red) + **Keep paired**.

Every permission toggle carries a one-line explainer of exactly what breaks without it.

### S8 · Paywall
Free = 2 pages. Premium = 8 pages, recents row, themes; **7 days free, then $2.99/month**, cancel in the App Store. Close ✕ is full size, top-left, present from the first frame — no timer, no fake discount. (Landscape layout not yet drawn; use the S7 premium card's copy and the ochre CTA treatment.)

### S9 · Recents (Premium)
A **92pt-wide left column** inside the content area, 14pt gap from the grid, holding 4 stacked recent-app cells (radius 10, `#1a1a1a`, 1pt `#262626`, 26pt icons) under a mono `RECENT` label. **The 4×2 grid does not shrink** — the column consumes the horizontal slack landscape provides. For free users the column shows a locked teaser that opens the paywall; it is never a dead tap.

---

## Interactions & behaviour

- **Motion tier: subtle.** 80–150ms tap feedback (fill + 4pt sink only, bounds fixed) · ~200ms for LED lighting and the frontmost ring moving between caps · spinners only after **300ms** · exits faster than entrances.
- **Reduce Motion**: every animation has a fade-only variant; the LED stops pulsing and stays lit.
- **Haptics**: tile tap and pairing success only.
- **Gestures**: one per region, as listed under S4. No competing gesture on the same surface.
- **Loading**: reconnecting desaturates the live deck rather than replacing it with a spinner screen.
- **Errors**: inline and in place; the user never loses their position in a flow.
- **Every screen ships empty, loading, error, and disconnected states** — designed with the happy path, not bolted on after.

## State model
- `pairing`: `unpaired | discovering | awaitingPIN | pairingError(attemptsLeft) | identityChanged | paired`
- `connection`: `connected(latencyMs) | reconnecting | disconnected` — drives the top bar, deck opacity, and tile interactivity.
- `deck`: `pages[]` → each `page` has ≤ 8 `tiles[]`; `tile` = `{ id, kind: app|shortcut|website, target, label, icon|emoji }`; `currentPage`; `editing: Bool`.
- `macState`: `runningBundleIDs: Set`, `frontmostBundleID` — pushed from the Mac, drives LEDs and the frontmost ring.
- `entitlement`: `free | premium` — caps pages at 2 and gates the recents column.
- `permissions`: `localNetwork | automation | accessibility`, each `notDetermined | granted | denied`, each with its own degraded path.
- `recents`: ordered list, capped at 4 visible, scrolls independently of pages.

## Assets
- **App icons in the prototypes are placeholders**: monochrome glyphs from [Simple Icons](https://simpleicons.org) v13 via jsDelivr, applied as CSS masks so they tint per surface. **In production, icons come from the Mac at runtime** (the real macOS app icons, in colour) — do not ship Simple Icons.
- Emoji appear **only** where the user chose them for a Shortcut tile. Never decorative.
- Fonts: Inter + IBM Plex Mono in the prototypes; **SF Pro + SF Mono** in production.
- The QR code on onboarding step 1 is a placeholder for the real App Store link.

## Files
| File | What it is |
|---|---|
| `NosoDeck Landscape Deck.dc.html` | **Start here.** 13-slide presentation: cover, palette, type & space, motion & accessibility, then every landscape screen with rationale in the speaker notes. |
| `NosoDeck Landscape.dc.html` | The landscape option board — four style directions on an identical 4×2 skeleton (`2a` Deep Teal, `2b` Warm Paper, `2c` **Hardware — chosen**, `2d` Brand Pop). Useful for seeing what was rejected and why. |
| `NosoDeck Design Theme.dc.html` | The earlier portrait-era theme deck: two-surface strategy, full brand palette, type scale, component set. Background context — where the landscape system disagrees with it, **the landscape deck wins**. |
| `NosoDeck Wireframes.dc.html` | Original low-fidelity wireframes for all 13 surfaces including the macOS ones. Use for flow and state coverage, not for styling. |
| `original-product-brief.md` | The original product brief these designs were built from — requirement IDs (FR-*), journeys, and constraints. |
| `deck-stage.js`, `support.js` | Runtime for the prototypes. Keep them beside the HTML files; not part of the product. |

Open any `.dc.html` directly in a browser.
