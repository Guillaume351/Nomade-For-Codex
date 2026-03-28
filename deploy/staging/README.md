# Staging deployment (remote server)

This setup deploys prebuilt images from GHCR.

## 1) GitHub setup (once)
- In GitHub: `Settings -> Actions -> General -> Workflow permissions`
- Enable `Read and write permissions` (required for publishing to GHCR).
- Merge to `main` (or run the workflow manually) to publish images via:
  - `.github/workflows/publish-images.yml`

Images published:
- `ghcr.io/<owner>/nomade-for-codex-control-api:<tag>`
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
docker compose logs -f control-api
```

## 4) API quick check
```bash
curl -i http://<STAGING_HOST_OR_IP>:8080/health
```

## 5) Pair + run your local agent against staging
1. Start auth flow:
```bash
curl -sX POST http://<STAGING_HOST_OR_IP>:8080/auth/device/start | jq
```
2. Approve code:
```bash
curl -sX POST http://<STAGING_HOST_OR_IP>:8080/auth/device/approve \
  -H 'content-type: application/json' \
  -d '{"userCode":"<USER_CODE>","email":"you@example.com"}'
```
3. Poll token:
```bash
curl -sX POST http://<STAGING_HOST_OR_IP>:8080/auth/device/poll \
  -H 'content-type: application/json' \
  -d '{"deviceCode":"<DEVICE_CODE>"}' | jq
```
4. Create pairing code:
```bash
curl -sX POST http://<STAGING_HOST_OR_IP>:8080/agents/pair \
  -H "authorization: Bearer <ACCESS_TOKEN>" | jq
```
5. Pair the agent:
```bash
npm run dev:agent:pair -- --server-url http://<STAGING_HOST_OR_IP>:8080 --pairing-code <PAIRING_CODE>
```
6. Run the agent:
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
