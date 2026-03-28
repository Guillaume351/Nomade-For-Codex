#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEV_DIR="$ROOT_DIR/.dev"
AGENT_PID_FILE="$DEV_DIR/agent.pid"

if [[ -f "$AGENT_PID_FILE" ]]; then
  pid="$(cat "$AGENT_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "[dev:stop] stopping agent (pid=$pid)..."
    kill "$pid" || true
  fi
  rm -f "$AGENT_PID_FILE"
fi

echo "[dev:stop] stopping docker stack..."
npm run dev:down
