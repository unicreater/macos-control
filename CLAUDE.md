# NosoDeck

An iPhone, docked beside a Mac keyboard, acting as a live control deck: tap a keycap
tile and that app comes to the front on the paired Mac; tiles reflect what is running
and frontmost. SwiftUI, iOS 17+ / macOS 14+, local network only, both App Stores.

**If you are picking this up on a Mac for the first time, read
`docs/local-agent-handoff.md`.** The code has never been compiled — see below.

## The documents are the contract

In precedence order:

1. `docs/PRD.md` — requirements FR-1…FR-24 with acceptance criteria, and the milestones.
2. `design/handoff/README.md` — the accepted design spec. **Where the PRD and this
   disagree on anything visual, the design handoff wins.**
3. `docs/decisions.md` — D1–D18, why things are the way they are. Don't re-litigate.
4. `docs/VERIFY.md` — what has and has not actually been proven.

When code and spec disagree, the spec is right and the code is a guess. If a requirement
is genuinely infeasible, stop and ask rather than quietly deviating — and record it in
`docs/VERIFY.md`.

## Current state: written, not verified

Every milestone M0–M9 is implemented. **None has been compiled.** It was written in a
Linux container with no Swift toolchain (`download.swift.org` is blocked by egress
policy), so expect shallow, numerous type errors on a first build.

Nothing may be marked "complete" until it has actually been run. `docs/VERIFY.md` is the
queue, and its rules at the top apply.

## Build

```bash
swift test                                    # DeckKit — no device needed
(cd apps/NosoDeck && xcodegen)                # then open the generated .xcodeproj
(cd apps/NosoDeckMac && xcodegen)
python3 scripts/swift-syntax-check.py .       # syntax only, not a compiler
```

`.xcodeproj` bundles are generated and gitignored — edit `project.yml`, never the
generated project. Signing is deliberately unset; pass `CODE_SIGNING_ALLOWED=NO` for
compile-only checks rather than committing a team ID.

## Structure

| Path | Role |
|---|---|
| `Sources/DeckKit` | Models, protocol, framing, pairing/session state machines |
| `apps/NosoDeck` | iOS app |
| `apps/NosoDeckMac` | macOS menu-bar agent |
| `apps/Shared` | Transport compiled into both apps |

**DeckKit must never import AppKit, UIKit, SwiftUI or Network.** Its portability is the
only reason any of this is testable away from a Mac (D12). Platform glue belongs in the
app targets.

## Non-negotiables

Changing any of these needs the owner's agreement, not a judgement call:

- **8 tiles per page, 4×2, hard maximum.** Larger devices get larger tiles, never more
  (D15). Enforced in `Page`, including through decoding.
- **2 pages free, 8 with premium** (D16). Premium is additive — nothing already free is
  ever locked, so a lapsed subscriber keeps every page they built.
- **Colour is semantic.** `mint` = state only, `ochre` = premium only, `red` =
  destructive only. Never decorative, and never the only cue for a state.
- **Landscape-primary, dark only** in v1 (D14). Portrait and light mode are undesigned.
- **The Mac agent stays MAS-sandbox-legal** (D3). No Accessibility-dependent feature
  except the emoji opt-in path (FR-15).
- **Every screen ships empty, loading, error and disconnected states**, and every
  permission ask is preceded by its *why · what breaks · degraded path* card (FR-24).

## Conventions

- Comments explain *why*, not *what*. Cite the FR or design slide when a line exists
  because a requirement says so.
- State machines in DeckKit are reducers with no clock and no I/O — that is what makes
  them testable. Keep timers and sockets in the app targets.
- Tests encode acceptance criteria. A failing test is a bug or a real disagreement with
  the PRD; it is never something to delete.
