# NosoDeck — Design Handover (for Claude Design)

Version 1.0 · 2026-08-11 · Prepared with the [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) standard (v2.13)

## 0. How to use this handover

You are designing every screen of NosoDeck for iOS and macOS **before** implementation
begins, so the build (milestones M0–M9 in `docs/PRD.md`) follows the designs, not the
other way around.

- **Source-of-truth chain:** `design-system/nosodeck/MASTER.md` (generated design
  system) → this handover → `docs/PRD.md` acceptance criteria. When you make a
  page-specific deviation, record it as `design-system/nosodeck/pages/<screen>.md`
  (the UI/UX Pro Max master+overrides pattern) — never edit MASTER.md silently.
- **Read first:** `docs/PRD.md` (§3 journeys, §4 requirements), `docs/decisions.md`,
  `design-system/nosodeck/MASTER.md`.
- Every screen below lists the FR-IDs it serves; your mockups must satisfy those
  acceptance criteria visually (e.g. FR-10's running/frontmost indicators must be
  designable states, not afterthoughts).

## 1. Product context (one paragraph)

NosoDeck turns an iPhone into a live control deck for a Mac: a grid of tiles (Mac
apps, Apple Shortcuts, websites) where tapping a tile acts on the Mac instantly and
tiles continuously reflect what is running and frontmost. Public App Store product,
free + premium (pages/recents/themes), local-network only, iOS 17+ / macOS 14+,
SwiftUI on both platforms. The Mac side is a menu-bar-only agent; the iPhone is the
primary surface and editor.

## 2. Design system baseline (generated, tunable)

Generated with dials **motion 3/10 (subtle)** and **density 8/10 (dense/dashboard)** —
a control deck is glanceable-dense, not editorial. Full output in
`design-system/nosodeck/MASTER.md`.

- **Style direction:** "Micro-interactions" — tactile, gesture-based, small subtle
  animations; best-for: touchscreen productivity tools. Light **and** dark mode are
  first-class; the deck's home screen should be designed dark-first (it sits beside a
  keyboard like a hardware device) but must ship both.
- **Color tokens (baseline — you may evolve hues, not the token structure):**
  primary `#0D9488` teal (connection/live), on-primary `#FFFFFF`, secondary
  `#14B8A6`, accent/CTA `#EA580C` orange (actions/paywall CTA), destructive
  `#DC2626`, plus background/foreground/muted/border/ring per MASTER.md. Semantic
  tokens only — no raw hex in screens; every token needs a light and a dark value.
  Reserved state colors: **running** = primary teal dot, **frontmost** = teal ring +
  elevated tile, **disconnected** = desaturated/40% opacity.
- **Typography:** system SF Pro (Text/Display) as the shipping default — native
  Dynamic Type support is a hard requirement — with Inter as the approved brand-adjacent
  alternative for marketing surfaces only. Numeric/label hierarchy per MASTER.md scale;
  body ≥ 16pt equivalent, captions never below 12pt.
- **Spacing:** dense dashboard rhythm on the 4/8pt system (8–32pt scale from the
  density dial). Deck grid: 4 columns, 8pt+ gutters, tiles ≥ 60pt square (comfortably
  above the 44pt minimum).
- **Iconography:** SF Symbols exclusively for UI chrome (one weight/style per
  hierarchy level, filled-vs-outline discipline); real Mac app icons inside tiles.
  **No emoji as structural icons** — emoji appear only where user-chosen (Shortcut
  tile labels, emoji strip).
- **Anti-patterns (from generator):** complex onboarding, slow/unresponsive feel,
  neon-on-dark vibrating contrasts, AI-purple gradients, decorative-only animation.

## 3. Screen inventory — iOS (9 screens)

For each screen deliver: light + dark mockups, all listed states, and a short spec of
spacing/typography/token usage. iPhone 375pt width first; verify at 430pt and iPad
(runs iPhone layout, must not break).

| # | Screen | FR-IDs | Must show |
|---|--------|--------|-----------|
| S1 | **Onboarding** (2 screens max) | FR-22 | Install-Mac-app step with App Store link; pairing step; skip logic when already paired. Anti-pattern reminder: no complex onboarding. |
| S2 | **Device discovery** | FR-1 | Found-Macs list (name, icon, paired badge); empty state ("looking for your Mac…" with troubleshooting hint); multiple-Macs state. |
| S3 | **PIN pairing** | FR-2, FR-3 | 6-digit PIN entry, error state (wrong PIN), success transition into starter deck; identity-changed re-pair warning variant. |
| S4 | **Deck (home)** | FR-6, FR-7, FR-9, FR-10, FR-12, FR-17, FR-21 | The hero screen. 4-col tile grid; app tiles with real icons + name; running dot; frontmost ring; page dots + swipe affordance; connection pill (connected/reconnecting/disconnected banner per Journey 3); pressed state (no layout shift); premium page-add affordance. |
| S5 | **Deck edit mode** | FR-6 | Wiggle/drag reorder, remove affordance, add-tile entry point, page management (add/delete page with premium gate). |
| S6 | **Add tile** | FR-8, FR-13, FR-14 | Segmented: Apps (searchable catalog with icons) / Shortcuts (list from Mac, emoji+label picker) / Website (URL + name form with inline validation). |
| S7 | **Settings** | FR-5, FR-15, FR-21 | Paired Mac card with unpair (destructive confirm); emoji-insertion toggle with Accessibility-permission explainer; keep-awake toggle; restore purchases; about. |
| S8 | **Paywall** | FR-17, FR-18 | Premium benefits (8 pages, recents row, themes), 7-day trial price display, restore link, non-dark-pattern close. |
| S9 | **Recents row** (deck variant) | FR-16 | Horizontal strip above/below grid, premium badge state for free users. |

