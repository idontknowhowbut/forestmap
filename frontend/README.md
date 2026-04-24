# Forestmap Frontend

## Что реализовано

- `keycloak-js` авторизация с fallback в mock mode
- логин/логаут, обработка redirect callback после Keycloak, хранение актуального access token в сессии приложения
- автоматическая передача `Authorization: Bearer <token>` через общий `authFetch`
- роли `viewer` и `admin`: viewer открывает рабочую карту, admin дополнительно видит базовый административный контур
- карта на React + Leaflet
- загрузка детекций через `POST /v1/detections:query`
- разбор ответа backend в формате GeoJSON `FeatureCollection`
- отображение Point как цветных точек, Polygon / MultiPolygon как полигонов
- дифференциация объектов по `class_type`: `fire`, `infection`/`disease`, `logging`
- popup по клику на объект карты с `class_type`, `detected_at`, `score`, `severity`, `image_path`
- левая панель фильтров: типы аномалий, диапазон дат, минимальный и максимальный score
- привязка фильтров к запросу `detections:query`
- правая панель со статистикой текущей выборки и списком последних детекций
- переключение темы день/ночь с сохранением в `localStorage`
- инверсия цветов PNG-иконок при смене темы
- переключение картографического слоя OSM / Satellite
- основной цвет интерфейса заменён на `rgb(15, 122, 58)`

## Как запустить

```bash
npm install
npm run dev
```

## Переменные окружения

При наличии параметров Keycloak фронтенд будет использовать реальную авторизацию:

```env
VITE_KEYCLOAK_URL=http://localhost:8443/auth
VITE_KEYCLOAK_REALM=forestmap
VITE_KEYCLOAK_CLIENT_ID=forestmap-frontend
VITE_USE_MOCKS=true
VITE_API_BASE_URL=
VITE_DETECTIONS_QUERY_ENDPOINT=/v1/detections:query
```

Если параметры Keycloak не заданы, приложение стартует в mock-режиме и предлагает вход как `viewer` или `admin`.

## Контракт detections:query

Фронтенд сейчас отправляет payload вида:

```json
{
  "classes": ["fire", "infection", "disease", "logging"],
  "geom": "auto",
  "bbox": [30.1, 60.0, 30.9, 60.5],
  "min_score": 0.2,
  "max_score": 0.9,
  "since": "2026-04-01T00:00:00Z",
  "until": "2026-04-24T23:59:59Z",
  "limit": 500
}
```

`max_score` и `until` уже подготовлены на фронте. Если текущий backend пока их игнорирует, frontend дополнительно фильтрует ответ локально, чтобы UI работал корректно до финализации контракта.
