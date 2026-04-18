CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS telemetry (
    packet_id UUID PRIMARY KEY,
    flight_id TEXT NOT NULL,
    drone_id TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    location GEOMETRY(POINTZ, 4326),
    heading FLOAT,
    pitch FLOAT,
    fov FLOAT,
    speed FLOAT,
    battery INT
);
CREATE INDEX IF NOT EXISTS idx_telemetry_flight ON telemetry (flight_id, recorded_at);

CREATE TABLE IF NOT EXISTS detections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    telemetry_packet_id UUID REFERENCES telemetry(packet_id) ON DELETE CASCADE,
    flight_id TEXT NOT NULL,
    detected_at TIMESTAMPTZ NOT NULL,
    class_type TEXT NOT NULL,
    score FLOAT,
    severity FLOAT,
    geometry_geo GEOMETRY(POLYGON, 4326),
    geometry_image JSONB,
    image_path TEXT
);
CREATE INDEX IF NOT EXISTS idx_detections_geo ON detections USING GIST (geometry_geo);

CREATE TABLE IF NOT EXISTS COMPANIES (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    code TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_companies_id ON COMPANIES (id, name);

CREATE TABLE IF NOT EXISTS USERS (
    id UUID PRIMARY KEY,
    keycloak_user_id TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_users_id ON USERS (id, keycloak_user_id);

CREATE TABLE IF NOT EXISTS COMPANY_USERS (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES COMPANIES(id),
    user_id UUID REFERENCES USERS(id),
    role TEXT NOT NULL,
    status TEXT NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_company_users_id ON COMPANY_USERS (id, user_id);

CREATE TABLE IF NOT EXISTS FLIGHTS (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES COMPANIES(id),
    external_id TEXT NOT NULL,
    status TEXT NOT NULL,
    flight_started_at TIMESTAMPTZ NOT NULL,
    flight_finished_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_flights_id ON FLIGHTS (id, company_id);

CREATE TABLE IF NOT EXISTS DETECTIONS_1 (
    id UUID PRIMARY KEY,
    flight_id UUID REFERENCES FLIGHTS(id),
    type TEXT NOT NULL,
    status TEXT NOT NULL,
    score INT,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    geometry GEOMETRY,
    centroid_lat DECIMAL,
    centroid_lon DECIMAL,
    area DECIMAL,  
    last_detection_at TIMESTAMPTZ NOT NULL,   
    created_by UUID REFERENCES USERS(id),
    updated_by UUID REFERENCES USERS(id),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    archived_at TIMESTAMPTZ NULL
);
CREATE INDEX IF NOT EXISTS idx_detections_id ON DETECTIONS_1 (id, flight_id);

CREATE TABLE IF NOT EXISTS DETECTION_EVENTS (
    id UUID PRIMARY KEY,
    detection_id UUID REFERENCES DETECTIONS_1(id),
    event_type TEXT NOT NULL,
    severity INT,
    payload JSON,
    created_by UUID REFERENCES USERS(id),
    event_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_detection_events_id ON DETECTION_EVENTS (id, detection_id);

CREATE TABLE IF NOT EXISTS DETECTION_COMMENTS (
    id UUID PRIMARY KEY,
    detection_id UUID REFERENCES DETECTIONS_1(id),
    author_user_id UUID REFERENCES USERS(id),
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    deleted_at TIMESTAMPTZ NULL
);
CREATE INDEX IF NOT EXISTS idx_detection_comments_id ON DETECTION_COMMENTS (id, detection_id);



