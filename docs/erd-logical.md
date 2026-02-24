```mermaid
erDiagram
...

erDiagram
    %% =========================
    %% Core domain (ForestMap)
    %% =========================

    DRONE ||--o{ FLIGHT : performs
    FLIGHT ||--o{ TELEMETRY_PACKET : contains
    TELEMETRY_PACKET ||--o{ DETECTION : anchors

    DETECTION }o--|| DETECTION_CLASS : classified_as
    DETECTION }o--|| MEDIA_ASSET : sourced_from

    %% Optional logical ownership by flight (denormalized in current schema)
    FLIGHT ||--o{ DETECTION : observed_in

    DRONE {
        string drone_id PK
        string model
        string callsign
        string status
    }

    FLIGHT {
        string flight_id PK
        string drone_id FK
        datetime started_at
        datetime ended_at
        string mission_type
        string status
    }

    TELEMETRY_PACKET {
        uuid packet_id PK
        string flight_id FK
        string drone_id FK
        datetime recorded_at
        pointz location_4326
        float heading
        float pitch
        float fov
        float speed
        int battery
    }

    DETECTION {
        uuid detection_id PK
        uuid telemetry_packet_id FK
        string flight_id FK
        datetime detected_at
        string class_code FK
        float score
        float severity
        geometry geometry_geo_4326
        json geometry_image
        string media_id FK
    }

    DETECTION_CLASS {
        string class_code PK
        string title
        string default_geom_mode
        string description
        bool active
    }

    MEDIA_ASSET {
        string media_id PK
        string storage_path
        string mime_type
        string source_type
        int width
        int height
        datetime created_at
        string checksum
    }

    %% =========================
    %% Auth domain (external / Keycloak)
    %% =========================

    KEYCLOAK_REALM ||--o{ OIDC_CLIENT : contains
    OIDC_CLIENT ||--o{ SERVICE_ACCOUNT : has
    SERVICE_ACCOUNT }o--o{ REALM_ROLE : granted
    APP_USER }o--o{ REALM_ROLE : granted

    KEYCLOAK_REALM {
        string realm_name PK
        string issuer_url
    }

    OIDC_CLIENT {
        string client_id PK
        string realm_name FK
        string client_type
        bool confidential
        bool service_accounts_enabled
    }

    SERVICE_ACCOUNT {
        string principal_id PK
        string client_id FK
    }

    APP_USER {
        string user_id PK
        string username
        string email
        bool enabled
    }

    REALM_ROLE {
        string role_name PK
        string realm_name FK
        string description
    }
