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

## M2 — Mac agent MVP · implemented, pending verification

Delivers FR-1, FR-2, FR-3, FR-19. **This is the highest-risk milestone in the repo**:
it is the first code touching Network.framework and the Keychain, and none of it has
been compiled. Expect the failures here to be API-shape mistakes, not logic.

| # | Check | Expected | Result |
|---|---|---|---|
| M2.1 | Build `NosoDeckMac` | Compiles | ☐ |
| M2.2 | Run it | Grid glyph in the menu bar, no Dock icon | ☐ |
| M2.3 | Open the menu, unpaired | "Waiting for your iPhone", a 6-digit PIN shown as `482 913`, **New PIN**, **Quit** | ☐ |
| M2.4 | Click **New PIN** | Digits change; the menu still says it is advertising | ☐ |
| M2.5 | `dns-sd -B _nosodeck._tcp` in Terminal | The service appears under this Mac's name (FR-1) | ☐ |
| M2.6 | `dns-sd -L "<name>" _nosodeck._tcp` | TXT record carries `did`, `name`, `v=1` | ☐ |
| M2.7 | Quit and relaunch the agent | Same `did` in the TXT record — the Keychain identity persisted | ☐ |
| M2.8 | Pair from the M3 phone build with the right PIN | Menu switches to "Connected — <phone>"; phone appears under **Forget** | ☐ |
| M2.9 | Force-quit both apps, relaunch both | Reconnects with no PIN prompt (FR-2) | ☐ |
| M2.10 | Pair with a wrong PIN | Handshake fails, no trust stored, menu unchanged | ☐ |
| M2.11 | **Forget <phone>**, then reconnect | Phone needs the PIN again (FR-5, Mac side) | ☐ |
| M2.12 | Console.app, filter "nosodeck" | No Keychain `OSStatus` errors on first launch | ☐ |

M2.8–M2.11 need the M3 phone build; everything above them can be checked with the
agent alone.

### The one architectural decision here, which is worth a look

Transport auth uses **TLS pre-shared keys, not certificate pinning**. The PRD says
"pinned peer public keys", but generating a self-signed X.509 identity at runtime has
no public API on either OS — it would mean hand-assembling DER and signing with
`SecKey`. PSK reaches the same guarantee by a supported route:

- The **pairing** connection is authenticated by `HMAC-SHA256(PIN, context:deviceID)`.
  Getting the PIN wrong fails the TLS handshake outright.
- Every **later** connection uses a 256-bit secret the agent mints at pairing and hands
  over once, on that PIN-authenticated channel. A Mac that does not hold the secret
  cannot complete the handshake — which is a stronger reading of FR-3 than "is shown as
  unpaired".
- `DeviceIdentity.publicKeyHash` carries an HMAC fingerprint of the agent's long-term
  secret. Safe to display, changes on reinstall.

Known limit, accepted for v1: a six-digit PIN as a PSK is offline-brute-forceable by
someone who captures the pairing handshake on the local network at the moment of
pairing. Mitigated by the PIN being single-use — it rotates after a successful pair and
after three failures. Apple's own peer-to-peer sample takes the same approach. Say so
if you want this hardened before submission.

### Other M2 notes

- The listener's acceptable keys are fixed when it starts, so pairing, unpairing and
  PIN rotation all rebuild it. Live sessions survive; only the advertised socket is
  replaced.
- Phone display names live in `UserDefaults`; only keys go in the Keychain.
- The Mac cannot count wrong-PIN attempts, because a wrong PIN never completes a
  handshake and so never reaches the app layer. The attempt counter the design calls
  for (S3, "2 tries left") is phone-side, which is where it is displayed anyway.

---

## M3 — iOS app MVP · implemented, pending verification

Delivers FR-1–FR-4 end to end, plus the FR-22/23/24 skeleton. Together with M2 this is
the first point where the product does its central thing: a phone finds a Mac, pairs
with it, and stays connected.

