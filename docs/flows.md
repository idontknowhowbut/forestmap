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
```
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
```
## 3. Flow: Admin (App Admin — развертывание, проверка и диагностика сервиса)

### Цель

Развернуть стек ForestMap, убедиться, что сервис работает, и уметь быстро локализовать проблему при сбое.

### Предусловия

- Есть доступ к серверу (SSH)
- Установлены Docker и Docker Compose
- Подготовлен `.env`
- Порты свободны (или согласованы значения в `.env`)
- В репозитории актуальная версия проекта

### Результат

- Контейнеры запущены (`api`, `db`, `frontend`, `nginx`, `keycloak`, `keycloak-db`)
- API отвечает на `healthz`
- Nginx проксирует `/api/` и `/auth/`
- Keycloak доступен и готов к настройке realm/clients
- Загруженные изображения отдаются через `/uploads/...` (если есть данные)

### Диаграмма (flowchart)

```mermaid
flowchart TD
    A[Подготовить .env] --> B[docker compose --env-file .env up -d --build]
    B --> C[docker compose --env-file .env ps]
    C --> D{Все сервисы Up?}

    D -- Нет --> E[docker compose --env-file .env logs --tail=200]
    E --> F[Исправить конфиг / env / порты / сборку]
    F --> B

    D -- Да --> G[Проверить API healthz :8081]
    G --> H[Проверить Nginx /api/healthz :8443]
    H --> I[Проверить Keycloak /auth]
    I --> J{Realm forestmap создан?}

    J -- Нет --> K[Перейти к IAM Admin flow и создать realm/clients/roles]
    J -- Да --> L[Проверить OIDC discovery]
    L --> M[Проверить защищённый API без токена -> 401]
    M --> N[Проверить защищённый API с токеном -> 200]
    N --> O[Сервис готов к работе]

    O --> P{Проблема в процессе эксплуатации?}
    P -- Нет --> Q[Нормальная эксплуатация]
    P -- Да --> R[Диагностика: API / Nginx / Keycloak / DB / uploads]
    R --> S[Исправление]
    S --> G
```
## 4. Flow: IAM Admin (Keycloak Admin — настройка авторизации)

### Цель

Настроить Keycloak для ForestMap:
- создать realm
- создать роли
- создать клиентов (drone / viewer)
- выдать роли service account / пользователям
- проверить токены и доступ к API

### Предусловия

- Keycloak запущен (`keycloak`, `keycloak-db`)
- Nginx проксирует `/auth/`
- Есть bootstrap admin credentials (из `.env`)
- Backend настроен на корректные `OIDC_ISSUER` и `OIDC_JWKS_URL`

### Результат

- Realm `forestmap` создан
- Созданы роли (`drone`, `viewer`, `admin`)
- Создан M2M-клиент `forestmap-drone` (confidential + service accounts)
- (Опционально) создан клиент для frontend/viewer
- Токены содержат нужные claims/roles
- Доступ к API работает согласно ролям

### Диаграмма (flowchart)

```mermaid
flowchart TD
    A[Войти в Keycloak Admin Console] --> B[Создать Realm: forestmap]
    B --> C[Создать роли: drone, viewer, admin]
    C --> D[Создать Client: forestmap-drone]
    D --> E[Включить Client Authentication]
    E --> F[Включить Service Accounts]
    F --> G[Скопировать Client Secret]
    G --> H[Назначить роли service account]
    H --> I[Проверить token по client_credentials]
    I --> J[Проверить доступ к API с токеном]
    J --> K[Готово]

    C --> L[Опционально: создать frontend client]
    L --> M[Настроить Redirect URIs / Web Origins]
    M --> N[Подготовить login flow (Authorization Code + PKCE)]

