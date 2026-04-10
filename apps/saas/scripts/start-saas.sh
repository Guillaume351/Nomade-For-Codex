#!/bin/sh
set -eu

PUBLIC_PORT="${PORT:-8080}"
INTERNAL_BACKEND_PORT="${INTERNAL_BACKEND_PORT:-8090}"

export INTERNAL_BACKEND_PORT

echo "[saas] starting Nuxt server on :${PUBLIC_PORT} (embedded backend :${INTERNAL_BACKEND_PORT})"
PORT="${PUBLIC_PORT}" node apps/saas/.output/server/index.mjs
