# Pulse Import Bot (cloud)

Setup: https://pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site/import-bot.html

1. Sign in with a Pulse administrator account.
2. Create a **new** bot using Telegram @BotFather `/newbot`. Paste its token into the HTTPS setup page, never into source, Actions secrets, or a chat.
3. Click “Привязать мой Telegram”, open the generated link, press Start.
4. Send `/artist Гуф` or `https://tunemir.com/artist/guf/`. `/status`, `/cancel`, `/retry` manage imports.

The existing Mini App bot and TELEGRAM_* secrets are independent. Setup refuses a bot with another webhook. Tokens are AES-GCM encrypted in D1 using the production secret IMPORT_MASTER_KEY. Only the paired private Telegram account can submit jobs. Only Pulse administrators can configure the integration. Job leases contain no account or Telegram credentials.

Telegram webhook and durable D1 queue run on the existing Pulse hosting. The public GitHub repository's `Pulse Import Bot` workflow checks every five minutes (offset from the hour), processes jobs on Linux, and uploads into existing Pulse R2/catalog storage. Mac can be off. No rented server or permanent GitHub PAT is needed. The runner uses GitHub OIDC; the API checks signed RS256 JWTs against GitHub JWKS and pins repository ID, branch, workflow and event. Existing account, music and community data are preserved.

GitHub schedules may be delayed, so five minutes is a polling interval, not an SLA. Public repository schedules are automatically disabled by GitHub after 60 days without repository activity; re-enable in Actions → Pulse Import Bot if that happens. The bot stays available but queued imports wait while Actions is disabled/unavailable. GitHub Actions must be enabled. Storage/hosting and GitHub service limits still apply.

## Sources

TuneMir: exact artist search, artist pagination, individual tracks, fresh public signed MP3 links. The legacy artist scanners follow their public pagination; every audio file is limited to 50 MB. Metadata preserves collaborations. Duplicate audio is identified by SHA-256; admin-removed tracks are not restored. No login/captcha bypass.

Other public links use yt-dlp generic/provider support, with ffmpeg for MP3 conversion. Support depends on the source. The runner installs pinned yt-dlp only when needed; all downloader traffic goes through a public-address-only local proxy. Track errors are counted; partial imports remain available and can be retried. Private IPs, local URLs, non-HTTP schemes, credentials and arbitrary ports are rejected. No credentials are passed to the extractor.

## Verification

Node 24:

```
node scripts/build-worker.mjs
node scripts/test-import-bot.mjs
node --test import-bot/test.mjs import-bot/open-media.test.mjs
node scripts/test-backend.mjs
node scripts/test-telegram.mjs
```

Tests use in-memory SQLite D1 and mocked R2/Telegram/JWKS; they never publish test music or message a real user. Live source diagnostics are optional: Actions → Pulse Import Bot → Run workflow → probe. They are not run automatically on push.

## Additional sources and artist interpretation

- MuzSo (`one.muzso.net`, bare `muzso.net` normalized to that host): local/remote artist pages, `/music/` and `/controls/` tracks, artist pagination, official public `/api/download/<id>` flow. Some responses are MP4/M4A despite `audio/mpeg`; the worker detects the container and converts locally using ffmpeg, never renames bytes as MP3.
- MuzPace: direct `/mp3/<id>` pages, authoritative data-artist/data-title and fresh player CDN links. Public search currently returns HTTP 403; the bot does not bypass this and falls back to another supported source for artist-name requests. CDN access depends on source availability; failures produce partial/error status, never fake success.
- Free text, commands, quoted names, Unicode spacing, case, punctuation, known aliases, Cyrillic/Latin transliteration and wrong keyboard layout are recognized. Examples: `Гуф`, `GUF`, `/artist «guf»`, `загрузи все песни Гуфа на сайт`, `добавь Гуфа с https://one.muzso.net`. Explicit names such as `All Saints` remain intact.
- Artist identity must match source metadata; ambiguous identities require an exact link. Requests cannot overwrite real credits. Common aliases converge to one spelling; featured artists are retained and deduplicated, repeated artist prefixes are removed from titles. Version/remix text is preserved.
- HTTP downloads have an overall 45-second deadline in addition to size and public-address restrictions.

