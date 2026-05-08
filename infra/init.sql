CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Legacy MVP tables were replaced by the canonical detections table.
DROP TABLE IF EXISTS detection_comments;
DROP TABLE IF EXISTS detection_events;
DROP TABLE IF EXISTS detections_business;

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
    score FLOAT CHECK (score IS NULL OR (score >= 0 AND score <= 1)),
    severity INT CHECK (severity IS NULL OR (severity >= 0 AND severity <= 100)),
    geometry_geo GEOMETRY,
    geometry_image JSONB,
    image_path TEXT
);
CREATE INDEX IF NOT EXISTS idx_detections_geo ON detections USING GIST (geometry_geo);

ALTER TABLE detections DROP CONSTRAINT IF EXISTS detections_score_range;
ALTER TABLE detections ADD CONSTRAINT detections_score_range CHECK (score IS NULL OR (score >= 0 AND score <= 1));
ALTER TABLE detections DROP CONSTRAINT IF EXISTS detections_severity_range;
ALTER TABLE detections ADD CONSTRAINT detections_severity_range CHECK (severity IS NULL OR (severity >= 0 AND severity <= 100));

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
CREATE INDEX IF NOT EXISTS idx_flights_external_id ON flights (external_id, company_id);

