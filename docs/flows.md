# ForestMap Flows

Документ описывает основные пользовательские и административные сценарии работы с сервисом **ForestMap**.

---

## Содержание

1. [Роли](#роли)
2. [Flow: Drone Client (телеметрия + детекции)](#1-flow-drone-client-телеметрия--детекции)
3. [Flow: Viewer (оператор карты, чтение детекций)](#2-flow-viewer-оператор-карты-чтение-детекций)
4. [Flow: App Admin (развертывание и проверка сервиса)](#3-flow-app-admin-развертывание-и-проверка-сервиса)
5. [Flow: IAM Admin (настройка Keycloak)](#4-flow-iam-admin-настройка-keycloak)

---

## Роли

- **Drone Client** — сервисный клиент (дрон / бортовой агент / интеграция), отправляет телеметрию и детекции
- **Viewer** — оператор (пользователь карты), запрашивает и просматривает детекции
- **App Admin** — администратор сервиса (infra/backend/nginx/db)
- **IAM Admin** — администратор Keycloak (realm, clients, roles, users)

---

## 1. Flow: Drone Client (телеметрия + детекции)

### Цель

Отправить данные полёта в backend:
1) телеметрию  
2) детекции с изображением

### Предусловия

- Развернуты `api`, `db`, `nginx`, `keycloak`
- В Keycloak создан realm `forestmap`
- Создан confidential client (например, `forestmap-drone`)
- Клиенту выданы нужные роли (например, `drone`)

### Результат

- Телеметрия сохранена в `telemetry`
- Детекции сохранены в `detections`
- Изображение сохранено в `/uploads/...`

### Диаграмма (sequence)

```mermaid
sequenceDiagram
    participant D as Drone Client
    participant KC as Keycloak
    participant NX as Nginx
    participant API as Backend API
    participant DB as PostGIS
    participant FS as Uploads Storage

    D->>KC: POST /auth/realms/forestmap/protocol/openid-connect/token (client_credentials)
    KC-->>D: access_token (JWT)

    D->>NX: POST /api/v1/telemetry (Bearer JWT)
    NX->>API: POST /v1/telemetry
    API->>DB: INSERT telemetry
    DB-->>API: OK
    API-->>NX: 201 Created
    NX-->>D: 201 Created

    D->>NX: POST /api/v1/detections (multipart: image + data, Bearer JWT)
    NX->>API: POST /v1/detections
    API->>FS: Save image to /uploads
    API->>DB: INSERT detections (transaction)
    DB-->>API: OK
    API-->>NX: 201 {"status":"saved","count":N}
    NX-->>D: 201 {"status":"saved","count":N}

## 2. Flow: Viewer (оператор карты, чтение детекций)

### Цель

Получить GeoJSON с детекциями и отобразить их на карте.

### Предусловия (текущий этап)

- API доступен
- Keycloak настроен
- У клиента/пользователя есть токен с ролью на чтение (например, `viewer`)

### Результат

- Получен `GeoJSON FeatureCollection`
- Карта показывает объекты (точки/полигоны)
- При наличии `image_path` можно запросить изображение через `/uploads/...`

### Диаграмма (sequence)

```mermaid
sequenceDiagram
    participant V as Viewer App
    participant KC as Keycloak
    participant NX as Nginx
    participant API as Backend API
    participant DB as PostGIS

    Note over V,KC: Получение access_token (client credentials или user login)
    V->>KC: Запрос токена
    KC-->>V: JWT access_token

    V->>NX: POST /api/v1/detections:query (Bearer JWT, filters)
    NX->>API: POST /v1/detections:query
    API->>DB: SELECT + GeoJSON build (PostGIS)
    DB-->>API: GeoJSON FeatureCollection
    API-->>NX: 200 application/geo+json
    NX-->>V: 200 application/geo+json

    V->>V: Render features on map (point/polygon)
    V->>NX: GET /uploads/<file> (optional)
    NX-->>V: image file (optional)
