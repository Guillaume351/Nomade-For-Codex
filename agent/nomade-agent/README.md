# `@nomade/agent`

Nomade host agent CLI for remote Codex control and local tunnel bridging.

## Install

```bash
npm install -g @nomade/agent
```

## First-time setup (recommended)

```bash
nomade-agent install --server-url https://app.example.com
```

This guided command will:
- login if no valid session exists
- pair/register this machine if needed
- start the daemon in background

## Lifecycle commands

```bash
nomade-agent status
nomade-agent start
nomade-agent stop
nomade-agent restart
nomade-agent logs --lines 200
nomade-agent uninstall
```

## Auth/pair commands (advanced/manual)

```bash
nomade-agent login --server-url https://app.example.com
nomade-agent whoami --server-url https://app.example.com
nomade-agent pair --server-url https://app.example.com
nomade-agent logout --server-url https://app.example.com
```

## Local files

- Session: `~/.config/nomade-agent/session.json`
- Agent config: `~/.config/nomade-agent/config.json`
- Runtime state: `~/.config/nomade-agent/runtime.json`
- Daemon log: `~/.config/nomade-agent/agent.log`

## Foreground mode

```bash
nomade-agent run
```
