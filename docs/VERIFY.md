# NosoDeck — Verification Queue

The build verification split (D12): the agent works in a Linux container, the owner
builds and runs on real hardware. This file is the contract between the two — the
authoritative list of what has *not* been proven yet.

**Rules**
- Nothing in this file is "tested" until the owner runs it and reports back.
- A milestone whose code cannot be compiled in the container is marked
  **implemented, pending verification** — never "complete".
- Every device-only behaviour gets a row here with an explicit pass/fail check.

## Environment status — read this first

| Capability | Status | Consequence |
|---|---|---|
| Swift toolchain in the container | **Unavailable** | `swift build` / `swift test` cannot be run here at all |
| `download.swift.org` | Blocked by egress policy (HTTP 403 at the proxy) | No toolchain can be installed; `apt` has no `swiftlang` package |
| Xcode / iOS + macOS SDKs | Unavailable (Linux) | App targets were never expected to build here (D12) |

This is worse than D12 assumed. D12 planned for **DeckKit to be `swift test`-green on
Linux**, with only the app targets deferred to the owner. With no toolchain, *all*
Swift in this repo — DeckKit included — is unverified until the owner compiles it.

**What this means in practice:** every milestone below carries a "compiles" row, not
just a "behaves" row, and DeckKit's unit tests are written but never executed here.
Running `swift test` at the repo root on the owner's Mac is now the single most
valuable verification step at every milestone boundary — it is fast, needs no device,
and covers the protocol and state-machine logic that everything else depends on.

## How to verify

```bash
# 1. Shared package — the whole test suite, no device needed
swift test                      # from the repo root

# 2. Generate the Xcode projects (once per project.yml change)
brew install xcodegen
cd apps/NosoDeck    && xcodegen && open NosoDeck.xcodeproj
cd apps/NosoDeckMac && xcodegen && open NosoDeckMac.xcodeproj
```

Then work the milestone checklist below and report results — including verbatim
compiler errors, which are the most useful thing you can send back.

---

## M0 — Scaffolding · implemented, pending verification

| # | Check | Expected | Result |
|---|---|---|---|
| M0.1 | `swift build` at repo root | Builds with no errors | ☐ |
| M0.2 | `swift test` at repo root | 2 tests pass (`DeckKitVersionTests`) | ☐ |
| M0.3 | `cd apps/NosoDeck && xcodegen` | Generates `NosoDeck.xcodeproj` with no spec errors | ☐ |
| M0.4 | `cd apps/NosoDeckMac && xcodegen` | Generates `NosoDeckMac.xcodeproj` with no spec errors | ☐ |
| M0.5 | Build `NosoDeck` scheme for an iPhone 15 Pro simulator | Compiles; launches to a black screen reading `NOSODECK · DECKKIT 0.1.0` | ☐ |
| M0.6 | Rotate the simulator to portrait | App stays landscape (D14 / FR-23) | ☐ |
| M0.7 | Build and run `NosoDeckMac` | Compiles; a grid glyph appears in the menu bar and **no Dock icon** (FR-19) | ☐ |
| M0.8 | Open the `NosoDeckMac` menu | Shows the DeckKit version row and a working **Quit NosoDeck** | ☐ |
| M0.9 | Xcode → target → Signing & Capabilities (Mac) | App Sandbox on, with Incoming + Outgoing Connections and Apple Events (PRD §5) | ☐ |

**Known open item (accepted, not a bug):** both targets use the placeholder bundle-ID
root `com.noso.nosodeck` and no `DEVELOPMENT_TEAM`. Xcode will need a team selected
locally to run on a device; that is expected until the owner confirms their domain
before M9.

---

## M1 — Protocol & pairing core (DeckKit) · implemented, pending verification

Pure logic, no platform frameworks — so `swift test` covers all of it and **no device
is needed for this milestone**. If any single check on this page is worth running, it
is M1.2.

| # | Check | Expected | Result |
|---|---|---|---|
| M1.1 | `swift build` at repo root | Builds with no errors | ☐ |
| M1.2 | `swift test` at repo root | All tests pass | ☐ |
| M1.3 | `swift build -Xswiftc -strict-concurrency=complete` | No concurrency warnings — the app targets build with this on | ☐ |

Send back verbatim compiler output for anything that fails. These files have never been
through a type-checker, so plain syntax and signature mistakes are the likeliest
failures, not logic ones.

### What the tests assert (the FR-2/3/4 logic this milestone delivers)

| Area | Covers |
|---|---|
| `FrameDecoderTests` | Length-prefixed reassembly: partial headers, partial bodies, coalesced frames, byte-at-a-time delivery, 50 seeded random split patterns, zero-length and oversized length rejection, a garbage frame that must not swallow the next one |
| `EnvelopeCodingTests` | Every one of the 15 message types round-trips; the `v`/`id`/`type`/`payload` wire shape; unknown types and missing payloads surface as `ProtocolError` |
| `PairingTests` | FR-2 (PIN validation, correct PIN pins the key, wrong PIN stores nothing and counts down 2→1→list), FR-3 (same device ID + different key ⇒ `identityChanged`, never silent trust; rename doesn't break trust), FR-5 (unpair requires a new PIN) |
| `SessionTests` | FR-4 (drop ⇒ reconnecting ⇒ resumes with no user action), PRD §5 keepalive (two missed pongs trip reconnect), reachability loss ⇒ disconnected, and that no backoff step can exceed five seconds |
| `DeckTests` | FR-6 eight-tile cap including through decoding, FR-17 tier page limits, cross-page moves, layout survives a persistence round trip |
| `ModelTests` | Keycap state precedence (frontmost > running > idle), FR-16 recents ordering/dedup, FR-8 "saf" finds Safari, website URL validation, FR-24 degraded paths |

### Deviations from the design's state model, for the record

- `ConnectionState` adds a `connecting` case alongside the handoff's three. It shares
  the `reconnecting` visual treatment; it exists because "Reconnecting…" is the wrong
  copy for a link that has never been up.
- `PairingState.pairingError` carries the device alongside `attemptsLeft`, so the PIN
  screen can keep naming the Mac — the flow never resets (design S3).
- `Deck` stores pages only. `currentPage` and `editing` from the handoff's state model
  are view state, owned by each app rather than persisted.

Flag any of these if they are the wrong call — they are cheap to change now, and much
less so after M3 builds screens on them.

---

## Milestones not yet implemented

M2–M9 sections are appended as each milestone lands. See `docs/PRD.md` §7 for the
milestone list and each one's stated verification method.
