# Troubleshooting (Dev)

## Tunnel preview not working / unavailable URL
- Cause: tunnel feature is currently WIP and not yet reliably available.
- Fix:
  1. Expected for now; use conversations/sessions without tunnel flow.
  2. Follow project updates before relying on external preview URLs.

## `Import failed: API 409: agent_offline`
- Cause: selected agent exists in DB but its websocket is not connected.
- Fix:
  1. Pair if needed: `npm run dev:agent:pair -- --server-url http://localhost:8080 --pairing-code <PAIRING_CODE>`
  2. Run daemon: `npm run dev:agent:start`
  3. In mobile app, ensure active agent is marked `Online`.

## `Control API is not reachable at http://localhost:8080`
- Cause: `control-api` crashed during startup while dependencies were being installed (often logged as `esbuild ETXTBSY`), typically due to concurrent writes in shared `node_modules` on bind mounts (common on WSL, can happen on macOS too).
- Fix:
  1. Reset the dev stack volumes: `docker compose -f deploy/selfhost/docker-compose.dev.yml down -v`
  2. Restart services: `npm run dev:up`
  3. Verify logs if needed: `docker compose -f deploy/selfhost/docker-compose.dev.yml logs --tail 120 control-api`

## `sh: 1: tsx: not found` during `npm run dev:full`
- Cause: local workspace dependencies are not installed on the host machine, so agent scripts cannot run `tsx`.
- Fix:
  1. Install host dependencies: `npm install`
  2. Retry: `npm run dev:full -- you@example.com`
  3. If install fails in WSL with a Windows/UNC path error, ensure you are using Linux Node/npm inside WSL (not `node.exe`/`npm.cmd` from Windows PATH).

## `npm ERR! EACCES ... node_modules` during `npm run dev:full`
- Cause: `node_modules` was created by `root` (often after an older Docker bind-mount setup), so your WSL user cannot write dependencies.
- Fix:
  1. Repair ownership once: `sudo chown -R $(id -u):$(id -g) node_modules`
  2. Reinstall dependencies: `npm install`
  3. Retry: `npm run dev:full -- you@example.com`

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

## `No Flutter device found` or invalid `macos` device on WSL
- Cause: `macos` is not available outside macOS, and WSL may not expose a desktop Flutter target by default.
- Fix:
  1. List devices: `cd apps/mobile && fvm flutter devices`
  2. Set an available target explicitly, for example:
     `NOMADE_FLUTTER_DEVICE=chrome npm run dev:full -- you@example.com`

## `The current Dart SDK version is 3.2.x` during `flutter pub get`
- Cause: active Flutter SDK is too old for this app (`apps/mobile/pubspec.yaml` requires Dart `>=3.3.0`).
- Fix:
  1. Install/use the project-pinned Flutter SDK from `.fvmrc`: `cd apps/mobile && fvm install`
  2. Retry: `NOMADE_FLUTTER_DEVICE=chrome npm run dev:full -- you@example.com`

## Testing Windows app from WSL
- Cause: Flutter Windows desktop target is built/run from Windows tooling, not Linux tooling inside WSL.
- Fix:
  1. From WSL, use web target (`chrome`) for fast local testing.
  2. For native Windows desktop, run Flutter commands from PowerShell/CMD on Windows (same repository path) with a compatible Flutter SDK.

## Linux build fails with `flutter_secure_storage_linux` / `pkg_check_modules`
- Cause: Linux system dependency for secure storage plugin is missing (`libsecret-1` development headers).
- Fix:
  1. Install package: `sudo apt-get update && sudo apt-get install -y libsecret-1-dev`
  2. Retry: `NOMADE_FLUTTER_DEVICE=linux npm run dev:full -- you@example.com`
