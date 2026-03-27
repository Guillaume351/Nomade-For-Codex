# API Contract (v1)

## Public auth
- `POST /auth/device/start` -> `{ deviceCode, userCode, expiresAt, intervalSec }`
- `POST /auth/device/approve` body `{ userCode, email }`
- `POST /auth/device/poll` body `{ deviceCode }` -> pending or `{ accessToken, refreshToken }`
- `POST /auth/refresh` body `{ refreshToken }`

## User endpoints (Bearer access token)
- `GET /me`
- `POST /agents/pair`
- `GET /agents`
- `POST /workspaces` body `{ agentId, name, path }`
- `GET /workspaces`
- `POST /conversations` body `{ workspaceId, agentId?, title? }`
- `GET /conversations?workspaceId=...`
- `GET /conversations/:conversationId/turns`
- `POST /conversations/:conversationId/turns` body `{ prompt, model?, cwd? }`
- `POST /conversations/:conversationId/turns/:turnId/interrupt`
- `POST /sessions` body `{ workspaceId, agentId, name, command, cwd? }`
- `GET /sessions?workspaceId=...`
- `POST /tunnels` body `{ workspaceId, agentId, targetPort, ttlSec? }`
- `GET /tunnels?workspaceId=...`

## Internal endpoint (gateway -> control-api)
- `POST /internal/tunnels/:slug/proxy`
- Requires `x-gateway-secret`.
- Body: `{ method, path, query?, headers, bodyBase64?, token }`.

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
