#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd jq
need_cmd npm
need_cmd fvm

API_URL="${NOMADE_API_URL:-http://localhost:8080}"
EMAIL="${1:-${NOMADE_DEV_EMAIL:-}}"
DEVICE="${NOMADE_FLUTTER_DEVICE:-macos}"
FORCE_PAIR="${NOMADE_FORCE_PAIR:-0}"
CONFIG_PATH="${NOMADE_AGENT_CONFIG_PATH:-$HOME/.config/nomade-agent/config.json}"
DEV_DIR="$ROOT_DIR/.dev"
AGENT_PID_FILE="$DEV_DIR/agent.pid"
AGENT_LOG_FILE="$DEV_DIR/agent.log"
AGENT_RESTARTED=0

if [[ -z "$EMAIL" ]]; then
  echo "Usage: npm run dev:full -- <email>" >&2
  echo "or set NOMADE_DEV_EMAIL in your environment." >&2
  exit 1
fi

echo "[dev:full] starting docker stack..."
npm run dev:up >/dev/null

echo "[dev:full] waiting for control API at $API_URL..."
for _ in $(seq 1 90); do
  if curl -sf "$API_URL/health" >/dev/null; then
    break
  fi
  sleep 1
done
if ! curl -sf "$API_URL/health" >/dev/null; then
  echo "Control API is not reachable at $API_URL" >&2
  exit 1
fi

echo "[dev:full] authenticating as $EMAIL..."
start_payload="$(curl -sfX POST "$API_URL/auth/device/start")"
device_code="$(jq -r '.deviceCode // empty' <<<"$start_payload")"
user_code="$(jq -r '.userCode // empty' <<<"$start_payload")"
if [[ -z "$device_code" || -z "$user_code" ]]; then
  echo "Failed to start device code flow: $start_payload" >&2
  exit 1
fi

curl -sfX POST "$API_URL/auth/device/approve" \
  -H 'content-type: application/json' \
  -d "{\"userCode\":\"$user_code\",\"email\":\"$EMAIL\"}" >/dev/null

access_token=""
for _ in $(seq 1 45); do
  poll_payload="$(curl -sfX POST "$API_URL/auth/device/poll" \
    -H 'content-type: application/json' \
    -d "{\"deviceCode\":\"$device_code\"}")"
  poll_status="$(jq -r '.status // "pending"' <<<"$poll_payload")"
  if [[ "$poll_status" == "ok" ]]; then
    access_token="$(jq -r '.accessToken // empty' <<<"$poll_payload")"
    break
  fi
  if [[ "$poll_status" == "expired" ]]; then
    echo "Device code expired while logging in." >&2
    exit 1
  fi
  sleep 1
done

if [[ -z "$access_token" ]]; then
  echo "Failed to retrieve access token." >&2
  exit 1
fi

pairing_code=""
pairing_reason=""
if [[ "$FORCE_PAIR" == "1" ]]; then
  pairing_reason="NOMADE_FORCE_PAIR=1"
elif [[ ! -f "$CONFIG_PATH" ]]; then
  pairing_reason="missing config"
fi

configured_agent_id=""
configured_server_url=""
if [[ -z "$pairing_reason" && -f "$CONFIG_PATH" ]]; then
  configured_agent_id="$(jq -r '.agentId // empty' "$CONFIG_PATH" 2>/dev/null || true)"
  configured_server_url="$(jq -r '.controlHttpUrl // empty' "$CONFIG_PATH" 2>/dev/null || true)"
  if [[ -z "$configured_agent_id" ]]; then
    pairing_reason="config has no agentId"
  elif [[ -n "$configured_server_url" && "$configured_server_url" != "$API_URL" ]]; then
    pairing_reason="config points to another server ($configured_server_url)"
  else
    agents_payload="$(curl -sf "$API_URL/agents" -H "authorization: Bearer $access_token")"
    known_agent="$(jq -r --arg id "$configured_agent_id" '.items[]? | select(.id == $id) | .id' <<<"$agents_payload")"
    if [[ -z "$known_agent" ]]; then
      pairing_reason="configured agent not owned by authenticated user"
    fi
  fi
fi

if [[ -n "$pairing_reason" ]]; then
  echo "[dev:full] pairing required: $pairing_reason"
  echo "[dev:full] creating pairing code..."
  pair_payload="$(curl -sfX POST "$API_URL/agents/pair" \
    -H "authorization: Bearer $access_token")"
  pairing_code="$(jq -r '.pairingCode // empty' <<<"$pair_payload")"
  if [[ -z "$pairing_code" ]]; then
    echo "Failed to get pairing code: $pair_payload" >&2
    exit 1
  fi
  echo "[dev:full] pairing code: $pairing_code"
  npm run dev:agent:pair -- --server-url "$API_URL" --pairing-code "$pairing_code"
  AGENT_RESTARTED=1
else
  echo "[dev:full] existing agent config is valid, pairing skipped ($CONFIG_PATH)."
fi

mkdir -p "$DEV_DIR"
if [[ -f "$AGENT_PID_FILE" ]]; then
  old_pid="$(cat "$AGENT_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    if [[ "$AGENT_RESTARTED" == "1" ]]; then
      echo "[dev:full] restarting agent to load fresh pairing (pid=$old_pid)..."
      kill "$old_pid" || true
      rm -f "$AGENT_PID_FILE"
      sleep 1
    else
      echo "[dev:full] agent already running (pid=$old_pid)."
    fi
  else
    rm -f "$AGENT_PID_FILE"
  fi
fi

if [[ ! -f "$AGENT_PID_FILE" ]]; then
  echo "[dev:full] starting local agent..."
  nohup npm run dev:agent:run >"$AGENT_LOG_FILE" 2>&1 &
  echo "$!" >"$AGENT_PID_FILE"
  sleep 1
  if ! kill -0 "$(cat "$AGENT_PID_FILE")" 2>/dev/null; then
    echo "Agent failed to start. Check $AGENT_LOG_FILE" >&2
    exit 1
  fi
fi

resolved_agent_id="$(jq -r '.agentId // empty' "$CONFIG_PATH" 2>/dev/null || true)"
if [[ -n "$resolved_agent_id" ]]; then
  echo "[dev:full] waiting for agent heartbeat ($resolved_agent_id)..."
  for _ in $(seq 1 30); do
    agents_payload="$(curl -sf "$API_URL/agents" -H "authorization: Bearer $access_token")"
    online="$(jq -r --arg id "$resolved_agent_id" '.items[]? | select(.id == $id) | .is_online' <<<"$agents_payload")"
    if [[ "$online" == "true" ]]; then
      echo "[dev:full] agent online."
      break
    fi
    sleep 1
  done
fi

echo "[dev:full] launching Flutter app on $DEVICE..."
cd "$ROOT_DIR/apps/mobile"
fvm flutter pub get >/dev/null
exec fvm flutter run -d "$DEVICE" \
  --dart-define="NOMADE_API_URL=$API_URL" \
  --dart-define="NOMADE_DEV_EMAIL=$EMAIL" \
  --dart-define="NOMADE_DEV_AUTO_LOGIN=true"
