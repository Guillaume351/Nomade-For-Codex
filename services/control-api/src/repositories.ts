import { type Pool } from "pg";
import { newId, randomCode, randomSlug, randomToken, sha256 } from "@nomade/shared";

export interface User {
  id: string;
  email: string;
}

const defaultNameFromEmail = (email: string): string => {
  const localPart = email.split("@")[0]?.trim() ?? "";
  if (localPart.length > 0) {
    return localPart.slice(0, 120);
  }
  return "Nomade User";
};

export interface UserEntitlements {
  userId: string;
  planCode: string;
  subscriptionStatus: string;
  maxAgents: number;
  currentAgents: number;
  limitReached: boolean;
  source: string;
  features: {
    tunnels: boolean;
    pushNotifications: boolean;
    deferredTurns: boolean;
  };
}

export interface BillingSubscriptionUpdate {
  userId: string;
  planCode: string;
  status: string;
  maxAgents: number;
  source: string;
  stripeSubscriptionId?: string | null;
  currentPeriodEnd?: Date | null;
}

export interface PushRegistrationRecord {
  id: string;
  user_id: string;
  device_id: string;
  provider: string;
  platform: string;
  token: string;
  status: "active" | "inactive";
  last_error: string | null;
  created_at: Date;
  updated_at: Date;
  last_seen_at: Date;
}

export class DeviceLimitReachedError extends Error {
  constructor(
    readonly currentAgents: number,
    readonly maxAgents: number
  ) {
    super("device_limit_reached");
    this.name = "DeviceLimitReachedError";
  }
}

export type DeviceCodeStartMode = "legacy" | "scan_secure";

export type DeviceCodeApprovalResult =
  | "approved"
  | "secure_scan_required"
  | "invalid_or_expired";

export interface ScanStartHostDevice {
  deviceId: string;
  name: string;
  platform: string;
  encPublicKey: string;
  signPublicKey: string;
  exchangePublicKey: string;
}

export interface DeviceCodeCreateParams {
  ttlSec: number;
  mode: DeviceCodeStartMode;
  hostDevice?: ScanStartHostDevice;
}

export interface DeviceCodeCreateResult {
  deviceCode: string;
  userCode: string;
  expiresAt: Date;
  mode: DeviceCodeStartMode;
  scanId?: string;
  scanShortCode?: string;
}

export interface DevicePollStatePending {
  status: "pending";
}

export interface DevicePollStatePendingScan {
  status: "pending_scan";
}

export interface DevicePollStatePendingKeyExchange {
  status: "pending_key_exchange";
  mobileExchangePublicKey?: string | null;
  mobileDeviceId?: string | null;
  mobileEncPublicKey?: string | null;
  mobileSignPublicKey?: string | null;
  hostBundleReady: boolean;
}

export interface DevicePollStateExpired {
  status: "expired";
}

export interface DevicePollStateApproved {
  status: "approved";
  userId: string;
}

export type DevicePollState =
  | DevicePollStatePending
  | DevicePollStatePendingScan
  | DevicePollStatePendingKeyExchange
  | DevicePollStateExpired
  | DevicePollStateApproved;

export interface DeviceScanFlowRecord {
  device_code_id: string;
  mode: DeviceCodeStartMode;
  scan_id: string | null;
  scan_short_code: string | null;
  status: string;
  host_device_id: string | null;
  host_enc_public_key: string | null;
  host_sign_public_key: string | null;
  host_exchange_public_key: string | null;
  mobile_user_id: string | null;
  mobile_device_id: string | null;
  mobile_enc_public_key: string | null;
  mobile_sign_public_key: string | null;
  mobile_exchange_public_key: string | null;
  host_bundle: Record<string, unknown> | null;
  key_acked_at: Date | null;
}

export interface UserDeviceRecord {
  id: string;
  user_id: string;
  name: string;
  platform: string;
  enc_public_key: string;
  sign_public_key: string;
  updated_at: Date;
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

export interface WorkspaceRecord {
  id: string;
  user_id: string;
  agent_id: string;
  name: string;
  path: string;
  created_at: Date;
}

export interface ConversationRecord {
  id: string;
  user_id: string;
  workspace_id: string;
  agent_id: string;
  title: string;
  status: string;
  codex_thread_id: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface ConversationTurnRecord {
  id: string;
  conversation_id: string;
  user_prompt: string;
  codex_turn_id: string | null;
  status: string;
  diff: string;
  error: string | null;
  delivery_policy: TurnDeliveryPolicy;
  delivery_state: TurnDeliveryState;
  delivery_attempts: number;
  delivery_error: string | null;
  next_delivery_at: Date | null;
  request_options: Record<string, unknown>;
  created_at: Date;
  updated_at: Date;
  completed_at: Date | null;
}

export type TurnDeliveryPolicy = "immediate" | "defer_if_offline";
export type TurnDeliveryState = "pending" | "deferred" | "dispatched" | "completed" | "failed";

export interface DeferredConversationTurnDispatch {
  userId: string;
  turnId: string;
  conversationId: string;
  workspaceId: string;
  agentId: string;
  codexThreadId: string | null;
  userPrompt: string;
  requestOptions: Record<string, unknown>;
  workspacePath: string | null;
}

export interface ConversationItemRecord {
  id: string;
  turn_id: string;
  item_id: string;
  item_type: string;
  ordinal: number;
  payload: Record<string, unknown>;
  created_at: Date;
}

export interface TunnelRecord {
  id: string;
  user_id: string;
  workspace_id: string;
  agent_id: string;
  service_id: string | null;
  slug: string;
  target_port: number;
  access_token_hash: string;
  token_required: boolean;
  status: string;
  expires_at?: Date | null;
  last_probe_at?: Date | null;
  last_probe_status?: string | null;
  last_probe_error?: string | null;
  last_probe_code?: number | null;
}

export interface WorkspaceDevSettingsRecord {
  workspace_id: string;
  trusted_dev_mode: boolean;
  created_at: Date;
  updated_at: Date;
}

export interface DevServiceRecord {
  id: string;
  user_id: string;
  workspace_id: string;
  agent_id: string;
  name: string;
  role: string;
  command: string;
  cwd: string | null;
  port: number;
  health_path: string;
  env_template: Record<string, string>;
  depends_on: string[];
  auto_tunnel: boolean;
  created_at: Date;
  updated_at: Date;
}

export interface DevServiceRuntimeRecord {
  service_id: string;
  session_id: string | null;
  tunnel_id: string | null;
  status: string;
  last_error: string | null;
  updated_at: Date;
}

export class Repositories {
  constructor(private readonly pool: Pool) {}

  async ensureUserBillingDefaults(userId: string): Promise<void> {
    await this.pool.query(
      `INSERT INTO subscriptions (user_id, plan_code, status)
       VALUES ($1, 'free', 'active')
       ON CONFLICT (user_id) DO NOTHING`,
      [userId]
    );
    await this.pool.query(
      `INSERT INTO device_entitlements (user_id, max_agents, source)
       VALUES ($1, 1, 'free')
       ON CONFLICT (user_id) DO NOTHING`,
      [userId]
    );
  }

  async findOrCreateUserByEmail(email: string): Promise<User> {
    const existing = await this.pool.query<User>("SELECT id, email FROM users WHERE email = $1", [email]);
    if ((existing.rowCount ?? 0) > 0 && existing.rows[0]) {
      await this.ensureUserBillingDefaults(existing.rows[0].id);
      return existing.rows[0];
    }

    const created = await this.pool.query<User>(
      `INSERT INTO users (id, email, name, email_verified, updated_at)
       VALUES ($1, $2, $3, FALSE, NOW())
       RETURNING id, email`,
      [newId(), email, defaultNameFromEmail(email)]
    );
    await this.ensureUserBillingDefaults(created.rows[0].id);
    return created.rows[0];
  }

