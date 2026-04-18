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

    COMPANIES ||--o{ COMPANY_USERS : "has (id -> company_id)"
    USERS ||--o{ COMPANY_USERS : "belongs to (id -> user_id)"

    COMPANIES ||--o{ FLIGHTS : "owns (id -> company_id) "
    FLIGHTS ||--o{ DETECTIONS_1 : "contains (id -> flight_id)"

    DETECTIONS_1 ||--o{ DETECTION_EVENTS : "has (id-> detection_id)"
    DETECTIONS_1 ||--o{ DETECTION_COMMENTS : "has (id -> detection_id)"

    USERS ||--o{ DETECTION_COMMENTS : "authors (id -> author_user_id)"
    USERS ||--o{ DETECTION_EVENTS : "creates (id -> created_by)"
    USERS ||--o{ DETECTIONS_1 : "creates (id -> created_by)"
    USERS ||--o{ DETECTIONS_1 : "updates (id -> updated_by)"

    COMPANIES {
        uuid        id PK
        string      name
        string      code
        string      status
        datetime    created_at
        datetime    updated_at
    }

    USERS {
        uuid        id PK
        string      keycloak_user_id UK
        string      email
        string      full_name
        string      status
        datetime    created_at
        datetime    updated_at
    }

    COMPANY_USERS {
        uuid        id PK
        uuid        company_id FK
        uuid        user_id FK
        string      role
        string      status
        datetime    joined_at
        datetime    created_at
        datetime    updated_at
    }

    FLIGHTS {
        uuid        id PK
        uuid        company_id FK
        string      external_id
        string      status
        datetime    flight_started_at
        datetime    flight_finished_at
        datetime    created_at
        datetime    updated_at
    }

    DETECTIONS_1 {
        uuid        id PK
        uuid        flight_id FK
        string      type
        string      status
        int         score
        string      title
        string      description
        geometry    geometry
        decimal     centroid_lat
        decimal     centroid_lon
        decimal     area
        datetime    last_detection_at
        uuid        created_by FK
        uuid        updated_by FK
        datetime    created_at
        datetime    updated_at
        datetime    archived_at
    }

    DETECTION_EVENTS {
        uuid        id PK
        uuid        detection_id FK
        string      event_type
        int         severity
        json        payload
        uuid        created_by FK
        datetime    event_at
        datetime    created_at
    }

    DETECTION_COMMENTS {
        uuid        id PK
        uuid        detection_id FK
        uuid        author_user_id FK
        text        body
        datetime    created_at
        datetime    updated_at
        datetime    deleted_at
    }
    
