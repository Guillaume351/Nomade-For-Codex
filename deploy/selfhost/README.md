# Self-host (Docker Compose)

## Start
```bash
export JWT_SECRET="$(openssl rand -hex 32)"
export INTERNAL_GATEWAY_SECRET="$(openssl rand -hex 32)"
docker compose -f deploy/selfhost/docker-compose.yml up --build
```

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