  async createDeviceCode(params: DeviceCodeCreateParams): Promise<DeviceCodeCreateResult> {
    const mode = params.mode;
    const deviceCodeId = newId();
    const deviceCode = randomToken("dc");
    const userCode = randomCode(8);
    const expiresAt = new Date(Date.now() + params.ttlSec * 1000);
    const scanId = mode === "scan_secure" ? randomToken("scan") : undefined;
    const scanShortCode = mode === "scan_secure" ? randomCode(8) : undefined;
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(
        `INSERT INTO device_codes (id, device_code, user_code, status, expires_at)
         VALUES ($1, $2, $3, 'pending', $4)`,
        [deviceCodeId, deviceCode, userCode, expiresAt]
      );
      if (mode === "scan_secure") {
        if (!params.hostDevice) {
          throw new Error("scan_secure_missing_host_device");
        }
        await client.query(
          `INSERT INTO device_scan_flows (
             device_code_id,
             mode,
             scan_id,
             scan_short_code,
             status,
             host_device_id,
             host_enc_public_key,
             host_sign_public_key,
             host_exchange_public_key
           )
           VALUES ($1, 'scan_secure', $2, $3, 'pending_scan', $4, $5, $6, $7)`,
          [
            deviceCodeId,
            scanId!,
            scanShortCode!,
            params.hostDevice.deviceId,
            params.hostDevice.encPublicKey,
            params.hostDevice.signPublicKey,
            params.hostDevice.exchangePublicKey
          ]
        );
      } else {
        await client.query(
          `INSERT INTO device_scan_flows (device_code_id, mode, status)
           VALUES ($1, 'legacy', 'pending')`,
          [deviceCodeId]
        );
      }
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }

    return {
      deviceCode,
      userCode,
      expiresAt,
      mode,
      scanId,
      scanShortCode
    };
  }

  async approveDeviceCode(userCode: string, userId: string): Promise<DeviceCodeApprovalResult> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const result = await client.query<{ id: string }>(
        `UPDATE device_codes
         SET status = 'approved', user_id = $1
         WHERE user_code = $2
           AND status IN ('pending', 'pending_key_exchange')
           AND expires_at > NOW()
           AND EXISTS (
             SELECT 1
             FROM device_scan_flows sf
             WHERE sf.device_code_id = device_codes.id
               AND sf.mode = 'legacy'
           )
         RETURNING id`,
        [userId, userCode]
      );
      const row = result.rows[0];
      if (!row) {
        const secureScan = await client.query<{ id: string }>(
          `SELECT dc.id
           FROM device_codes dc
           JOIN device_scan_flows sf ON sf.device_code_id = dc.id
           WHERE dc.user_code = $1
             AND dc.status IN ('pending', 'pending_key_exchange')
             AND dc.expires_at > NOW()
             AND sf.mode = 'scan_secure'
           LIMIT 1`,
          [userCode]
        );
        await client.query("ROLLBACK");
        if ((secureScan.rowCount ?? 0) > 0) {
          return "secure_scan_required";
        }
        return "invalid_or_expired";
      }
      await client.query(
        `UPDATE device_scan_flows
         SET status = 'approved', key_acked_at = NOW(), updated_at = NOW()
         WHERE device_code_id = $1`,
        [row.id]
      );
      await client.query("COMMIT");
      return "approved";
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async consumeDeviceCodePollState(deviceCode: string): Promise<DevicePollState | null> {
    const row = await this.pool.query<{
      id: string;
      dc_status: string;
      user_id: string | null;
      expires_at: Date;
      consumed_at: Date | null;
      flow_mode: string | null;
      flow_status: string | null;
      mobile_device_id: string | null;
      mobile_enc_public_key: string | null;
      mobile_sign_public_key: string | null;
      mobile_exchange_public_key: string | null;
      host_bundle: Record<string, unknown> | null;
    }>(
      `SELECT
         dc.id,
         dc.status AS dc_status,
         dc.user_id,
         dc.expires_at,
         dc.consumed_at,
         sf.mode AS flow_mode,
         sf.status AS flow_status,
         sf.mobile_device_id,
         sf.mobile_enc_public_key,
         sf.mobile_sign_public_key,
         sf.mobile_exchange_public_key,
         sf.host_bundle
       FROM device_codes dc
       LEFT JOIN device_scan_flows sf ON sf.device_code_id = dc.id
       WHERE dc.device_code = $1`,
      [deviceCode]
    );

    const dc = row.rows[0];
    if (!dc) {
      return null;
    }
    if (dc.expires_at.getTime() <= Date.now()) {
      return { status: "expired" };
    }
    if (dc.dc_status === "pending_key_exchange") {
      return {
        status: "pending_key_exchange",
        mobileDeviceId: dc.mobile_device_id,
        mobileEncPublicKey: dc.mobile_enc_public_key,
        mobileSignPublicKey: dc.mobile_sign_public_key,
        mobileExchangePublicKey: dc.mobile_exchange_public_key,
        hostBundleReady: Boolean(dc.host_bundle)
      };
    }
    if (dc.dc_status === "pending") {
      if (dc.flow_mode === "scan_secure") {
        return { status: "pending_scan" };
      }
      return { status: "pending" };
    }
    if (!dc.user_id || dc.consumed_at) {
      return null;
    }
    await this.pool.query("UPDATE device_codes SET consumed_at = NOW() WHERE id = $1", [dc.id]);
    return { status: "approved", userId: dc.user_id };
  }

  async getScanFlowByScanId(scanId: string): Promise<
    | (DeviceScanFlowRecord & {
        device_code: string;
        user_code: string;
        expires_at: Date;
        device_code_status: string;
        device_user_id: string | null;
      })
    | null
  > {
    const result = await this.pool.query<
      DeviceScanFlowRecord & {
        device_code: string;
        user_code: string;
        expires_at: Date;
        device_code_status: string;
        device_user_id: string | null;
      }
    >(
      `SELECT
         sf.*,
         dc.device_code,
         dc.user_code,
         dc.expires_at,
         dc.status AS device_code_status,
         dc.user_id AS device_user_id
       FROM device_scan_flows sf
       JOIN device_codes dc ON dc.id = sf.device_code_id
       WHERE sf.scan_id = $1`,
      [scanId]
    );
    return result.rows[0] ?? null;
  }

  async getScanFlowByDeviceCode(deviceCode: string): Promise<
    | (DeviceScanFlowRecord & {
        device_code: string;
        user_code: string;
        expires_at: Date;
        device_code_status: string;
        device_user_id: string | null;
      })
    | null
  > {
    const result = await this.pool.query<
      DeviceScanFlowRecord & {
        device_code: string;
        user_code: string;
        expires_at: Date;
        device_code_status: string;
        device_user_id: string | null;
      }
    >(
      `SELECT
         sf.*,
         dc.device_code,
         dc.user_code,
         dc.expires_at,
         dc.status AS device_code_status,
         dc.user_id AS device_user_id
       FROM device_scan_flows sf
       JOIN device_codes dc ON dc.id = sf.device_code_id
       WHERE dc.device_code = $1`,
      [deviceCode]
    );
    return result.rows[0] ?? null;
  }