| # | Check | Expected | Result |
|---|---|---|---|
| M3.1 | Build `NosoDeck` for an iPhone 15 Pro Max simulator | Compiles | ☐ |
| M3.2 | First launch, no Mac ever paired | Onboarding step 1, landscape, dark (FR-22) | ☐ |
| M3.3 | **Continue** → step 2 | Local-network pre-prompt card: why / without it / degraded path "none" (FR-24) | ☐ |
| M3.4 | **Allow** | iOS local-network dialog appears *after* the card, then the device list | ☐ |
| M3.5 | With the agent running | The Mac appears within 3 s (FR-1) | ☐ |
| M3.6 | Kill the agent | Row disappears; "Still scanning…" and the three checks remain — never a blank screen | ☐ |
| M3.7 | Tap the Mac, type the right PIN | Pairs on the sixth digit and lands on the deck shell | ☐ |
| M3.8 | Tap the Mac, type a wrong PIN | Cells shake ~200 ms, clear in place, "Wrong PIN — 2 tries left"; the screen does not reset | ☐ |
| M3.9 | Two more wrong PINs | Counter goes 2 → 1, then back to the device list | ☐ |
| M3.10 | Force-quit both apps, relaunch both | Deck returns with **no PIN prompt** and no tap (FR-2, journey 2) | ☐ |
| M3.11 | Turn the Mac's Wi-Fi off for 10 s | Deck stays on screen, desaturates, "Reconnecting…" — never blanked | ☐ |
| M3.12 | Turn it back on | Live within 5 s of reachability, no taps (FR-4) | ☐ |
| M3.13 | Turn the **phone's** Wi-Fi off | Red banner, deck at 38 %, taps refused | ☐ |
| M3.14 | Delete the Mac app's Keychain items (or reinstall the agent) and reconnect | "Identity changed" card, **Re-pair** / **Cancel** — never silent trust (FR-3) | ☐ |
| M3.15 | Gear → **Unpair** → reconnect | PIN required again | ☐ |
| M3.16 | Rotate the device to portrait | Stays landscape (FR-23) | ☐ |
| M3.17 | Settings → Accessibility → Reduce Motion on, then a wrong PIN | No shake, error still shown | ☐ |
| M3.18 | Settings → Display → Larger Text at maximum | Labels scale; the 4×2 grid keeps its shape | ☐ |

### Things I would look at first if something misbehaves

- **The invisible PIN field.** The six cells are drawn; a `TextField` behind them at 1 %
  opacity takes the keyboard so paste and autofill work like typing. If the keypad
  never appears or digits do not land, that field is the cause.
- **Auto-reconnect racing.** Two things can trigger a reconnect — the backoff timer and
  a Mac reappearing in the browse results. The second cancels the first. If you see
  duplicate connections, that is where to look.
- **Latency reads 0 ms** until the first keepalive pong, ten seconds in. Expected, not a
  bug.

### Design questions this milestone raised

1. **The reconnecting banner.** S4 calls for an "amber-bordered banner", but the palette
   has no amber and reserves ochre for premium. I used ochre. It is the only warm token
   available, and it does tension with the "ochre = premium only" rule. Worth a ruling.
2. **Settings.** S7 is M9 work. Until then the gear opens only a destructive-confirm
   unpair, because pairing needs to be testable more than once.
3. **Onboarding step 1's QR** is a placeholder square, per the handoff's Assets note.

---

## M4 — App tiles & activation · implemented, pending verification

Delivers FR-6, FR-7, FR-8, FR-9, FR-12. Compare against slides S4–S6.

| # | Check | Expected | Result |
|---|---|---|---|
| M4.1 | Build both targets | Compile | ☐ |
| M4.2 | Pair fresh (unpair first, delete the app) | Page 1 arrives pre-filled, not eight dashed slots (FR-12) | ☐ |
| M4.3 | Tile icons | Real macOS icons, in colour, within ~2 s (FR-7) | ☐ |
| M4.4 | Tap a closed app's tile | It launches on the Mac (FR-9) | ☐ |
| M4.5 | Tap a running app's tile | It comes to the front in under 1 s (FR-9) | ☐ |
| M4.6 | Relaunch the phone app | Icons appear immediately from the disk cache, before the Mac answers | ☐ |
| M4.7 | Long-press a tile ≥500 ms | Edit mode: caps tilt, red − badges, **Done** in the top bar (S5) | ☐ |
| M4.8 | The same long press | The app must **not** also launch — the tap is suppressed once editing starts | ☐ |
| M4.9 | Drag a tile onto another slot | Reorders; **Done**, relaunch, order persists (FR-6) | ☐ |
| M4.10 | Drag a tile onto a full page | Refused; the tile stays where it was | ☐ |
| M4.11 | Tap a − badge | Tile removed; the slot becomes the dashed **Add tile** placeholder | ☐ |
| M4.12 | Tap an empty slot → search "saf" | Safari is first in the list (FR-8) | ☐ |
| M4.13 | Select an app in the picker | Live keycap preview, label field, "Page 1 · slot N of 8" | ☐ |
| M4.14 | Fill a page to seven, then open the picker | "— page full after this" in ochre | ☐ |
| M4.15 | Fill every page, then open the picker | **Add** dimmed but still visible, with the reason | ☐ |
| M4.16 | Any page, any device size | Never more than 8 tiles; larger devices get larger tiles (D15) | ☐ |
| M4.17 | Disconnect the Mac, tap a tile | Nothing sent; the deck is inert at reduced opacity | ☐ |
| M4.18 | Agent launch time | Menu bar appears promptly — the catalog is built at launch, so watch for a hitch | ☐ |

