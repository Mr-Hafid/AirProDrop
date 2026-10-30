# AirProDrop

**English** · [Bahasa Indonesia](README.id.md)

Gesture-driven file transfer between a Mac and an iPhone — like AirDrop, but you fling files across the edge of the screen and watch them glide from one device to the other.

- Drag a file to the edge of your Mac's screen and it flies onto your iPhone.
- Touch and hold a file on your iPhone, flick it toward your Mac, and it opens on the Mac.
- Share a photo or file from any iPhone app, tap **AirProDrop**, and it lifts off the screen and flies to your Mac.
- A silver glow lights up the screen edge facing the other device, and a light arc sweeps across both screens as the file crosses over.

No shared Wi-Fi network is needed. Like AirDrop, AirProDrop talks directly between devices over Apple's peer-to-peer Wi-Fi (AWDL) — Wi-Fi just has to be turned on.

## Features

- **Edge drop on Mac** — a menu bar app watches the screen edge next to your iPhone. Drop a file there to send it.
- **Flick to send on iPhone** — long-press a file, then flick it toward the Mac.
- **Send from any app** — a Share Extension puts AirProDrop in the iOS share sheet. Tap it and the file floats over the screen, flies to the Mac and the sheet closes on its own. No extra taps, and the AirProDrop app doesn't have to be open.
- **AirDrop-style visuals** — edge glow, screen-border light that tapers from the center outward, a sweeping silver arc, and a ripple that bends the iPhone's content as the wave passes.
- **Radar pairing** — the iPhone shows a pulsing radar with every nearby Mac. Tap your Mac and it pops up a 6-digit code on its screen; type it on the iPhone, once. After that the devices find and reconnect to each other automatically.
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
| Tools | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |
| Apple Developer account | A paid team is needed for the App Group shared between the app and its Share Extension |

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

### 2. Use your own signing team

`project.yml` is set up with the maintainer's team. If you build with a different Apple Developer account, change it to your own Team ID before building:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: YOUR_TEAM_ID
```

If the bundle IDs or the App Group (`group.com.mrhafid.airpro`) are already taken, change them in `project.yml`, the `.entitlements` properties and `Shared/SharedContainer.swift`. Then run `xcodegen generate`.

### 3. Build and install

The quickest way is the build script. It regenerates the project, installs the Mac app to `/Applications` and installs the iPhone app on the iPhone plugged into your Mac:

```bash
./build.sh          # Mac and iPhone
./build.sh mac      # Mac only → /Applications
./build.sh phone    # iPhone only → the connected iPhone
./build.sh phone achmad   # pick an iPhone by part of its name
```

Before the first iPhone install, plug the iPhone in, tap **Trust This Computer** and turn on **Settings → Privacy & Security → Developer Mode**.

You can also build from Xcode: pick the **AirProDropMac** scheme with **My Mac**, or the **AirProDropPhone** scheme with your iPhone, and press **⌘R**.

On first launch, allow **Local Network** access on both devices, and allow notifications on the Mac. The Mac app has no window; an iPhone icon appears in the menu bar.

### 4. Pair once

1. Open AirProDrop on the iPhone. A radar appears and your Mac shows up on it.
2. Tap your Mac. A small window with a 6-digit code pops up at the top of the Mac's screen.
3. Type the code on the iPhone. The status dot turns green with your Mac's name, and from now on they reconnect automatically.

A code is valid for 2 minutes. After a wrong code the Mac shows a new one; after 3 wrong codes it closes the window and ignores pairing requests for 30 seconds. You can still show a code by hand with **Pair New iPhone…** in the menu bar.

Close the radar with **✕** and bring it back with **Nearby Macs** in the middle of the empty file screen.

### 5. Tell AirProDrop where your iPhone sits

- **Mac:** menu bar → *iPhone sits on the* **Left / Right**
- **iPhone:** `⋯` menu → **Mac on the left / right**

The glow and the send direction follow this setting.

## Usage

**Mac → iPhone**

Drag a file from Finder to the very edge of the screen on the iPhone's side. The edge lights up and the iPhone dims — release to send. You can also use **Send Files…** in the menu bar.

**iPhone → Mac**

Add files with the photo button or **Import from Files**, then touch and hold a file until it lifts and flick it toward the Mac.

**From any app (Photos, Files, Safari, …)**

1. Tap **Share** and choose **AirProDrop** in the app row.
2. The file floats over the screen and, as soon as the Mac is connected, flies toward it on its own. You can also flick it yourself.
3. The sheet closes when the file has arrived.

To keep AirProDrop right next to AirDrop, scroll the app row to the end, tap **More → Edit** and move AirProDrop to the front. Up to 20 photos, videos or files can be sent at once.

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
- **Device identity:** each device creates its own Ed25519 identity key on first launch. On iOS it is kept in the Keychain under the App Group, so the app and its Share Extension present the same identity and the Share Extension never needs to pair.
- **Requesting a code:** tapping a Mac on the radar sends a short code request. The Mac opens its pairing window and shows the code, then the iPhone pairs on a new connection with the code you typed.
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
  SharedContainer.swift        App Group storage shared by the iPhone app and its extension
  GlassStyles.swift            Liquid Glass panel styles and panel transition (iOS)
Mac/                           Menu bar app, overlay window, edge drop target, pairing code window
Phone/                         iPhone app, file library, radar pairing UI, snapshot container
ShareExtension/                Share sheet extension that sends files straight to the Mac
build.sh                       Builds and installs the Mac and iPhone apps
```

## Limitations

- **The iPhone app must be open in the foreground.** iOS suspends third-party apps in the background, so unlike AirDrop, AirProDrop can't receive while the app is closed.
- **The drop strip on the Mac is 4 px wide.** If an external display is arranged on the same side as the iPhone, the cursor passes onto that display instead of stopping at the edge.
- **Only Finder files are accepted on the Mac.** Dragging straight out of Photos or a browser (file promises) isn't supported yet.
- **The Mac desktop doesn't ripple.** Distorting other apps' windows would need Screen Recording permission, so the Mac shows the glow and arc without bending what's behind them.
- **The share sheet has to stay open until the file arrives.** iOS stops a Share Extension as soon as it closes, so AirProDrop only closes it after the transfer is done. For photos over AWDL this takes a second or two.
- **The transparent share overlay relies on undocumented behavior.** It works on iOS 26, but a future iOS may show a plain sheet instead. Sending still works either way.
- **One active connection per Mac.** Several iPhones can be trusted, but the Mac talks to the most recently connected one at a time.
- **The Mac app is signed ad hoc.** Its keys are kept in UserDefaults, macOS may ask for notification permission again after a rebuild, and other Macs show an "unverified developer" warning. Signing with a Developer ID certificate and notarizing would fix all three.

## License

Copyright (C) 2026 Achmad Hafid Supriyadi (Mr Hafid)

AirProDrop is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

AirProDrop is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the [LICENSE](LICENSE) file for the full text.

If you distribute a modified version, you must release its source code under the same license.
