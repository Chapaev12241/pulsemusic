Pulse Telegram Mini App
======================

Entry: https://chapaev12241.github.io/pulsemusic/telegram.html

The same API, accounts, shared catalog and private playlists are used by the web and Telegram versions. Telegram login links an existing Pulse account after server-side validation of Telegram's initData. Accounts are never merged by display name or username.

Runtime secrets on the existing backend:
- TELEGRAM_BOT_TOKEN: token issued by BotFather.
- TELEGRAM_WEBHOOK_SECRET: random 32-byte base64url value.
- TELEGRAM_BOT_USERNAME: public bot username without @.

Configure these through the hosting environment, never through GitHub Pages or a committed .env file. Run scripts/configure-telegram-bot.mjs and pass {token, webhookSecret, username} through hidden stdin. It sets commands, description, app menu and the authenticated webhook. No always-running local bot process is required.

Tests: node scripts/test-telegram.mjs; node scripts/test-backend.mjs.

Inside Telegram, native Back, Settings, safe areas and viewport changes are supported. The adapter does not pause the player when minimized. Whether playback continues while Telegram is suspended is controlled by the Telegram client and OS and needs device testing.
