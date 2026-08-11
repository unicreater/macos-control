# NosoDeck — Implementation Handoff (for Opus)

2026-08-11 · Branch: `claude/choclift-swift-macos-ios-mckdv1` · Repo: `unicreater/macos-control`

## What this project is

NosoDeck: an iPhone (landscape, docked beside the keyboard) acting as a live control
deck for a Mac. Tap a keycap-styled tile → the app comes to the front on the paired
Mac; tiles show live running/frontmost state. SwiftUI on iOS 17+ and macOS 14+
(menu-bar agent), local-network only (Bonjour + Network.framework TLS, PIN pairing),
Mac App Store sandboxed, free (2 pages) + premium ($2.99/mo, 7-day trial).

## Read in this order (everything is in-repo; no chat context needed)

1. `docs/PRD.md` — **v1.1, the contract.** Requirements FR-1…FR-24 with acceptance
   criteria, architecture, protocol schema, milestones M0–M9 with checkboxes.
2. `design/handoff/README.md` — **the accepted design spec.** Tokens, keycap state
   table, per-screen layouts S1–S9, motion tiers, state model. Where PRD prose and
   this file disagree on visuals/layout, **the design handoff wins**.
3. `docs/decisions.md` — D1–D18, why everything is the way it is. Do not re-litigate.
4. `design/handoff/*.dc.html` — open in a browser for the visual reference
   (`NosoDeck Landscape Deck.dc.html` first). Prototypes are references — recreate in
   SwiftUI, never port the HTML/JS.
5. Background only: `docs/research-choclift.md`, `docs/design-handover.md`,
   `design-system/nosodeck/MASTER.md` (superseded visual baseline, per D14).

## Your job

Run `/implementation-loop` (project skill, `.claude/skills/implementation-loop/`)
starting at **M0** and proceed milestone by milestone. Per milestone: implement →
verify → self-review → commit → push → short report → next. Update the PRD milestone
checkboxes as you go.

## Hard constraints

- **Branch:** all work on `claude/choclift-swift-macos-ios-mckdv1`; push with
  `git push -u origin <branch>`. Never push elsewhere. No PRs unless the user asks.
- **Verification split (D12):** this environment is Linux. `DeckKit` (shared SwiftPM
  package: models, protocol framing, pairing/session state machines) must build and
  pass `swift test` on Linux — keep it free of Apple-only frameworks. The iOS/macOS
  app targets cannot be compiled here: structure them via committed XcodeGen
  `project.yml` specs, keep sources syntax-clean, and record everything needing
  on-device verification in `docs/VERIFY.md` (the owner builds in Xcode at milestone
  boundaries and reports back). **Never claim device-only behavior is tested.**
- **Design fidelity:** implement the keycap component exactly per the state table
  (fixed bounds; fill/border/shadow/4pt sink only), the token palette (mint = state
  only, ochre = premium only, red = destructive only), SF Pro/SF Mono roles, and the
  4×2-max grid. Every screen ships empty/loading/error/disconnected states.
- **Scope:** v1 = FR-1…FR-24 per PRD priorities. Anything new goes to the PRD's
  Deferred list, not into a milestone. If a requirement proves infeasible, stop and
  ask the user — don't silently deviate.
- **Sandbox:** the Mac agent must remain MAS-sandbox-legal (entitlement plan in PRD
  §5). No Accessibility-dependent features except the emoji opt-in path (FR-15).

## Open items already accepted (don't block on these)

- Bundle-ID root is a placeholder (`com.noso.nosodeck`) until the owner confirms —
  fine for all milestones before M9.
- Portrait is undesigned: lock the deck to landscape with a rotate hint (PRD risks).
- macOS popovers: build with native macOS conventions following the wireframe flows;
  a Hardware-language styling pass comes in a later design round.
- v1 UI is dark-appearance (light mode undesigned).

## State when you start

- Repo contains docs, design bundle, and project skills only — **no Swift code yet**.
  M0 (scaffolding) is the first milestone; nothing is checked off.
- The owner (user) is the device-verification loop and the final authority on scope.
