# Staging deployment (remote server)

This setup deploys prebuilt images from GHCR.

Before deployment, complete:
- `docs/auth-better-auth-checklist.md`
- `docs/saas-nuxt-big-bang-checklist.md`

## 1) GitHub setup (once)
- In GitHub: `Settings -> Actions -> General -> Workflow permissions`
- Enable `Read and write permissions` (required for publishing to GHCR).
- Merge to `main` (or run the workflow manually) to publish images via:
  - `.github/workflows/publish-images.yml`

Images published:
- `ghcr.io/<owner>/nomade-for-codex-saas:<tag>`
- `ghcr.io/<owner>/nomade-for-codex-tunnel-gateway:<tag>`

## 2) Prepare server
```bash
mkdir -p ~/nomade-staging
cd ~/nomade-staging
```

Copy the two files:
- `deploy/staging/docker-compose.yml`
- `deploy/staging/.env.example` as `.env`

Edit `.env` with your values.
For temporary auth troubleshooting, set:
- `AUTH_DEBUG_LOGS=true`
- `HTTP_ACCESS_LOGS=true`

If the GHCR package is private, log in:
```bash
echo "$GHCR_PAT" | docker login ghcr.io -u <github_username> --password-stdin
```
`GHCR_PAT` must have at least `read:packages`.

## 3) Deploy/update
```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs -f saas
```

## 4) API quick check
```bash
curl -i http://<STAGING_HOST_OR_IP>:8080/health
```

## 5) Login + pair + run your local agent against staging
1. Login (prints code + activation URL):
```bash
npm --workspace agent/nomade-agent run login -- --server-url http://<STAGING_HOST_OR_IP>:8080
```
2. Pair the agent (auto-requests pairing code):
```bash
npm --workspace agent/nomade-agent run pair -- --server-url http://<STAGING_HOST_OR_IP>:8080
```
3. Run the agent:
```bash
npm run dev:agent:run
```

## 6) Test from mobile over remote staging
Use a public URL reachable from your phone. HTTPS is recommended for mobile compatibility.

Run mobile app with staging API URL:
```bash
cd apps/mobile
fvm flutter run -d <device-id> --dart-define NOMADE_API_URL=https://<YOUR_STAGING_DOMAIN>
```

If you only expose plain HTTP:
```bash
fvm flutter run -d <device-id> --dart-define NOMADE_API_URL=http://<STAGING_HOST_OR_IP>:8080
```
