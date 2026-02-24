# ForestMap Unified Flow

```mermaid
flowchart TD
    START([Start])

    START --> ROLE{Кто действует?}

    ROLE -->|App Admin| ADMIN_BOOT
    ROLE -->|IAM Admin| IAM_LOGIN
    ROLE -->|Drone Client| DRONE_TOKEN
    ROLE -->|Viewer| VIEWER_TOKEN
    ROLE -->|Incident / Debug| DEBUG_ENTRY

    ADMIN_BOOT[Подготовить .env] --> ADMIN_UP[docker compose up -d --build]
    ADMIN_UP --> ADMIN_PS[Проверить docker compose ps]
    ADMIN_PS --> ADMIN_OK{Все сервисы Up?}
    ADMIN_OK -->|Нет| ADMIN_LOGS[Смотреть docker compose logs]
    ADMIN_LOGS --> ADMIN_FIX[Исправить конфиг / env / ports]
    ADMIN_FIX --> ADMIN_UP
    ADMIN_OK -->|Да| ADMIN_H1[Проверить API healthz :8081]
    ADMIN_H1 --> ADMIN_H2[Проверить Nginx /api/healthz :8443]
    ADMIN_H2 --> ADMIN_H3[Проверить Keycloak /auth]
    ADMIN_H3 --> ADMIN_H4[Проверить OIDC discovery realm]
    ADMIN_H4 --> ADMIN_READY[Сервис готов к использованию]

    IAM_LOGIN[Войти в Keycloak Admin Console] --> IAM_REALM[Создать realm forestmap]
    IAM_REALM --> IAM_ROLES[Создать роли: drone / viewer / admin]
    IAM_ROLES --> IAM_CLIENT_DRONE[Создать client forestmap-drone]
    IAM_CLIENT_DRONE --> IAM_CLIENT_FLAGS[Включить Client Authentication + Service Accounts]
    IAM_CLIENT_FLAGS --> IAM_SECRET[Скопировать client secret]
    IAM_SECRET --> IAM_ASSIGN[Назначить роли service account]
    IAM_ASSIGN --> IAM_TEST_TOKEN[Проверить получение токена client_credentials]
    IAM_TEST_TOKEN --> IAM_DONE[Auth-контур готов]
    IAM_ROLES --> IAM_CLIENT_WEB[Позже: создать frontend client (PKCE)]
    IAM_CLIENT_WEB --> IAM_WEB_CFG[Redirect URIs / Web Origins]

    DRONE_TOKEN[Запросить access_token в Keycloak\nclient_credentials] --> DRONE_TOKEN_OK{Токен получен?}
    DRONE_TOKEN_OK -->|Нет| DRONE_AUTH_ERR[Проверить realm / client / secret / роли]
    DRONE_AUTH_ERR --> DRONE_TOKEN
    DRONE_TOKEN_OK -->|Да| DRONE_TLM[POST /api/v1/telemetry (Bearer JWT)]
    DRONE_TLM --> DRONE_TLM_OK{201 Created?}
    DRONE_TLM_OK -->|Нет| DRONE_TLM_ERR[Проверить JWT / payload / API logs / DB]
    DRONE_TLM_ERR --> DEBUG_ENTRY
    DRONE_TLM_OK -->|Да| DRONE_DET[POST /api/v1/detections multipart\nimage + data + Bearer JWT]
    DRONE_DET --> DRONE_DET_OK{201 Created?}
    DRONE_DET_OK -->|Нет| DRONE_DET_ERR[Проверить multipart / telemetry_packet_id /\nсохранение файла / транзакцию БД]
    DRONE_DET_ERR --> DEBUG_ENTRY
    DRONE_DET_OK -->|Да| DRONE_DONE[Данные полета сохранены]

    VIEWER_TOKEN[Получить access_token\n(client credentials или user login в будущем)] --> VIEWER_TOKEN_OK{Токен получен?}
    VIEWER_TOKEN_OK -->|Нет| VIEWER_AUTH_ERR[Проверить client / user / realm / роли]
    VIEWER_AUTH_ERR --> VIEWER_TOKEN
    VIEWER_TOKEN_OK -->|Да| VIEWER_QUERY[POST /api/v1/detections:query\nfilters: classes, geom, bbox, aoi, since, limit]
    VIEWER_QUERY --> VIEWER_Q_OK{200 GeoJSON?}
    VIEWER_Q_OK -->|Нет 401| VIEWER_401[Нет роли viewer / невалидный токен]
    VIEWER_401 --> DEBUG_ENTRY
    VIEWER_Q_OK -->|Нет 4xx/5xx| VIEWER_Q_ERR[Проверить filters / backend logs / SQL]
    VIEWER_Q_ERR --> DEBUG_ENTRY
    VIEWER_Q_OK -->|Да| VIEWER_RENDER[Отрисовать карту:\ngeom=auto -> fire=Point, disease=Polygon]
    VIEWER_RENDER --> VIEWER_IMG[При наличии image_path загрузить /uploads/... через Nginx]
    VIEWER_IMG --> VIEWER_DONE[Просмотр данных завершен]

    DEBUG_ENTRY[Диагностика] --> DBG1{API healthz на :8081 OK?}
    DBG1 -->|Нет| DBG_API[Проблема API:\nконтейнер / env / build / logs]
    DBG_API --> DBG_RETURN[Исправить и повторить шаг]
    DBG1 -->|Да| DBG2{Через Nginx /api/healthz OK?}
    DBG2 -->|Нет| DBG_NGINX[Проблема Nginx:\nproxy_pass / upstream / config / logs]
    DBG_NGINX --> DBG_RETURN
    DBG2 -->|Да| DBG3{Проблема с auth?}
    DBG3 -->|Да| DBG_KC[Проверить /auth,\nrealm discovery,\nissuer, jwks_uri,\nclaims, roles]
    DBG_KC --> DBG_RETURN
    DBG3 -->|Нет| DBG4{Проблема с данными?}
    DBG4 -->|Да| DBG_DATA[Проверить payload,\ntelemetry_packet_id,\nSQL ошибки,\nPostGIS геометрию]
    DBG_DATA --> DBG_RETURN
    DBG4 -->|Нет| DBG_UPLOADS[Проверить /uploads volume,\nalias /uploads/ в nginx,\nпути файлов]
    DBG_UPLOADS --> DBG_RETURN
    DBG_RETURN --> ROLE

    ADMIN_READY --> END([Operational])
    IAM_DONE --> END
    DRONE_DONE --> END
    VIEWER_DONE --> END