## 4. Screen inventory — macOS (4 surfaces)

Menu-bar-only agent (no Dock icon). Follow macOS HIG for menu-bar extras: compact,
system-native materials (vibrancy), SF Symbols menu icon that reflects state.

| # | Surface | FR-IDs | Must show |
|---|---------|--------|-----------|
| M1 | **Menu bar icon states** | FR-19 | Glyph variants: unpaired / paired-connected / paired-disconnected / action-in-flight (subtle). |
| M2 | **Popover — unpaired** | FR-2, FR-19 | Large 6-digit PIN, "enter this on your iPhone" copy, Bonjour-visibility hint. |
| M3 | **Popover — paired** | FR-5, FR-19, FR-20 | Connected device name + status, launch-at-login toggle, unpair (destructive confirm), quit. |
| M4 | **Permission moments** | FR-13, FR-15 | Designed pre-prompt explainers for: Local Network (both OSes), Automation/Apple-events (Shortcuts), Accessibility (emoji opt-in only) — each states why, what breaks without it, and the degraded path. |

## 5. Interaction & motion spec (subtle tier)

- Tap feedback within 80–150ms: opacity/elevation change only — **pressed states never
  shift layout bounds**. Haptic (light impact) on tile tap and pairing success only —
  not on every interaction.
- Micro-interactions 150–300ms, platform-native easing (`withAnimation` spring defaults);
  state changes (running dot appearing, frontmost ring moving) animate at ~200ms.
- Reconnecting: skeleton/desaturation over the existing deck, never a blank screen;
  spinner only for operations > 300ms.
- Exit animations faster than entrances. Respect `accessibilityReduceMotion` — every
  animation needs a reduced variant (fade only).
- One primary gesture per region: tile tap (activate), tile swipe-down (quit, FR-11),
  horizontal page swipe — design so these never conflict (e.g. quit-swipe requires
  clear directional threshold).

## 6. Accessibility requirements (blocking, not advisory)

- Touch targets ≥ 44×44pt with ≥ 8pt spacing (our 60pt tiles + 8pt gutters comply).
- Text contrast ≥ 4.5:1 (primary) / ≥ 3:1 (secondary) — **verified independently in
  both modes**; state colors (running/frontmost) must also hit 3:1 against tile fill.
- Color is never the only indicator: running = dot **+** VoiceOver value; frontmost =
  ring **+** elevation; disconnected = opacity **+** banner text.
- Every tile: `accessibilityLabel` = app name, `accessibilityValue` = running state,
  trait = button. Focus order matches visual order.
- Dynamic Type: deck labels truncate gracefully at larger sizes; settings/paywall
  reflow without breakage.

## 7. Deliverables expected back from Claude Design

1. **Mockups** — every screen/surface in §3–§4, light + dark, all listed states, as
   HTML/SVG artifacts or images committed under `design/mockups/`.
2. **Token sheet** — final color/spacing/type tokens as a table mapping token name →
   light value → dark value → intended SwiftUI Asset Catalog color name, committed as
   `design/tokens.md` (structure must stay compatible with MASTER.md).
3. **Component spec** — the reusable pieces: Tile (app/shortcut/URL variants × states),
   connection pill/banner, page dots, PIN display/entry, paywall card, settings rows —
   with dimensions on the 4/8pt grid, in `design/components.md`.
4. **Page overrides** — any screen deviating from MASTER.md gets
   `design-system/nosodeck/pages/<screen>.md`.
5. **Checklist sign-off** — §8 completed per screen.

## 8. Pre-delivery checklist (UI/UX Pro Max canonical, adapted to native)

Per screen, before handover back:
- [ ] No emoji as structural icons; SF Symbols family consistent (weight + fill discipline)
- [ ] All tappables have pressed feedback; no layout-bound shifts on press
- [ ] Touch targets ≥ 44pt; ≥ 8pt spacing between targets
- [ ] Micro-interactions 150–300ms; reduced-motion variant specified
- [ ] Contrast: 4.5:1 primary / 3:1 secondary — checked in light **and** dark
- [ ] Color never the sole state indicator; VoiceOver labels/values specified
- [ ] Safe areas respected (notch, home indicator; menu-bar popover margins on macOS)
- [ ] 4/8pt spacing rhythm; dense (8–32pt) scale per density dial
- [ ] Semantic tokens only — no ad-hoc hex in any screen spec
- [ ] Dynamic Type behavior specified for text-bearing components
- [ ] Empty/loading/error/disconnected states designed, not just the happy path
- [ ] Verified at 375pt and largest-phone width; iPad fallback does not break
