# Nomade for Codex

Monorepo for remote control of `codex-cli` and localhost preview tunneling.

## Components
- `services/control-api`: device-code auth (QR/code activation), web account + OIDC/Stripe hooks, agent pairing, workspace/session/tunnel APIs, WS broker.
- `services/tunnel-gateway`: public preview subdomain gateway that proxies through control-api to the agent.
- `agent/nomade-agent`: host daemon + CLI (`login`, `whoami`, `pair`, `run`) for shell session execution and local HTTP tunnel fetches.
- `apps/mobile`: Flutter scaffold for login + pairing code generation.

## Local development
Fast one-command dev loop:
- `npm run dev:full -- you@example.com`
- `npm run dev:stop`

1. Start Postgres (`docker run ...` from `QUICKSTART.md`).
2. Set strong secrets in env (`JWT_SECRET`, `INTERNAL_GATEWAY_SECRET`).
3. Install dependencies: `npm install`.
4. Build and test: `npm run build && npm test`.
5. Start API and gateway:
   - `npm run dev:control`
   - `npm run dev:gateway`
6. Login, pair and run agent:
   - `npm --workspace agent/nomade-agent run login -- --server-url http://localhost:8080`
   - `npm --workspace agent/nomade-agent run pair -- --server-url http://localhost:8080`
   - `npm run dev:agent:run`

Detailed local flow: [`QUICKSTART.md`](./QUICKSTART.md)  
Troubleshooting: [`docs/troubleshooting.md`](./docs/troubleshooting.md)

## Self-host
Use [`deploy/selfhost/docker-compose.yml`](./deploy/selfhost/docker-compose.yml).

## Notes
- Tunnel WebSocket upgrade proxying is not yet implemented in the gateway.
- Shell sessions use spawned shell processes (interactive), not a full native PTY implementation yet.
- Public device login requires OIDC configuration (`OIDC_*`), otherwise only optional dev fallback login can be enabled.
# Nomade-For-Codex
