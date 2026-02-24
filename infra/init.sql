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
