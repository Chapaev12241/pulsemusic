CREATE TABLE pulse_import_config (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, token_cipher TEXT NOT NULL, username TEXT NOT NULL, webhook_secret TEXT NOT NULL, pair_hash TEXT, pair_expires INTEGER, telegram_id TEXT, created_at INTEGER NOT NULL);
--> statement-breakpoint
CREATE TABLE pulse_import_jobs (id TEXT PRIMARY KEY, update_id INTEGER NOT NULL UNIQUE, owner_id TEXT NOT NULL, chat_id TEXT NOT NULL, source TEXT NOT NULL, artist TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'queued', total INTEGER NOT NULL DEFAULT 0, failed INTEGER NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '', lease TEXT, lease_until INTEGER NOT NULL DEFAULT 0, attempts INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
--> statement-breakpoint
CREATE INDEX pulse_import_jobs_queue ON pulse_import_jobs(status, created_at);
--> statement-breakpoint
CREATE TABLE pulse_import_tracks (job_id TEXT NOT NULL, source_id TEXT NOT NULL, track_id TEXT NOT NULL, duplicate INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(job_id,source_id));
