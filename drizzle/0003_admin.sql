ALTER TABLE pulse_accounts ADD COLUMN role TEXT NOT NULL DEFAULT 'user';
--> statement-breakpoint
ALTER TABLE pulse_accounts ADD COLUMN banned INTEGER NOT NULL DEFAULT 0;
--> statement-breakpoint
ALTER TABLE pulse_catalog ADD COLUMN deleted_at TEXT;
--> statement-breakpoint
ALTER TABLE pulse_catalog ADD COLUMN deleted_by TEXT;
--> statement-breakpoint
ALTER TABLE pulse_catalog ADD COLUMN removed_was_public INTEGER NOT NULL DEFAULT 1;
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS pulse_admin_audit (id INTEGER PRIMARY KEY AUTOINCREMENT,actor_id TEXT NOT NULL,action TEXT NOT NULL,target_id TEXT NOT NULL,created_at TEXT NOT NULL);
