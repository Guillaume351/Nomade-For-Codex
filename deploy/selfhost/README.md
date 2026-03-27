# Self-host (Docker Compose)

## Start
```bash
docker compose -f deploy/selfhost/docker-compose.yml up --build
```

## Pair an agent
1. Create a user device code:
```bash
curl -sX POST http://localhost:8080/auth/device/start | jq
```
2. Approve with your email:
```bash
curl -sX POST http://localhost:8080/auth/device/approve \
  -H 'content-type: application/json' \
  -d '{"userCode":"<USER_CODE>","email":"you@example.com"}'
```
3. Poll for access token:
```bash
curl -sX POST http://localhost:8080/auth/device/poll \
  -H 'content-type: application/json' \
  -d '{"deviceCode":"<DEVICE_CODE>"}' | jq
```
4. Request pairing code:
```bash
curl -sX POST http://localhost:8080/agents/pair \
  -H "authorization: Bearer <ACCESS_TOKEN>" | jq
```
5. Pair local agent:
```bash
npm --workspace agent/nomade-agent run dev -- pair --server-url http://localhost:8080 --pairing-code <PAIRING_CODE>
```
6. Run agent:
```bash
npm --workspace agent/nomade-agent run dev -- run
```
