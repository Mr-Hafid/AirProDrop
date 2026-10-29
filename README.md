# AirProDrop

**English** · [Bahasa Indonesia](README.id.md)

Gesture-driven file transfer between a Mac and an iPhone — like AirDrop, but you fling files across the edge of the screen and watch them glide from one device to the other.

- Drag a file to the edge of your Mac's screen and it flies onto your iPhone.
- Touch and hold a file on your iPhone, flick it toward your Mac, and it opens on the Mac.
- A silver glow lights up the screen edge facing the other device, and a light arc sweeps across both screens as the file crosses over.

No shared Wi-Fi network is needed. Like AirDrop, AirProDrop talks directly between devices over Apple's peer-to-peer Wi-Fi (AWDL) — Wi-Fi just has to be turned on.

## Features

- **Edge drop on Mac** — a menu bar app watches the screen edge next to your iPhone. Drop a file there to send it.
- **Flick to send on iPhone** — long-press a file, then flick it toward the Mac.
- **AirDrop-style visuals** — edge glow, screen-border light that tapers from the center outward, a sweeping silver arc, and a ripple that bends the iPhone's content as the wave passes.
- **One-time pairing** — pick your Mac from the list of nearby Macs and enter the 6-digit code it shows, once. After that the devices find and reconnect to each other automatically whenever the app is open.
- **Encrypted, with forward secrecy** — every connection uses a fresh key exchange, so even a leaked key can't decrypt earlier transfers.
- **Multiple trusted devices** — trust several iPhones or Macs and forget any of them at any time.
- **Received files**
  - Mac: saved straight to `~/Downloads`, like AirDrop, and opened automatically.
  - iPhone: kept in the app's file grid, with Quick Look preview, Share and Delete.

## Requirements

