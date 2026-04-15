# Using a Deployed Instance (SaaS / Staging / Self-host)

This guide explains how to use Nomade from your machine against a remote deployed server (not `localhost`).

Auth deployment checklist (env + SMTP + DB migration):
- [`docs/auth-better-auth-checklist.md`](./auth-better-auth-checklist.md)

## Prerequisites
- Node.js 24+ (LTS) and npm.
- Network access to your deployed control API URL (for example `https://app.example.com`).
- A user account on that deployed instance (Better Auth email/password or enabled social login).
- No extra system package is required for QR display (rendered by the CLI itself).

## 1) Install the CLI
Global install (recommended):

```bash
npm install -g @nomade/agent
```

One-shot without global install:

```bash
npx -y @nomade/agent help
```

## 2) Set the server URL
You can pass `--server-url` to each command, or set it once:

```bash
export CONTROL_HTTP_URL=https://app.example.com
```

## 3) Guided setup (login + pair + start)
Run:

```bash
nomade-agent install --server-url https://app.example.com
```

What happens:
- If no valid session exists, CLI starts login (QR/code flow), then stores local session tokens.
- If no pairing config exists, CLI requests a pairing code and registers this machine as an agent.
- CLI starts the daemon in the background and writes runtime/log files.

Default session file:
- `~/.config/nomade-agent/session.json` (mode `600`)

Default agent config file:
- `~/.config/nomade-agent/config.json`

Runtime files:
- `~/.config/nomade-agent/runtime.json`
- `~/.config/nomade-agent/agent.log`

## 4) Check identity and plan
Run:

```bash
nomade-agent whoami --server-url https://app.example.com
```

This prints:
- authenticated user email/id
- plan and current device usage (`current/max`)

## 5) Common operations
- Status:

```bash
nomade-agent status
```

- Start daemon:

```bash
nomade-agent start
```

- Stop daemon:

```bash
nomade-agent stop
```

- Restart daemon:

```bash
nomade-agent restart
```

- Logs:

```bash
nomade-agent logs --lines 200
```

- Logout current user session:

```bash
nomade-agent logout --server-url https://app.example.com
```

- Clean local uninstall (stops daemon + removes local state files):

```bash
nomade-agent uninstall
```

- Remove global binary:

```bash
npm uninstall -g @nomade/agent
```

- Use non-default paths:

```bash
nomade-agent login --server-url https://app.example.com --session /path/session.json
nomade-agent pair --server-url https://app.example.com --config /path/config.json
```

## 6) Quick troubleshooting
- `Control API is not reachable`: verify URL, DNS, TLS certificate, and firewall.
- `invalid_token`: run `logout`, then `login` again.
- `device_limit_reached`: remove device from account/devices or upgrade plan from account/billing page (`/account`, legacy `/web/account` still redirects).
- Agent appears offline: ensure daemon is running (`nomade-agent status`) and machine can reach API/WebSocket.

## 7) Use from Flutter app (iPhone / iPad) to control the paired machine
The mobile app controls an already paired/running agent. Recommended order:

1. On the host machine (the machine you want to control), complete:
   - `install`
   - `status` (confirm online daemon)
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
