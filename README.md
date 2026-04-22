# 🌲 ForestMap
The system for monitoring forest fires and forest diseases using drones, PostGIS, and a geospatial API.
ForestMap receives data from drones (telemetry and detection results), stores the geometry in PostGIS, and outputs the data in **GeoJSON** format for display on a map.

> **Status:** MVP / Active Development  
> **Archtecture:** Dockerized microservices  
> **Backend:** Go + PostgreSQL/PostGIS  
> **Gateway:** Nginx  
> **Auth:** Keycloak (OIDC/JWT)  
> **Frontend:** React + TypeScript (under development)


------------------------------------------------------

## 🌲 О проекте
Система мониторинга лесных пожаров и заболеваний леса с использованием дронов, PostGIS и геопространственного API.
ForestMap принимает данные от дронов (телеметрия + результаты детекций), сохраняет геометрию в PostGIS и отдает данные в формате **GeoJSON** для отображения на карте.

### Что умеет сейчас
- Принимать **телеметрию** дрона
- Принимать **детекции** (multipart: изображение + JSON-метаданные)
- Сохранять изображения в `uploads` (persistent volume)
- Отдавать **GeoJSON FeatureCollection** по фильтрам через `POST /v1/detections:query`
- Защищать API через **JWT (Keycloak / OIDC)**

### Геометрии (текущая логика)
- **Болезни леса** — как **Polygon**
- **Пожары** — сейчас могут отображаться как **Point** (`geom=auto`)
- В будущем пожары могут быть и **Polygon** — API уже спроектирован универсально

---

## Архитектура

### Поток данных
1. **Drone Client** получает JWT в Keycloak
2. Отправляет `telemetry` в Backend API
3. Отправляет `detections` (image + data) в Backend API
4. Backend сохраняет:
   - телеметрию в `telemetry`
   - детекции в `detections`
   - файл изображения в `/uploads`
5. Viewer/Frontend запрашивает `detections:query`
6. Backend возвращает GeoJSON
7. Frontend рендерит объекты на карте

### Сервисы (Docker Compose)
- `api` — Go backend
- `db` — PostgreSQL + PostGIS
- `frontend` — web frontend
- `nginx` — reverse proxy / gateway / static uploads
- `keycloak` — IAM / OIDC provider
- `keycloak-db` — БД для Keycloak

---

## Технологический стек

### Backend
- Go (Golang) 1.23+ / 1.24
- `net/http`
- `lib/pq`
- OIDC/JWT validation (Keycloak JWKS)

### Database
- PostgreSQL 16
- PostGIS 3.4
- SRID: `4326` (WGS84)

### Infra
- Docker
- Docker Compose
- Nginx

### Auth
- Keycloak (OIDC / JWT / JWKS)

---

## Структура проекта (основное)

```text
backend/
  cmd/api/main.go
  internal/httpapi/
  internal/store/
  internal/model/
frontend/
infra/
  docker-compose.yml
  .env.example
  init.sql
  nginx/default.conf
docs/
  api/openapi.yaml
  flows/flows.md
  erd/logical-erd.md
```
---

## Быстрый старт

### 1) Клонировать проект

```bash
git clone <YOUR_REPO_URL> /opt/forestmap
cd /opt/forestmap
```

### 2) Подготовить `.env`

```bash
cd /opt/forestmap/infra
cp .env.example .env
# отредактировать .env
```

### 3) Запустить стек

```bash
docker compose --env-file .env up -d --build
docker compose --env-file .env ps
```

### 4) Проверить доступность

```bash
curl -i http://localhost:8081/healthz
curl -i http://localhost:8443/api/healthz
curl -I http://localhost:8443/auth/
```

---

## Конфигурация окружения (.env)

```dotenv
COMPOSE_PROJECT_NAME=forestmap

# Ports (host)
API_PORT=8081
NGINX_PORT=8443
DB_PORT=5432
KEYCLOAK_PORT=18080

# API runtime
API_ADDR=:8080
UPLOAD_DIR=/uploads

# App DB (PostGIS)
POSTGRES_USER=forest
POSTGRES_PASSWORD=CHANGE_ME_FOREST_DB_PASSWORD
POSTGRES_DB=forestmap
POSTGRES_SSLMODE=disable

# Keycloak DB
KEYCLOAK_DB_NAME=keycloak
KEYCLOAK_DB_USER=keycloak
KEYCLOAK_DB_PASSWORD=CHANGE_ME_KEYCLOAK_DB_PASSWORD

# Keycloak admin bootstrap
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=CHANGE_ME_KEYCLOAK_ADMIN_PASSWORD

# Keycloak public URL behind nginx
KEYCLOAK_HOSTNAME=http://localhost:8443/auth

# Realm / OIDC
KEYCLOAK_REALM=forestmap
OIDC_ISSUER=http://localhost:8443/auth/realms/forestmap
OIDC_JWKS_URL=http://keycloak:8080/auth/realms/forestmap/protocol/openid-connect/certs
```

