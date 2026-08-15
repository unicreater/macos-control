# NosoDeck — Design Brief

## What It Is

NosoDeck turns an iPhone into a live control deck for macOS. The phone sits beside the keyboard and gives one-tap access to Mac apps, AI coding sessions, voice dictation, and system gestures — all over local Wi-Fi with no cloud service.

## Target User

Developer/power user with multiple apps, terminal sessions (Warp), and AI tools (Claude, ChatGPT) running simultaneously across multiple desktops. Uses the phone as a "third input" alongside keyboard and trackpad.

## Platform & Constraints

- **iPhone**: iOS 17+, landscape-primary (portrait supported), dark mode only
- **Mac**: macOS 14+, menu-bar agent (no Dock icon)
- **Connection**: Bonjour discovery, TLS pre-shared key, local network only
- **Screen sizes**: iPhone 15 Pro (852×393pt landscape) to iPhone 17 Pro Max (932×430pt landscape)

---

## Screens & Current State

### 1. Onboarding (2 steps)
- Step 1: "Install NosoDeck on your Mac" — title + body + QR card + CONTINUE button
- Step 2: "Pair your iPhone" — local network permission pre-prompt
- Only shown on first launch; skipped if previously paired

### 2. Device Discovery
- List of Macs found on local network via Bonjour
- Each row shows Mac name, connection status
- Auto-connects to last paired Mac (skips this screen)

### 3. PIN Entry
- Centered layout, 6 digit cells (64×72pt) grouped 3+3
- Phone connects to Mac, Mac shows PIN in a floating dark window
- Error state: red inline banner with attempts remaining
- Cancel button to go back

### 4. Main Deck (Primary Screen)
**Top bar:**
- Connection status pill (green dot + Mac name + latency)
- Emoji strip (2 pages of 8, swipeable, customizable via long-press)
- Settings gear button (44×44pt)

**Grid:**
- 4×2 landscape / 2×4 portrait, 8 tiles per page
- Swipe left/right to change pages
- Page pips at bottom + "AI" pill for AI sessions page + "+ PAGE" button

