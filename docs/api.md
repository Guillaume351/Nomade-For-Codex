# API Contract (v1)

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
- `GET /me/entitlements` -> `{ planCode, maxAgents, currentAgents, limitReached, ... }`
- `POST /billing/checkout-session` -> `{ id, url }` (Stripe Checkout)
- `POST /billing/portal-session` -> `{ id, url }` (Stripe Customer Portal)
- `POST /agents/pair`
  - returns `403 { error: "device_limit_reached", ... }` when free plan quota is reached
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
    - `defaults` (`model`, `approvalPolicy`, `sandboxMode`, `effort`)
- `POST /workspaces` body `{ agentId, name, path }`
- `GET /workspaces?agentId=...` (optional filter by active agent)
- `POST /conversations` body `{ workspaceId, agentId?, title? }`
- `GET /conversations?workspaceId=...`
- `GET /conversations/:conversationId/turns?forceHydrate=1`
  - includes `hydration` metadata: `{ attempted, repaired, deferred, reason }`
- `POST /conversations/:conversationId/turns` body `{ prompt, model?, cwd?, approvalPolicy?, sandboxMode?, effort? }`
- `POST /conversations/:conversationId/turns/:turnId/interrupt`
- `POST /sessions` body `{ workspaceId, agentId, name, command, cwd? }`
- `GET /sessions?workspaceId=...`
- `POST /tunnels` body `{ workspaceId, agentId, targetPort, ttlSec? }`
- `GET /tunnels?workspaceId=...`

## Internal endpoint (gateway -> saas backend API)
- `POST /internal/tunnels/:slug/proxy`
- `GET /internal/tunnels/:slug/ws` (WebSocket upgrade)
- Requires `x-gateway-secret`.
- Body: `{ method, path, query?, headers, bodyBase64?, token }`.

## Billing webhook
- `POST /billing/webhook`
- Expects Stripe signature header `Stripe-Signature`.

## WebSocket protocol (`/ws`)
### Auth
- User socket: `?access_token=<jwt>`
- Agent socket: `?agent_token=<opaque token>`

### Messages to agent
- `session.create`, `session.input`, `session.terminate`, `tunnel.open`, `tunnel.http.request`
- `conversation.turn.start`, `conversation.turn.interrupt`

### Messages from agent
- `session.output`, `session.status`, `tunnel.status`, `tunnel.http.response`, `agent.heartbeat`
- `conversation.thread.started`
- `conversation.turn.started`
- `conversation.item.delta`
- `conversation.item.completed`
- `conversation.turn.diff.updated`
- `conversation.turn.completed`
