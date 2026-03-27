import { type Pool } from "pg";
import { newId, randomCode, randomSlug, randomToken, sha256 } from "@nomade/shared";

export interface User {
  id: string;
  email: string;
}

export interface SessionRecord {
  id: string;
  user_id: string;
  workspace_id: string;
  agent_id: string;
  name: string;
  status: string;
  cursor: number;
}

export interface TunnelRecord {
  id: string;
  user_id: string;
  workspace_id: string;
  agent_id: string;
  slug: string;
  target_port: number;
  access_token_hash: string;
  status: string;
}

export class Repositories {
  constructor(private readonly pool: Pool) {}

  async findOrCreateUserByEmail(email: string): Promise<User> {
    const existing = await this.pool.query<User>("SELECT id, email FROM users WHERE email = $1", [email]);
    if ((existing.rowCount ?? 0) > 0 && existing.rows[0]) {
      return existing.rows[0];
    }

    const created = await this.pool.query<User>(
      "INSERT INTO users (id, email) VALUES ($1, $2) RETURNING id, email",
      [newId(), email]
    );
    return created.rows[0];
  }

  async createDeviceCode(ttlSec: number): Promise<{ deviceCode: string; userCode: string; expiresAt: Date }> {
    const deviceCode = randomToken("dc");
    const userCode = randomCode(8);
    const expiresAt = new Date(Date.now() + ttlSec * 1000);

    await this.pool.query(
      `INSERT INTO device_codes (id, device_code, user_code, status, expires_at)
       VALUES ($1, $2, $3, 'pending', $4)`,
      [newId(), deviceCode, userCode, expiresAt]
    );

    return { deviceCode, userCode, expiresAt };
  }

