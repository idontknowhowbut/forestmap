#!/usr/bin/env bash
set -euo pipefail

# ForestMap: create infra/.env from infra/.env.example and generate secrets.
# Usage:
#   ./scripts/init_env.sh
#   ./scripts/init_env.sh --force
#   ./scripts/init_env.sh --regen-secrets
#
# Options:
#   --force         overwrite existing infra/.env
#   --regen-secrets regenerate secret values even if they are already set
#   --example PATH  path to .env.example (default: infra/.env.example)
#   --output PATH   path to .env (default: infra/.env)

FORCE=0
REGEN_SECRETS=0
EXAMPLE_PATH=""
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --regen-secrets)
      REGEN_SECRETS=1
      shift
      ;;
    --example)
      EXAMPLE_PATH="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '1,35p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Resolve repo root by script location (../ from scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXAMPLE_PATH="${EXAMPLE_PATH:-${REPO_ROOT}/infra/.env.example}"
OUTPUT_PATH="${OUTPUT_PATH:-${REPO_ROOT}/infra/.env}"

if [[ ! -f "$EXAMPLE_PATH" ]]; then
  echo "ERROR: .env.example not found: $EXAMPLE_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

if [[ -f "$OUTPUT_PATH" && "$FORCE" -ne 1 ]]; then
  echo "ERROR: $OUTPUT_PATH already exists."
  echo "Use --force to overwrite or --regen-secrets to regenerate secret values."
  exit 1
fi

# Secret keys to generate / replace
SECRET_KEYS=(
  POSTGRES_PASSWORD
  KEYCLOAK_DB_PASSWORD
  KEYCLOAK_ADMIN_PASSWORD
  DRONE_CLIENT_SECRET
  VIEWER_CLIENT_SECRET
)

# Generate random URL-safe-ish secret
rand_secret() {
  local len="${1:-40}"
  if command -v openssl >/dev/null 2>&1; then
    # remove chars that often break shell/yaml copy-paste
    openssl rand -base64 48 | tr -d '\n' | tr '/+=' 'XYZ' | cut -c1-"$len"
  else
    # fallback without openssl
    head -c 64 /dev/urandom | base64 | tr -d '\n' | tr '/+=' 'XYZ' | cut -c1-"$len"
  fi
}

is_secret_key() {
  local key="$1"
  local k
  for k in "${SECRET_KEYS[@]}"; do
    [[ "$k" == "$key" ]] && return 0
  done
  return 1
}

# If output exists and --force not used but --regen-secrets is used, work in-place.
# If output doesn't exist, copy from example first.
if [[ ! -f "$OUTPUT_PATH" || "$FORCE" -eq 1 ]]; then
  cp "$EXAMPLE_PATH" "$OUTPUT_PATH"
fi

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

# Read current file and patch secret values
while IFS= read -r line || [[ -n "$line" ]]; do
  # Preserve comments / empty lines
  if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
    printf '%s\n' "$line" >> "$TMP_FILE"
    continue
  fi

  # Match KEY=VALUE (allow spaces around '=')
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    raw_value="${BASH_REMATCH[2]}"

    if is_secret_key "$key"; then
      # Preserve quoting style if present
      quote=""
      value="$raw_value"

      # trim leading spaces in value
      value="${value#"${value%%[![:space:]]*}"}"

      if [[ "$value" =~ ^\"(.*)\"$ ]]; then
        quote='"'
        current="${BASH_REMATCH[1]}"
      elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
        quote="'"
        current="${BASH_REMATCH[1]}"
      else
        current="$value"
      fi

      should_replace=0
      if [[ "$REGEN_SECRETS" -eq 1 ]]; then
        should_replace=1
      elif [[ -z "$current" ]]; then
        should_replace=1
      elif [[ "$current" == CHANGE_ME* ]]; then
        should_replace=1
      fi

      if [[ "$should_replace" -eq 1 ]]; then
        new_val="$(rand_secret 40)"
        if [[ "$quote" == '"' ]]; then
          printf '%s="%s"\n' "$key" "$new_val" >> "$TMP_FILE"
        elif [[ "$quote" == "'" ]]; then
          printf "%s='%s'\n" "$key" "$new_val" >> "$TMP_FILE"
        else
          printf '%s=%s\n' "$key" "$new_val" >> "$TMP_FILE"
        fi
      else
        printf '%s\n' "$line" >> "$TMP_FILE"
      fi
    else
      printf '%s\n' "$line" >> "$TMP_FILE"
    fi
  else
    # Preserve non-standard lines as-is
    printf '%s\n' "$line" >> "$TMP_FILE"
  fi
done < "$OUTPUT_PATH"

mv "$TMP_FILE" "$OUTPUT_PATH"
chmod 600 "$OUTPUT_PATH"

echo "✅ Created/updated: $OUTPUT_PATH"
echo "   Example source:  $EXAMPLE_PATH"
echo "   Permissions:     $(stat -c '%a' "$OUTPUT_PATH" 2>/dev/null || ls -l "$OUTPUT_PATH")"
echo
echo "Generated/managed secret keys:"
for k in "${SECRET_KEYS[@]}"; do
  v="$(grep -E "^${k}=" "$OUTPUT_PATH" | head -n1 | cut -d= -f2- || true)"
  # redact value
  if [[ -n "$v" ]]; then
    # strip simple quotes for display
    v="${v%\"}"; v="${v#\"}"
    v="${v%\'}"; v="${v#\'}"
    echo "  - ${k}=*** (len=${#v})"
  else
    echo "  - ${k}=<not found in .env>"
  fi
done

echo
echo "Next steps:"
echo "  1) Review non-secret values in $OUTPUT_PATH (ports, issuer, jwks URL)"
echo "  2) docker compose --env-file infra/.env config"
echo "  3) docker compose --env-file infra/.env up -d --build"
