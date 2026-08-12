# App Store submission checklist

Two products, two App Store Connect records, one shared privacy story. Nothing here is
done — this is the list to work through once the device verification in `docs/VERIFY.md`
passes.

## Blocking on the owner

- [ ] **Bundle-ID root.** Both targets ship the placeholder `com.noso.nosodeck`
      (`…​.ios`, `…​.mac`). Replace it in both `project.yml` files with your
      developer-account domain, then regenerate. This is the one open item the PRD has
      carried since M0.
- [ ] **`DEVELOPMENT_TEAM`.** Deliberately absent from both specs. Set it in Xcode or a
      local `.xcconfig`.
- [ ] **Subscription product.** Create `com.noso.nosodeck.premium.monthly` in App Store
      Connect: auto-renewable, $2.99/month, with a 7-day free-trial introductory offer
      (D17). The paywall reads price and trial length from StoreKit, so the copy follows
      whatever you configure.

## Privacy

The honest version is short, which is the advantage of building it this way.

- [ ] **Data collection: none.** No analytics, no accounts, no third-party SDKs, no
      network traffic beyond phone ↔ Mac on the local network. Answer App Store
      Connect's privacy questionnaire accordingly — "Data Not Collected" for every
      category.
- [ ] **Privacy strings**, already in the generated Info.plists — check the wording
      still reads well before submitting:
      - iOS `NSLocalNetworkUsageDescription`, `NSBonjourServices` (`_nosodeck._tcp`)
      - macOS the same, plus `NSAppleEventsUsageDescription` for Shortcuts
- [ ] **Accessibility** is requested only when the user turns emoji typing on, and is
      never a precondition for anything else. Worth stating in the review notes.

## Mac sandbox and entitlements

Generated from `apps/NosoDeckMac/project.yml`; confirm in Signing & Capabilities:

- [ ] App Sandbox on
- [ ] Incoming Connections (Server) — the deck listener
- [ ] Outgoing Connections (Client)
- [ ] Apple Events — Shortcuts, via Shortcuts Events

## Review notes to write

App Review is the known risk for local-network control apps (PRD §8). Follow the
ChocLift precedent:

- [ ] State plainly that the app is local-network only, with no cloud service and no
      account.
- [ ] Explain that the iPhone app is useless without the Mac app, and give reviewers a
      way to try both — a **demo video** of pairing and a tile tap is the single most
      useful attachment.
- [ ] Note that the Mac app is a menu-bar agent with no Dock icon and no main window,
      so it will not appear where a reviewer first looks.
- [ ] Explain the PIN pairing flow, since a reviewer with only one device cannot pair.

## Assets still to make

- [ ] App icons for both apps
- [ ] Screenshots — landscape, which App Store Connect treats differently from portrait
- [ ] The real QR code and `nosodeck.app/mac` link on onboarding step 1 (currently a
      placeholder square, per the design handoff's Assets note)

## Known gaps to decide on before shipping

These are recorded rather than fixed, and each has a fuller entry in `docs/VERIFY.md`:

- [ ] **Light mode is undesigned.** v1 ships dark-appearance only, declared via
      `UIUserInterfaceStyle`. Check this against current HIG expectations.
- [ ] **Portrait is undesigned.** The deck is landscape-locked with no rotate hint yet.
- [ ] **macOS menu-bar surfaces** are native menus, not the Hardware visual language —
      the handoff leaves them undesigned.
- [ ] **PIN brute-force window.** A six-digit PIN used as a TLS pre-shared key is
      offline-attackable by someone capturing the pairing handshake at the moment of
      pairing. Mitigated by single use and rotation. Decide whether to harden before
      submission (VERIFY.md §M2).
