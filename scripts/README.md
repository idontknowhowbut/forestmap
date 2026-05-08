# Scripts

Основные сценарии для локального запуска и clean install.

## Windows PowerShell
- `./scripts/generate-env.ps1` — создать `infra/.env` из примера с безопасными случайными секретами.
- `./scripts/check-deps.ps1` — проверить наличие Docker и Docker Compose.
- `./scripts/clean-install.ps1` — полный clean install: генерация `.env`, `docker compose down -v`, `up -d --build`, затем `restart api`.
- `./scripts/apply-dev-seed.ps1` — повторно применить `infra/dev_detections_seed.sql` к уже запущенной БД.

## Linux / macOS
- `./scripts/generate-env.sh`
- `./scripts/check-deps.sh`
- `./scripts/clean-install.sh`
- `./scripts/apply-dev-seed.sh`