  async getScanFlowByShortCode(shortCode: string): Promise<
    | (DeviceScanFlowRecord & {
        device_code: string;
        user_code: string;
        expires_at: Date;
        device_code_status: string;
        device_user_id: string | null;
      })
    | null
  > {
    const result = await this.pool.query<
      DeviceScanFlowRecord & {
        device_code: string;
        user_code: string;
        expires_at: Date;
        device_code_status: string;
        device_user_id: string | null;
      }
    >(
      `SELECT
         sf.*,
         dc.device_code,
         dc.user_code,
         dc.expires_at,
         dc.status AS device_code_status,
         dc.user_id AS device_user_id
       FROM device_scan_flows sf
       JOIN device_codes dc ON dc.id = sf.device_code_id
       WHERE sf.scan_short_code = $1`,
      [shortCode]
    );
    return result.rows[0] ?? null;
  }

  async approveScanByMobile(params: {
    deviceCodeId: string;
    userId: string;
    deviceId: string;
    name: string;
    platform: string;
    encPublicKey: string;
    signPublicKey: string;
    exchangePublicKey: string;
  }): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(
        `INSERT INTO user_devices (
           id, user_id, name, platform, enc_public_key, sign_public_key
         ) VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (id) DO UPDATE
         SET user_id = EXCLUDED.user_id,
             name = EXCLUDED.name,
             platform = EXCLUDED.platform,
             enc_public_key = EXCLUDED.enc_public_key,
             sign_public_key = EXCLUDED.sign_public_key,
             revoked_at = NULL,
             updated_at = NOW()`,
        [
          params.deviceId,
          params.userId,
          params.name,
          params.platform,
          params.encPublicKey,
          params.signPublicKey
        ]
      );
      await client.query(
        `UPDATE device_scan_flows
         SET status = 'pending_key_exchange',
             mobile_user_id = $2,
             mobile_device_id = $3,
             mobile_enc_public_key = $4,
             mobile_sign_public_key = $5,
             mobile_exchange_public_key = $6,
             updated_at = NOW()
         WHERE device_code_id = $1`,
        [
          params.deviceCodeId,
          params.userId,
          params.deviceId,
          params.encPublicKey,
          params.signPublicKey,
          params.exchangePublicKey
        ]
      );
      await client.query(
        `UPDATE device_codes
         SET user_id = $2,
             status = 'pending_key_exchange'
         WHERE id = $1`,
        [params.deviceCodeId, params.userId]
      );
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async storeScanHostBundle(params: { deviceCodeId: string; hostBundle: Record<string, unknown> }): Promise<void> {
    await this.pool.query(
      `UPDATE device_scan_flows
       SET host_bundle = $2::jsonb,
           updated_at = NOW()
       WHERE device_code_id = $1`,
      [params.deviceCodeId, JSON.stringify(params.hostBundle)]
    );
  }

  async acknowledgeScanKeyExchange(params: { deviceCodeId: string; userId: string }): Promise<boolean> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const result = await client.query<{ device_code_id: string }>(
        `UPDATE device_scan_flows
         SET status = 'approved',
             key_acked_at = NOW(),
             updated_at = NOW()
         WHERE device_code_id = $1
           AND mobile_user_id = $2
           AND host_bundle IS NOT NULL
         RETURNING device_code_id`,
        [params.deviceCodeId, params.userId]
      );
      if (!result.rows[0]) {
        await client.query("ROLLBACK");
        return false;
      }
      await client.query(
        `UPDATE device_codes
         SET status = 'approved', user_id = $2
         WHERE id = $1`,
        [params.deviceCodeId, params.userId]
      );
      await client.query("COMMIT");
      return true;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
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

