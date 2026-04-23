CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    code TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_companies_id ON companies (id, name);

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    keycloak_user_id TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_users_id ON users (id, keycloak_user_id);

CREATE TABLE IF NOT EXISTS company_users (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES companies(id),
    user_id UUID REFERENCES users(id),
    role TEXT NOT NULL,
    status TEXT NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_company_users_id ON company_users (id, user_id);

CREATE TABLE IF NOT EXISTS telemetry (
    packet_id UUID PRIMARY KEY,
    flight_id TEXT NOT NULL,
    drone_id TEXT NOT NULL,
    company_id UUID REFERENCES companies(id),
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
    company_id UUID REFERENCES companies(id),
    score FLOAT,
    severity FLOAT,
    geometry_geo GEOMETRY(POLYGON, 4326),
    geometry_image JSONB,
    image_path TEXT
);
CREATE INDEX IF NOT EXISTS idx_detections_geo ON detections USING GIST (geometry_geo);

CREATE TABLE IF NOT EXISTS flights (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES companies(id),
    external_id TEXT NOT NULL,
    status TEXT NOT NULL,
    flight_started_at TIMESTAMPTZ NOT NULL,
    flight_finished_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_flights_id ON flights (id, company_id);

CREATE TABLE IF NOT EXISTS detections_business (
    id UUID PRIMARY KEY,
    flight_id UUID REFERENCES flights(id),
    company_id UUID REFERENCES companies(id),
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
    created_by UUID REFERENCES users(id),
    updated_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    archived_at TIMESTAMPTZ NULL
);
CREATE INDEX IF NOT EXISTS idx_detections_id ON detections_business (id, flight_id);

CREATE TABLE IF NOT EXISTS detection_events (
    id UUID PRIMARY KEY,
    detection_id UUID REFERENCES detections_business(id),
    event_type TEXT NOT NULL,
    severity INT,
    payload JSON,
    created_by UUID REFERENCES users(id),
    event_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_detection_events_id ON detection_events (id, detection_id);

CREATE TABLE IF NOT EXISTS detection_comments (
    id UUID PRIMARY KEY,
    detection_id UUID REFERENCES detections_business(id),
    author_user_id UUID REFERENCES users(id),
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    deleted_at TIMESTAMPTZ NULL
);
CREATE INDEX IF NOT EXISTS idx_detection_comments_id ON detection_comments (id, detection_id);



