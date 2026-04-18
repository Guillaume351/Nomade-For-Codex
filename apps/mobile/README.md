# Nomade Mobile (Flutter)

This app now includes a cross-platform conversation UI scaffold for:
- Device code login flow
- Secure session restore (access + refresh token)
- Pairing code generation
- Codex thread import (`thread/list`) into Nomade workspaces/conversations
- Auto sync + repair of imported history (`thread/read`) with retry action
- Conversation list + turn timeline
- Streaming Markdown output
- Diff rendering per turn
- Running/completed/interrupted turn states
- Agent online/offline status and explicit active agent selection
- Logout and realtime reconnect controls

## Run
```bash
cd apps/mobile
fvm install
fvm flutter pub get
fvm flutter run -d macos
```

Other supported targets:
```bash
fvm flutter run -d linux
fvm flutter run -d chrome
fvm flutter run -d <ios-device-id>
```

For Windows desktop builds, run Flutter from Windows PowerShell/CMD (not from WSL shell).

Linux desktop prerequisites (Ubuntu/WSL):
```bash
sudo apt-get update
sudo apt-get install -y libsecret-1-dev
```

For a physical iPhone/iPad, do not use `localhost` (it points to the phone).
Use your Mac LAN IP:
```bash
ipconfig getifaddr en0
fvm flutter run -d <ios-device-id> --dart-define NOMADE_API_URL=http://<MAC_LAN_IP>:8080
```

Use Android emulator host alias (`10.0.2.2`) if needed instead of `localhost`.

You can override API URL:
```bash
fvm flutter run -d macos --dart-define NOMADE_API_URL=http://localhost:8080
```

RevenueCat mobile billing keys:
```bash
fvm flutter run -d <ios-device-id> \
  --dart-define NOMADE_API_URL=http://<MAC_LAN_IP>:8080 \
  --dart-define NOMADE_RC_APPLE_API_KEY=appl_xxxxxxxxxxxxx
```

For Android builds:
```bash
fvm flutter run -d <android-device-id> \
  --dart-define NOMADE_API_URL=http://10.0.2.2:8080 \
  --dart-define NOMADE_RC_GOOGLE_API_KEY=goog_xxxxxxxxxxxxx
```

The mobile app passes Nomade `/me.id` to RevenueCat as `appUserID`, which must match the RevenueCat webhook mapping expected by the control API.

Dev auto-login (used by `npm run dev:full`):
```bash
fvm flutter run -d macos \
  --dart-define NOMADE_API_URL=http://localhost:8080 \
  --dart-define NOMADE_DEV_EMAIL=you@example.com \
  --dart-define NOMADE_DEV_AUTO_LOGIN=true
```

Common errors:
- `API 409: agent_offline`: pair done, but daemon is not running. Start `npm run dev:agent:run`.
- `History hydration deferred: agent_offline`: agent disconnected while loading imported turns. Reconnect agent and click `Retry hydrate`.
