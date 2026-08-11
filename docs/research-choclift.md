# Research: ChocLift and the scope for our macOS/iOS deck app

*Compiled 2026-08-11 from the App Store listing, Product Hunt, the maker's posts, and
third-party reviews (choclift.com itself was unreachable from the research environment).*

## What ChocLift is

ChocLift ("choclift: Workflow Sweetener") is a free iOS + macOS app pair by indie
developer Phil Traut (launched early 2026). The iPhone becomes a "third interface"
for the Mac — alongside keyboard, trackpad, and mouse — shaped like a chocolate bar
of tappable tiles. Tapping a tile on the iPhone executes an action on the Mac.

**Connectivity:** both devices on the same Wi-Fi network; pair once via a PIN shown
on the Mac and entered on the iPhone; pairing is remembered. All actions execute
locally on the Mac through the companion app — no cloud. The iPhone app is purely a
touch remote and does not control iPhone apps.

## ChocLift's complete capability list

- **App launcher deck** — pin favorite Mac apps as tiles; one tap opens/switches;
  swipe to close apps.
- **App Time Travel** — scrollable timeline of recently opened Mac apps; pin favorites.
- **Apple Shortcuts triggers** — any Shortcut as a tile with custom emoji labels.
- **Website bookmarks** — named URLs, one tap opens on the Mac.
- **Window gestures** — two fingers up = maximize, two fingers down = minimize;
  four-finger "grab and throw" copy/paste via clipboard.
- **Emoji Bar** — up to 64 emojis across 8 slides; tap to insert into active Mac text.
- **Pages** — up to 8 swipeable pages of tiles.
- **Polish** — haptics, icon animations, prevents iPhone auto-lock during use.
- **Platforms** — iOS 18+, macOS 14+, visionOS 26.
- **Monetization** — free core; "Added Sugar" subscription/one-time purchase (7-day
  trial) unlocks multiple pages, App Time Travel, future premium features.

**Gaps (what ChocLift does NOT do):** two-way status display (tiles show no live
state), media/volume control, window arrangement beyond min/max, text macros, system
stats, multi-Mac switching, Stream Deck-style live-tile feedback.

## Enhanced scope proposal (tiers)

### Tier 1 — Parity baseline
1. iPhone deck of tiles → launch/activate/quit Mac apps
2. Pairing over local network (Bonjour discovery + PIN, remembered devices)
3. Apple Shortcuts as tiles; URL bookmarks as tiles
4. Recent-apps timeline; multiple swipeable pages; reorderable grid
5. Window gestures (minimize/maximize/hide), clipboard push/pull
6. Emoji/snippet insertion into the Mac's active text field

### Tier 2 — "Live deck" differentiators (bidirectional)
7. Real-time tile status: running indicator, frontmost highlight, badge counts —
   Mac streams state changes to the phone
8. Two-way toggles reflected on both screens instantly: Do Not Disturb, mic mute,
   dark mode, custom user status (Available/Busy/Recording)
9. System control tiles: volume, media play/pause/next with Now Playing mirrored,
   brightness, lock screen, sleep, screenshot
10. Window management: halves/quarters snapping, move to display/Space
11. Live system-monitor cells: CPU, memory, battery, network
12. User-defined shell/AppleScript action tiles (with confirmation guardrails)

### Tier 3 — Beyond
13. Multi-Mac support with quick switching
14. Profiles/context switching — deck auto-swaps with the Mac's frontmost app
15. macOS menu-bar UI for editing the deck on the Mac side
16. iPad grid layout; Apple Watch mini-deck
17. Peer-to-peer fallback transport when devices aren't on the same Wi-Fi

## Proposed architecture sketch

Swift Package with three parts:
- **DeckKit** (shared): deck/page/tile/action models, Codable protocol messages,
  versioned message schema. Cross-platform, unit-testable on Linux.
- **macOS agent**: menu-bar app; `Network.framework` TLS listener advertised via
  Bonjour; executors using `NSWorkspace`, Accessibility API, `shortcuts run`,
  AppleScript/ScriptingBridge; state observers streaming app/system events.
- **iOS app**: SwiftUI deck grid; Bonjour browser; bidirectional session with
  state subscription; haptics.

Pairing = PIN → key exchange → pinned TLS identity. Fully local, no cloud.

## Key risks to resolve before building

- macOS Accessibility/Automation permission prompts (window control, paste).
- Mac App Store sandbox forbids much of Tier 2 → likely direct distribution
  (Developer ID + notarization) for the Mac agent.
- Definition of "status" for the user's actual workflow.
- Build/test environment: iOS/macOS app targets require Xcode on a Mac; the shared
  package is the only Linux-testable part.

## Sources

- https://choclift.com/
- https://apps.apple.com/us/app/choclift-workflow-sweetener/id6759246284
- https://www.producthunt.com/products/choclift-workflow-sweetener
- https://www.macitynet.it/choclift-trasforma-liphone-in-deck-di-controllo-per-mac/
- https://chatgate.ai/post/choclift
- https://huntscreens.com/products/choclift
- https://x.com/SpatiallyMe/status/2034323421765505102
