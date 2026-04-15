# Quickstart (local)

> Status note (April 2026)
> - Preview tunnels are currently work in progress and not yet available for reliable use.
> - This quickstart focuses on the flows that work now: auth, pairing, conversations, and remote sessions.

## Fast path (one command)
```bash
npm run dev:full
```
- Starts Docker services
- Authenticates your user
- Pairs agent automatically if needed
- Starts local agent daemon
- Launches Flutter app on macOS with dev auto-login

Stop everything:
```bash
npm run dev:stop
```

## 1. Install and build
```bash
# set strong secrets first (example)
export JWT_SECRET="$(openssl rand -hex 32)"
export INTERNAL_GATEWAY_SECRET="$(openssl rand -hex 32)"

npm install
npm run build
npm test
```

## 2. Start backend services (one command)
```bash
npm run dev:up
npm run dev:logs
```

## 3. Setup and start agent
```bash
# one guided flow: login (if needed) + pair (if needed)
npm run dev:agent:setup -- --server-url http://localhost:8080

# daemon lifecycle
npm run dev:agent:start
npm run dev:agent:status
npm run dev:agent:logs
```

In local dev, auth emails are logged by default (`AUTH_EMAIL_MODE=log`). Use Mailpit by setting `AUTH_EMAIL_MODE=smtp`, `AUTH_SMTP_HOST=mailpit`, `AUTH_SMTP_PORT=1025`.

## 4. Run Flutter app (macOS / iOS)
```bash
cd apps/mobile
fvm install
fvm flutter pub get
fvm flutter run -d macos
```

For iPhone/iPad, use your Mac LAN IP (not `localhost`):
```bash
ipconfig getifaddr en0
fvm flutter run -d <ios-device-id> --dart-define NOMADE_API_URL=http://<MAC_LAN_IP>:8080
```

## 5. Stop backend services
```bash
npm run dev:down
```

## Troubleshooting
- `Import failed: API 409: agent_offline`: pair succeeded but agent daemon is not running. Start it with `npm run dev:agent:start`.
- Turns show only `completed` without message body: open the conversation again (auto hydration/repair runs), or use `Retry hydrate` in the app.
- `API 401: invalid_token`: session expired; app should auto-refresh. If needed, logout/login again.
- Tunnel creation/proxy errors: expected for now, tunnel feature is still WIP.
