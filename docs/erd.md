# ForestMap ERD

## Application DB (`forestmap`)

```mermaid
erDiagram
    telemetry ||--o{ detections : "packet_id -> telemetry_packet_id"

    telemetry {
        uuid        packet_id PK
        uuid        company_id FK
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
        uuid        company_id FK
        text        flight_id
        timestamptz detected_at
        text        class_type
        float       score
        float       severity
        geometry    geometry_geo "POLYGON, SRID 4326"
        jsonb       geometry_image
        text        image_path
    }

    companies ||--o{ company_users : "has (id -> company_id)"
    users ||--o{ company_users : "belongs to (id -> user_id)"

    companies ||--o{ flights : "owns (id -> company_id) "
    flights ||--o{ detections_business : "contains (id -> flight_id)"

    detections_business ||--o{ detection_events : "has (id-> detections_business)"
    detections_business ||--o{ detection_comments : "has (id -> detections_business)"

    users ||--o{ detection_comments : "authors (id -> author_user_id)"
    users ||--o{ detection_events : "creates (id -> created_by)"
    users ||--o{ detections_business : "creates (id -> created_by)"
    users ||--o{ detections_business : "updates (id -> updated_by)"

    companies ||--o{ telemetry : "owns (id -> company_id)"
    companies ||--o{ detections : "owns (id -> company_id)"

    companies {
        uuid        id PK
        string      name
        string      code
        string      status
        datetime    created_at
        datetime    updated_at
    }

    users {
        uuid        id PK
        string      keycloak_user_id UK
        string      email
        string      full_name
        string      status
        datetime    created_at
        datetime    updated_at
    }

    company_users {
        uuid        id PK
        uuid        company_id FK
        uuid        user_id FK
        string      role
        string      status
        datetime    joined_at
        datetime    created_at
        datetime    updated_at
    }

    flights {
        uuid        id PK
        uuid        company_id FK
        string      external_id
        string      status
        datetime    flight_started_at
        datetime    flight_finished_at
        datetime    created_at
        datetime    updated_at
    }

    detections_business {
        uuid        id PK
        uuid        company_id FK
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

    detection_events {
        uuid        id PK
        uuid        detection_id FK
        string      event_type
        int         severity
        json        payload
        uuid        created_by FK
        datetime    event_at
        datetime    created_at
    }

    detection_comments {
        uuid        id PK
        uuid        detection_id FK
        uuid        author_user_id FK
        text        body
        datetime    created_at
        datetime    updated_at
        datetime    deleted_at
    }
    
