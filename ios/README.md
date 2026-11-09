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
next sync. Offline audio downloads are not included. Native profiles, friends, chats,
synchronized lyrics and a ten-band audio equalizer are included in version 1.3.

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

## Mac icon and Touch Bar

The Mac icon has its own rounded artwork with transparent padding for macOS 14/15.
The iPhone icon remains full-bleed artwork, masked by iOS. The icon check validates
transparent corners for all ten generated Mac representations.

Touch Bar controls attach to the app window: previous, play/pause, next, favorite
and volume. Play can start the loaded library when no track is selected. Favorites
are available after login. Transport state and volume stay in sync with the app.
Automated AppKit tests check window attachment, control availability, restoration
and volume routing; physical Touch Bar hardware remains a device check.

## Version 1.3

Profiles, photo avatars, display names, bios, colors, symbols, invite links and QR
codes use the same community API as the website. Friends and chats poll every four
seconds only while their screen is open and the app is active. History pagination,
2000-character messages, request acceptance and session separation are preserved.

Lyrics use the existing server providers and support LRC line timing, seeking and
manual scrolling. iPhone mini-player and full-player artwork accept horizontal
track swipes; vertical and short drags are ignored. Motion respects both system
Reduce Motion and the app preference.

The equalizer uses an MTAudioProcessingTap on AVPlayer's file-based audio tracks.
Ten peaking filters process Float32 PCM; disabled/neutral settings bypass DSP.
The render callback uses preallocated filter state and a non-blocking configuration
snapshot. Presets provide conservative bass, vocal, warm, rock, electronic, acoustic
and low-volume balances; there is no single best preset for all headphones.

Now Playing artwork shares the same image resolver as the interface, with a bundled
fallback and metadata updates for Lock Screen and Dynamic Island. Physical iPhone
checks are required for background audio, system surfaces, audio routing and gestures.

## Version 1.4

Search lives in its own tab and includes artists and their catalogs. Friends and
chats are reached from the profile. Enhanced LRC preserves word timestamps and
repeated-line offsets; ordinary line-only LRC uses labeled, estimated word timing.
Only the current line renders word fill at 30 Hz. The swipe deck follows the
finger, reveals the adjacent queue item and springs back on rejected drags.

The vinyl scales to a live low-frequency PCM envelope independently of the EQ.
Its animation respects Reduce Motion; meter polling stops while the app is inactive.
Playback, beat and library observables remain separate.

The DJ playlist analyzes up to sixteen files locally with AVAudioFile: tempo via
onset autocorrelation, RMS energy, bass balance and zero-crossing brightness.
A nearest-neighbor recommender builds a sound-compatible queue. This is local
signal analysis and feature matching, not a remote generative AI service. BPM is
approximate and tracks retain their original pitch and speed. Failed or oversized
files are skipped, temporary audio is deleted, and features are cached on disk.

DJ transitions use equal-power fades with per-item bass handoff, filter sweeps or
an echo delay. The render callback uses preallocated channel state and delay memory.
The next stream starts before the outgoing track ends, and fades wait for buffering.
Normal playback keeps its existing simple crossfade. Like/bookmark remote commands
toggle the same cloud favorite state as the app; iOS decides which system surfaces
expose those commands. No custom Live Activity is claimed.
