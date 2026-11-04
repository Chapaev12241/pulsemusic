CREATE TABLE pulse_telegram_links (telegram_id TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL);
--> statement-breakpoint
CREATE TABLE pulse_telegram_updates (update_id INTEGER PRIMARY KEY, created_at TEXT NOT NULL);
--> statement-breakpoint
CREATE INDEX pulse_telegram_updates_created ON pulse_telegram_updates(created_at);
