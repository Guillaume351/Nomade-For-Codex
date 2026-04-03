import { Pool } from "pg";

export const createPool = (databaseUrl: string): Pool => {
  return new Pool({ connectionString: databaseUrl });
};

export const ensureSchema = async (pool: Pool): Promise<void> => {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT NOT NULL UNIQUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS device_codes (
      id TEXT PRIMARY KEY,
      device_code TEXT NOT NULL UNIQUE,
      user_code TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL,
      user_id TEXT REFERENCES users(id),
      expires_at TIMESTAMPTZ NOT NULL,
      consumed_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS refresh_tokens (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      token_hash TEXT NOT NULL UNIQUE,
      expires_at TIMESTAMPTZ NOT NULL,
      revoked_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS pairings (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      code_hash TEXT NOT NULL UNIQUE,
      expires_at TIMESTAMPTZ NOT NULL,
      used_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS agents (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      name TEXT NOT NULL,
      token_hash TEXT NOT NULL UNIQUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_seen_at TIMESTAMPTZ
    );

    CREATE TABLE IF NOT EXISTS workspaces (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      agent_id TEXT NOT NULL REFERENCES agents(id),
      name TEXT NOT NULL,
      path TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      workspace_id TEXT NOT NULL REFERENCES workspaces(id),
      agent_id TEXT NOT NULL REFERENCES agents(id),
      name TEXT NOT NULL,
      status TEXT NOT NULL,
      cursor BIGINT NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS conversations (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      workspace_id TEXT NOT NULL REFERENCES workspaces(id),
      agent_id TEXT NOT NULL REFERENCES agents(id),
      title TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'idle',
      codex_thread_id TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS conversation_turns (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      user_prompt TEXT NOT NULL,
      codex_turn_id TEXT,
      status TEXT NOT NULL DEFAULT 'queued',
      diff TEXT NOT NULL DEFAULT '',
      error TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      completed_at TIMESTAMPTZ
    );

    CREATE TABLE IF NOT EXISTS conversation_items (
      id TEXT PRIMARY KEY,
      turn_id TEXT NOT NULL REFERENCES conversation_turns(id) ON DELETE CASCADE,
      item_id TEXT NOT NULL,
      item_type TEXT NOT NULL,
      ordinal INT NOT NULL,
      payload JSONB NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS tunnels (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      workspace_id TEXT NOT NULL REFERENCES workspaces(id),
      agent_id TEXT NOT NULL REFERENCES agents(id),
      service_id TEXT,
      slug TEXT NOT NULL UNIQUE,
      target_port INT NOT NULL,
      access_token_hash TEXT NOT NULL,
      token_required BOOLEAN NOT NULL DEFAULT TRUE,
      status TEXT NOT NULL,
      expires_at TIMESTAMPTZ,
      last_probe_at TIMESTAMPTZ,
      last_probe_status TEXT,
      last_probe_error TEXT,
      last_probe_code INT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS workspace_dev_settings (
      workspace_id TEXT PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
      trusted_dev_mode BOOLEAN NOT NULL DEFAULT FALSE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS dev_services (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      agent_id TEXT NOT NULL REFERENCES agents(id),
      name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'service',
      command TEXT NOT NULL,
      cwd TEXT,
      port INT NOT NULL,
      health_path TEXT NOT NULL DEFAULT '/',
      env_template JSONB NOT NULL DEFAULT '{}'::jsonb,
      depends_on JSONB NOT NULL DEFAULT '[]'::jsonb,
      auto_tunnel BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (workspace_id, name)
    );

    CREATE TABLE IF NOT EXISTS dev_service_runtime (
      service_id TEXT PRIMARY KEY REFERENCES dev_services(id) ON DELETE CASCADE,
      session_id TEXT REFERENCES sessions(id),
      tunnel_id TEXT REFERENCES tunnels(id),
      status TEXT NOT NULL DEFAULT 'stopped',
      last_error TEXT,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS audit_events (
      id TEXT PRIMARY KEY,
      user_id TEXT REFERENCES users(id),
      actor_type TEXT NOT NULL,
      actor_id TEXT,
      action TEXT NOT NULL,
      metadata JSONB NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    ALTER TABLE tunnels ADD COLUMN IF NOT EXISTS service_id TEXT;
    ALTER TABLE tunnels ADD COLUMN IF NOT EXISTS token_required BOOLEAN NOT NULL DEFAULT TRUE;
    ALTER TABLE tunnels ADD COLUMN IF NOT EXISTS last_probe_at TIMESTAMPTZ;
    ALTER TABLE tunnels ADD COLUMN IF NOT EXISTS last_probe_status TEXT;
    ALTER TABLE tunnels ADD COLUMN IF NOT EXISTS last_probe_error TEXT;
    ALTER TABLE tunnels ADD COLUMN IF NOT EXISTS last_probe_code INT;

    -- Keep one row per (turn_id, item_id) for idempotent upserts.
    DELETE FROM conversation_items newer
    USING conversation_items older
    WHERE newer.turn_id = older.turn_id
      AND newer.item_id = older.item_id
      AND newer.created_at > older.created_at;

    CREATE INDEX IF NOT EXISTS idx_dev_services_workspace_id ON dev_services (workspace_id);
    CREATE INDEX IF NOT EXISTS idx_tunnels_service_id ON tunnels (service_id);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_conversation_items_turn_item ON conversation_items (turn_id, item_id);
  `);
};
