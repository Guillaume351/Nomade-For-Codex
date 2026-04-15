# Architecture (v1)

> Status note (April 2026)
> - Production focus is currently on auth, pairing, conversations, and remote session control.
> - The tunnel path is still under active development and is not yet considered available/reliable.

## Components
- `services/control-api`:
  - Device code auth and refresh tokens
  - Web activation/account UI, Better Auth (`/api/auth/*`) and Stripe webhook handling
  - Agent pairing and registration
  - Workspaces and sessions metadata in Postgres (tunnel metadata path is WIP)
  - Conversations + turns + items metadata in Postgres
  - WebSocket broker between mobile users and host agents
  - Internal tunnel proxy RPC endpoint for gateway
- `agent/nomade-agent`:
  - User-space daemon process
  - Managed shell sessions for remote command execution
  - Local Codex App Server bridge (`thread/start`, `turn/start`, `turn/interrupt`)
  - Localhost HTTP request execution for tunnels (WIP path)
- `services/tunnel-gateway`:
  - Public entrypoint for preview URLs (`<slug>.<preview-domain>`)
  - Validates tunnel access token
  - Forwards each HTTP request to control-api internal proxy
  - Current status: WIP / not yet reliably available
- `apps/mobile`:
  - Flutter scaffold for device code login and agent pairing code generation

## Data and control flow
1. CLI starts device code login, shows user code + verification URL (QR-compatible).
2. User approves code from web account session (`/web/activate`) backed by Better Auth login.
3. CLI polls and stores access+refresh token.
4. CLI requests pairing code; control-api enforces plan device limits.
5. Agent registers with pairing code and receives `agentToken`.
4. Agent opens WS connection to `/ws?agent_token=...`.
5. Mobile creates conversations/sessions/tunnels via REST; control-api pushes commands to agent WS.
6. Agent streams output/status/Codex turn events over WS.
7. Planned flow (WIP): tunnel gateway forwards HTTP preview requests through control-api WS RPC to the agent.

## Security defaults
- Access tokens: JWT, short-lived.
- Refresh tokens: random opaque tokens hashed in Postgres.
- Agent tokens: random opaque tokens hashed in Postgres.
- Tunnel access: random opaque token hashed in Postgres.
- Telemetry: no command/payload persistence in this v1 scaffold.

## Current v1 limits
- Session runtime uses shell child processes (interactive but not full PTY emulation).
