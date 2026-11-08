# Pulse for iPhone and Mac

Native SwiftUI applications sharing the production Pulse API, accounts, D1 database
and R2 audio storage with the website. No web view and no dependency on the custom
domain's certificate. All API and audio requests use the existing HTTPS API host.

## Features

- Existing email/password login, registration and logout; token stored in Keychain.
- Public catalog and personal uploads, search, likes, history and playlists.
- Synchronization on launch, on foreground return, every 30 seconds while running,
  after import and after listening-history saves. Pull to refresh and toolbar refresh.
- Multi-file audio import, SHA-256 duplicate detection, embedded title/artist/album
  metadata and per-file results. Existing 50 MB per-file server limit applies.
- AVPlayer playback, seek, volume on Mac, queue, optional 3-second crossfade,
  system media controls, artwork, and iPhone background audio.
- Private state is cleared on logout; transient network failures retain the session
  and last in-memory library. The app reports failed synchronization rather than
  replacing it with an empty cloud library.

The server remains authoritative. Changes made on another device appear on the
next sync. Offline audio downloads, native equalizer, chats and lyrics are not part
of this release. The website remains available for those existing web features.

## Download personal builds

Open **Actions → Apple apps → latest successful run** in GitHub.

- `Pulse-Mac`: contains a universal `Pulse-Mac.dmg` and `Pulse-Mac.zip` for Intel
  and Apple Silicon, macOS 14 or later. Drag Pulse to Applications. This personal
  build is ad-hoc signed, not notarized; macOS may require approval in
  System Settings → Privacy & Security before opening it. Do not disable Gatekeeper.
- `Pulse-iPhone-unsigned`: contains `Pulse-unsigned.ipa`, iOS 17 or later.
  An unsigned IPA cannot be installed by tapping it. Use a personal signing tool
  such as AltStore Classic/AltServer, or open the project in Xcode, select your
  Personal Team and run on your connected iPhone. Free signing has renewal limits;
  consult Apple's current Personal Team terms. Never share Apple credentials in chat.

App Store/TestFlight release requires Apple Developer distribution signing and is
separate from these personal builds. No signing passwords or certificates are
stored in this repository or workflow.

## Build locally with Xcode

Install Xcode and XcodeGen. From the repository root:

```sh
node scripts/prepare-ios-icons.mjs
cd ios
xcodegen generate
open Pulse.xcodeproj
```

Choose scheme `Pulse` for iPhone or `PulseMac` for macOS. The CI workflow builds
both platforms, runs shared model/state tests on macOS, and emits personal builds.

## Device acceptance checks

1. Sign in with the website account on both apps. Compare uploaded tracks,
   likes and playlists with the website.
2. Upload a new audio file on the site. Return to the app or wait 30 seconds;
   confirm it appears. Repeat importing a file in the app, then refresh the site.
3. Like a track and create a playlist on one device. Confirm the second device
   receives them. Sign out and verify personal state disappears.
4. Play music, seek, pause and skip from the app and system controls. Lock the
   iPhone screen and check uninterrupted playback and listening history.
5. Test headphone disconnection, incoming calls, network loss and recovery.
   Confirm a network failure does not delete the account's library.

Cloud builds do not replace physical-device checks of background audio, imports,
Keychain persistence or installation signing.

## Native design and rendering

The native interface follows the website's palette and Soledago headings, with a
custom sidebar on Mac, bottom navigation on iPhone, home cards, artist collections
and an expanded iPhone player. Playback clock updates are observed by the transport
only, rather than invalidating the library four times per second. A regression
test verifies 120 transport ticks produce no library object-change notifications.

Artwork uses a shared coalescing cache, a maximum of two concurrent lookup jobs,
512-pixel decoded thumbnails, a 64 MB decoded-image cache and a 100 MB disk cache.
The website artwork index is bundled at build time; missing images use the existing
metadata API. File reading and SHA-256 hashing run off the main actor during imports.

These are structural optimizations. Device frame-rate and energy measurements
remain physical-device checks; no battery-life or frame-rate benchmark is claimed.