  async revokeRefreshToken(token: string, userId: string): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE refresh_tokens
       SET revoked_at = NOW()
       WHERE token_hash = $1
         AND user_id = $2
         AND revoked_at IS NULL`,
      [sha256(token), userId]
    );
    return (result.rowCount ?? 0) > 0;
  }

  async getUserById(userId: string): Promise<User | null> {
    const result = await this.pool.query<User>("SELECT id, email FROM users WHERE id = $1", [userId]);
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    await this.ensureUserBillingDefaults(result.rows[0].id);
    return result.rows[0];
  }

  async listActiveUserDevices(userId: string): Promise<UserDeviceRecord[]> {
    const result = await this.pool.query<UserDeviceRecord>(
      `SELECT
         id,
         user_id,
         name,
         platform,
         enc_public_key,
         sign_public_key,
         updated_at
       FROM user_devices
       WHERE user_id = $1
         AND revoked_at IS NULL
       ORDER BY updated_at DESC`,
      [userId]
    );
    return result.rows;
  }

  async getUserByStripeCustomerId(stripeCustomerId: string): Promise<User | null> {
    const result = await this.pool.query<User>(
      `SELECT u.id, u.email
       FROM users u
       JOIN billing_customers b ON b.user_id = u.id
       WHERE b.stripe_customer_id = $1`,
      [stripeCustomerId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
  }

  async getStripeCustomerIdForUser(userId: string): Promise<string | null> {
    const result = await this.pool.query<{ stripe_customer_id: string }>(
      "SELECT stripe_customer_id FROM billing_customers WHERE user_id = $1",
      [userId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0].stripe_customer_id;
  }

  async upsertStripeCustomer(params: { userId: string; stripeCustomerId: string }): Promise<void> {
    await this.pool.query(
      `INSERT INTO billing_customers (user_id, stripe_customer_id)
       VALUES ($1, $2)
       ON CONFLICT (user_id) DO UPDATE
       SET stripe_customer_id = EXCLUDED.stripe_customer_id,
           updated_at = NOW()`,
      [params.userId, params.stripeCustomerId]
    );
  }

  async applyBillingSubscriptionUpdate(params: BillingSubscriptionUpdate): Promise<void> {
    await this.ensureUserBillingDefaults(params.userId);
    const hasStripeSubscriptionId = params.stripeSubscriptionId !== undefined;
    const hasCurrentPeriodEnd = params.currentPeriodEnd !== undefined;
    await this.pool.query(
      `INSERT INTO subscriptions (
         user_id, plan_code, status, stripe_subscription_id, current_period_end, updated_at
       ) VALUES ($1, $2, $3, $4, $5, NOW())
       ON CONFLICT (user_id) DO UPDATE
       SET plan_code = EXCLUDED.plan_code,
           status = EXCLUDED.status,
           stripe_subscription_id = CASE
             WHEN $6::boolean THEN EXCLUDED.stripe_subscription_id
             ELSE subscriptions.stripe_subscription_id
           END,
           current_period_end = CASE
             WHEN $7::boolean THEN EXCLUDED.current_period_end
             ELSE subscriptions.current_period_end
           END,
           updated_at = NOW()`,
      [
        params.userId,
        params.planCode,
        params.status,
        params.stripeSubscriptionId ?? null,
        params.currentPeriodEnd ?? null,
        hasStripeSubscriptionId,
        hasCurrentPeriodEnd
      ]
    );

    await this.pool.query(
      `INSERT INTO device_entitlements (user_id, max_agents, source, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (user_id) DO UPDATE
       SET max_agents = EXCLUDED.max_agents,
           source = EXCLUDED.source,
           updated_at = NOW()`,
      [params.userId, Math.max(1, params.maxAgents), params.source]
    );
  }

  async tryRecordBillingWebhookEvent(params: { provider: string; eventId: string }): Promise<boolean> {
    const result = await this.pool.query<{ event_id: string }>(
      `INSERT INTO billing_webhook_events (provider, event_id)
       VALUES ($1, $2)
       ON CONFLICT (provider, event_id) DO NOTHING
       RETURNING event_id`,
      [params.provider, params.eventId]
    );
    return Boolean(result.rows[0]);
  }

  async upsertPushRegistration(params: {
    userId: string;
    deviceId: string;
    provider: string;
    platform: string;
    token: string;
  }): Promise<PushRegistrationRecord> {
    const id = newId();
    const result = await this.pool.query<PushRegistrationRecord>(
      `INSERT INTO push_registrations (
         id,
         user_id,
         device_id,
         provider,
         platform,
         token,
         status,
         last_seen_at,
         updated_at
       )
       VALUES ($1, $2, $3, $4, $5, $6, 'active', NOW(), NOW())
       ON CONFLICT (provider, token) DO UPDATE
       SET user_id = EXCLUDED.user_id,
           device_id = EXCLUDED.device_id,
           platform = EXCLUDED.platform,
           status = 'active',
           last_error = NULL,
           last_seen_at = NOW(),
           updated_at = NOW()
       RETURNING
         id,
         user_id,
         device_id,
         provider,
         platform,
         token,
         status,
         last_error,
         created_at,
         updated_at,
         last_seen_at`,
      [id, params.userId, params.deviceId, params.provider, params.platform, params.token]
    );

    await this.pool.query(
      `UPDATE push_registrations
       SET status = 'inactive',
           last_error = 'superseded_by_new_token',
           updated_at = NOW()
       WHERE user_id = $1
         AND device_id = $2
         AND provider = $3
         AND token <> $4
         AND status = 'active'`,
      [params.userId, params.deviceId, params.provider, params.token]
    );
    return result.rows[0];
  }

  async listPushRegistrations(userId: string): Promise<PushRegistrationRecord[]> {
    const result = await this.pool.query<PushRegistrationRecord>(
      `SELECT
         id,
         user_id,
         device_id,
         provider,
         platform,
         token,
         status,
         last_error,
         created_at,
         updated_at,
         last_seen_at
       FROM push_registrations
       WHERE user_id = $1
       ORDER BY updated_at DESC`,
      [userId]
    );
    return result.rows;
  }

  async listActivePushRegistrations(userId: string): Promise<PushRegistrationRecord[]> {
    const result = await this.pool.query<PushRegistrationRecord>(
      `SELECT
         id,
         user_id,
         device_id,
         provider,
         platform,
         token,
         status,
         last_error,
         created_at,
         updated_at,
         last_seen_at
       FROM push_registrations
       WHERE user_id = $1
         AND status = 'active'
       ORDER BY updated_at DESC`,
      [userId]
    );
    return result.rows;
  }

  async deactivatePushRegistrations(params: {
    userId: string;
    provider?: string;
    token?: string;
    deviceId?: string;
    reason?: string;
  }): Promise<number> {
    const clauses = ["user_id = $1", "status = 'active'"];
    const values: string[] = [params.userId];
    if (params.provider) {
      values.push(params.provider);
      clauses.push(`provider = $${values.length}`);
    }
    if (params.token) {
      values.push(params.token);
      clauses.push(`token = $${values.length}`);
    }
    if (params.deviceId) {
      values.push(params.deviceId);
      clauses.push(`device_id = $${values.length}`);
    }
    values.push(params.reason ?? "deactivated");

    const query = `
      UPDATE push_registrations
      SET status = 'inactive',
          last_error = $${values.length},
          updated_at = NOW()
      WHERE ${clauses.join(" AND ")}
    `;
    const result = await this.pool.query(query, values);
    return result.rowCount ?? 0;
  }

  async markPushRegistrationInvalid(params: { registrationId: string; error?: string }): Promise<void> {
    await this.pool.query(
      `UPDATE push_registrations
       SET status = 'inactive',
           last_error = $2,
           updated_at = NOW()
       WHERE id = $1`,
      [params.registrationId, params.error ?? "invalid_token"]
    );
  }

  async countAgentsForUser(userId: string): Promise<number> {
    const result = await this.pool.query<{ count: number }>(
      "SELECT COUNT(*)::int AS count FROM agents WHERE user_id = $1",
      [userId]
    );
    return Number(result.rows[0]?.count ?? 0);
  }

  async getUserEntitlements(userId: string): Promise<UserEntitlements> {
    await this.ensureUserBillingDefaults(userId);
    const result = await this.pool.query<{
      plan_code: string;
      subscription_status: string;
      max_agents: number;
      source: string;
      current_agents: number;
    }>(
      `SELECT
         COALESCE(s.plan_code, 'free') AS plan_code,
         COALESCE(s.status, 'active') AS subscription_status,
         COALESCE(e.max_agents, 1) AS max_agents,
         COALESCE(e.source, 'free') AS source,
         COALESCE(a.current_agents, 0)::int AS current_agents
       FROM users u
       LEFT JOIN subscriptions s ON s.user_id = u.id
       LEFT JOIN device_entitlements e ON e.user_id = u.id
       LEFT JOIN (
         SELECT user_id, COUNT(*)::int AS current_agents
         FROM agents
         GROUP BY user_id
       ) a ON a.user_id = u.id
       WHERE u.id = $1`,
      [userId]
    );

    const row = result.rows[0];
    if (!row) {
      return {
        userId,
        planCode: "free",
        subscriptionStatus: "active",
        maxAgents: 1,
        currentAgents: 0,
        limitReached: false,
        source: "free",
        features: {
          tunnels: false,
          pushNotifications: false,
          deferredTurns: false
        }
      };
    }

    const maxAgents = Math.max(1, Number(row.max_agents));
    const currentAgents = Math.max(0, Number(row.current_agents));
    const paidFeaturesEnabled = row.plan_code !== "free" && row.subscription_status === "active";
    return {
      userId,
      planCode: row.plan_code,
      subscriptionStatus: row.subscription_status,
      maxAgents,
      currentAgents,
      limitReached: currentAgents >= maxAgents,
      source: row.source,
      features: {
        tunnels: paidFeaturesEnabled,
        pushNotifications: paidFeaturesEnabled,
        deferredTurns: paidFeaturesEnabled
      }
    };
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

  async createAgent(
    userId: string,
    name: string,
    maxAgents: number
  ): Promise<{ agentId: string; agentToken: string }> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT id FROM users WHERE id = $1 FOR UPDATE", [userId]);
      const countResult = await client.query<{ count: number }>(
        "SELECT COUNT(*)::int AS count FROM agents WHERE user_id = $1",
        [userId]
      );
      const currentAgents = Number(countResult.rows[0]?.count ?? 0);
      const normalizedMax = Math.max(1, maxAgents);
      if (currentAgents >= normalizedMax) {
        throw new DeviceLimitReachedError(currentAgents, normalizedMax);
      }

      const agentId = newId();
      const agentToken = randomToken("na");
      await client.query(
        `INSERT INTO agents (id, user_id, name, token_hash)
         VALUES ($1, $2, $3, $4)`,
        [agentId, userId, name, sha256(agentToken)]
      );
      await client.query("COMMIT");
      return { agentId, agentToken };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
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

  async listAgents(
    userId: string
  ): Promise<Array<{ id: string; name: string; last_seen_at: Date | null; created_at: Date }>> {
    const result = await this.pool.query<{ id: string; name: string; last_seen_at: Date | null; created_at: Date }>(
      "SELECT id, name, last_seen_at, created_at FROM agents WHERE user_id = $1 ORDER BY created_at DESC",
      [userId]
    );
    return result.rows;
  }

  async createWorkspace(params: {
    userId: string;
    agentId: string;
    name: string;
    path: string;
  }): Promise<{ id: string; name: string; path: string; agent_id: string; created_at: Date }> {
    const workspaceId = newId();
    const result = await this.pool.query<{ id: string; name: string; path: string; agent_id: string; created_at: Date }>(
      `INSERT INTO workspaces (id, user_id, agent_id, name, path)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, name, path, agent_id, created_at`,
      [workspaceId, params.userId, params.agentId, params.name, params.path]
    );
    return result.rows[0];
  }

  async listWorkspaces(
    userId: string,
    agentId?: string
  ): Promise<Array<{ id: string; name: string; path: string; agent_id: string; created_at: Date }>> {
    const values: string[] = [userId];
    let query = "SELECT id, name, path, agent_id, created_at FROM workspaces WHERE user_id = $1";
    if (agentId) {
      query += " AND agent_id = $2";
      values.push(agentId);
    }
    query += " ORDER BY created_at DESC";
    const result = await this.pool.query<{ id: string; name: string; path: string; agent_id: string; created_at: Date }>(
      query,
      values
    );
    return result.rows;
  }

  async findWorkspaceById(userId: string, workspaceId: string): Promise<WorkspaceRecord | null> {
    const result = await this.pool.query<WorkspaceRecord>(
      `SELECT id, user_id, agent_id, name, path, created_at
       FROM workspaces
       WHERE user_id = $1 AND id = $2`,
      [userId, workspaceId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
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

  async getSessionById(sessionId: string): Promise<SessionRecord | null> {
    const result = await this.pool.query<SessionRecord>(
      `SELECT id, user_id, workspace_id, agent_id, name, status, cursor
       FROM sessions
       WHERE id = $1`,
      [sessionId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
  }

  async updateSessionStatus(sessionId: string, status: string): Promise<void> {
    await this.pool.query("UPDATE sessions SET status = $1, updated_at = NOW() WHERE id = $2", [status, sessionId]);
  }

  async updateSessionCursor(sessionId: string, cursor: number): Promise<void> {
    await this.pool.query("UPDATE sessions SET cursor = $1, updated_at = NOW() WHERE id = $2", [cursor, sessionId]);
  }

  async createConversation(params: {
    userId: string;
    workspaceId: string;
    agentId: string;
    title: string;
  }): Promise<ConversationRecord> {
    const id = newId();
    const result = await this.pool.query<ConversationRecord>(
      `INSERT INTO conversations (id, user_id, workspace_id, agent_id, title, status)
       VALUES ($1, $2, $3, $4, $5, 'idle')
       RETURNING id, user_id, workspace_id, agent_id, title, status, codex_thread_id, created_at, updated_at`,
      [id, params.userId, params.workspaceId, params.agentId, params.title]
    );
    return result.rows[0];
  }

  async listConversations(userId: string, workspaceId: string): Promise<ConversationRecord[]> {
    const result = await this.pool.query<ConversationRecord>(
      `SELECT id, user_id, workspace_id, agent_id, title, status, codex_thread_id, created_at, updated_at
       FROM conversations
       WHERE user_id = $1 AND workspace_id = $2
       ORDER BY updated_at DESC`,
      [userId, workspaceId]
    );
    return result.rows;
  }

  async findConversation(userId: string, conversationId: string): Promise<ConversationRecord | null> {
    const result = await this.pool.query<ConversationRecord>(
      `SELECT id, user_id, workspace_id, agent_id, title, status, codex_thread_id, created_at, updated_at
       FROM conversations
       WHERE user_id = $1 AND id = $2`,
      [userId, conversationId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
  }

  async updateConversationThreadId(conversationId: string, threadId: string): Promise<void> {
    await this.pool.query(
      "UPDATE conversations SET codex_thread_id = $1, status = 'running', updated_at = NOW() WHERE id = $2",
      [threadId, conversationId]
    );
  }

  async updateConversationStatus(conversationId: string, status: string): Promise<void> {
    await this.pool.query("UPDATE conversations SET status = $1, updated_at = NOW() WHERE id = $2", [
      status,
      conversationId
    ]);
  }

  async updateConversationTitle(conversationId: string, title: string): Promise<void> {
    await this.pool.query("UPDATE conversations SET title = $1, updated_at = NOW() WHERE id = $2", [
      title,
      conversationId
    ]);
  }

  async listConversationTurnCounts(conversationIds: string[]): Promise<Map<string, number>> {
    if (conversationIds.length === 0) {
      return new Map();
    }
    const result = await this.pool.query<{ conversation_id: string; turn_count: number | string }>(
      `SELECT conversation_id, COUNT(*)::int AS turn_count
       FROM conversation_turns
       WHERE conversation_id = ANY($1::text[])
       GROUP BY conversation_id`,
      [conversationIds]
    );
    const counts = new Map<string, number>();
    for (const row of result.rows) {
      counts.set(row.conversation_id, Number(row.turn_count) || 0);
    }
    return counts;
  }

  async listConversationHasActiveTurns(conversationIds: string[]): Promise<Map<string, boolean>> {
    if (conversationIds.length === 0) {
      return new Map();
    }
    const result = await this.pool.query<{ conversation_id: string; has_active: boolean }>(
      `SELECT
         conversation_id,
         BOOL_OR(status IN ('queued', 'running')) AS has_active
       FROM conversation_turns
       WHERE conversation_id = ANY($1::text[])
       GROUP BY conversation_id`,
      [conversationIds]
    );
    const activity = new Map<string, boolean>();
    for (const row of result.rows) {
      activity.set(row.conversation_id, row.has_active === true);
    }
    return activity;
  }

  async createConversationTurn(params: {
    conversationId: string;
    prompt: string;
    deliveryPolicy: TurnDeliveryPolicy;
    requestOptions?: Record<string, unknown>;
  }): Promise<ConversationTurnRecord> {
    const id = newId();
    const result = await this.pool.query<ConversationTurnRecord>(
      `INSERT INTO conversation_turns (
         id,
         conversation_id,
         user_prompt,
         status,
         delivery_policy,
         request_options
       )
       VALUES ($1, $2, $3, 'queued', $4, $5::jsonb)
       RETURNING
         id,
         conversation_id,
         user_prompt,
         codex_turn_id,
         status,
         diff,
         error,
         delivery_policy,
         delivery_state,
         delivery_attempts,
         delivery_error,
         next_delivery_at,
         request_options,
         created_at,
         updated_at,
         completed_at`,
      [id, params.conversationId, params.prompt, params.deliveryPolicy, JSON.stringify(params.requestOptions ?? {})]
    );
    return result.rows[0];
  }

  async listConversationTurns(conversationId: string): Promise<Array<ConversationTurnRecord & { items: ConversationItemRecord[] }>> {
    const result = await this.pool.query<
      ConversationTurnRecord & {
        items: ConversationItemRecord[];
      }
    >(
      `SELECT
         t.id,
         t.conversation_id,
         t.user_prompt,
         t.codex_turn_id,
         t.status,
         t.diff,
         t.error,
         t.delivery_policy,
         t.delivery_state,
         t.delivery_attempts,
         t.delivery_error,
         t.next_delivery_at,
         t.request_options,
         t.created_at,
         t.updated_at,
         t.completed_at,
         COALESCE(
           (
             SELECT json_agg(
               json_build_object(
                 'id', i.id,
                 'turn_id', i.turn_id,
                 'item_id', i.item_id,
                 'item_type', i.item_type,
                 'ordinal', i.ordinal,
                 'payload', i.payload,
                 'created_at', i.created_at
               )
               ORDER BY i.ordinal ASC
             )
             FROM conversation_items i
             WHERE i.turn_id = t.id
           ),
           '[]'::json
         ) AS items
       FROM conversation_turns t
       WHERE t.conversation_id = $1
       ORDER BY t.created_at ASC`,
      [conversationId]
    );
    return result.rows;
  }

  async deleteConversationTurns(conversationId: string): Promise<void> {
    await this.pool.query("DELETE FROM conversation_turns WHERE conversation_id = $1", [conversationId]);
  }

  async findConversationTurn(turnId: string): Promise<ConversationTurnRecord | null> {
    const result = await this.pool.query<ConversationTurnRecord>(
      `SELECT
         id,
         conversation_id,
         user_prompt,
         codex_turn_id,
         status,
         diff,
         error,
         delivery_policy,
         delivery_state,
         delivery_attempts,
         delivery_error,
         next_delivery_at,
         request_options,
         created_at,
         updated_at,
         completed_at
       FROM conversation_turns
       WHERE id = $1`,
      [turnId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
  }

  async markConversationTurnStarted(params: {
    turnId: string;
    codexTurnId: string;
  }): Promise<void> {
    await this.pool.query(
      `UPDATE conversation_turns
       SET status = 'running',
           codex_turn_id = $1,
           delivery_state = 'dispatched',
           delivery_error = NULL,
           next_delivery_at = NULL,
           updated_at = NOW()
       WHERE id = $2`,
      [params.codexTurnId, params.turnId]
    );
  }

  async updateConversationTurnDiff(turnId: string, diff: string): Promise<void> {
    await this.pool.query(
      `UPDATE conversation_turns
       SET diff = $1, updated_at = NOW()
       WHERE id = $2`,
      [diff, turnId]
    );
  }

  async completeConversationTurn(params: {
    turnId: string;
    status: "completed" | "interrupted" | "failed";
    error?: string;
  }): Promise<void> {
    await this.pool.query(
      `UPDATE conversation_turns
       SET status = $1,
           error = $2,
           delivery_state = CASE WHEN $1 = 'completed' THEN 'completed' ELSE 'failed' END,
           delivery_error = CASE WHEN $1 = 'completed' THEN NULL ELSE $2 END,
           completed_at = NOW(),
           updated_at = NOW()
       WHERE id = $3`,
      [params.status, params.error ?? null, params.turnId]
    );
  }

  async markConversationTurnDispatched(params: { turnId: string; incrementAttempt?: boolean }): Promise<void> {
    await this.pool.query(
      `UPDATE conversation_turns
       SET delivery_state = 'dispatched',
           delivery_attempts = delivery_attempts + CASE WHEN $1::boolean THEN 1 ELSE 0 END,
           delivery_error = NULL,
           next_delivery_at = NULL,
           updated_at = NOW()
       WHERE id = $2`,
      [params.incrementAttempt === true, params.turnId]
    );
  }

  async markConversationTurnDeferred(params: {
    turnId: string;
    error?: string;
    nextDeliveryAt?: Date | null;
  }): Promise<void> {
    await this.pool.query(
      `UPDATE conversation_turns
       SET delivery_state = 'deferred',
           delivery_error = $1,
           next_delivery_at = $2,
           updated_at = NOW()
       WHERE id = $3`,
      [params.error ?? null, params.nextDeliveryAt ?? null, params.turnId]
    );
  }

  async rescheduleDeferredConversationTurn(turnId: string): Promise<void> {
    await this.pool.query(
      `UPDATE conversation_turns
       SET delivery_state = 'deferred',
           delivery_error = NULL,
           next_delivery_at = NOW(),
           updated_at = NOW()
       WHERE id = $1`,
      [turnId]
    );
  }

  async claimDeferredConversationTurns(params: {
    agentId: string;
    limit: number;
  }): Promise<DeferredConversationTurnDispatch[]> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const selected = await client.query<{ id: string }>(
        `SELECT t.id
         FROM conversation_turns t
         JOIN conversations c ON c.id = t.conversation_id
         WHERE c.agent_id = $1
           AND t.status = 'queued'
           AND t.delivery_state = 'deferred'
           AND (t.next_delivery_at IS NULL OR t.next_delivery_at <= NOW())
         ORDER BY t.created_at ASC
         FOR UPDATE OF t SKIP LOCKED
         LIMIT $2`,
        [params.agentId, Math.max(1, Math.min(params.limit, 100))]
      );
      const claimedIds = selected.rows.map((row) => row.id);
      if (claimedIds.length === 0) {
        await client.query("COMMIT");
        return [];
      }

      await client.query(
        `UPDATE conversation_turns
         SET delivery_state = 'pending',
             delivery_attempts = delivery_attempts + 1,
             delivery_error = NULL,
             next_delivery_at = NULL,
             updated_at = NOW()
         WHERE id = ANY($1::text[])`,
        [claimedIds]
      );

      const result = await client.query<{
        user_id: string;
        turn_id: string;
        conversation_id: string;
        workspace_id: string;
        agent_id: string;
        codex_thread_id: string | null;
        user_prompt: string;
        request_options: Record<string, unknown> | null;
        workspace_path: string | null;
      }>(
        `SELECT
           c.user_id,
           t.id AS turn_id,
           t.conversation_id,
           c.workspace_id,
           c.agent_id,
           c.codex_thread_id,
           t.user_prompt,
           t.request_options,
           w.path AS workspace_path
         FROM conversation_turns t
         JOIN conversations c ON c.id = t.conversation_id
         LEFT JOIN workspaces w ON w.id = c.workspace_id
         WHERE t.id = ANY($1::text[])
         ORDER BY t.created_at ASC`,
        [claimedIds]
      );
      await client.query("COMMIT");

      return result.rows.map((row) => ({
        userId: row.user_id,
        turnId: row.turn_id,
        conversationId: row.conversation_id,
        workspaceId: row.workspace_id,
        agentId: row.agent_id,
        codexThreadId: row.codex_thread_id,
        userPrompt: row.user_prompt,
        requestOptions:
          row.request_options && typeof row.request_options === "object" ? row.request_options : {},
        workspacePath: row.workspace_path
      }));
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async upsertConversationItem(params: {
    turnId: string;
    itemId: string;
    itemType: string;
    payload: Record<string, unknown>;
  }): Promise<void> {
    const id = newId();
    await this.pool.query(
      `INSERT INTO conversation_items (id, turn_id, item_id, item_type, ordinal, payload)
       VALUES (
         $1,
         $2,
         $3,
         $4,
         (
           SELECT COALESCE(
             (
               SELECT ordinal
               FROM conversation_items
               WHERE turn_id = $2
                 AND item_id = $3
               LIMIT 1
             ),
             (
               SELECT COALESCE(MAX(ordinal), 0) + 1
               FROM conversation_items
               WHERE turn_id = $2
             )
           )
         ),
         $5::jsonb
       )
       ON CONFLICT (turn_id, item_id)
       DO UPDATE SET item_type = EXCLUDED.item_type, payload = EXCLUDED.payload`,
      [id, params.turnId, params.itemId, params.itemType, JSON.stringify(params.payload)]
    );
  }

  async addConversationItem(params: {
    turnId: string;
    itemId: string;
    itemType: string;
    payload: Record<string, unknown>;
  }): Promise<void> {
    await this.upsertConversationItem(params);
  }

  async createTunnel(params: {
    userId: string;
    workspaceId: string;
    agentId: string;
    targetPort: number;
    serviceId?: string | null;
    tokenRequired?: boolean;
    slug?: string;
    accessToken?: string;
    ttlSec?: number;
  }): Promise<{ tunnel: TunnelRecord; accessToken: string }> {
    const id = newId();
    const slug = params.slug ?? randomSlug();
    const accessToken = params.accessToken ?? randomToken("tp");
    const expiresAt = params.ttlSec ? new Date(Date.now() + params.ttlSec * 1000) : null;
    const tokenRequired = params.tokenRequired ?? true;
    const result = await this.pool.query<TunnelRecord>(
      `INSERT INTO tunnels (
         id, user_id, workspace_id, agent_id, service_id, slug,
         target_port, access_token_hash, token_required, status, expires_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'open', $10)
       RETURNING id, user_id, workspace_id, agent_id, service_id, slug, target_port, access_token_hash, token_required, status, expires_at, last_probe_at, last_probe_status, last_probe_error, last_probe_code`,
      [
        id,
        params.userId,
        params.workspaceId,
        params.agentId,
        params.serviceId ?? null,
        slug,
        params.targetPort,
        sha256(accessToken),
        tokenRequired,
        expiresAt
      ]
    );
    return { tunnel: result.rows[0], accessToken };
  }

  async listTunnels(userId: string, workspaceId: string): Promise<TunnelRecord[]> {
    const result = await this.pool.query<TunnelRecord>(
      `SELECT id, user_id, workspace_id, agent_id, service_id, slug, target_port, access_token_hash, token_required, status, expires_at, last_probe_at, last_probe_status, last_probe_error, last_probe_code
       FROM tunnels
       WHERE user_id = $1 AND workspace_id = $2
       ORDER BY created_at DESC`,
      [userId, workspaceId]
    );
    return result.rows;
  }

  async findTunnelBySlug(slug: string): Promise<TunnelRecord | null> {
    const result = await this.pool.query<TunnelRecord>(
      `SELECT id, user_id, workspace_id, agent_id, service_id, slug, target_port, access_token_hash, token_required, status, expires_at, last_probe_at, last_probe_status, last_probe_error, last_probe_code
       FROM tunnels
       WHERE slug = $1`,
      [slug]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
  }

  async findTunnelByIdForUser(userId: string, tunnelId: string): Promise<TunnelRecord | null> {
    const result = await this.pool.query<TunnelRecord>(
      `SELECT id, user_id, workspace_id, agent_id, service_id, slug, target_port, access_token_hash, token_required, status, expires_at, last_probe_at, last_probe_status, last_probe_error, last_probe_code
       FROM tunnels
       WHERE id = $1 AND user_id = $2`,
      [tunnelId, userId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
  }

  async findOpenTunnelByService(serviceId: string): Promise<TunnelRecord | null> {
    const result = await this.pool.query<TunnelRecord>(
      `SELECT id, user_id, workspace_id, agent_id, service_id, slug, target_port, access_token_hash, token_required, status, expires_at, last_probe_at, last_probe_status, last_probe_error, last_probe_code
       FROM tunnels
       WHERE service_id = $1
         AND status = 'open'
         AND (expires_at IS NULL OR expires_at > NOW())
       ORDER BY created_at DESC
       LIMIT 1`,
      [serviceId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
  }

  async updateTunnelAgent(tunnelId: string, agentId: string): Promise<void> {
    await this.pool.query(
      `UPDATE tunnels
       SET agent_id = $1, updated_at = NOW()
       WHERE id = $2`,
      [agentId, tunnelId]
    );
  }

  async updateTunnelToken(tunnelId: string, accessToken: string): Promise<void> {
    await this.pool.query(
      `UPDATE tunnels
       SET access_token_hash = $1, updated_at = NOW()
       WHERE id = $2`,
      [sha256(accessToken), tunnelId]
    );
  }

  async updateTunnelStatus(tunnelId: string, status: string): Promise<void> {
    await this.pool.query(
      `UPDATE tunnels
       SET status = $1, updated_at = NOW()
       WHERE id = $2`,
      [status, tunnelId]
    );
  }

  async updateTunnelProbe(params: {
    tunnelId: string;
    probeStatus: "ok" | "error" | "unknown";
    probeCode?: number;
    error?: string;
  }): Promise<void> {
    await this.pool.query(
      `UPDATE tunnels
       SET last_probe_at = NOW(),
           last_probe_status = $1,
           last_probe_code = $2,
           last_probe_error = $3,
           updated_at = NOW()
       WHERE id = $4`,
      [params.probeStatus, params.probeCode ?? null, params.error ?? null, params.tunnelId]
    );
  }

  async deleteTunnel(tunnelId: string, userId: string): Promise<boolean> {
    const result = await this.pool.query(
      `DELETE FROM tunnels
       WHERE id = $1 AND user_id = $2`,
      [tunnelId, userId]
    );
    return (result.rowCount ?? 0) > 0;
  }

  async getWorkspaceDevSettings(userId: string, workspaceId: string): Promise<WorkspaceDevSettingsRecord | null> {
    const workspace = await this.findWorkspaceById(userId, workspaceId);
    if (!workspace) {
      return null;
    }
    const result = await this.pool.query<WorkspaceDevSettingsRecord>(
      `SELECT workspace_id, trusted_dev_mode, created_at, updated_at
       FROM workspace_dev_settings
       WHERE workspace_id = $1`,
      [workspaceId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      const inserted = await this.pool.query<WorkspaceDevSettingsRecord>(
        `INSERT INTO workspace_dev_settings (workspace_id, trusted_dev_mode)
         VALUES ($1, FALSE)
         ON CONFLICT (workspace_id) DO UPDATE SET workspace_id = EXCLUDED.workspace_id
         RETURNING workspace_id, trusted_dev_mode, created_at, updated_at`,
        [workspaceId]
      );
      return inserted.rows[0] ?? null;
    }
    return result.rows[0];
  }

  async setWorkspaceDevSettings(params: {
    userId: string;
    workspaceId: string;
    trustedDevMode: boolean;
  }): Promise<WorkspaceDevSettingsRecord | null> {
    const workspace = await this.findWorkspaceById(params.userId, params.workspaceId);
    if (!workspace) {
      return null;
    }
    const result = await this.pool.query<WorkspaceDevSettingsRecord>(
      `INSERT INTO workspace_dev_settings (workspace_id, trusted_dev_mode)
       VALUES ($1, $2)
       ON CONFLICT (workspace_id) DO UPDATE
       SET trusted_dev_mode = EXCLUDED.trusted_dev_mode,
           updated_at = NOW()
       RETURNING workspace_id, trusted_dev_mode, created_at, updated_at`,
      [params.workspaceId, params.trustedDevMode]
    );
    return result.rows[0] ?? null;
  }

  async listDevServices(userId: string, workspaceId: string): Promise<DevServiceRecord[]> {
    const workspace = await this.findWorkspaceById(userId, workspaceId);
    if (!workspace) {
      return [];
    }
    const result = await this.pool.query<
      Omit<DevServiceRecord, "env_template" | "depends_on"> & {
        env_template: Record<string, string> | null;
        depends_on: string[] | null;
      }
    >(
      `SELECT id, user_id, workspace_id, agent_id, name, role, command, cwd, port, health_path, env_template, depends_on, auto_tunnel, created_at, updated_at
       FROM dev_services
       WHERE user_id = $1 AND workspace_id = $2
       ORDER BY created_at ASC`,
      [userId, workspaceId]
    );

    return result.rows.map((row) => ({
      ...row,
      env_template: row.env_template ?? {},
      depends_on: row.depends_on ?? []
    }));
  }

  async findDevServiceById(userId: string, serviceId: string): Promise<DevServiceRecord | null> {
    const result = await this.pool.query<
      Omit<DevServiceRecord, "env_template" | "depends_on"> & {
        env_template: Record<string, string> | null;
        depends_on: string[] | null;
      }
    >(
      `SELECT id, user_id, workspace_id, agent_id, name, role, command, cwd, port, health_path, env_template, depends_on, auto_tunnel, created_at, updated_at
       FROM dev_services
       WHERE id = $1 AND user_id = $2`,
      [serviceId, userId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    const row = result.rows[0];
    return {
      ...row,
      env_template: row.env_template ?? {},
      depends_on: row.depends_on ?? []
    };
  }

  async createDevService(params: {
    userId: string;
    workspaceId: string;
    agentId: string;
    name: string;
    role: string;
    command: string;
    cwd?: string | null;
    port: number;
    healthPath?: string;
    envTemplate?: Record<string, string>;
    dependsOn?: string[];
    autoTunnel?: boolean;
  }): Promise<DevServiceRecord> {
    const id = newId();
    const result = await this.pool.query<DevServiceRecord>(
      `INSERT INTO dev_services (
         id, user_id, workspace_id, agent_id, name, role, command, cwd, port,
         health_path, env_template, depends_on, auto_tunnel
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb, $12::jsonb, $13)
       RETURNING id, user_id, workspace_id, agent_id, name, role, command, cwd, port, health_path, env_template, depends_on, auto_tunnel, created_at, updated_at`,
      [
        id,
        params.userId,
        params.workspaceId,
        params.agentId,
        params.name,
        params.role,
        params.command,
        params.cwd ?? null,
        params.port,
        params.healthPath ?? "/",
        JSON.stringify(params.envTemplate ?? {}),
        JSON.stringify(params.dependsOn ?? []),
        params.autoTunnel ?? true
      ]
    );
    const runtime = await this.pool.query<DevServiceRuntimeRecord>(
      `INSERT INTO dev_service_runtime (service_id, status)
       VALUES ($1, 'stopped')
       ON CONFLICT (service_id) DO NOTHING
       RETURNING service_id, session_id, tunnel_id, status, last_error, updated_at`,
      [id]
    );
    void runtime;
    const created = result.rows[0];
    return {
      ...created,
      env_template: (created.env_template as unknown as Record<string, string>) ?? {},
      depends_on: (created.depends_on as unknown as string[]) ?? []
    };
  }

  async updateDevService(params: {
    userId: string;
    serviceId: string;
    name?: string;
    role?: string;
    command?: string;
    cwd?: string | null;
    port?: number;
    healthPath?: string;
    envTemplate?: Record<string, string>;
    dependsOn?: string[];
    autoTunnel?: boolean;
  }): Promise<DevServiceRecord | null> {
    const existing = await this.findDevServiceById(params.userId, params.serviceId);
    if (!existing) {
      return null;
    }
    const result = await this.pool.query<DevServiceRecord>(
      `UPDATE dev_services
       SET name = $1,
           role = $2,
           command = $3,
           cwd = $4,
           port = $5,
           health_path = $6,
           env_template = $7::jsonb,
           depends_on = $8::jsonb,
           auto_tunnel = $9,
           updated_at = NOW()
       WHERE id = $10 AND user_id = $11
       RETURNING id, user_id, workspace_id, agent_id, name, role, command, cwd, port, health_path, env_template, depends_on, auto_tunnel, created_at, updated_at`,
      [
        params.name ?? existing.name,
        params.role ?? existing.role,
        params.command ?? existing.command,
        params.cwd === undefined ? existing.cwd : params.cwd,
        params.port ?? existing.port,
        params.healthPath ?? existing.health_path,
        JSON.stringify(params.envTemplate ?? existing.env_template),
        JSON.stringify(params.dependsOn ?? existing.depends_on),
        params.autoTunnel ?? existing.auto_tunnel,
        params.serviceId,
        params.userId
      ]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    const updated = result.rows[0];
    return {
      ...updated,
      env_template: (updated.env_template as unknown as Record<string, string>) ?? {},
      depends_on: (updated.depends_on as unknown as string[]) ?? []
    };
  }

  async getServiceRuntime(serviceId: string): Promise<DevServiceRuntimeRecord | null> {
    const result = await this.pool.query<DevServiceRuntimeRecord>(
      `SELECT service_id, session_id, tunnel_id, status, last_error, updated_at
       FROM dev_service_runtime
       WHERE service_id = $1`,
      [serviceId]
    );
    if ((result.rowCount ?? 0) === 0 || !result.rows[0]) {
      return null;
    }
    return result.rows[0];
  }

  async listServiceRuntimes(workspaceId: string): Promise<DevServiceRuntimeRecord[]> {
    const result = await this.pool.query<DevServiceRuntimeRecord>(
      `SELECT r.service_id, r.session_id, r.tunnel_id, r.status, r.last_error, r.updated_at
       FROM dev_service_runtime r
       JOIN dev_services s ON s.id = r.service_id
       WHERE s.workspace_id = $1`,
      [workspaceId]
    );
    return result.rows;
  }

  async upsertServiceRuntime(params: {
    serviceId: string;
    sessionId?: string | null;
    tunnelId?: string | null;
    status: string;
    lastError?: string | null;
  }): Promise<void> {
    await this.pool.query(
      `INSERT INTO dev_service_runtime (service_id, session_id, tunnel_id, status, last_error, updated_at)
       VALUES ($1, $2, $3, $4, $5, NOW())
       ON CONFLICT (service_id) DO UPDATE
       SET session_id = EXCLUDED.session_id,
           tunnel_id = EXCLUDED.tunnel_id,
           status = EXCLUDED.status,
           last_error = EXCLUDED.last_error,
           updated_at = NOW()`,
      [params.serviceId, params.sessionId ?? null, params.tunnelId ?? null, params.status, params.lastError ?? null]
    );
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

  async consumeRateLimit(params: {
    key: string;
    maxHits: number;
    windowSec: number;
  }): Promise<{ allowed: boolean; retryAfterSec: number }> {
    const windowSec = Math.max(1, params.windowSec);
    const maxHits = Math.max(1, params.maxHits);
    const result = await this.pool.query<{
      hit_count: number;
      elapsed_sec: number;
    }>(
      `WITH upsert AS (
         INSERT INTO rate_limits (key, window_started_at, hit_count, updated_at)
         VALUES ($1, NOW(), 1, NOW())
         ON CONFLICT (key) DO UPDATE
         SET hit_count = CASE
               WHEN rate_limits.window_started_at <= NOW() - ($2::text || ' seconds')::interval THEN 1
               ELSE rate_limits.hit_count + 1
             END,
             window_started_at = CASE
               WHEN rate_limits.window_started_at <= NOW() - ($2::text || ' seconds')::interval THEN NOW()
               ELSE rate_limits.window_started_at
             END,
             updated_at = NOW()
         RETURNING hit_count, EXTRACT(EPOCH FROM (NOW() - window_started_at))::int AS elapsed_sec
       )
       SELECT hit_count, elapsed_sec FROM upsert`,
      [params.key, windowSec]
    );
    const hitCount = Number(result.rows[0]?.hit_count ?? 1);
    const elapsed = Math.max(0, Number(result.rows[0]?.elapsed_sec ?? 0));
    const retryAfterSec = Math.max(0, windowSec - elapsed);
    const allowed = hitCount <= maxHits;
    return { allowed, retryAfterSec };
  }
}
