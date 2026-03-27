# Architecture (v1)

## Components
- `services/control-api`:
  - Device code auth and refresh tokens
  - Agent pairing and registration
  - Workspaces, sessions, tunnels metadata in Postgres
  - Conversations + turns + items metadata in Postgres
  - WebSocket broker between mobile users and host agents
  - Internal tunnel proxy RPC endpoint for gateway
- `agent/nomade-agent`:
  - User-space daemon process
  - Managed shell sessions for remote command execution
  - Local Codex App Server bridge (`thread/start`, `turn/start`, `turn/interrupt`)
  - Localhost HTTP request execution for tunnels
- `services/tunnel-gateway`:
  - Public entrypoint for preview URLs (`<slug>.<preview-domain>`)
  - Validates tunnel access token
  - Forwards each HTTP request to control-api internal proxy
- `apps/mobile`:
  - Flutter scaffold for device code login and agent pairing code generation

## Data and control flow
1. Mobile starts device code, then approves and polls for access token.
2. Mobile requests pairing code.
3. Agent registers with pairing code and receives `agentToken`.
4. Agent opens WS connection to `/ws?agent_token=...`.
5. Mobile creates conversations/sessions/tunnels via REST; control-api pushes commands to agent WS.
6. Agent streams output/status/Codex turn events over WS.
7. Tunnel gateway forwards HTTP preview requests through control-api WS RPC to the agent.

## Security defaults
- Access tokens: JWT, short-lived.
- Refresh tokens: random opaque tokens hashed in Postgres.
- Agent tokens: random opaque tokens hashed in Postgres.
- Tunnel access: random opaque token hashed in Postgres.
- Telemetry: no command/payload persistence in this v1 scaffold.

## Current v1 limits
- Tunnel WebSocket upgrade proxying is not implemented yet in gateway.
- Session runtime uses shell child processes (interactive but not full PTY emulation).
