#!/usr/bin/env bash
set -euo pipefail

# ForestMap service manager (interactive menu + CLI)
# Intended location:
#   <repo>/scripts/forestmapctl.sh
#
# Works with the CURRENT local repository (no git clone / no git pull).
# "update" = rebuild/restart containers from current local sources.
#
# Commands:
#   install/start/stop/restart/status/logs/update/env-init/deps
#   backup-db restore-db safe-remove remove purge
#
# safe-remove = stop stack + remove containers/networks (KEEP volumes/data) + remove systemd unit
# remove      = stop stack + remove containers/networks/volumes (DELETE data) + remove systemd unit
# purge       = remove + delete project directory (dangerous)

APP_NAME="forestmap"

# Script location: <repo>/scripts/forestmapctl.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_DEFAULT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Optional override, otherwise use repo root detected from script location
INSTALL_DIR="${FORESTMAP_DIR:-$PROJECT_ROOT_DEFAULT}"
INFRA_DIR="$INSTALL_DIR/infra"
COMPOSE_FILE="$INFRA_DIR/docker-compose.yml"
ENV_FILE="$INFRA_DIR/.env"
ENV_EXAMPLE="$INFRA_DIR/.env.example"
SYSTEMD_UNIT="/etc/systemd/system/${APP_NAME}.service"
BACKUP_DIR_DEFAULT="$INSTALL_DIR/backups"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "ERROR: run as root (or via sudo)."
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

os_id() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

normalize_unix_eol() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  local tmp
  tmp="$(mktemp)"
  sed 's/\r$//' "$f" > "$tmp"
  cat "$tmp" > "$f"
  rm -f "$tmp"
}

load_env_file() {
  if [[ -f "$ENV_FILE" ]]; then
    normalize_unix_eol "$ENV_FILE"
    # shellcheck disable=SC1090
    source "$ENV_FILE" >/dev/null 2>&1 || true
  fi
}

install_deps() {
  need_root

  local id
  id="$(os_id)"

  if [[ "$id" != "ubuntu" && "$id" != "debian" ]]; then
    echo "WARN: this installer is optimized for Debian/Ubuntu."
    echo "      Detected OS ID: $id"
    echo "      Install manually if needed: docker + docker compose plugin + git + curl + jq + openssl"
  fi

  if ! have_cmd curl || ! have_cmd jq || ! have_cmd git || ! have_cmd openssl; then
    echo "==> Installing base tools (curl, jq, git, openssl)..."
    apt_install ca-certificates curl jq git openssl
  fi

  if ! have_cmd docker; then
    echo "==> Installing Docker (docker.io)..."
    apt_install docker.io
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "==> Installing docker compose plugin..."
    if apt-cache show docker-compose-plugin >/dev/null 2>&1; then
      apt_install docker-compose-plugin
    else
      apt_install docker-compose
    fi
  fi

  echo "==> Enabling Docker daemon..."
  systemctl enable --now docker >/dev/null 2>&1 || true

  echo "==> Dependencies OK:"
  docker --version || true
  docker compose version || true
  git --version || true
  jq --version || true
  openssl version || true
}

require_project_layout() {
  [[ -d "$INSTALL_DIR" ]] || { echo "ERROR: project dir not found: $INSTALL_DIR"; exit 1; }
  [[ -d "$INFRA_DIR" ]] || { echo "ERROR: infra dir not found: $INFRA_DIR"; exit 1; }
  [[ -f "$COMPOSE_FILE" ]] || { echo "ERROR: docker-compose.yml not found: $COMPOSE_FILE"; exit 1; }
}

compose() {
  require_project_layout
  if [[ -f "$ENV_FILE" ]]; then
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  else
    docker compose -f "$COMPOSE_FILE" "$@"
  fi
}

rand_secret() {
  openssl rand -base64 24 | tr -d '\n' | tr '+/' 'Aa'
}

