# Pulse for iPhone

Native AVPlayer playback with a persistent WKWebView for the existing Pulse interface.
The playback queue, 3-second equal-power crossfade, lock-screen controls, audio session
and listening-history requests run natively, independently of JavaScript background suspension.
The web deployment and existing accounts/storage are not migrated or reset.
Sign in to your existing Pulse account inside the app; Safari and the app have separate sessions.

## Build without a Mac

Open the repository's **Actions → iOS app**. Each change under `ios/` builds on a GitHub macOS runner.
Download `Pulse-iPhone-unsigned` from a successful run and extract `Pulse-unsigned.ipa`.
This artifact is NOT signed and cannot be installed by tapping it in Safari.

For a free Apple ID, use [AltStore Classic for Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
to sign and install the IPA on your own iPhone. Free signatures expire after 7 days;
refresh them through AltServer on Windows. Follow AltStore's instructions for Developer Mode.
Enter Apple credentials only in the signing tool, never in a GitHub issue, repository or chat.
TestFlight distribution instead requires Apple Developer Program membership and signing setup.

## Physical iPhone acceptance checks

Cloud compilation does not verify real-device background behavior. Check on your iPhone:

1. Sign in to the existing account; verify library and playlists match the website.
2. Turn on DJ in settings; play two tracks longer than 20 seconds. Listen to a full automatic transition.
3. Lock the screen and repeat; then use lock-screen next/pause/seek.
4. Test headphones disconnect and a phone call: playback must pause without forced resuming.
5. Return after 30 seconds of listening; verify history on a second device.
6. Test unavailable network and a stale private URL; no lost account or music data.

DJ is an equal-power crossfade, not beat matching or a trained AI model.
Native EQ is not implemented in this initial shell; the web EQ remains for desktop.
