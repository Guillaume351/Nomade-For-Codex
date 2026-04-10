# Nomade for Codex

Monorepo for remote control of `codex-cli` and localhost preview tunneling.

## Components
- `apps/saas`: Nuxt fullstack app for `nomade.*` (canonical SaaS UI: login/signup/account/billing/devices/activate) and public API surface.
- `services/control-api`: backend logic embedded by SaaS runtime for API/device/tunnel contracts.
- `services/tunnel-gateway`: public preview subdomain gateway that proxies through SaaS backend routes to the agent.
- `agent/nomade-agent`: host daemon + CLI (`login`, `whoami`, `pair`, `run`) for shell session execution and local HTTP tunnel fetches.
- `apps/mobile`: Flutter scaffold for login + pairing code generation.

## Local development
Fast one-command dev loop:
- `npm run dev:full`
- `npm run dev:stop`

1. Start Postgres (`docker run ...` from `QUICKSTART.md`).
2. Set strong secrets in env (`JWT_SECRET`, `INTERNAL_GATEWAY_SECRET`).
3. Use Node LTS from repo config: `nvm use` (reads `.nvmrc`, Node 24).
4. Install dependencies: `npm install`.
5. Build and test: `npm run build && npm test`.
6. Start API and gateway:
   - `npm run dev:control`
   - `npm run dev:gateway`
7. Login, pair and run agent:
   - `npm --workspace agent/nomade-agent run login -- --server-url http://localhost:8080`
   - `npm --workspace agent/nomade-agent run pair -- --server-url http://localhost:8080`
   - `npm run dev:agent:run`

Detailed local flow: [`QUICKSTART.md`](./QUICKSTART.md)  
Troubleshooting: [`docs/troubleshooting.md`](./docs/troubleshooting.md)
Deployed usage (SaaS/staging/self-host): [`docs/deployed-usage.md`](./docs/deployed-usage.md)
Auth rollout checklist (Better Auth + SMTP + DB migration): [`docs/auth-better-auth-checklist.md`](./docs/auth-better-auth-checklist.md)
Nuxt SaaS cutover checklist: [`docs/saas-nuxt-big-bang-checklist.md`](./docs/saas-nuxt-big-bang-checklist.md)

## Self-host
Use [`deploy/selfhost/docker-compose.yml`](./deploy/selfhost/docker-compose.yml).

## Notes
- Shell sessions use spawned shell processes (interactive), not a full native PTY implementation yet.
- Public device login uses Better Auth web session (`/api/auth/*`), no external OIDC server required.