init_env() {
  need_root
  require_project_layout

  if [[ -f "$ENV_FILE" ]]; then
    echo "==> .env already exists: $ENV_FILE"
    return 0
  fi

  if [[ ! -f "$ENV_EXAMPLE" ]]; then
    echo "ERROR: .env.example not found: $ENV_EXAMPLE"
    echo "Please add infra/.env.example to the repository."
    exit 1
  fi

  normalize_unix_eol "$ENV_EXAMPLE"

  echo "==> Creating .env from .env.example..."
  cp -f "$ENV_EXAMPLE" "$ENV_FILE"
  normalize_unix_eol "$ENV_FILE"

  local forest_db kc_db kc_admin
  forest_db="$(rand_secret)"
  kc_db="$(rand_secret)"
  kc_admin="$(rand_secret)"

  sed -i \
    -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${forest_db}/" \
    -e "s/^KEYCLOAK_DB_PASSWORD=.*/KEYCLOAK_DB_PASSWORD=${kc_db}/" \
    -e "s/^KEYCLOAK_ADMIN_PASSWORD=.*/KEYCLOAK_ADMIN_PASSWORD=${kc_admin}/" \
    "$ENV_FILE" || true

  sed -i \
    -e "s/CHANGE_ME_FOREST_DB_PASSWORD/${forest_db}/g" \
    -e "s/CHANGE_ME_KEYCLOAK_DB_PASSWORD/${kc_db}/g" \
    -e "s/CHANGE_ME_KEYCLOAK_ADMIN_PASSWORD/${kc_admin}/g" \
    "$ENV_FILE" || true

  chmod 600 "$ENV_FILE"
  echo "==> Created: $ENV_FILE"
  echo "    (passwords generated automatically)"
}

create_systemd_unit() {
  need_root
  require_project_layout

  local compose_start compose_stop
  if [[ -f "$ENV_FILE" ]]; then
    compose_start="/usr/bin/docker compose --env-file $ENV_FILE -f $COMPOSE_FILE up -d --build"
    compose_stop="/usr/bin/docker compose --env-file $ENV_FILE -f $COMPOSE_FILE down"
  else
    compose_start="/usr/bin/docker compose -f $COMPOSE_FILE up -d --build"
    compose_stop="/usr/bin/docker compose -f $COMPOSE_FILE down"
  fi

  echo "==> Creating systemd unit: $SYSTEMD_UNIT"

  cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=ForestMap (docker compose stack)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INFRA_DIR
Environment=COMPOSE_PROJECT_NAME=forestmap
ExecStart=$compose_start
ExecStop=$compose_stop
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${APP_NAME}.service"
  echo "==> systemd service enabled: ${APP_NAME}.service"
}

remove_systemd_unit() {
  need_root
  if [[ -f "$SYSTEMD_UNIT" ]]; then
    systemctl disable --now "${APP_NAME}.service" >/dev/null 2>&1 || true
    rm -f "$SYSTEMD_UNIT"
    systemctl daemon-reload
    echo "==> Removed systemd unit: $SYSTEMD_UNIT"
  else
    echo "==> systemd unit not found (skip): $SYSTEMD_UNIT"
  fi
}

wait_http_ready() {
  local name="$1"
  local url="$2"
  local timeout="${3:-90}"
  local sleep_s="${4:-2}"

  local started now elapsed
  started="$(date +%s)"

  echo "==> Waiting for $name: $url (timeout ${timeout}s)"
  while true; do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1 || curl -fsSI --max-time 3 "$url" >/dev/null 2>&1; then
      echo "   OK: $name"
      return 0
    fi

    now="$(date +%s)"
    elapsed=$((now - started))
    if (( elapsed >= timeout )); then
      echo "   TIMEOUT: $name not ready after ${timeout}s"
      return 1
    fi

    sleep "$sleep_s"
  done
}