| | Minimum |
|---|---|
| Mac | macOS 14 Sonoma |
| iPhone | iOS 17 |
| Xcode | 16 or later (built with Xcode 26) |
| Tools | [XcodeGen](https://github.com/yonaskolb/XcodeGen) — only if you change `project.yml` |

Both devices need Wi-Fi turned on. They do not need to be on the same network.

## Getting started

### 1. Open the project

```bash
git clone https://github.com/Mr-Hafid/AirProDrop.git
cd AirProDrop
open AirProDrop.xcodeproj
```

If you edit `project.yml`, regenerate the project first:

```bash
brew install xcodegen
xcodegen generate
```

### 2. Run the Mac app

1. Select the **AirProDropMac** scheme and **My Mac**, then press **⌘R**.
2. An iPhone icon appears in the menu bar. There is no window; the app lives there.
3. Allow **Local Network** access if macOS asks.

### 3. Run the iPhone app

1. Select the **AirProDropPhone** target → **Signing & Capabilities** → choose your **Team**.
2. Connect your iPhone, select the **AirProDropPhone** scheme, and press **⌘R**.
3. Allow **Local Network** access when iOS asks.

### 4. Pair once

1. Click the menu bar icon on your Mac. The first time, a 6-digit pairing code is already shown; later, click **Pair New iPhone…** to show one. Each code is valid for 2 minutes.
2. On your iPhone, choose your Mac from **Nearby Macs** and enter the code.
3. The status dot in the iPhone app turns green with your Mac's name. From now on they reconnect automatically whenever the iPhone app is open.

After 3 wrong codes the Mac stops accepting new devices until you click **Pair New iPhone…** again.

### 5. Tell AirProDrop where your iPhone sits

- **Mac:** menu bar → *iPhone sits on the* **Left / Right**
- **iPhone:** `⋯` menu → **Mac on the left / right**

The glow and the send direction follow this setting.

## Usage

**Mac → iPhone**

Drag a file from Finder to the very edge of the screen on the iPhone's side. The edge lights up and the iPhone dims — release to send. You can also use **Send Files…** in the menu bar.

**iPhone → Mac**

Add files with the photo button or **Import from Files**, then touch and hold a file until it lifts and flick it toward the Mac.

## How it works

```
┌──────────────── Mac (menu bar app) ────────────────┐      ┌──────────── iPhone app ────────────┐
│ Edge drop strip ─┐                                 │      │ File grid ─ long-press + flick     │
│                  ▼                                 │      │              │                     │
│           MacCoordinator ── NWListener (Bonjour) ◄─┼─AWDL─┼─► NWBrowser ─ PhoneCoordinator     │
│                  │       X25519 + Ed25519          │      │              │                     │
│   Overlay window (glow, arc, flying card)          │      │  Glow, arc, content ripple, card   │
└────────────────────────────────────────────────────┘      └────────────────────────────────────┘
```

- **Discovery & transport:** `Network.framework` with Bonjour (`_airpro._tcp`) and `includePeerToPeer = true`, which enables AWDL — the same peer-to-peer Wi-Fi link AirDrop uses.
- **Device identity:** each device creates its own Ed25519 identity key on first launch (Keychain on iOS).
- **Pairing:** the devices exchange ephemeral X25519 keys, then check the 6-digit code bit by bit with commitments (the same idea as Bluetooth passkey pairing). Someone in the middle gets a single guess with a one-in-a-million chance and can't brute-force the code offline. Once the code matches, each device stores the other's identity key as trusted.
- **Reconnecting:** every connection runs a fresh X25519 key exchange signed with both identity keys, so a device pretending to be your Mac or iPhone is rejected, and each session has its own keys (forward secrecy).
- **Encryption:** frames are sealed with ChaCha20-Poly1305 using CryptoKit.
- **Protocol:** length-prefixed frames carrying JSON control messages (hover, transfer start, pairing), plus 256 KB file chunks.
- **Visuals:** Metal shaders through SwiftUI's `colorEffect` and `layerEffect`. On iPhone, the content ripple runs on a snapshot of the screen, because shaders can't run directly on UIKit-backed views.

## Project structure

```
project.yml                    XcodeGen spec for both targets
Shared/                        Code used by both apps
  PeerConnection.swift         Framing, control messages, chunked file transfer
  TransportParameters.swift    TCP NWParameters with peer-to-peer enabled
  SecureHandshake.swift        Pairing and reconnect handshakes
  SessionCipher.swift          ChaCha20-Poly1305 frame encryption
  DeviceIdentity.swift         Per-device identity key
  TrustStore.swift             Trusted devices
  SecureStore.swift            Keychain / UserDefaults storage
  ControlMessage.swift         Messages exchanged between devices
  TransferStage.swift          Glow state and flying-card animation
  EdgeGlow.swift               Glow view and content ripple modifier
  AirDropGlow.metal            Glow, border light, sweeping arc and ripple shaders
  FlyingCard.swift             Thumbnail card views
  ThumbnailRenderer.swift      Quick Look thumbnails and encoding
Mac/                           Menu bar app, overlay window, edge drop target
Phone/                         iPhone app, file library, pairing UI, snapshot container
```

## Limitations

- **The iPhone app must be open in the foreground.** iOS suspends third-party apps in the background, so unlike AirDrop, AirProDrop can't receive while the app is closed.
- **The drop strip on the Mac is 4 px wide.** If an external display is arranged on the same side as the iPhone, the cursor passes onto that display instead of stopping at the edge.
- **Only Finder files are accepted on the Mac.** Dragging straight out of Photos or a browser (file promises) isn't supported yet.
- **The Mac desktop doesn't ripple.** Distorting other apps' windows would need Screen Recording permission, so the Mac shows the glow and arc without bending what's behind them.
- **One active connection per Mac.** Several iPhones can be trusted, but the Mac talks to the most recently connected one at a time.
- **On the Mac, keys are stored in UserDefaults** because the development build is signed ad hoc. Moving them to the Keychain needs a proper signing team.

## License

No license has been chosen yet. All rights reserved until one is added.
