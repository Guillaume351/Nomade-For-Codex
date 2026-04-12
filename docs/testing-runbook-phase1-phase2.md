# Testing Runbook (Phase 1 + Phase 2)

This runbook validates reliability features, deferred delivery, entitlements, RevenueCat ingestion, and optional push behavior.

## 1) Local Build & Unit Tests

From repo root:

```bash
npm --workspace packages/shared run build
npm --workspace agent/nomade-agent run build
npm --workspace services/control-api run build
npm --workspace agent/nomade-agent run test
npm --workspace services/control-api run test
cd apps/mobile && fvm flutter analyze && fvm flutter test
```

## 2) No-Integration Regression Path (must pass first)

Run control-api with:

- no RevenueCat vars
- no Firebase vars

Expected:

- API boots cleanly.
- `POST /billing/revenuecat/webhook` returns `404 revenuecat_not_configured`.
- push registration endpoints can still be called if entitlement allows, but provider readiness is `false`.
- normal auth, conversation, deferred queue, and tunnels behave as before.

## 3) Agent Resilience (Phase 1A)

1. Start agent with:
   - `nomade-agent run --keep-awake=active --offline-turn-default=prompt`
2. Kill network / sleep machine / drop Wi-Fi.
3. Restore network.

Expected:

- agent process does not exit on transient websocket failure.
- reconnect loop resumes automatically.
- deferred dispatch resumes on `agent.hello` or heartbeat.

## 4) Deferred Turn Delivery (Phase 1B)

1. With agent offline:
   - create turn with `deliveryPolicy=immediate` -> expect `503 agent_offline`.
   - create turn with `deliveryPolicy=defer_if_offline` -> expect `202` + `delivery_state=deferred`.
2. Bring agent online.
3. Verify turn transitions:
   - `deferred` -> `pending/dispatched` -> `completed` (single execution only).
4. Call retry endpoint on deferred/failed turn:
   - `POST /conversations/:conversationId/turns/:turnId/retry` -> `202`.

## 5) Entitlement Enforcement (Phase 1C)

### Free user
- `features.tunnels=false`, `features.deferredTurns=false`, `features.pushNotifications=false`
- Tunnel endpoints return `403 feature_not_enabled`.
- Deferred delivery policy returns `403 feature_not_enabled`.

### Paid user
- same calls succeed.

## 6) RevenueCat Webhook (Phase 2)

Preconditions:

- `REVENUECAT_WEBHOOK_AUTH` set
- webhook payload includes app user id equal to Nomade `user.id`

Tests:

1. Send signed/authenticated webhook with active event (`INITIAL_PURCHASE`, product mapped to pro).
2. Verify `/me/entitlements` updates to paid plan.
3. Send expiration event (`EXPIRATION`) for same user.
4. Verify plan returns to free defaults.
5. Replay same webhook event id.

Expected:

- duplicate event is ignored (`duplicate: true`).
- no crashes on unknown event types (ignored safely).

## 7) Push Pipeline (Phase 2, optional)

Preconditions:

- Firebase env configured (`FIREBASE_*`)
- paid user with `features.pushNotifications=true`
- mobile registered token via `POST /me/push/register`

Trigger tests:

1. `conversation.server.request` emitted by agent:
   - expect websocket `notification.event` with `eventType=action_required`
   - expect push dispatched
2. Deferred turn resumed and completed:
   - expect `deferred_turn_started`
   - expect `deferred_turn_completed`
3. Rate limit recovery update:
   - expect `quota_available` (cooldown throttled)

Token hygiene:

- use invalid token and confirm backend marks registration inactive after provider rejection.

## 8) Mobile Runtime / Native Bridges

### Default mode (no flag)

Run app without:

```bash
--dart-define=NOMADE_ENABLE_NATIVE_NOTIFICATIONS=true
```

Expected:

- app runs normally
- no crashes from missing native integrations
- push/live status bridge is disabled by design

### Enabled mode

Run with:

```bash
--dart-define=NOMADE_ENABLE_NATIVE_NOTIFICATIONS=true
```

Expected:

- if native channels are still no-op, app still runs (no regressions)
- once native handlers are implemented, push token registration and runtime status calls execute.

## 9) npm Publish Flow (Phase 1D)

1. Create tag `vX.Y.Z`.
2. Verify GitHub Action `publish-npm.yml` runs:
   - builds shared + agent
   - publishes `@nomade/shared` then `@nomade/agent`
3. Smoke install:

```bash
npm i -g @nomade/agent
nomade-agent --help
```
