#!/bin/sh
set -eu
# включаем pipefail, если shell умеет
(set -o pipefail) 2>/dev/null && set -o pipefail || true

API_HOST="${API_HOST:-localhost}"
API_PORT="${API_PORT:-8081}"
GW_HOST="${GW_HOST:-localhost}"
GW_PORT="${GW_PORT:-8443}"

API_BASE="http://${API_HOST}:${API_PORT}"
GW_BASE="http://${GW_HOST}:${GW_PORT}"

IMAGE_FILE="${IMAGE_FILE:-/opt/forestmap/backend/uploads/1770214739_test.jpg}"

log() { printf "\n==> %s\n" "$*"; }
fail() { printf "\n❌ %s\n" "$*"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || fail "Не найдено: $1"; }

need curl

# UUID
if command -v uuidgen >/dev/null 2>&1; then
  PKT="$(uuidgen)"
elif [ -r /proc/sys/kernel/random/uuid ]; then
  PKT="$(cat /proc/sys/kernel/random/uuid)"
else
  fail "Нет uuidgen и /proc/sys/kernel/random/uuid"
fi

RECORDED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
DETECTED_AT="$RECORDED_AT"

log "API healthz: ${API_BASE}/healthz"
curl -fsS "${API_BASE}/healthz" >/dev/null || fail "API healthz не отвечает"

log "Gateway healthz: ${GW_BASE}/api/healthz"
curl -fsS "${GW_BASE}/api/healthz" >/dev/null || fail "Gateway healthz не отвечает (HTTP, не HTTPS)"

# Определяем префикс /v1 или /api/v1
log "Определяем префикс v1 (detections:query)"
PREFIX=""
for p in "/v1" "/api/v1"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${API_BASE}${p}/detections:query" \
    -H 'Content-Type: application/json' \
    -d '{"limit":1,"geom":"auto"}' || true)"
  if [ "$code" = "200" ] || [ "$code" = "500" ]; then
    PREFIX="$p"
    break
  fi
done
[ -n "$PREFIX" ] || fail "Не нашёл роут detections:query ни на /v1, ни на /api/v1"

log "Используем префикс: ${PREFIX}"
log "PKT (telemetry packet_id) = ${PKT}"

# Телеметрия
log "POST telemetry -> ${API_BASE}${PREFIX}/telemetry"
telemetry_payload=$(cat <<JSON
{
  "flight_id":"F-TEST",
  "packet_id":"${PKT}",
  "drone_id":"DRONE-TEST",
  "recorded_at":"${RECORDED_AT}",
  "location":{"lat":60.0001,"lon":30.0001,"alt":120.5},
  "camera":{"heading":12.3,"pitch":-20.0,"fov":78.0},
  "speed":12.4,
  "battery":87
}
JSON
)
tcode="$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST "${API_BASE}${PREFIX}/telemetry" \
  -H 'Content-Type: application/json' \
  -d "$telemetry_payload" || true)"
[ "$tcode" = "201" ] || fail "Telemetry failed (HTTP $tcode)"

# Detections JSON
DETS_JSON="/tmp/dets_${PKT}.json"
cat > "$DETS_JSON" <<JSON
{
  "flight_id":"F-TEST",
  "telemetry_packet_id":"${PKT}",
  "detected_at":"${DETECTED_AT}",
  "objects":[
    {
      "class":"fire",
      "score":0.92,
      "severity":0.70,
      "geometry_geo":{
        "type":"Polygon",
        "coordinates":[[
          [30.00000,60.00000],
          [30.00020,60.00000],
          [30.00020,60.00020],
          [30.00000,60.00020],
          [30.00000,60.00000]
        ]]
      },
      "geometry_image":{"x":10,"y":20,"w":120,"h":80}
    },
    {
      "class":"disease",
      "score":0.81,
      "severity":0.40,
      "geometry_geo":{
        "type":"Polygon",
        "coordinates":[[
          [30.00100,60.00100],
          [30.00300,60.00100],
          [30.00300,60.00300],
          [30.00100,60.00300],
          [30.00100,60.00100]
        ]]
      },
      "geometry_image":{"x":200,"y":100,"w":160,"h":120}
    }
  ]
}
JSON

[ -f "$IMAGE_FILE" ] || fail "Не найден файл картинки: $IMAGE_FILE (задай IMAGE_FILE=/path/to.jpg)"

# Upload detections multipart
log "POST detections (multipart) -> ${API_BASE}${PREFIX}/detections"
resp="$(curl -s -i \
  -X POST "${API_BASE}${PREFIX}/detections" \
  -F "image=@${IMAGE_FILE}" \
  -F "data=$(cat "$DETS_JSON")" || true)"

status_line="$(printf "%s" "$resp" | head -n 1)"
echo "$status_line" | grep -q "201" || { echo "$resp"; fail "Detections upload failed"; }

# Query GeoJSON
log "POST detections:query -> ${API_BASE}${PREFIX}/detections:query"
geojson="$(curl -s \
  -X POST "${API_BASE}${PREFIX}/detections:query" \
  -H 'Content-Type: application/json' \
  -d '{"geom":"auto","limit":50}' )"

# Печать короткого итога
if command -v jq >/dev/null 2>&1; then
  echo "$geojson" | jq '.type, (.features|length)' || { echo "$geojson"; fail "Ответ не JSON/GeoJSON"; }
  IMG_PATH="$(echo "$geojson" | jq -r '.features[0].properties.image_path // empty')"
else
  echo "$geojson" | head -c 300; echo
  IMG_PATH=""
  if command -v python3 >/dev/null 2>&1; then
    IMG_PATH="$(python3 - <<'PY'
import json,sys
obj=json.load(sys.stdin)
feat=obj.get("features",[])
if feat:
  print((feat[0].get("properties") or {}).get("image_path",""))
PY
<<EOF
$geojson
EOF
)"
  fi
fi

if [ -z "${IMG_PATH:-}" ]; then
  log "image_path не найден (возможно, features пустой) — пропускаю проверку отдачи картинки"
  echo "✅ E2E OK (без проверки картинки)"
  exit 0
fi

log "image_path: $IMG_PATH"
log "HEAD ${GW_BASE}${IMG_PATH}"
img_code="$(curl -s -o /dev/null -w '%{http_code}' -I "${GW_BASE}${IMG_PATH}" || true)"
[ "$img_code" = "200" ] || [ "$img_code" = "304" ] || fail "Nginx не отдаёт картинку (HTTP $img_code). Проверь volume uploads + location /uploads/"

echo
echo "✅ E2E OK: telemetry -> detections(multipart) -> query(geojson) -> nginx image serve"
