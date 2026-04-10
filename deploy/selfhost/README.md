# Self-host (Docker Compose)

## Start
```bash
export JWT_SECRET="$(openssl rand -hex 32)"
export INTERNAL_GATEWAY_SECRET="$(openssl rand -hex 32)"
docker compose -f deploy/selfhost/docker-compose.yml up --build
```

Auth rollout checklist (SMTP + Better Auth + DB migration):
- `docs/auth-better-auth-checklist.md`
- `docs/saas-nuxt-big-bang-checklist.md`
- Manual SQL fallback: `deploy/selfhost/sql/2026-04-03-better-auth.sql`

For temporary auth troubleshooting, export:
- `AUTH_DEBUG_LOGS=true`
- `HTTP_ACCESS_LOGS=true`

SaaS service:
- Public app runs on `saas` (`:8080`) and proxies to the embedded backend process.
- `tunnel-gateway` must target `CONTROL_API_URL=http://saas:8080`.

## Pair an agent
1. Login with device code (prints activation URL):
```bash
npm --workspace agent/nomade-agent run login -- --server-url http://localhost:8080
```
2. Pair local agent (auto-requests pairing code):
```bash
npm --workspace agent/nomade-agent run pair -- --server-url http://localhost:8080
```
3. Run agent:
```bash
npm --workspace agent/nomade-agent run dev -- run
```
