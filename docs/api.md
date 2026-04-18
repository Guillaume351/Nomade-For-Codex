# API Contract (v1)

> Status note (April 2026)
> - Auth, pairing, conversations, and sessions are the actively supported API flows.
> - Tunnel endpoints exist in the contract but are currently WIP and may be unavailable in running deployments.

## Canonical SaaS web routes
- `/login`, `/signup`, `/forgot-password`, `/reset-password`, `/verify-email`
- `/activate`, `/account`, `/devices`, `/billing`
- Legacy `/web/*` routes are redirected to canonical routes.

## Public auth
- `POST/GET /api/auth/*` Better Auth endpoints (email/password, email verification, password reset, magic link, optional social providers)
- `POST /auth/device/start` -> `{ deviceCode, userCode, expiresAt, intervalSec, verificationUri, verificationUriComplete }`
- `POST /auth/device/approve` body `{ userCode }` with authenticated web session (or Bearer token)
- `POST /auth/device/poll` body `{ deviceCode }` -> pending or `{ accessToken, refreshToken }`
- `POST /auth/refresh` body `{ refreshToken }`
- `POST /auth/logout` body `{ refreshToken }` (requires Bearer access token)

## User endpoints (Bearer access token)
- `GET /me`
- `GET /me/entitlements` -> `{ planCode, maxAgents, currentAgents, limitReached, features: { tunnels, pushNotifications, deferredTurns }, ... }`
  - `planCode` may be `self_host` when server runs with `BILLING_MODE=self_host`.
- `GET /me/push/registrations`
- `POST /me/push/register` body `{ deviceId, provider: "fcm", platform: "ios"|"android", token }`
- `POST /me/push/unregister` body `{ provider?, token? | deviceId? }`
- `POST /billing/checkout-session` -> `{ id, url }` (Stripe Checkout)
- `POST /billing/portal-session` -> `{ id, url }` (Stripe Customer Portal)
- `POST /agents/pair`
  - returns `403 { error: "device_limit_reached", ... }` when free plan quota is reached
  - in `BILLING_MODE=self_host`, quota depends on server-side `FREE_MAX_AGENTS` (not client settings)
- `GET /agents` (sorted online first; each item includes `display_name`, `is_online`, `last_seen_at`, `created_at`)
  - response includes `entitlements`
- `POST /agents/:agentId/codex/import` body `{ limit? }`
  - imports threads from Codex app-server into Nomade workspaces/conversations (default limit `500`)
  - response counters include `threads_scanned`, `imported`, `skipped`, `hydrated_or_repaired`
- `GET /agents/:agentId/codex/options?cwd=...`
  - returns runtime options from Codex app-server:
    - `models`
    - `approvalPolicies`
    - `sandboxModes`
    - `reasoningEfforts`
    - `mcpServers`
    - `defaults` (`model`, `approvalPolicy`, `sandboxMode`, `effort`)
- `POST /agents/:agentId/codex/mcp/server-enabled` body `{ name, enabled }`
  - toggles an MCP server `enabled` flag through the online agent (Codex config write + MCP reload)
- `POST /workspaces` body `{ agentId, name, path }`
- `GET /workspaces?agentId=...` (optional filter by active agent)
- `POST /conversations` body `{ workspaceId, agentId?, title? }`
- `GET /conversations?workspaceId=...`
- `GET /conversations/:conversationId/turns?forceHydrate=1`
  - includes `hydration` metadata: `{ attempted, repaired, deferred, reason }`
- `POST /conversations/:conversationId/turns` body `{ prompt?, e2ePromptEnvelope, inputItems?, model?, cwd?, approvalPolicy?, sandboxMode?, effort?, deliveryPolicy? }`
  - `deliveryPolicy`: `immediate` (default) | `defer_if_offline`
  - when offline + `defer_if_offline`, returns `202` with `delivery_state=deferred`
- `POST /conversations/:conversationId/turns/:turnId/interrupt`
- `POST /conversations/:conversationId/turns/:turnId/retry` (manual deferred retry)
- `POST /sessions` body `{ workspaceId, agentId, name, command, cwd? }`
- `GET /sessions?workspaceId=...`
- `POST /tunnels` body `{ workspaceId, agentId, targetPort, ttlSec? }` (WIP, currently not reliably available)
- `GET /tunnels?workspaceId=...` (WIP, currently not reliably available)

## Internal endpoint (gateway -> saas backend API)
- `POST /internal/tunnels/:slug/proxy` (WIP)
- `GET /internal/tunnels/:slug/ws` (WebSocket upgrade, WIP)
- Requires `x-gateway-secret`.
- Body: `{ method, path, query?, headers, bodyBase64?, token }`.

## Billing webhook
- `POST /billing/webhook` (Stripe)
  - Expects Stripe signature header `Stripe-Signature`.
- `POST /billing/revenuecat/webhook` (RevenueCat)
  - Expects configured `Authorization` header value.

## WebSocket protocol (`/ws`)
### Auth
- User socket: `?access_token=<jwt>`
- Agent socket: `?agent_token=<opaque token>`

### Messages to agent
- `session.create`, `session.input`, `session.terminate`, `tunnel.open`, `tunnel.http.request`
- `conversation.turn.start`, `conversation.turn.interrupt`
- `conversation.sync.threads` (internal sync bindings: conversation <-> thread)

### Messages from agent
- `session.output`, `session.status`, `tunnel.status`, `tunnel.http.response`, `agent.heartbeat`
- `conversation.thread.started`
- `conversation.thread.status.changed`
- `conversation.thread.name.updated`
- `conversation.turn.started`
- `conversation.item.delta`
- `conversation.item.completed`
- `conversation.turn.diff.updated`
- `conversation.turn.completed`

### Messages from control-api to user socket
- `notification.event`
  - `eventType`: `action_required` | `quota_available` | `deferred_turn_started` | `deferred_turn_completed`
- `codex.sync.updated` (automatic Codex thread sync completed, refresh local lists)
- `codex.sync.error` (automatic Codex sync failed, includes recoverable auth/config hints)
