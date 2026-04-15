# Nomade for Codex

Nomade is an open-source remote companion for Codex: pair a machine running `codex-cli` and control it from web/mobile with conversations, sessions, and device-aware auth.

## Project status (April 2026)
- Active development, not production-ready.
- Core flows are usable: login, device pairing, conversation sync, and remote shell sessions.
- Strict E2E transport is enforced for turns, terminal input/output, and server request approvals (plaintext fallback paths disabled, including terminal stream/cursor metadata and server-request method names).
- Dev service start is disabled in strict E2E mode until an encrypted launch design is implemented.
- Preview tunnels are currently **work in progress** and should be treated as **not available** for real usage.
- Interfaces and APIs can still change between releases.

## What is in this monorepo
- `apps/saas`: Nuxt fullstack app for `nomade.*` (canonical SaaS UI: login/signup/account/billing/devices/activate) and public API surface.
- `services/control-api`: backend runtime used by SaaS for auth, agents, workspaces, conversations, and session orchestration.
- `services/tunnel-gateway`: public preview subdomain gateway (currently WIP; see status above).
- `agent/nomade-agent`: host daemon + production CLI (`install`, `start`, `stop`, `status`, `logs`, `login`, `whoami`, `pair`, `run`, `uninstall`) for remote execution and Codex bridge.
- `apps/mobile`: Flutter client scaffold for login, pairing, and conversation UX.

## Quick local run
Fast loop:
- `npm run dev:full`
- `npm run dev:stop`

Manual flow:
1. Set strong secrets in env (`JWT_SECRET`, `INTERNAL_GATEWAY_SECRET`).
2. Use Node from repo config: `nvm use` (Node 24 from `.nvmrc`).
3. Install dependencies: `npm install`.
4. Build and test: `npm run build && npm test`.
5. Start backend stack:
   - `npm run dev:control`
   - `npm run dev:gateway`
6. Setup/start local agent daemon:
   - `npm run dev:agent:setup -- --server-url http://localhost:8080`
   - `npm run dev:agent:start`
   - `npm run dev:agent:status`

Detailed local flow: [`QUICKSTART.md`](./QUICKSTART.md)  
Troubleshooting: [`docs/troubleshooting.md`](./docs/troubleshooting.md)

## Deployed usage
SaaS/staging/self-host guide: [`docs/deployed-usage.md`](./docs/deployed-usage.md)

## Additional docs
- API contract: [`docs/api.md`](./docs/api.md)
- Architecture: [`docs/architecture.md`](./docs/architecture.md)
- Auth rollout checklist (Better Auth + SMTP + DB migration): [`docs/auth-better-auth-checklist.md`](./docs/auth-better-auth-checklist.md)
- Nuxt SaaS cutover checklist: [`docs/saas-nuxt-big-bang-checklist.md`](./docs/saas-nuxt-big-bang-checklist.md)
- Phase 2 setup checklist (RevenueCat/Firebase/mobile bridge): [`docs/setup-checklist-phase2.md`](./docs/setup-checklist-phase2.md)
- Phase 1+2 test runbook: [`docs/testing-runbook-phase1-phase2.md`](./docs/testing-runbook-phase1-phase2.md)

## Self-host
Use [`deploy/selfhost/docker-compose.yml`](./deploy/selfhost/docker-compose.yml).

## Notes
- Shell sessions use spawned shell processes (interactive), not full native PTY emulation yet.
- Public device login uses Better Auth web session (`/api/auth/*`), no external OIDC server required.

## Roadmap
- Stabilize core remote workflows (pairing, conversations, session lifecycle, diagnostics).
- Improve mobile UX for long-running conversations and agent state visibility.
- Harden self-host/deploy docs and operational checks.
- Re-introduce preview tunnels only once reliability and security targets are met.

## Support
If this project helps you and you want to follow progress, please give it a star on GitHub.
