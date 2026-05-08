#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR/infra"
cat seed.sql | docker compose exec -T db psql -v ON_ERROR_STOP=1 -U forest -d forestmap
cat dev_detections_seed.sql | docker compose exec -T db psql -v ON_ERROR_STOP=1 -U forest -d forestmap
echo 'Dev seed applied.'