wait_services() {
  load_env_file

  local api_port="${API_PORT:-8081}"
  local nginx_port="${NGINX_PORT:-8443}"

  api_port="$(printf '%s' "$api_port" | tr -d '\r' | xargs)"
  nginx_port="$(printf '%s' "$nginx_port" | tr -d '\r' | xargs)"

  local ok=0

  # API обычно поднимается быстро, но может рестартнуться из-за ожидания БД
  if ! wait_http_ready "API" "http://localhost:${api_port}/healthz" 90 2; then
    ok=1
  fi

  # Через nginx API может быть доступен чуть позже
  if ! wait_http_ready "Gateway API" "http://localhost:${nginx_port}/api/healthz" 90 2; then
    ok=1
  fi

  # Keycloak на первом старте может подниматься дольше (миграции)
  if ! wait_http_ready "Keycloak via nginx" "http://localhost:${nginx_port}/auth/" 180 3; then
    ok=1
  fi

  return "$ok"
}

health_check() {
  echo "==> Health checks (best effort):"
  set +e

  load_env_file

  local api_port="${API_PORT:-8081}"
  local nginx_port="${NGINX_PORT:-8443}"

  api_port="$(printf '%s' "$api_port" | tr -d '\r' | xargs)"
  nginx_port="$(printf '%s' "$nginx_port" | tr -d '\r' | xargs)"

  echo "  - API:     http://localhost:${api_port}/healthz"
  curl -fsS "http://localhost:${api_port}/healthz" && echo || echo "  (failed)"

  echo "  - Gateway: http://localhost:${nginx_port}/api/healthz"
  curl -fsS "http://localhost:${nginx_port}/api/healthz" && echo || echo "  (failed)"

  echo "  - Keycloak via nginx: http://localhost:${nginx_port}/auth/"
  curl -fsSI "http://localhost:${nginx_port}/auth/" | head -n 5 || echo "  (failed)"

  set -e
}

backup_db_cmd() {
  need_root
  require_project_layout

  load_env_file

  local db_service="${FORESTMAP_DB_SERVICE:-db}"
  local backup_dir="${FORESTMAP_BACKUP_DIR:-$BACKUP_DIR_DEFAULT}"
  local ts out_file

  mkdir -p "$backup_dir"
  ts="$(date +%Y%m%d_%H%M%S)"
  out_file="${backup_dir}/${APP_NAME}_db_${ts}.sql.gz"

  echo "==> Ensuring DB container is running..."
  compose up -d "$db_service" >/dev/null

  echo "==> Creating DB backup..."
  echo "   service : $db_service"
  echo "   file    : $out_file"

  # Используем переменные окружения внутри контейнера БД.
  compose exec -T "$db_service" sh -lc \
    'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    | gzip -c > "$out_file"

  chmod 600 "$out_file" || true
  echo "✅ Backup created: $out_file"
  echo
  echo "Restore examples:"
  echo "  $0 restore-db \"$out_file\""
  echo "  $0 restore-db              # restore latest backup from default backups dir"
}