### Two things I am least sure of, having not run any of it

- **Gesture arbitration.** The keycap owns a press gesture for the 4pt sink; edit mode
  is a simultaneous long press; drag-to-reorder is attached *only* in edit mode so it
  cannot compete. M4.8 and M4.9 are the checks that matter, and this is the likeliest
  thing to need adjusting on a real device.
- **Sandbox reach.** The agent enumerates `/Applications`, `/Applications/Utilities`,
  `/System/Applications` and its Utilities folder. If the sandbox refuses any of these
  the catalog comes back short or empty — M4.12 would show it immediately.

### Deviation: the starter deck is not the Dock (FR-12)

FR-12 says page 1 is pre-filled from the Mac's Dock. The Dock's preferences live outside
the agent's container and a sandboxed process cannot read them; there is no MAS-legal
way to ask what is in someone's Dock. The suggestion list is instead built from **apps
running right now**, topped up from a short list of common apps that are installed.

This still meets FR-12's stated acceptance criterion ("a fresh pair shows a non-empty
deck"), and is arguably a better first guess than the Dock, which tends to accumulate
things nobody opens. Flag it if you want the requirement reworded rather than
reinterpreted — the alternative is dropping the sandbox, which contradicts D3.

---

## M5 — Live status · implemented, pending verification

Delivers FR-10 and FR-11. FR-10 is the differentiator — the reason this is a deck and
not a launcher — so M5.2 is the check that matters most.

| # | Check | Expected | Result |
|---|---|---|---|
| M5.1 | Connect with apps already running | Their tiles show the mint LED immediately, before anything changes | ☐ |
| M5.2 | Launch an app on the Mac by hand | Its tile lights up within 1 s, phone untouched (FR-10) | ☐ |
| M5.3 | Cmd-Tab between two apps on the Mac | The frontmost ring moves between caps, ~200 ms | ☐ |
| M5.4 | Quit an app on the Mac by hand | Its LED goes out within 1 s | ☐ |
| M5.5 | Tile bounds during all of the above | Nothing reflows or resizes — only fill, border and shadow change | ☐ |
| M5.6 | Swipe down on a running tile | That app quits gracefully (FR-11) | ☐ |
| M5.7 | Swipe down on a tile for a closed app | Nothing happens — no error, no launch | ☐ |
| M5.8 | Swipe down on an app with unsaved changes | The Mac shows its own save dialog; the tile still reads running | ☐ |
| M5.9 | Swipe **horizontally** across tiles | Changes page; never quits anything | ☐ |
| M5.10 | Tap a tile normally | Still activates — the quit gesture has not eaten the tap | ☐ |
| M5.11 | VoiceOver on a running tile | Reads the app name, then "Running" / "Frontmost" | ☐ |

**Sandbox risk, flagged in the PRD's own risk table:** `NSRunningApplication.terminate()`
from inside the sandbox is the uncertain part of FR-11. If M5.6 does nothing, the
fallback is an Apple Events `quit`, which needs the automation consent flow that M6
introduces anyway. FR-11 is P1, so it can be cut without touching anything P0.

Gesture thresholds, if M5.6/M5.9 need tuning: a quit needs more than 44pt of downward
travel and at least twice as much vertical as horizontal movement.

---

## M6 — Shortcuts & URL tiles · implemented, pending verification

Delivers FR-13 and FR-14.

