#!/usr/bin/env bash
set -euo pipefail

# Создает infra/.env из infra/.env.example и заполняет CHANGE_ME_* случайными значениями.
#
# Использование:
#   ./scripts/init_env.sh
#   ./scripts/init_env.sh --force       # перезаписать существующий infra/.env
#   ./scripts/init_env.sh --example /path/to/.env.example
#   ./scripts/init_env.sh --output  /path/to/.env
#
# Требования:
#   bash, awk, sed, tr, cut
#   openssl (желательно; если нет — fallback через /dev/urandom + base64)

FORCE=0
EXAMPLE_PATH=""
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
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
      sed -n '1,40p' "$0"
      exit 0
      ;;
    *)
      echo "Неизвестный аргумент: $1" >&2
      exit 1
      ;;
  esac
done

# Определяем корень репозитория относительно scripts/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXAMPLE_PATH="${EXAMPLE_PATH:-${REPO_ROOT}/infra/.env.example}"
OUTPUT_PATH="${OUTPUT_PATH:-${REPO_ROOT}/infra/.env}"

if [[ ! -f "$EXAMPLE_PATH" ]]; then
  echo "ERROR: не найден файл примера: $EXAMPLE_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

if [[ -f "$OUTPUT_PATH" && "$FORCE" -ne 1 ]]; then
  echo "ERROR: файл уже существует: $OUTPUT_PATH"
  echo "Используй --force, если хочешь перезаписать."
  exit 1
fi

# Генератор случайного секрета (без символов, которые часто ломают yaml/shell copy-paste)
rand_secret() {
  local len="${1:-32}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -d '\n' | tr '/+=' 'XYZ' | cut -c1-"$len"
  else
    # fallback
    head -c 64 /dev/urandom | base64 | tr -d '\n' | tr '/+=' 'XYZ' | cut -c1-"$len"
  fi
}

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

# Читаем example и заменяем только строки KEY=CHANGE_ME_...
while IFS= read -r line || [[ -n "$line" ]]; do
  # Пустые строки и комментарии сохраняем как есть
  if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
    printf '%s\n' "$line" >> "$TMP_FILE"
    continue
  fi

  # Матчим KEY=VALUE (с возможными пробелами)
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"

    # trim leading spaces in value
    value="${value#"${value%%[![:space:]]*}"}"

    # Сохраняем стиль кавычек, если вдруг появятся
    if [[ "$value" =~ ^\"(.*)\"$ ]]; then
      inner="${BASH_REMATCH[1]}"
      if [[ "$inner" == CHANGE_ME* ]]; then
        printf '%s="%s"\n' "$key" "$(rand_secret 32)" >> "$TMP_FILE"
      else
        printf '%s\n' "$line" >> "$TMP_FILE"
      fi
    elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
      inner="${BASH_REMATCH[1]}"
      if [[ "$inner" == CHANGE_ME* ]]; then
        printf "%s='%s'\n" "$key" "$(rand_secret 32)" >> "$TMP_FILE"
      else
        printf '%s\n' "$line" >> "$TMP_FILE"
      fi
    else
      if [[ "$value" == CHANGE_ME* ]]; then
        printf '%s=%s\n' "$key" "$(rand_secret 32)" >> "$TMP_FILE"
      else
        printf '%s\n' "$line" >> "$TMP_FILE"
      fi
    fi
  else
    # Нестандартные строки оставляем как есть
    printf '%s\n' "$line" >> "$TMP_FILE"
  fi
done < "$EXAMPLE_PATH"

mv "$TMP_FILE" "$OUTPUT_PATH"
chmod 600 "$OUTPUT_PATH"

echo "✅ Создан файл: $OUTPUT_PATH"
echo "🔐 Права: 600"

echo
echo "Сгенерированные значения (маскированно):"
grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$OUTPUT_PATH" \
  | while IFS='=' read -r k v; do
      raw="${v%\"}"; raw="${raw#\"}"
      raw="${raw%\'}"; raw="${raw#\'}"
      if [[ "$k" =~ PASSWORD|SECRET ]]; then
        echo "  $k=*** (len=${#raw})"
      fi
    done

echo
echo "Дальше:"
echo "  1) Проверь infra/.env (OIDC_ISSUER, OIDC_JWKS_URL, порты)"
echo "  2) docker compose --env-file infra/.env config"
echo "  3) docker compose --env-file infra/.env up -d --build"
