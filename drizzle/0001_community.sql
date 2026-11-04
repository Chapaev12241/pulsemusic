CREATE TABLE IF NOT EXISTS pulse_profiles (user_id TEXT PRIMARY KEY,display_name TEXT NOT NULL,bio TEXT NOT NULL DEFAULT '',color TEXT NOT NULL DEFAULT '#a59aff',emoji TEXT NOT NULL DEFAULT '♫');
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS pulse_catalog (id TEXT PRIMARY KEY,owner_id TEXT NOT NULL,storage_key TEXT NOT NULL,title TEXT NOT NULL,artist TEXT NOT NULL,album TEXT NOT NULL DEFAULT '',genres_json TEXT NOT NULL DEFAULT '[]',size INTEGER NOT NULL,published_at TEXT NOT NULL,is_public INTEGER NOT NULL DEFAULT 1);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS pulse_friend_requests (sender TEXT NOT NULL,recipient TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(sender,recipient),CHECK(sender<>recipient));
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS pulse_friendships (a TEXT NOT NULL,b TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(a,b),CHECK(a<b));
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS pulse_messages (id INTEGER PRIMARY KEY AUTOINCREMENT,sender TEXT NOT NULL,recipient TEXT NOT NULL,body TEXT NOT NULL,created_at TEXT NOT NULL);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS pulse_messages_pair ON pulse_messages(sender,recipient,id);
