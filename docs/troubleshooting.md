# Troubleshooting (Dev)

## `Import failed: API 409: agent_offline`
- Cause: selected agent exists in DB but its websocket is not connected.
- Fix:
  1. Pair if needed: `npm run dev:agent:pair -- --server-url http://localhost:8080 --pairing-code <PAIRING_CODE>`
  2. Run daemon: `npm run dev:agent:run`
  3. In mobile app, ensure active agent is marked `Online`.

## Conversation shows only `completed` with no assistant text
- Cause: imported turn payload was incomplete or requires refresh.
- Fix:
  1. Open the conversation again (auto hydration/repair runs).
  2. If banner appears, click `Retry hydrate`.

## `API 401: invalid_token`
- Cause: expired access token and refresh failed.
- Fix:
  1. Use in-app logout/login.
  2. If reproducing often, check system clock drift and backend uptime.

## macOS `PlatformException ... -34018 ... required entitlement isn't present`
- Cause: keychain capability missing for secure session storage.
- Fix:
  1. Ensure `keychain-access-groups` exists in both `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`.
  2. Rebuild app (`fvm flutter run -d macos`).

## Flutter app cannot connect on iPhone/iPad
- Cause: `localhost` on device points to the phone, not your Mac.
- Fix:
  1. `ipconfig getifaddr en0`
  2. Run with `--dart-define NOMADE_API_URL=http://<MAC_LAN_IP>:8080`