**Tiles (app tiles):**
- Gradient dark background (#1E1E1E → #161616)
- 1px border (#2A2A2A, mint glow when frontmost)
- 72×72pt app icon (real macOS icons from agent, rounded corners 16pt)
- Mono uppercase label below (11pt)
- Running LED: mint dot with glow halo (top-right)
- Frontmost: mint border glow around icon
- Press: spring scale to 0.97 + brightness shift
- Website tiles: show favicon via Google's service
- Empty slots: dashed border + "ADD" + plus.circle icon

**Voice tile:**
- Sits in first empty slot on page 1
- Mic icon (36pt), "VOICE" label
- Recording: red tint, pulsing ring, "LISTENING..." label
- Tapping opens fullscreen overlay

**Bottom bar:**
- "✨ AI" capsule pill (links to AI Sessions page)
- Page pips (capsules, active = white)
- "+ PAGE" ochre button

### 5. AI Sessions Page
**Header:** "AI SESSIONS" + active count
**Grid:** Same 4×2/2×4 as deck, up to 8 session tiles

**Session tiles:**
- Same card style as app tiles (gradient + border)
- Real app icon (48×48pt) from catalog
- Session label: project name for Warp, conversation title for Claude
- Status LED (top-right): mint = busy, ochre = done, gray = idle
- Status detail text: "Running", "sourcekit-lsp, swift", "Needs input", "IDLE"

**Detected sessions:**
- **Warp**: Each terminal tab = 1 tile. Shows project directory name. Status from process tree (caffeinate = running, no descendants = needs input)
- **Claude Desktop**: Each conversation from sidebar. Shows title (e.g. "Loop implementation"). Status from AX prefix ("Running" vs "Idle")
- **ChatGPT**: Single tile (AX tree not accessible)

### 6. Voice Overlay (Fullscreen)
- Dark overlay (80% opacity) covering entire app
- Red "LISTENING" indicator
- Live transcript (22pt, centered, updates in real-time)
- "SEND TO MAC" mint capsule button (always visible, dimmed until text appears)
- "Close" text button to dismiss
- Sends cleaned text (fillers removed) to Mac clipboard + synthetic Cmd+V

### 7. Settings
- Fits one screen in landscape
- Device card (name + latency + UNPAIR)
- Emoji toggle, keep awake toggle
- Premium card (2 free pages, 8 with premium)
- Permissions summary

### 8. Edit Mode
- Long-press any tile → tiles tilt ±1°, red minus badges appear
- Drag to reorder, tap minus to remove
- "DONE" button top-right (mint, 44pt)
- Bottom: page strip with delete page option

### 9. Add Tile Sheet
- Segmented: APPS / SHORTCUTS / WEBSITE
- Search field + results list
- Preview panel with live keycap, label field, slot indicator
- Website: URL field with validation (red border for invalid)

### 10. Paywall
- Full-screen sheet with ✕ top-left
- Free: 2 pages. Premium: 8 pages, recents, themes
- "$2.99/month after 7-day trial"
- No fake urgency

### 11. PIN Window (Mac)
- Floating dark window (360×200pt), center screen
- "PAIRING PIN" header, large monospaced digits (52pt)
- "Enter this on your iPhone" subtitle
- Appears when unpaired phone connects, closes on successful pair

---

## Gestures

| Gesture | Action | Feedback |
|---------|--------|----------|
| 1-finger tap (tile) | Activate/focus app on Mac | Spring scale 0.97 + haptic |
| 1-finger swipe left/right | Change page | Page pips update |
| 1-finger long-press (500ms) | Enter edit mode | Tiles tilt |
| 2-finger swipe up | Maximize frontmost window | Mint badge "MAXIMIZE" + haptic |
| 2-finger swipe down | Minimize frontmost window | Mint badge "MINIMIZE" + haptic |
| 2-finger swipe left | Copy (Cmd+C) | Mint badge "COPY" + haptic |
| 2-finger swipe right | Paste (Cmd+V) | Mint badge "PASTE" + haptic |
| 2-finger double-tap | Copy (alternative) | Mint badge + haptic |
| 2-finger long-press | Paste (alternative) | Mint badge + haptic |

---

## Design Language

**Theme:** "Hardware" — dark, mechanical, keycap-inspired. The deck should feel like a physical control surface.

**Color tokens:**
- `chassis` #111111 — app background
- `surface` #161616 — cards, sheets
- `keycap gradient` #1E1E1E → #161616 — tile background
- `stroke` #2A2A2A — tile borders
- `ink` #E8E8E8 — primary text
- `ink-muted` #8A8A8A — secondary text
- `ink-faint` #6A6A6A — tertiary text
- `mint` #A4D4C5 — state indicator (running, connected, confirm)
- `ochre` #E8B94A — premium gates, "done" session status
- `red` #EF4444 — destructive, recording, errors

**Color rules:**
- Mint = state only (never decorative)
- Ochre = premium or "needs attention"
- Red = destructive or recording
- Color is never the only cue — always paired with shape/text

**Typography:**
- SF Mono: tile labels, status text, meta info (uppercase, tracked)
- SF Pro: headings, body, buttons

**Spacing:** 4/8/12/16/24/34pt scale
**Corner radius:** 6 (badges) / 10 (buttons) / 16 (tiles/cards)
**Touch targets:** 44×44pt minimum everywhere

**Motion:**
- Press: spring(response: 0.2, damping: 0.7)
- State changes: 200ms ease-in-out
- Reduced motion: fade only, no scale/rotation

**Running LED:** 8pt mint circle + 16pt glow halo (top-right of tile)
**Frontmost ring:** 2pt mint strokeBorder + 8pt mint shadow on icon

---

## Features to Design For

1. App tiles with live state (running/frontmost/idle)
2. AI Sessions page with real-time status per session
3. Voice-to-Mac dictation with fullscreen overlay
4. Multi-finger gesture feedback badges
5. Customizable emoji bar (2 pages)
6. Portrait + landscape adaptive layout
7. Website tiles with favicons
8. Edit mode (reorder, remove, add tiles)
9. PIN pairing flow (phone + Mac window)
10. Auto-reconnect (straight to deck on launch)

---

## What Needs Design Attention

1. **AI Sessions page** — current layout is functional but not polished. Session tiles need clearer visual hierarchy between project name, app icon, and status
2. **Voice overlay** — needs more visual polish. Waveform or audio visualization while recording would improve feedback
3. **Tile density** — 8 tiles feels sparse in landscape on larger phones. Consider denser layouts or variable tile sizes
4. **Gesture discoverability** — users don't know about 2-finger gestures. Need onboarding hint or visual affordance
5. **Status indicators** — the mint/ochre/gray LED system works but could be more expressive (animations, progress rings)
6. **Empty states** — first launch with no apps detected, no sessions, disconnected states all need distinct designs
7. **Settings screen** — currently wireframe-level, needs full design
8. **Page management** — adding/removing pages needs smoother UX
9. **Website tile creation** — currently requires typing URLs. Browser tab picker is built but needs UI
10. **Mac PIN window** — functional but plain. Should match the phone's design language