## Queue recovery / additional platforms

One failed scan no longer ends the runner: errors are persisted and remaining jobs
are processed. The five-minute cron uses the standard `*/5` expression. A D1
heartbeat records actual authenticated worker contact; `/status` and the setup
page distinguish a stalled worker from an empty/failed source. Natural Russian
`отмена`, `стоп`, `статус`, `повтори` work. For ambiguous artist results, `1`, `2`
or `оба` queues the selected previously-offered pages. `бери два` asks which
meaning was intended rather than importing an artist with that phrase as a name.

YouTube links use the extractor in the existing isolated public-only downloader.
Spotify public embed data and Yandex public metadata supply artist/title/duration;
full audio is matched in accessible sources, with YouTube as an additional source.
Protected audio, account/paywall bypasses and 30-second previews are not used.
Albums/playlists expose only the metadata their public embeds provide, with a
truncated flag where completeness cannot be established. Private or inaccessible
collections require a different public link. Known clean/censored/radio editions
are filtered and explicit/uncensored labels preferred. This cannot guarantee that
a mislabeled recording contains no audio edits; the bot never removes censorship
from an existing censored recording.


## Broader public-source import

- Public YouTube videos, Shorts, playlists and channel pages; SoundCloud, Bandcamp,
  Mixcloud, Audiomack, Vimeo, VK, Bilibili, Archive.org, Jamendo and other public
  providers supported by the pinned yt-dlp release use one extractor pipeline.
  The authoritative registry is [yt-dlp supported sites](https://github.com/yt-dlp/yt-dlp/blob/2026.10.26/supportedsites.md).
  A listed extractor is not a promise that every page or region is available.
- Public direct MP3/M4A/AAC/FLAC/Ogg/Opus/WAV/AIFF/WebM/MP4 audio links, HTML
  audio/source elements, downloadable audio anchors, OpenGraph audio and JSON-LD
  recordings are read directly. RSS/Atom enclosures and explicit HTML next-page links follow same-origin
  pagination, up to100 pages. Pages are bounded to2 MB; audio remains bounded to50 MB.
- Generic extractor jobs expose up to2000 tracks; larger catalogs are marked
  partial instead of reported complete. Jobs resume on the next Actions run
  after the worker's time budget, with duplicate protection.
- Spotify short links (`spotify.link`, `spotify.app.link`, `spoti.fi`) and
  supported `clck.ru` platform redirects are expanded through public-only HEAD/GET
  requests before routing. An unresolved short link asks for the full URL.
- Yandex Music first uses its native extractor for publicly exposed downloads.
  If that path is unavailable, existing public metadata and exact full-recording
  matching remain available. Spotify supplies metadata, not decrypted audio.
- The downloader uses native HTTP/HLS/DASH fetching through the validated public
  proxy. ffmpeg/ffprobe process only local files; extractor subprocesses receive
  no account credentials or cookies. The pinned package provides the YouTube JS
  solver; runtime remote component downloads are disabled.
- All recordings, including direct MP3 files, are limited to30 minutes; actual duration is
  read locally and compared with expected duration to reject short samples. Known preview URLs
  are rejected. A direct file with no trustworthy duration metadata cannot be
  proven to contain a particular complete recording just from its filename.
- Diagnostics distinguish unavailable, login-only, region-restricted, rate-limited
  and DRM sources without exposing upstream signed URLs. No authentication,
  subscription, CAPTCHA or DRM bypass is performed.


When a name-only request fails across the legacy artist catalogs, the worker may
fall back to100 public YouTube search results. Candidates must match explicit
artist metadata, the exact artist channel (ignoring Topic/VEVO/Official suffixes)
or a clear artist/title prefix. Live streams, mixes, clean editions and ambiguous
legacy artist identities are excluded. This fallback is always labelled
“Поиск YouTube, неполная дискография”; it never claims a complete catalog.
