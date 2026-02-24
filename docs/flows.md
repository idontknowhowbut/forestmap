# ForestMap Flows

Документ описывает основные пользовательские и административные сценарии работы с сервисом ForestMap.

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
