CREATE TABLE pulse_devices (
 user_id TEXT NOT NULL REFERENCES pulse_accounts(id) ON DELETE CASCADE,
 id TEXT NOT NULL,
 name TEXT NOT NULL,
 platform TEXT NOT NULL,
 available INTEGER NOT NULL DEFAULT 1,
 ready INTEGER NOT NULL DEFAULT 0,
 state_json TEXT NOT NULL DEFAULT '{}',
 queue_json TEXT NOT NULL DEFAULT '[]',
 original_queue_json TEXT NOT NULL DEFAULT '[]',
 seen_at INTEGER NOT NULL,
 PRIMARY KEY(user_id,id)
);
--> statement-breakpoint
CREATE INDEX pulse_devices_online ON pulse_devices(user_id,seen_at DESC);
--> statement-breakpoint
CREATE TABLE pulse_device_commands (
 seq INTEGER PRIMARY KEY AUTOINCREMENT,
 id TEXT NOT NULL UNIQUE,
 user_id TEXT NOT NULL REFERENCES pulse_accounts(id) ON DELETE CASCADE,
 source_id TEXT NOT NULL,
 target_id TEXT NOT NULL,
 type TEXT NOT NULL,
 payload_json TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'pending',
 error TEXT NOT NULL DEFAULT '',
 created_at INTEGER NOT NULL,
 completed_at INTEGER
);
--> statement-breakpoint
CREATE INDEX pulse_device_command_poll ON pulse_device_commands(user_id,target_id,status,seq);
--> statement-breakpoint
CREATE TABLE pulse_device_focus (
 user_id TEXT PRIMARY KEY REFERENCES pulse_accounts(id) ON DELETE CASCADE,
 device_id TEXT,
 last_seq INTEGER NOT NULL DEFAULT 0,
 pending_id TEXT,
 revision INTEGER NOT NULL DEFAULT 0,
 updated_at INTEGER NOT NULL
);
