CREATE TABLE IF NOT EXISTS pulse_accounts (id TEXT PRIMARY KEY,email TEXT UNIQUE NOT NULL,name TEXT NOT NULL,password_hash TEXT NOT NULL,password_salt TEXT NOT NULL,created_at TEXT NOT NULL);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS pulse_sessions (token TEXT PRIMARY KEY,user_id TEXT NOT NULL,expires_at TEXT NOT NULL);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS pulse_state (user_id TEXT PRIMARY KEY,liked_json TEXT NOT NULL DEFAULT '[]',history_json TEXT NOT NULL DEFAULT '[]',playlists_json TEXT NOT NULL DEFAULT '[]',updated_at TEXT NOT NULL);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS pulse_sessions_user ON pulse_sessions(user_id);
