# ForestMap ERD

## Application DB (`forestmap`)

```mermaid
erDiagram
    telemetry ||--o{ detections : "packet_id -> telemetry_packet_id"

    telemetry {
        uuid        packet_id PK
        text        flight_id
        text        drone_id
        timestamptz recorded_at
        geometry    location "POINTZ, SRID 4326"
        float       heading
        float       pitch
        float       fov
        float       speed
        int         battery
    }

    detections {
        uuid        id PK "default gen_random_uuid()"
        uuid        telemetry_packet_id FK "references telemetry(packet_id) ON DELETE CASCADE"
        text        flight_id
        timestamptz detected_at
        text        class_type
        float       score
        float       severity
        geometry    geometry_geo "POLYGON, SRID 4326"
        jsonb       geometry_image
        text        image_path
    }