| # | Check | Expected | Result |
|---|---|---|---|
| M6.1 | Add-tile → **Shortcuts** tab, first time | The Automation pre-prompt card, *before* any system dialog (FR-24) | ☐ |
| M6.2 | Tap **Show my Shortcuts** → allow on the Mac | Your Shortcuts list appears | ☐ |
| M6.3 | Pick one, set an emoji, **Add** | A keycap with the emoji at 34pt where the icon would be | ☐ |
| M6.4 | Tap it — use a Shortcut that shows a notification | The notification fires on the Mac (FR-13 acceptance) | ☐ |
| M6.5 | **Deny** Automation instead (System Settings → Privacy → Automation) | The tab explains the degraded path; app and website tiles keep working (FR-24) | ☐ |
| M6.6 | **Website** tab, type `example.com` | Red 2pt border, "Needs a valid http(s) address", **Add** dimmed but visible | ☐ |
| M6.7 | Correct it to `https://example.com` | Border returns to normal, **Add** enables | ☐ |
| M6.8 | Tap the website tile | That exact URL opens frontmost in the default browser (FR-14) | ☐ |
| M6.9 | A Shortcut whose name contains a quote or backslash | Runs correctly — the name is escaped into the AppleScript literal, not interpolated raw | ☐ |
| M6.10 | Rename a Shortcut on the Mac, then tap its tile | A readable failure in the top bar, not silence | ☐ |

**The sandbox question this milestone turns on.** Shortcuts are driven through Shortcuts
Events with Apple Events — the route PRD §5's entitlement plan chose, since the
`shortcuts` CLI and the Shortcuts database are both out of reach from a sandboxed
process. If M6.2 returns an empty list even after allowing Automation, the entitlement
or the consent prompt is the place to look, not the script. The PRD's risk table already
flags "Shortcuts enumeration inside sandbox" as a verify-in-M6 item.

---

## M7 — Pages & premium · implemented, pending verification

Delivers FR-17 and FR-18. Needs a **StoreKit configuration file**, which I cannot
generate reliably without Xcode:

> Xcode → File → New → File → StoreKit Configuration File. Add an auto-renewable
> subscription with product ID **`com.noso.nosodeck.premium.monthly`**, price $2.99/month,
> and a 7-day free-trial introductory offer. Then set it in the scheme:
> Run → Options → StoreKit Configuration.

| # | Check | Expected | Result |
|---|---|---|---|
| M7.1 | Free tier, swipe to page 2 | Works — two pages are free (D16) | ☐ |
| M7.2 | Free tier, tap **+ Page** on page 2 | Paywall opens; no third page is created (FR-17) | ☐ |
| M7.3 | The paywall, first frame | Full-size ✕ top-left, present immediately. No timer, no countdown, no fake discount | ☐ |
| M7.4 | The price shown | Comes from StoreKit, reading "7 days free, then $2.99/month" | ☐ |
| M7.5 | Buy with a sandbox account | Unlocks immediately and the paywall dismisses itself | ☐ |
| M7.6 | After purchase, **+ Page** repeatedly | Reaches 8 pages, then stops offering more | ☐ |
| M7.7 | Delete the app, reinstall, pair, **Restore purchases** | Premium returns (FR-18) | ☐ |
| M7.8 | **Restore** on an Apple ID that never bought | A plain "No previous purchase found", not a crash or silence | ☐ |
| M7.9 | Build 8 pages on premium, then revoke the subscription in the StoreKit transaction manager | All 8 pages remain and are still usable; only **+ Page** is gated (FR-17: nothing already free is ever locked) | ☐ |
| M7.10 | Airplane mode with premium active | Still premium — the entitlement is cached | ☐ |
| M7.11 | Edit mode, bottom bar | Page strip with per-page buttons, ochre **+ Page**, and **Delete page** (S5) | ☐ |
| M7.12 | **Delete page** | Confirms first, then removes it and its tiles | ☐ |
| M7.13 | Try to delete the only page | Refused — a deck always keeps one page | ☐ |

M7.9 is the one I would not skip: it is the difference between a fair paywall and one
that holds someone's work hostage.

---

## M8 — Recents & emoji · implemented, pending verification

Delivers FR-15 and FR-16.

