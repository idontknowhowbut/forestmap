#!/usr/bin/env bash
set -euo pipefail
command -v docker >/dev/null 2>&1 || { echo 'docker is required' >&2; exit 1; }
docker version >/dev/null

docker compose version >/dev/null
echo 'Docker and Docker Compose are available.'
