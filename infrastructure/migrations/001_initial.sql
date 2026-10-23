CREATE TABLE IF NOT EXISTS schema_migrations(version integer PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE users (
 id text PRIMARY KEY, email text UNIQUE NOT NULL, password_hash text NOT NULL,
 display_name text NOT NULL, role text NOT NULL CHECK(role IN ('creator','moderator','admin')),
 created_at timestamptz NOT NULL DEFAULT now(), disabled_at timestamptz
);
CREATE TABLE sessions (
 token_hash text PRIMARY KEY, refresh_hash text UNIQUE NOT NULL,
 user_id text NOT NULL REFERENCES users(id), expires_at timestamptz NOT NULL,
 refresh_expires_at timestamptz NOT NULL, revoked_at timestamptz
);
CREATE TABLE projects (
 id text PRIMARY KEY, owner_id text NOT NULL REFERENCES users(id),
 name text NOT NULL, revision integer NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE assets (
 id text PRIMARY KEY, owner_id text NOT NULL REFERENCES users(id), data jsonb NOT NULL,
 revision integer NOT NULL DEFAULT 1, updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz
);
CREATE INDEX assets_owner_updated ON assets(owner_id,updated_at DESC);
CREATE TABLE generation_jobs (
 id text PRIMARY KEY, asset_id text NOT NULL REFERENCES assets(id), owner_id text NOT NULL REFERENCES users(id),
 status text NOT NULL CHECK(status IN ('queued','running','succeeded','failed','cancelled')),
 accepted_at timestamptz NOT NULL, started_at timestamptz, finished_at timestamptz,
 lease_until timestamptz, attempt integer NOT NULL DEFAULT 0, data jsonb NOT NULL,
 failure_code text, idempotency_key text NOT NULL, UNIQUE(owner_id,idempotency_key)
);
CREATE INDEX generation_queue ON generation_jobs(status,accepted_at);
CREATE TABLE publication_submissions (
 id text PRIMARY KEY, asset_id text NOT NULL REFERENCES assets(id), submitter_id text NOT NULL REFERENCES users(id),
 status text NOT NULL CHECK(status IN ('pending_review','approved','rejected','withdrawn','unpublished')),
 snapshot jsonb NOT NULL, revision integer NOT NULL DEFAULT 1, slug text UNIQUE NOT NULL,
 submitted_at timestamptz NOT NULL DEFAULT now(), reviewed_at timestamptz, reviewed_by text REFERENCES users(id), rejection_reason text
);
CREATE UNIQUE INDEX one_active_submission ON publication_submissions(asset_id) WHERE status IN ('pending_review','approved');
CREATE INDEX submission_queue ON publication_submissions(status,submitted_at);
CREATE TABLE moderation_events (
 id text PRIMARY KEY, submission_id text NOT NULL REFERENCES publication_submissions(id),
 moderator_id text NOT NULL REFERENCES users(id), action text NOT NULL, reason text, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE daily_usage (
 day date PRIMARY KEY, accepted_generations integer NOT NULL DEFAULT 0 CHECK(accepted_generations BETWEEN 0 AND 20),
 transferred_bytes bigint NOT NULL DEFAULT 0 CHECK(transferred_bytes>=0), reserved_transfer_bytes bigint NOT NULL DEFAULT 0 CHECK(reserved_transfer_bytes>=0),
 CHECK(transferred_bytes+reserved_transfer_bytes<=1000000000)
);
CREATE TABLE storage_usage (
 singleton integer PRIMARY KEY CHECK(singleton=1), stored_bytes bigint NOT NULL DEFAULT 0 CHECK(stored_bytes>=0),
 reserved_bytes bigint NOT NULL DEFAULT 0 CHECK(reserved_bytes>=0), CHECK(stored_bytes+reserved_bytes<=10000000000)
);
INSERT INTO storage_usage(singleton) VALUES(1);
CREATE TABLE stored_files (
 id text PRIMARY KEY, owner_id text NOT NULL REFERENCES users(id), asset_id text NOT NULL REFERENCES assets(id),
 storage_key text UNIQUE NOT NULL, kind text NOT NULL, byte_length bigint NOT NULL CHECK(byte_length>=0),
 mime text NOT NULL, checksum text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz
);
CREATE TABLE transfer_reservations (
 id text PRIMARY KEY, day date NOT NULL REFERENCES daily_usage(day), requested_bytes bigint NOT NULL CHECK(requested_bytes>=0),
 actual_bytes bigint NOT NULL DEFAULT 0, finalized_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE idempotent_commands (
 actor_id text NOT NULL REFERENCES users(id), command_key text NOT NULL, request_hash text NOT NULL, response jsonb NOT NULL,
 PRIMARY KEY(actor_id,command_key)
);
CREATE TABLE worker_callback_nonces (
 nonce text PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO schema_migrations(version) VALUES(1);