| # | Check | Expected | Result |
|---|---|---|---|
| M8.1 | Free tier, look left of the grid | A 92pt locked teaser with an ochre "Premium" label | ☐ |
| M8.2 | Tap the teaser | The paywall opens — never a dead tap (FR-16) | ☐ |
| M8.3 | Measure the grid with and without premium | The 4×2 grid is the **same size** either way; the column takes the slack, not the tiles | ☐ |
| M8.4 | Premium, activate three apps on the Mac in order | They appear in that order within 2 s, most recent first (FR-16) | ☐ |
| M8.5 | Activate one of them again | It moves to the top; no duplicate row | ☐ |
| M8.6 | Quit a recent app on the Mac | It drops out of the column | ☐ |
| M8.7 | Look for NosoDeck itself in the column | Never there — the agent excludes itself | ☐ |
| M8.8 | Tap a recents cell | That app activates on the Mac | ☐ |
| M8.9 | Mac menu → **Type emoji from the deck** | The Accessibility prompt appears — and only now, never at launch (FR-24) | ☐ |
| M8.10 | Grant it, focus TextEdit, tap 🎉 on the phone | 🎉 is typed into TextEdit (FR-15) | ☐ |
| M8.11 | Copy something on the Mac, then tap an emoji | After ~1 s your clipboard holds the original text again (FR-15) | ☐ |
| M8.12 | Revoke Accessibility in System Settings, tap 🎉 | 🎉 lands on the clipboard and the Mac shows a "press ⌘V" notification | ☐ |
| M8.13 | With Accessibility off, tap app and website tiles | They still work — only typing degrades | ☐ |

**The known-flaky one.** FR-15 is P1 precisely because synthetic ⌘V behaves
inconsistently across apps: some ignore a posted event, some are picky about timing.
M8.10 in TextEdit is the baseline; if it works there and nowhere else, that is the
feature's real ceiling and the clipboard fallback is what ships. It can be cut without
touching anything P0.

The paste uses virtual key code 9, which is positional rather than character-based, so
it is still ⌘V on Dvorak and AZERTY.

---

## M9 — Polish & submission prep · implemented, pending verification

Delivers FR-5, FR-20, FR-21, FR-22. Submission steps are in `docs/APP-STORE.md`.

| # | Check | Expected | Result |
|---|---|---|---|
| M9.1 | Tap a tile | A rigid haptic, once (FR-21) | ☐ |
| M9.2 | Pair successfully | A success haptic; a wrong PIN gives an error haptic alongside the shake | ☐ |
| M9.3 | Anything else — page swipes, edit mode, settings | **No** haptic. Two events only, by design | ☐ |
| M9.4 | Leave the deck open and connected past the screen-lock interval | Screen stays awake (FR-21) | ☐ |
| M9.5 | Disconnect the Mac and wait | Screen sleeps normally — a dead deck has no claim on the battery | ☐ |
| M9.6 | Open Settings and wait | Screen sleeps normally; the idle timer is deck-only | ☐ |
| M9.7 | Settings → **Keep this iPhone awake** off | Takes effect at once and survives relaunch | ☐ |
| M9.8 | Settings screen in landscape | Fits on one screen — **no scrolling** (S7) | ☐ |
| M9.9 | Settings → **Unpair** | Confirms, then unpairs; reconnecting needs the PIN (FR-5) | ☐ |
| M9.10 | Settings → Permissions row | Reads "N of 3 granted" and tracks reality | ☐ |
| M9.11 | Settings → **Emoji insertion** off | The emoji strip disappears from the deck; everything else is unaffected | ☐ |
| M9.12 | Mac menu → **Open at login**, then reboot | The menu-bar icon is there without launching anything (FR-20) | ☐ |
| M9.13 | macOS asks for approval instead | The menu says so rather than looking broken | ☐ |
| M9.14 | System Settings → Login Items, turn NosoDeck off | The menu toggle reflects it — status is read live, not remembered | ☐ |
| M9.15 | Relaunch the phone app with a Mac already paired | Onboarding is skipped entirely (FR-22) | ☐ |
| M9.16 | Delete and reinstall the phone app | Onboarding returns | ☐ |

### What is deliberately not in v1

Recorded so none of it reads as an oversight: light mode and portrait are undesigned;
the macOS popovers use native conventions rather than the Hardware language; the
onboarding QR is a placeholder. All four are in `docs/APP-STORE.md` as decisions to
confirm, not bugs to fix.

---

## After the first successful build

Once `swift test` passes and both apps compile, work back through M0 → M9 in order. The
milestones build on each other, so an early failure will usually explain several later
ones. Send back verbatim errors — for code that has never been compiled, the first
hundred lines of compiler output are worth more than any description of what it
should do. See `docs/PRD.md` §7 for the
milestone list and each one's stated verification method.
