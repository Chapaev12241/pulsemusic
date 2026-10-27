# Pulse Music

Pulse is a dark music player Worker app with local Pulse auth UI, playlists, history, PWA support, Audius fallback, Soledago and Docker One font assets.

## Run locally

This repository contains the Cloudflare Worker entrypoint at `worker/index.js`. Deploy it with the Worker ESM setup or your own Cloudflare/VPS host. The current hosted version is available at https://pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site.

The browser account form is a personal local account flow. For production multi-device auth, connect it to the D1 schema in the Worker API or a managed auth provider.
