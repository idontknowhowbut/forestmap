#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra"
EXAMPLE="$INFRA_DIR/.env.example"
TARGET="$INFRA_DIR/.env"
rand() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; }
[[ -f "$EXAMPLE" ]] || { echo "Missing $EXAMPLE" >&2; exit 1; }
content="$(cat "$EXAMPLE")"
content="${content/CHANGE_ME_FOREST_DB_PASSWORD/$(rand)}"
content="${content/CHANGE_ME_KEYCLOAK_DB_PASSWORD/$(rand)}"
content="${content/CHANGE_ME_KEYCLOAK_ADMIN_PASSWORD/$(rand)}"
printf '%s
' "$content" > "$TARGET"
echo "Generated $TARGET"