restore_db_cmd() {
  need_root
  require_project_layout
  load_env_file

  local db_service="${FORESTMAP_DB_SERVICE:-db}"
  local backup_dir="${FORESTMAP_BACKUP_DIR:-$BACKUP_DIR_DEFAULT}"
  local input_file="${1:-}"

  if [[ -z "$input_file" ]]; then
    if [[ -d "$backup_dir" ]]; then
      input_file="$(ls -1t "$backup_dir"/*.sql.gz "$backup_dir"/*.sql 2>/dev/null | head -n1 || true)"
    fi
  fi

  if [[ -z "$input_file" ]]; then
    echo "ERROR: backup file not specified and no backups found in: $backup_dir"
    echo "Usage: $0 restore-db /path/to/backup.sql.gz"
    exit 1
  fi

  if [[ ! -f "$input_file" ]]; then
    echo "ERROR: backup file not found: $input_file"
    exit 1
  fi

  echo "⚠️  RESTORE will overwrite app DB contents in service '$db_service'."
  echo "   Backup file: $input_file"
  echo "   This operation is destructive for current data."
  read -r -p "Подтвердить восстановление БД? (yes/NO): " ans
  if [[ "${ans:-}" != "yes" ]]; then
    echo "Cancelled."
    return 0
  fi

  echo "==> Ensuring DB container is running..."
  compose up -d "$db_service" >/dev/null

  echo "==> Recreating public schema + PostGIS extension..."
  compose exec -T "$db_service" sh -lc '
    PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<SQL
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO PUBLIC;
GRANT ALL ON SCHEMA public TO "$POSTGRES_USER";
CREATE EXTENSION IF NOT EXISTS postgis;
SQL
  '

  echo "==> Restoring from backup..."
  case "$input_file" in
    *.sql.gz)
      gunzip -c "$input_file" | compose exec -T "$db_service" sh -lc \
        'PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
      ;;
    *.sql)
      cat "$input_file" | compose exec -T "$db_service" sh -lc \
        'PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
      ;;
    *)
      echo "ERROR: unsupported backup format (use .sql or .sql.gz)"
      exit 1
      ;;
  esac

  echo "✅ Restore completed."
}

install_cmd() {
  install_deps
  require_project_layout
  init_env
  echo "==> Starting stack..."
  compose up -d --build
  create_systemd_unit

  # Ждем готовность сервисов, чтобы не ловить ложные 502/connection reset
  if ! wait_services; then
    echo "WARN: Some services did not become ready in time. Showing logs snapshot..."
    compose ps || true
    compose logs --tail=80 api nginx db keycloak keycloak-db 2>/dev/null || true
  fi

  health_check
  echo "✅ Installed & running from local repository."
  echo "   - Project dir: $INSTALL_DIR"
  echo "   - Env file:    $ENV_FILE"
}

start_cmd() {
  require_project_layout
  echo "==> Starting..."
  compose up -d
  systemctl start "${APP_NAME}.service" >/dev/null 2>&1 || true

  if ! wait_services; then
    echo "WARN: Some services did not become ready in time."
  fi
  health_check
}

stop_cmd() {
  require_project_layout
  echo "==> Stopping..."
  systemctl stop "${APP_NAME}.service" >/dev/null 2>&1 || true
  compose down
}

restart_cmd() {
  echo "==> Restarting..."
  stop_cmd
  start_cmd
}

status_cmd() {
  echo "==> systemd status:"
  systemctl status "${APP_NAME}.service" --no-pager || true
  echo
  echo "==> docker compose ps:"
  compose ps || true
}

logs_cmd() {
  require_project_layout
  local svc="${1:-}"
  if [[ -n "$svc" ]]; then
    compose logs --tail=200 -f "$svc"
  else
    compose logs --tail=200 -f
  fi
}

update_cmd() {
  need_root
  require_project_layout
  echo "==> Rebuild/restart from current local sources..."
  compose up -d --build

  if ! wait_services; then
    echo "WARN: Some services did not become ready in time."
  fi
  health_check
}

safe_remove_cmd() {
  need_root
  require_project_layout

  echo "⚠️  SAFE REMOVE will delete:"
  echo "   - Docker containers/networks for this compose project (compose down)"
  echo "   - orphan containers for this compose file"
  echo "   - systemd unit ${APP_NAME}.service"
  echo "   It will KEEP:"
  echo "   - Docker volumes (DB data, uploads, etc.)"
  echo "   - project directory: $INSTALL_DIR"
  read -r -p "Подтвердить safe remove? (yes/NO): " ans
  if [[ "${ans:-}" != "yes" ]]; then
    echo "Cancelled."
    return 0
  fi

  remove_systemd_unit
  compose down --remove-orphans || true
  echo "✅ Safe remove completed (volumes/data preserved)."
}

