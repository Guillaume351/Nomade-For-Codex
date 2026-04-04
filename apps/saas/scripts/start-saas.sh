#!/bin/sh
set -eu

PUBLIC_PORT="${PORT:-8080}"
COMPAT_BACKEND_PORT="${COMPAT_BACKEND_PORT:-8090}"

if [ -z "${COMPAT_BACKEND_URL:-}" ]; then
  export COMPAT_BACKEND_URL="http://127.0.0.1:${COMPAT_BACKEND_PORT}"
fi
export NUXT_COMPAT_BACKEND_URL="${COMPAT_BACKEND_URL}"

echo "[saas] starting embedded compatibility backend on :${COMPAT_BACKEND_PORT}"
PORT="${COMPAT_BACKEND_PORT}" node services/control-api/dist/index.js &
CONTROL_PID=$!
sleep 1
if ! kill -0 "${CONTROL_PID}" 2>/dev/null; then
  echo "[saas] compatibility backend failed to start"
  wait "${CONTROL_PID}" || true
  exit 1
fi

cleanup() {
  if kill -0 "${CONTROL_PID}" 2>/dev/null; then
    kill "${CONTROL_PID}" || true
  fi
}

trap cleanup INT TERM EXIT

echo "[saas] starting Nuxt server on :${PUBLIC_PORT}"
PORT="${PUBLIC_PORT}" node apps/saas/.output/server/index.mjs