### Важные замечания
- `OIDC_ISSUER` должен совпадать с `iss` в токене
- `OIDC_JWKS_URL` — внутренний адрес Keycloak для backend-контейнера
- `UPLOAD_DIR=/uploads` должен совпадать с volume-монтом в `api` и `nginx`

---

## Авторизация и роли (Keycloak)

ForestMap использует **Bearer JWT** (OIDC).

### Роли
- `drone` — загрузка телеметрии и детекций
- `viewer` — чтение детекций (`detections:query`)
- `admin` — административные операции

### Минимальная настройка Keycloak
1. Создать realm `forestmap`
2. Создать роли `drone`, `viewer`, `admin`
3. Создать client `forestmap-drone` (confidential)
4. Включить **Client Authentication** и **Service Accounts**
5. Выдать роли service account (например `drone`)
6. Получить токен по `client_credentials`

### Получение токена (пример)
```bash
KC_BASE="http://localhost:8443/auth"
REALM="forestmap"
CLIENT_ID="forestmap-drone"
CLIENT_SECRET="<SECRET>"

curl -s -X POST "$KC_BASE/realms/$REALM/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" | jq
```

---

## API (кратко)

> Детальную спецификацию рекомендуется хранить в `docs/api/openapi.yaml`.

### `GET /healthz`
Проверка работоспособности API.

```bash
curl -i http://localhost:8081/healthz
```

---

### `POST /v1/telemetry`
Прием телеметрии дрона (JWT required).

**Content-Type:** `application/json`

Пример:
```json
{
  "flight_id": "flight-001",
  "packet_id": "d332aba1-90fb-4dc0-9fbc-eade11393a48",
  "drone_id": "drone-7",
  "recorded_at": "2026-02-24T12:00:00Z",
  "location": { "lat": 55.751244, "lon": 37.618423, "alt": 120.5 },
  "camera": { "heading": 180, "pitch": -35, "fov": 72 },
  "speed": 12.4,
  "battery": 78
}
```

Ответ: `201 Created`

---

### `POST /v1/detections`
Загрузка изображения и пакета детекций (JWT required).

**Content-Type:** `multipart/form-data`

Поля:
- `image` — файл (`jpg/png`)
- `data` — JSON-строка с метаданными и объектами

Пример:
```bash
curl -i -X POST http://localhost:8081/v1/detections \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -F "image=@/path/to/frame.jpg" \
  -F "data={
    \"flight_id\": \"flight-001\",
    \"telemetry_packet_id\": \"d332aba1-90fb-4dc0-9fbc-eade11393a48\",
    \"detected_at\": \"2026-02-24T12:00:02Z\",
    \"objects\": [
      {
        \"class\": \"fire\",
        \"score\": 0.97,
        \"severity\": 0.8,
        \"geometry_geo\": {
          \"type\": \"Polygon\",
          \"coordinates\": [[[37.6181,55.7511],[37.6182,55.7511],[37.6182,55.7512],[37.6181,55.7512],[37.6181,55.7511]]]
        },
        \"geometry_image\": { \"x\": 100, \"y\": 120, \"w\": 80, \"h\": 60 }
      }
    ]
  }"
```

Ответ:
```json
{"status":"saved","count":1}
```

---

### `POST /v1/detections:query`
Универсальный запрос детекций в формате **GeoJSON FeatureCollection** (JWT required).

**Content-Type:** `application/json`  
**Response:** `application/geo+json`

#### Поддерживаемые фильтры
- `classes`
- `geom` — `auto | point | polygon`
- `limit`
- `bbox`
- `aoi`
- `flight_id`
- `min_score`
- `since`

#### Пример запроса
```bash
curl -s -X POST http://localhost:8443/api/v1/detections:query \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "classes": ["fire", "disease"],
    "geom": "auto",
    "limit": 50
  }' | jq '.type, (.features|length)'
```

