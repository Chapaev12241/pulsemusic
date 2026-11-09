ALTER TABLE pulse_import_config ADD COLUMN github_cipher TEXT;
--> statement-breakpoint
ALTER TABLE pulse_import_config ADD COLUMN github_next_kick INTEGER NOT NULL DEFAULT 0;
--> statement-breakpoint
ALTER TABLE pulse_import_config ADD COLUMN github_error TEXT NOT NULL DEFAULT '';
