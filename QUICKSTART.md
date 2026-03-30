# Quickstart (local)

## Fast path (one command)
```bash
npm run dev:full -- you@example.com
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
npm install
npm run build
npm test
```

## 2. Start backend services (one command)
```bash
npm run dev:up
npm run dev:logs
```

## 3. Login and pair agent
```bash
# device code start
curl -sX POST http://localhost:8080/auth/device/start | jq

# approve user code
curl -sX POST http://localhost:8080/auth/device/approve \
  -H 'content-type: application/json' \
  -d '{"userCode":"<USER_CODE>","email":"you@example.com"}'

# poll for access token
curl -sX POST http://localhost:8080/auth/device/poll \
  -H 'content-type: application/json' \
  -d '{"deviceCode":"<DEVICE_CODE>"}' | jq

# create pairing code
curl -sX POST http://localhost:8080/agents/pair \
  -H "authorization: Bearer <ACCESS_TOKEN>" | jq

# pair + run agent
npm run dev:agent:pair -- --server-url http://localhost:8080 --pairing-code <PAIRING_CODE>
npm run dev:agent:run
```

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
- `Import failed: API 409: agent_offline`: pair succeeded but agent daemon is not running. Start it with `npm run dev:agent:run`.
- Turns show only `completed` without message body: open the conversation again (auto hydration/repair runs), or use `Retry hydrate` in the app.
- `API 401: invalid_token`: session expired; app should auto-refresh. If needed, logout/login again.