remove_cmd() {
  need_root
  require_project_layout

  echo "⚠️  REMOVE will delete:"
  echo "   - Docker containers/networks/volumes for this compose project (compose down -v)"
  echo "   - orphan containers for this compose file"
  echo "   - systemd unit ${APP_NAME}.service"
  echo "   It will NOT delete the project directory: $INSTALL_DIR"
  echo "   NOTE: volumes include DB data and uploaded files."
  read -r -p "Подтвердить удаление стека С ДАННЫМИ? (yes/NO): " ans
  if [[ "${ans:-}" != "yes" ]]; then
    echo "Cancelled."
    return 0
  fi

  remove_systemd_unit
  compose down -v --remove-orphans || true
  echo "✅ Stack removed (project files kept, data volumes deleted)."
}

purge_cmd() {
  need_root
  require_project_layout

  echo "⚠️  PURGE will delete EVERYTHING:"
  echo "   - systemd unit ${APP_NAME}.service"
  echo "   - Docker containers/networks/volumes (compose down -v)"
  echo "   - project directory $INSTALL_DIR"
  echo "   - this script too, if it is inside the project directory"
  read -r -p "Подтвердить ПОЛНОЕ удаление? (yes/NO): " ans
  if [[ "${ans:-}" != "yes" ]]; then
    echo "Cancelled."
    return 0
  fi

  remove_systemd_unit
  compose down -v --remove-orphans || true
  rm -rf "$INSTALL_DIR"
  echo "✅ Purged."
}

env_init_cmd() { init_env; }
deps_cmd() { install_deps; }

menu_pause() {
  echo
  read -r -p "Нажмите Enter для возврата в меню..." _
}

menu_logs() {
  echo
  read -r -p "Имя сервиса для логов (api/nginx/db/keycloak/keycloak-db/frontend) или пусто для всех: " svc
  echo "Ctrl+C чтобы выйти из tail."
  if [[ -n "${svc:-}" ]]; then
    logs_cmd "$svc"
  else
    logs_cmd
  fi
}

menu_backup_restore() {
  echo
  echo "1) Создать бэкап (backup-db)"
  echo "2) Восстановить последний бэкап"
  echo "3) Восстановить из указанного файла"
  echo "0) Назад"
  read -r -p "Выберите пункт [0-3]: " c
  case "${c:-}" in
    1) backup_db_cmd ;;
    2) restore_db_cmd ;;
    3)
      read -r -p "Путь к .sql или .sql.gz: " f
      restore_db_cmd "${f:-}"
      ;;
    0) ;;
    *) echo "Неверный пункт." ;;
  esac
}

menu_show_paths() {
  echo
  echo "APP_NAME      = $APP_NAME"
  echo "SCRIPT_DIR    = $SCRIPT_DIR"
  echo "INSTALL_DIR   = $INSTALL_DIR"
  echo "INFRA_DIR     = $INFRA_DIR"
  echo "COMPOSE_FILE  = $COMPOSE_FILE"
  echo "ENV_FILE      = $ENV_FILE"
  echo "ENV_EXAMPLE   = $ENV_EXAMPLE"
  echo "SYSTEMD_UNIT  = $SYSTEMD_UNIT"
  echo "BACKUP_DIR    = ${FORESTMAP_BACKUP_DIR:-$BACKUP_DIR_DEFAULT}"
}

interactive_menu() {
  while true; do
    clear 2>/dev/null || true
    cat <<EOF
========================================
        ForestMap Service Manager
========================================
PROJECT_ROOT: $INSTALL_DIR

 1) Установка (deps + .env + up + systemd)
 2) Запуск сервиса
 3) Остановка сервиса
 4) Перезапуск сервиса
 5) Статус
 6) Логи
 7) Обновление (rebuild текущего кода)
 8) Создать .env из .env.example (env-init)
 9) Установить/проверить зависимости
