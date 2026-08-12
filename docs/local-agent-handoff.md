# Handoff: taking over on a Mac

Everything in this repo was written on Linux with no Swift toolchain. It has never been
compiled. This file is for the agent picking it up on a Mac, where it can be.

Read `docs/opus-handoff.md` first for what the product is, then this for what to do.

## The prompt to start with

> Read docs/local-agent-handoff.md and work Phase 1 until both targets compile and
> `swift test` is green. Commit as you go. Stop and report when you reach something in
> Phase 3.

## What changes now that you have a Mac

The container this was written in could not run `swiftc` at all, so `docs/VERIFY.md`
was written for a human working through checks by hand. That is no longer the right
split. Most of Phase 1 and Phase 2 below you can do alone, without asking anyone.

The split that matters is **what a machine can prove** versus **what needs two physical
devices and a person's consent dialogs**. Phase 3 is the second kind. Everything before
it is yours.

---

## Phase 1 — Make it compile (fully autonomous)

Expect a lot of errors. ~8,200 lines of Swift have never been through a type-checker, so
the failures will be shallow and numerous: wrong argument labels, initialisers that
don't exist in that shape, protocol conformances that need a witness. That is the
expected state, not a sign something is deeply wrong.

### 1. The shared package first

```bash
swift build
swift test
```

`DeckKit` is pure logic with no Apple frameworks, so it should be the easiest thing here
and it gates everything else. Get this green before touching the apps — the app targets
import it, and an error in `DeckKit` will produce confusing cascading failures in both.

### 2. Generate the Xcode projects

```bash
brew install xcodegen
(cd apps/NosoDeck    && xcodegen)
(cd apps/NosoDeckMac && xcodegen)
```

The `.xcodeproj` bundles are generated output and gitignored. If a spec is wrong, fix
`project.yml` — never the generated project, which is thrown away on the next run.

### 3. Compile both apps

Signing is deliberately unset (no `DEVELOPMENT_TEAM`), so disable it for a compile-only
check rather than adding a team to the committed spec:

```bash
xcodebuild -project apps/NosoDeck/NosoDeck.xcodeproj -scheme NosoDeck \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project apps/NosoDeckMac/NosoDeckMac.xcodeproj -scheme NosoDeckMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

### The rule while fixing

**The PRD and the design handoff are the contract; the code is the guess.** When
something doesn't compile, fix the code to meet the spec. Do not quietly relax the spec
to match code that was written blind.

Two specific traps:

- **Don't delete a failing test to get green.** The tests encode the acceptance criteria
  in `docs/PRD.md` §4. A test that fails is either a real bug in the code or a real
  disagreement with the PRD — both worth surfacing, neither worth deleting.
- **Don't loosen `Page.maxTiles`, the tier page limits, or the keycap state table** to
  make something typecheck. Those are D15, D16 and the design handoff's non-negotiables.

If a requirement turns out to be genuinely infeasible, stop and ask — the same rule the
`/implementation-loop` skill uses. Record it in `docs/VERIFY.md` rather than silently
deviating.

### Commit rhythm

Commit per coherent batch, not per file — "Fix DeckKit compile errors", "Fix
Network.framework API shapes in the agent". A reviewer should be able to see what class
of thing was wrong. Keep the commits on `claude/choclift-swift-macos-ios-mckdv1`; PR #1
tracks that branch and updates automatically.

---

## Phase 2 — What you can verify alone

Once it compiles, these need no second device and no human:

| Check | How |
|---|---|
| All of M1 | `swift test` — the protocol, framing, pairing and session logic |
| Strict concurrency | `swift build -Xswiftc -strict-concurrency=complete`; the app targets already build with `complete`, so warnings here are real |
| Syntax, as a fast pre-check | `scripts/swift-syntax-check.py` (see `docs/BUILDING.md`) |
| The agent advertises (FR-1) | Run `NosoDeckMac`, then `dns-sd -B _nosodeck._tcp` and `dns-sd -L "<mac name>" _nosodeck._tcp` — the TXT record should carry `did`, `name`, `v=1`, `fp` |
| Identity survives relaunch (FR-2) | Quit and relaunch the agent; `did` in the TXT record must be unchanged |
| The catalog isn't empty (FR-8) | The sandbox may refuse to enumerate `/Applications`. Check Console.app filtered to `nosodeck` for sandbox denials — this is the M4 risk flagged in VERIFY.md |
| iOS app launches landscape-locked | Boot it in the simulator; rotate to portrait, it should stay landscape |
| Screens against the design | Run in the simulator at **932×430** (iPhone 15 Pro Max) and **852×393** (15 Pro), and compare with `design/handoff/NosoDeck Landscape Deck.dc.html` opened in a browser |

The simulator can't reach a real Mac agent over Bonjour in a useful way for pairing, so
treat simulator work as layout and compile verification only.

Update `docs/VERIFY.md` as you go: tick what you have actually run, and leave what you
have not. The rule at the top of that file still holds — nothing is "tested" until it
has actually been run.

---

## Phase 3 — What needs the owner

Stop and hand back for these. They need two physical devices on one Wi-Fi, and consent
dialogs only a person can accept:

- **Pairing end to end** — PIN entry, wrong-PIN attempt counter, identity-changed re-pair
  (M2.8–M2.11, M3.7–M3.9, M3.14)
- **Reconnect behaviour** — toggling Wi-Fi off and back on, within FR-4's five seconds
  (M3.11–M3.13)
- **Live tile state** — launching and switching apps by hand and watching the phone
  (M5.1–M5.5)
- **Automation consent** for Shortcuts, and **Accessibility** for emoji typing
  (M6.1–M6.5, M8.9–M8.13)
- **StoreKit** — needs a StoreKit configuration file created in Xcode (product ID and
  settings in VERIFY.md §M7) and a sandbox Apple ID
- **Login item across a reboot** (M9.12–M9.14)

When you get here, report what you fixed, what you verified, and hand over the Phase 3
list with anything you learned that changes it.

---

## Four decisions to re-examine, not inherit

These were made without a compiler and each has a fuller entry in `docs/VERIFY.md`. If
the first build contradicts one, that is information, not just a bug:

1. **TLS pre-shared keys instead of certificate pinning** (`apps/Shared/DeckTransport.swift`).
   The `sec_protocol_options_add_pre_shared_key` call and the `__DispatchData` bridging
   are the least certain API shapes in the repo.
2. **The starter deck is not the Dock** (FR-12) — the Dock's prefs are outside the
   sandbox container. If you find a MAS-legal way to read it, say so.
3. **The reconnecting banner uses ochre** where design S4 says "amber" — a design
   question for the owner, not something to fix in code.
4. **`ConnectionState` has a fourth case**, `connecting`, beyond the handoff's three.

## Repo layout, briefly

| Path | What |
|---|---|
| `Package.swift`, `Sources/DeckKit`, `Tests/DeckKitTests` | Shared logic. **Must stay free of AppKit/UIKit/SwiftUI/Network** — that portability is what makes it testable |
| `apps/NosoDeck` | iOS app |
| `apps/NosoDeckMac` | macOS menu-bar agent |
| `apps/Shared` | Transport and framing compiled into both apps; imports Network and CryptoKit, which is why it can't live in DeckKit |
| `docs/VERIFY.md` | The verification queue — the authoritative list of what is not yet proven |
| `docs/APP-STORE.md` | Submission checklist |
