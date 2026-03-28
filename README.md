# Nomade for Codex

Monorepo for remote control of `codex-cli` and localhost preview tunneling.

## Components
- `services/control-api`: device-code auth, agent pairing, workspace/session/tunnel APIs, WS broker.
- `services/tunnel-gateway`: public preview subdomain gateway that proxies through control-api to the agent.
- `agent/nomade-agent`: host daemon for shell session execution and local HTTP tunnel fetches.
- `apps/mobile`: Flutter scaffold for login + pairing code generation.

## Local development
Fast one-command dev loop:
- `npm run dev:full -- you@example.com`
- `npm run dev:stop`

1. Start Postgres (`docker run ...` from `QUICKSTART.md`).
2. Install dependencies: `npm install`.
3. Build and test: `npm run build && npm test`.
4. Start API and gateway:
   - `npm run dev:control`
   - `npm run dev:gateway`
5. Pair and run agent:
   - `npm run dev:agent:pair -- --server-url http://localhost:8080 --pairing-code <PAIRING_CODE>`
   - `npm run dev:agent:run`

Detailed local flow: [`QUICKSTART.md`](./QUICKSTART.md)  
Troubleshooting: [`docs/troubleshooting.md`](./docs/troubleshooting.md)

## Self-host
Use [`deploy/selfhost/docker-compose.yml`](./deploy/selfhost/docker-compose.yml).

## Notes
- Tunnel WebSocket upgrade proxying is not yet implemented in the gateway.
- Shell sessions use spawned shell processes (interactive), not a full native PTY implementation yet.
# Nomade-For-Codex