10) Бэкап БД (app db -> .sql.gz)
11) Восстановление БД из бэкапа
12) Safe Remove (удалить стек, но СОХРАНИТЬ volumes/данные)
13) Remove (удалить стек + volumes/данные)
14) Purge (удалить всё, включая папку проекта)
15) Показать пути/переменные
 0) Выход
EOF
    echo
    read -r -p "Выберите пункт [0-15]: " choice

    case "${choice:-}" in
      1) install_cmd; menu_pause ;;
      2) start_cmd; menu_pause ;;
      3) stop_cmd; menu_pause ;;
      4) restart_cmd; menu_pause ;;
      5) status_cmd; menu_pause ;;
      6) menu_logs; menu_pause ;;
      7) update_cmd; menu_pause ;;
      8) env_init_cmd; menu_pause ;;
      9) deps_cmd; menu_pause ;;
      10) backup_db_cmd; menu_pause ;;
      11) menu_backup_restore; menu_pause ;;
      12) safe_remove_cmd; menu_pause ;;
      13) remove_cmd; menu_pause ;;
      14) purge_cmd; menu_pause ;;
      15) menu_show_paths; menu_pause ;;
      0) echo "Bye."; break ;;
      *) echo "Неверный пункт."; sleep 1 ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage:
  $0                      # interactive menu
  $0 install              Install deps, init .env, start stack, enable systemd
  $0 start                Start docker compose stack
  $0 stop                 Stop stack
  $0 restart              Restart stack
  $0 status               Show systemd + compose status
  $0 logs [svc]           Tail logs (optionally service name)
  $0 update               Rebuild/restart from CURRENT local sources (no git pull)
  $0 env-init             Create infra/.env from .env.example + generate secrets
  $0 deps                 Install/check dependencies
  $0 backup-db            Backup app PostgreSQL DB to .sql.gz (default: <repo>/backups)
  $0 restore-db [file]    Restore app PostgreSQL DB from .sql/.sql.gz (if no file: latest backup)
  $0 safe-remove          Remove stack + systemd, KEEP volumes/data
  $0 remove               Remove stack + volumes + systemd unit (DELETE data)
  $0 purge                Remove stack + volumes + systemd unit + project directory

Important:
  This script is intended to be located at:
    <repo>/scripts/forestmapctl.sh
  Paths are resolved automatically from the script location.

Environment variables:
  FORESTMAP_DIR          Optional override for repository root (default: parent dir of script)
  FORESTMAP_BACKUP_DIR   Optional backup output dir (default: <repo>/backups)
  FORESTMAP_DB_SERVICE   Optional compose DB service name for backup/restore (default: db)

Examples:
  sudo ./scripts/forestmapctl.sh install
  sudo ./scripts/forestmapctl.sh status
  sudo ./scripts/forestmapctl.sh logs api
  sudo ./scripts/forestmapctl.sh backup-db
  sudo ./scripts/forestmapctl.sh restore-db
  sudo ./scripts/forestmapctl.sh restore-db /path/to/backup.sql.gz
  sudo ./scripts/forestmapctl.sh safe-remove
  sudo ./scripts/forestmapctl.sh update
EOF
}

cmd="${1:-}"
if [[ $# -gt 0 ]]; then shift; fi

case "$cmd" in
  install)      install_cmd ;;
  start)        start_cmd ;;
  stop)         stop_cmd ;;
  restart)      restart_cmd ;;
  status)       status_cmd ;;
  logs)         logs_cmd "$@" ;;
  update)       update_cmd ;;
  env-init)     env_init_cmd ;;
  deps)         deps_cmd ;;
  backup-db)    backup_db_cmd ;;
  restore-db)   restore_db_cmd "$@" ;;
  safe-remove)  safe_remove_cmd ;;
  remove)       remove_cmd ;;
  purge)        purge_cmd ;;
  "")           interactive_menu ;;
  -h|--help|help) usage ;;
  *)
    echo "Unknown command: $cmd"
    usage
    exit 1
    ;;
esac
