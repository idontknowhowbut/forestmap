#!/usr/bin/env bash
set -euo pipefail

# ForestMap service manager (interactive menu + CLI)
# This script is intended to live inside the repository:
#   <repo>/scripts/forestmapctl.sh
#
# It works with the CURRENT local repository (no git clone / no git pull).
# Use "update" to rebuild/restart containers from current sources.
#
# Commands:
#   install/start/stop/restart/status/logs/update/env-init/deps/remove/purge
#
# remove = stop stack + remove containers/networks/volumes + remove systemd unit
# purge  = remove + delete project directory (dangerous)

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

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "ERROR: run as root (or via sudo)."
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

os_id() {
  if [[ -f /etc/os-release ]]; then
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

  echo "==> Creating .env from .env.example..."
  cp -f "$ENV_EXAMPLE" "$ENV_FILE"

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
ExecStart=/usr/bin/docker compose --env-file $ENV_FILE -f $COMPOSE_FILE up -d --build
ExecStop=/usr/bin/docker compose --env-file $ENV_FILE -f $COMPOSE_FILE down
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

health_check() {
  echo "==> Health checks (best effort):"
  set +e
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE" >/dev/null 2>&1 || true
  fi

  local api_port="${API_PORT:-8081}"
  local nginx_port="${NGINX_PORT:-8443}"

  echo "  - API:     http://localhost:${api_port}/healthz"
  curl -fsS "http://localhost:${api_port}/healthz" && echo || echo "  (failed)"

  echo "  - Gateway: http://localhost:${nginx_port}/api/healthz"
  curl -fsS "http://localhost:${nginx_port}/api/healthz" && echo || echo "  (failed)"

  echo "  - Keycloak via nginx: http://localhost:${nginx_port}/auth/"
  curl -fsSI "http://localhost:${nginx_port}/auth/" | head -n 5 || echo "  (failed)"
  set -e
}

install_cmd() {
  install_deps
  require_project_layout
  init_env
  echo "==> Starting stack..."
  compose up -d --build
  create_systemd_unit
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
  health_check
}

remove_cmd() {
  need_root
  require_project_layout
  echo "⚠️  REMOVE will delete:"
  echo "   - Docker containers/networks/volumes for this compose project (compose down -v)"
  echo "   - orphan containers for this compose file"
  echo "   - systemd unit ${APP_NAME}.service"
  echo "   It will NOT delete the project directory: $INSTALL_DIR"
  read -r -p "Подтвердить удаление стека? (yes/NO): " ans
  if [[ "${ans:-}" != "yes" ]]; then
    echo "Cancelled."
    return 0
  fi

  remove_systemd_unit
  compose down -v --remove-orphans || true
  echo "✅ Stack removed (project files kept)."
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
  read -r -p "Имя сервиса для логов (api/nginx/db/keycloak/frontend) или пусто для всех: " svc
  echo "Ctrl+C чтобы выйти из tail."
  if [[ -n "${svc:-}" ]]; then
    logs_cmd "$svc"
  else
    logs_cmd
  fi
}

menu_show_paths() {
  echo
  echo "APP_NAME      = $APP_NAME"
  echo "SCRIPT_DIR     = $SCRIPT_DIR"
  echo "INSTALL_DIR    = $INSTALL_DIR"
  echo "INFRA_DIR      = $INFRA_DIR"
  echo "COMPOSE_FILE   = $COMPOSE_FILE"
  echo "ENV_FILE       = $ENV_FILE"
  echo "ENV_EXAMPLE    = $ENV_EXAMPLE"
  echo "SYSTEMD_UNIT   = $SYSTEMD_UNIT"
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
10) Remove (удалить стек, volumes, systemd; проект оставить)
11) Purge (удалить всё, включая папку проекта)
12) Показать пути/переменные
 0) Выход
EOF
    echo
    read -r -p "Выберите пункт [0-12]: " choice

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
      10) remove_cmd; menu_pause ;;
      11) purge_cmd; menu_pause ;;
      12) menu_show_paths; menu_pause ;;
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
  $0 remove               Remove stack + volumes + systemd unit (keep project files)
  $0 purge                Remove stack + volumes + systemd unit + project directory

Important:
  This script is intended to be located at:
    <repo>/scripts/forestmapctl.sh
  Paths are resolved automatically from the script location.

Environment variables:
  FORESTMAP_DIR        Optional override for repository root (default: parent dir of script)

Examples:
  sudo ./scripts/forestmapctl.sh install
  sudo ./scripts/forestmapctl.sh status
  sudo ./scripts/forestmapctl.sh logs api
  sudo ./scripts/forestmapctl.sh update
EOF
}

cmd="${1:-}"
if [[ $# -gt 0 ]]; then shift; fi

case "$cmd" in
  install)   install_cmd ;;
  start)     start_cmd ;;
  stop)      stop_cmd ;;
  restart)   restart_cmd ;;
  status)    status_cmd ;;
  logs)      logs_cmd "$@" ;;
  update)    update_cmd ;;
  env-init)  env_init_cmd ;;
  deps)      deps_cmd ;;
  remove)    remove_cmd ;;
  purge)     purge_cmd ;;
  "" )       interactive_menu ;;
  -h|--help|help) usage ;;
  *)
    echo "Unknown command: $cmd"
    usage
    exit 1
    ;;
esac
