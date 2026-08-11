# NosoDeck — Scope Decisions

Product: **NosoDeck** — an iPhone deck that live-controls a Mac (Steam-Deck-style app
tiles: tap a tile, that app comes to the front on the Mac; tiles reflect live state).

All decisions recorded from the /grill-me session with the product owner.

| # | Question | Decision | Rationale | Date |
|---|----------|----------|-----------|------|
| 1 | Audience & success | **Public App Store product** | Built for strangers from day one: onboarding, review compliance, monetization. | 2026-08-11 |
| 2 | Mac distribution model | **Sandboxed MAS core + non-sandboxed helper (long-term)** | MAS reach without permanently giving up power features; helper hosts what the sandbox forbids. | 2026-08-11 |
| 3 | Helper timing | **v1 ships MAS-only; helper in v1.1** | Everything in v1 scope is sandbox-legal; helper (window control, shell tiles, system toggles) deferred but architected for. | 2026-08-11 |
| 4 | v1 scope tier | **Tier 1 parity + live status** | Launcher parity plus the differentiator: live running/frontmost tile state streamed Mac→phone. | 2026-08-11 |
| 5 | Meaning of "status" | **Steam-Deck-style app tiles** | Tiles are apps; tapping brings the app to front on the Mac; tile shows live app state. Not a status-board/kanban; system toggles & custom statuses deferred. | 2026-08-11 |
| 6 | OS minimums & devices | **iOS 17 + macOS 14, iPhone-first** | ~95% device reach with modern SwiftUI/Observation. iPad uses iPhone layout in v1; true iPad grid later. | 2026-08-11 |
| 7 | Transport | **Bonjour discovery + Network.framework TLS** | Mac advertises service, phone discovers, PIN pairing pins keys, robust reconnects. Local-network only, no cloud. | 2026-08-11 |
| 8 | Monetization | **Free + premium unlock (StoreKit 2 in v1)** | Mirrors ChocLift's proven model; core genuinely useful free. | 2026-08-11 |
| 9 | v1 feature cut | **Shortcuts tiles, URL tiles, recent-apps row, emoji/text insertion — all in** | Full ChocLift parity minus window gestures (helper-dependent, v1.1). | 2026-08-11 |
| 10 | Paywall placement | **Free: 1 page + live deck. Premium: up to 8 pages, recent-apps row, icon themes** | ChocLift-style split; premium is additive, never crippling. | 2026-08-11 |
| 11 | Product name | **NosoDeck** | Owner's choice. Targets: NosoDeck (iOS), NosoDeck for Mac (agent), DeckKit (shared package). Bundle-ID root placeholder `com.noso.nosodeck` until the owner confirms their domain. | 2026-08-11 |
| 12 | Build verification | **Owner builds/runs on their Mac; Claude unit-tests DeckKit on Linux** | Agent environment is Linux: full swift test coverage for DeckKit + syntax checks; app targets verified by owner in Xcode at milestone boundaries, per docs/VERIFY.md. | 2026-08-11 |
| 13 | Deck editing surface (delegated) | **iPhone is the primary editor in v1; Mac agent supplies the installed-app catalog and a read-only status menu** | Delegated to recommendation: keeps v1 UI surface small; Mac-side editing arrives with the v1.1 helper work. | 2026-08-11 |
| 14 | Design language & orientation | **"Hardware" direction (design handoff 2c), landscape-primary iPhone experience** | Accepted design round in `design/handoff/`; dark keycap aesthetic, mint/ochre/red semantic accents, SF Pro + SF Mono. Supersedes the generated teal baseline in `design-system/nosodeck/MASTER.md` (kept as background). | 2026-08-11 |
| 15 | Deck grid | **4×2 = 8 tiles per page, hard maximum; larger devices get larger tiles, never more** | Design handoff "non-negotiable" grid spec. | 2026-08-11 |
| 16 | Free tier size | **Free = 2 pages** (supersedes D10's 1 page) | Design round judged 1 page too thin to demonstrate value; premium remains 8 pages + recents + themes. | 2026-08-11 |
| 17 | Premium price | **$2.99/month after 7-day free trial** | Set during design round (paywall S8); no fake urgency, full-size close from first frame. | 2026-08-11 |
| 18 | Recents presentation | **92pt left column with 4 cells (premium); locked teaser for free users** | Landscape slack absorbs the column without shrinking the grid. | 2026-08-11 |

## Non-goals for v1 (explicitly out)

- Window management gestures/snapping (min/max, halves/quarters) — requires Accessibility API → helper, v1.1
- Shell / AppleScript action tiles — non-sandboxable → helper, v1.1
- System toggles (DND, dark mode, mic mute), media controls, system monitors — v1.1+
- Multi-Mac pairing/switching — v2
- Profiles that follow the frontmost app — v2
- iPad-optimized grid, Apple Watch, visionOS — post-v1
- Peer-to-peer transport fallback (different networks) — v1.1+
- Cloud sync of deck layouts — not planned; local + device-to-device only

## Open items carried into the PRD

- Final bundle-ID domain (needs owner's developer-account domain).
- Premium price point and subscription-vs-one-time — needed before App Store submission, not before code.
- Emoji/text insertion is sandbox-legal but the flakiest v1 feature (pasteboard + synthetic paste); PRD must define its degradation path.
