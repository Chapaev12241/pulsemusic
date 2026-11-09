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

TuneMir: exact artist search, artist pagination, individual tracks, fresh public signed MP3 links. Max 250 tracks per job, max 50 MB per audio file. Metadata preserves collaborations. Duplicate audio is identified by SHA-256; admin-removed tracks are not restored. No login/captcha bypass.

Other public links use yt-dlp generic/provider support, with ffmpeg for MP3 conversion. Support depends on the source. The runner installs pinned yt-dlp only when needed; all downloader traffic goes through a public-address-only local proxy. Track errors are counted; partial imports remain available and can be retried. Private IPs, local URLs, non-HTTP schemes, credentials and arbitrary ports are rejected. No credentials are passed to the extractor.

## Verification

Node 24:

```
node scripts/build-worker.mjs
node scripts/test-import-bot.mjs
node --test import-bot/test.mjs
node scripts/test-backend.mjs
node scripts/test-telegram.mjs
```

Tests use in-memory SQLite D1 and mocked R2/Telegram/JWKS; they never publish test music or message a real user. Live TuneMir check: artist Гуф resolves correctly; all 42 tracks across three pages; single Ice Baby MP3 downloads with ID3 signature, 10,176,701 bytes.

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
