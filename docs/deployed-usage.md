# Using a Deployed Instance (SaaS / Staging / Self-host)

This guide explains how to use Nomade from your machine against a remote deployed server (not `localhost`).

Auth deployment checklist (env + SMTP + DB migration):
- [`docs/auth-better-auth-checklist.md`](./auth-better-auth-checklist.md)

## Prerequisites
- Node.js 20+ and npm.
- Network access to your deployed control API URL (for example `https://app.example.com`).
- A user account on that deployed instance (Better Auth email/password or enabled social login).
- No extra system package is required for QR display (rendered by the CLI itself).

## 1) Set the server URL
You can pass `--server-url` to each command, or set it once:

```bash
export CONTROL_HTTP_URL=https://app.example.com
```

## 2) Login from CLI (QR/code flow)
Run:

```bash
npm --workspace agent/nomade-agent run login -- --server-url https://app.example.com
```

What happens:
- CLI prints a `user code`.
- CLI prints an activation URL and tries to open your browser.
- You can scan/use that URL from another device (phone, other laptop), sign in, and approve.
- CLI polls until tokens are issued, then stores a local session.

Default session file:
- `~/.config/nomade-agent/session.json` (mode `600`)

## 3) Check identity and plan
Run:

```bash
npm --workspace agent/nomade-agent run whoami -- --server-url https://app.example.com
```

This prints:
- authenticated user email/id
- plan and current device usage (`current/max`)

## 4) Pair this machine as an agent
Run:

```bash
npm --workspace agent/nomade-agent run pair -- --server-url https://app.example.com
```

What happens:
- CLI uses your user session to request a pairing code from API.
- API enforces plan limits (`Free=1` by default).
- Agent credentials are saved locally.

Default agent config file:
- `~/.config/nomade-agent/config.json`

If device limit is reached, pairing is blocked with:
- `device_limit_reached`
- upgrade URL (`/web/account`)

## 5) Start the agent daemon
Run:

```bash
npm --workspace agent/nomade-agent run run
```

Keep this process running on the machine you want to control remotely.

## 6) Common operations
- Logout current user session:

```bash
npm --workspace agent/nomade-agent run logout -- --server-url https://app.example.com
```

- Use non-default paths:

```bash
npm --workspace agent/nomade-agent run login -- --server-url https://app.example.com --session /path/session.json
npm --workspace agent/nomade-agent run pair -- --server-url https://app.example.com --config /path/config.json
```

## 7) Quick troubleshooting
- `Control API is not reachable`: verify URL, DNS, TLS certificate, and firewall.
- `invalid_token`: run `logout`, then `login` again.
- `device_limit_reached`: remove device from account/devices or upgrade plan from account/billing page.
- Agent appears offline: ensure `run` command is still active and machine can reach API/WebSocket.

## 8) Use from Flutter app (iPhone / iPad) to control the paired machine
The mobile app controls an already paired/running agent. Recommended order:

1. On the host machine (the machine you want to control), complete:
   - `login`
   - `pair`
   - `run`
2. On your Mac (for iOS build), run Flutter app with deployed API URL:

```bash
cd apps/mobile
fvm install
fvm flutter pub get
fvm flutter devices
fvm flutter run -d <ios-device-id> --dart-define NOMADE_API_URL=https://app.example.com
```

3. In the app:
   - Sign in.
   - Open sidebar and select an online agent.
   - Create/select a workspace.
   - Create/select a conversation and send prompts.

### Mobile auth note
Mobile login opens `verificationUriComplete` in the browser and polls `/auth/device/poll` until approved.
No legacy `{ userCode, email }` approve call is required.