  async approveDeviceCode(userCode: string, userId: string): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE device_codes
       SET status = 'approved', user_id = $1
       WHERE user_code = $2
         AND status = 'pending'
         AND expires_at > NOW()`,
      [userId, userCode]
    );
    return (result.rowCount ?? 0) > 0;
  }

  async consumeApprovedDeviceCode(
    deviceCode: string
  ): Promise<{ userId: string } | { pending: true } | { expired: true } | null> {
    const row = await this.pool.query<{
      status: string;
      user_id: string | null;
      expires_at: Date;
      consumed_at: Date | null;
    }>(
      `SELECT status, user_id, expires_at, consumed_at
       FROM device_codes
       WHERE device_code = $1`,
      [deviceCode]
    );

    if ((row.rowCount ?? 0) === 0 || !row.rows[0]) {
      return null;
    }

    const dc = row.rows[0];
    if (dc.expires_at.getTime() <= Date.now()) {
      return { expired: true };
    }

    if (dc.status === "pending") {
      return { pending: true };
    }

    if (!dc.user_id || dc.consumed_at) {
      return null;
    }

    await this.pool.query("UPDATE device_codes SET consumed_at = NOW() WHERE device_code = $1", [deviceCode]);
    return { userId: dc.user_id };
  }

  async createRefreshToken(userId: string, token: string, ttlSec: number): Promise<void> {
    const expiresAt = new Date(Date.now() + ttlSec * 1000);
    await this.pool.query(
      `INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at)
       VALUES ($1, $2, $3, $4)`,
      [newId(), userId, sha256(token), expiresAt]
    );
  }

  async useRefreshToken(token: string): Promise<{ userId: string } | null> {
    const result = await this.pool.query<{ user_id: string }>(
      `UPDATE refresh_tokens
       SET revoked_at = NOW()
       WHERE token_hash = $1
         AND revoked_at IS NULL
         AND expires_at > NOW()
       RETURNING user_id`,
      [sha256(token)]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return { userId: result.rows[0].user_id };
  }

  async getUserById(userId: string): Promise<User | null> {
    const result = await this.pool.query<User>("SELECT id, email FROM users WHERE id = $1", [userId]);
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
  }

  async createPairingCode(userId: string, ttlSec: number): Promise<string> {
    const code = randomCode(10);
    const expiresAt = new Date(Date.now() + ttlSec * 1000);
    await this.pool.query(
      `INSERT INTO pairings (id, user_id, code_hash, expires_at)
       VALUES ($1, $2, $3, $4)`,
      [newId(), userId, sha256(code), expiresAt]
    );
    return code;
  }

  async consumePairingCode(code: string): Promise<{ userId: string } | null> {
    const result = await this.pool.query<{ user_id: string }>(
      `UPDATE pairings
       SET used_at = NOW()
       WHERE code_hash = $1
         AND used_at IS NULL
         AND expires_at > NOW()
       RETURNING user_id`,
      [sha256(code)]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return { userId: result.rows[0].user_id };
  }

  async createAgent(userId: string, name: string): Promise<{ agentId: string; agentToken: string }> {
    const agentId = newId();
    const agentToken = randomToken("na");
    await this.pool.query(
      `INSERT INTO agents (id, user_id, name, token_hash)
       VALUES ($1, $2, $3, $4)`,
      [agentId, userId, name, sha256(agentToken)]
    );
    return { agentId, agentToken };
  }

  async findAgentByToken(agentToken: string): Promise<{ agentId: string; userId: string } | null> {
    const result = await this.pool.query<{ id: string; user_id: string }>(
      "SELECT id, user_id FROM agents WHERE token_hash = $1",
      [sha256(agentToken)]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return { agentId: result.rows[0].id, userId: result.rows[0].user_id };
  }

  async touchAgentLastSeen(agentId: string): Promise<void> {
    await this.pool.query("UPDATE agents SET last_seen_at = NOW() WHERE id = $1", [agentId]);
  }

  async listAgents(userId: string): Promise<Array<{ id: string; name: string; last_seen_at: Date | null }>> {
    const result = await this.pool.query<{ id: string; name: string; last_seen_at: Date | null }>(
      "SELECT id, name, last_seen_at FROM agents WHERE user_id = $1 ORDER BY created_at DESC",
      [userId]
    );
    return result.rows;
  }

  async createWorkspace(params: {
    userId: string;
    agentId: string;
    name: string;
    path: string;
  }): Promise<{ id: string; name: string; path: string; agent_id: string }> {
    const workspaceId = newId();
    const result = await this.pool.query<{ id: string; name: string; path: string; agent_id: string }>(
      `INSERT INTO workspaces (id, user_id, agent_id, name, path)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, name, path, agent_id`,
      [workspaceId, params.userId, params.agentId, params.name, params.path]
    );
    return result.rows[0];
  }

  async listWorkspaces(userId: string): Promise<Array<{ id: string; name: string; path: string; agent_id: string }>> {
    const result = await this.pool.query<{ id: string; name: string; path: string; agent_id: string }>(
      "SELECT id, name, path, agent_id FROM workspaces WHERE user_id = $1 ORDER BY created_at DESC",
      [userId]
    );
    return result.rows;
  }

  async createSession(params: {
    userId: string;
    workspaceId: string;
    agentId: string;
    name: string;
  }): Promise<SessionRecord> {
    const id = newId();
    const result = await this.pool.query<SessionRecord>(
      `INSERT INTO sessions (id, user_id, workspace_id, agent_id, name, status)
       VALUES ($1, $2, $3, $4, $5, 'running')
       RETURNING id, user_id, workspace_id, agent_id, name, status, cursor`,
      [id, params.userId, params.workspaceId, params.agentId, params.name]
    );
    return result.rows[0];
  }

  async listSessions(userId: string, workspaceId: string): Promise<SessionRecord[]> {
    const result = await this.pool.query<SessionRecord>(
      `SELECT id, user_id, workspace_id, agent_id, name, status, cursor
       FROM sessions
       WHERE user_id = $1 AND workspace_id = $2
       ORDER BY created_at DESC`,
      [userId, workspaceId]
    );
    return result.rows;
  }

  async updateSessionStatus(sessionId: string, status: string): Promise<void> {
    await this.pool.query("UPDATE sessions SET status = $1, updated_at = NOW() WHERE id = $2", [status, sessionId]);
  }

  async updateSessionCursor(sessionId: string, cursor: number): Promise<void> {
    await this.pool.query("UPDATE sessions SET cursor = $1, updated_at = NOW() WHERE id = $2", [cursor, sessionId]);
  }

  async createTunnel(params: {
    userId: string;
    workspaceId: string;
    agentId: string;
    targetPort: number;
    ttlSec?: number;
  }): Promise<{ tunnel: TunnelRecord; accessToken: string }> {
    const id = newId();
    const slug = randomSlug();
    const accessToken = randomToken("tp");
    const expiresAt = params.ttlSec ? new Date(Date.now() + params.ttlSec * 1000) : null;
    const result = await this.pool.query<TunnelRecord>(
      `INSERT INTO tunnels (
         id, user_id, workspace_id, agent_id, slug,
         target_port, access_token_hash, status, expires_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, 'open', $8)
       RETURNING id, user_id, workspace_id, agent_id, slug, target_port, access_token_hash, status`,
      [id, params.userId, params.workspaceId, params.agentId, slug, params.targetPort, sha256(accessToken), expiresAt]
    );
    return { tunnel: result.rows[0], accessToken };
  }

  async listTunnels(userId: string, workspaceId: string): Promise<TunnelRecord[]> {
    const result = await this.pool.query<TunnelRecord>(
      `SELECT id, user_id, workspace_id, agent_id, slug, target_port, access_token_hash, status
       FROM tunnels
       WHERE user_id = $1 AND workspace_id = $2
       ORDER BY created_at DESC`,
      [userId, workspaceId]
    );
    return result.rows;
  }

  async findTunnelBySlug(slug: string): Promise<(TunnelRecord & { expires_at: Date | null }) | null> {
    const result = await this.pool.query<TunnelRecord & { expires_at: Date | null }>(
      `SELECT id, user_id, workspace_id, agent_id, slug, target_port, access_token_hash, status, expires_at
       FROM tunnels
       WHERE slug = $1`,
      [slug]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
  }

  async writeAuditEvent(params: {
    userId: string | null;
    actorType: string;
    actorId: string | null;
    action: string;
    metadata: unknown;
  }): Promise<void> {
    await this.pool.query(
      `INSERT INTO audit_events (id, user_id, actor_type, actor_id, action, metadata)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
      [newId(), params.userId, params.actorType, params.actorId, params.action, JSON.stringify(params.metadata)]
    );
  }
}
