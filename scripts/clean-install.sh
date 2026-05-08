#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra"
[[ -f "$INFRA_DIR/.env" ]] || "$ROOT_DIR/scripts/generate-env.sh"
"$ROOT_DIR/scripts/check-deps.sh"
cd "$INFRA_DIR"
docker compose down -v --remove-orphans
docker compose up -d --build
sleep 8
docker compose restart api
echo 'Clean install completed.'