#### Пример ответа
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "3bbf7f7a-....",
      "geometry": {
        "type": "Point",
        "coordinates": [37.61815, 55.75115]
      },
      "properties": {
        "flight_id": "flight-001",
        "detected_at": "2026-02-24T12:00:02Z",
        "class_type": "fire",
        "score": 0.97,
        "severity": 0.8,
        "image_path": "/uploads/1771596434_frame.jpg",
        "geometry_image": { "x": 100, "y": 120, "w": 80, "h": 60 },
        "telemetry_packet_id": "d332aba1-90fb-4dc0-9fbc-eade11393a48"
      }
    }
  ]
}
```

### Поведение `geom=auto`
- `fire` → `Point` (`ST_PointOnSurface`)
- остальные классы (например `disease`) → исходный `Polygon`

---

## Nginx / Gateway

### Маршрутизация
- `/api/` → backend API (`/v1/...` внутри приложения)
- `/auth/` → Keycloak
- `/` → frontend
- `/uploads/` → статическая отдача изображений (read-only)

### Важно
Nginx с `proxy_pass .../;` обрезает префикс `/api/`, поэтому внутри backend роуты должны быть без `/api`:
- `/v1/telemetry`
- `/v1/detections`
- `/v1/detections:query`

---

## База данных (PostGIS)

### Таблицы
- `telemetry`
- `detections`

### `telemetry`
- `packet_id UUID` (PK)
- `flight_id`
- `drone_id`
- `recorded_at`
- `location GEOMETRY(POINTZ, 4326)`

### `detections`
- `id UUID` (PK)
- `telemetry_packet_id UUID` (FK -> telemetry.packet_id)
- `flight_id`
- `detected_at`
- `class_type`
- `score`, `severity`
- `geometry_geo GEOMETRY(POLYGON, 4326)`
- `geometry_image JSONB`
- `image_path TEXT`

---

## Хранение файлов (uploads)

### Как работает
- Backend сохраняет изображение в `UPLOAD_DIR` (обычно `/uploads`)
- Путь сохраняется в БД (`image_path`)
- Nginx отдает файлы через `location /uploads/` (`alias /uploads/`)

### Для production
- Persistent volume
- Ограничение методов (`GET`, `HEAD`)
- Кэширование
- Валидация типов файлов и размеров

---

## Тестирование (smoke / e2e)

### Health checks
```bash
curl -i http://localhost:8081/healthz
curl -i http://localhost:8443/api/healthz
curl -I http://localhost:8443/auth/
```

### OIDC discovery (после создания realm)
```bash
curl -s http://localhost:8443/auth/realms/forestmap/.well-known/openid-configuration | jq '.issuer, .jwks_uri'
```

### Защищенный API
```bash
# Без токена — 401
curl -i -X POST http://localhost:8081/v1/detections:query \
  -H 'Content-Type: application/json' \
  -d '{"geom":"auto","limit":10}'
```

### E2E сценарий
1. `POST /v1/telemetry`
2. `POST /v1/detections`
3. `POST /v1/detections:query`
4. `GET /uploads/<file>` через Nginx

---

## Документация (рекомендуемая структура)

```text
docs/
  api/
    openapi.yaml
  flows/
    flows.md
  erd/
    logical-erd.md
```

- **OpenAPI** — контракт API + auth
- **Flows** — Drone / Viewer / App Admin / IAM Admin
- **ERD** — логическая схема

---

## Troubleshooting

### `401 Unauthorized` на `detections:query`
- нет/битый Bearer token
- не совпадает `OIDC_ISSUER`
- недоступен JWKS
- нет нужной роли (`viewer` / `drone`)

### `Realm does not exist`
- realm `forestmap` еще не создан
- ошибка в имени realm
- неверный URL `/auth/realms/<realm>/...`

### `curl: (56) Recv failure: Connection reset by peer` на `8443`
- nginx контейнер не поднялся / рестартуется
- ошибка в `nginx/default.conf`
- upstream недоступен на момент старта

### Не открываются `/uploads/...`
- проверить volume `uploads_data`
- проверить `UPLOAD_DIR=/uploads`
- проверить `location /uploads/` в nginx
- проверить наличие файла в контейнере

### Ошибки SQL / PostGIS
- невалидная GeoJSON-геометрия
- SRID не 4326
- `telemetry_packet_id` не существует
- смотреть логи `api` и `db`

---

## Безопасность

- Не коммитить `.env`, токены, client secrets, пароли
- Разные секреты для dev/stage/prod
- Ротация `client_secret`
- Ограничение доступа к портам (`db`, `keycloak`)
- В production включить TLS (HTTPS)
- Настроить аудит и логирование

---

## Roadmap

- [x] Универсальный GeoJSON endpoint (`POST /v1/detections:query`)
- [x] Persistence для uploads (volume)
- [x] JWT/OIDC авторизация (Keycloak)
- [ ] CORS (если потребуется прямой доступ к API)
- [ ] Frontend auth flow (Authorization Code + PKCE)
- [ ] OpenAPI (`docs/api/openapi.yaml`)
- [ ] Swagger UI / ReDoc публикация
- [ ] Метрики / observability
- [ ] RBAC-политики по endpoint'ам
- [ ] Версионирование API и контрактов

---

## Полезные команды

### Логи
```bash
cd /opt/forestmap/infra
docker compose --env-file .env logs --tail=100 api
docker compose --env-file .env logs --tail=100 nginx
docker compose --env-file .env logs --tail=100 keycloak
docker compose --env-file .env logs --tail=100 db
```

### Пересборка API
```bash
docker compose --env-file .env build api
docker compose --env-file .env up -d --force-recreate api
```

### Проверка nginx-конфига
```bash
docker compose --env-file .env exec nginx nginx -t
docker compose --env-file .env exec nginx cat /etc/nginx/conf.d/default.conf
```
---

## Контакты / сопровождение

- Владелец проекта: idontknowhow
- Репозиторий: https://github.com/idontknowhowbut/forestmap/
- API: `docs/api/openapi.yaml`
- Flows: `docs/flows/flows.md`
- ERD: `docs/erd/logical-erd.md`
