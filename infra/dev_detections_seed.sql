BEGIN;

-- Demo detections for local/dev map testing.
-- Requires the default company from infra/seed.sql.

INSERT INTO flights (
    id, company_id, external_id, status,
    flight_started_at, flight_finished_at, created_at, updated_at
) VALUES
(
    '11111111-1111-4111-8111-111111111111',
    'f2e67fd0-1234-496a-ac02-a1ffcc6274ef',
    'demo-flight-fire',
    'completed',
    now() - interval '2 days',
    now() - interval '2 days' + interval '45 minutes',
    now(), now()
),
(
    '22222222-2222-4222-8222-222222222222',
    'f2e67fd0-1234-496a-ac02-a1ffcc6274ef',
    'demo-flight-infection',
    'completed',
    now() - interval '1 day',
    now() - interval '1 day' + interval '35 minutes',
    now(), now()
),
(
    '33333333-3333-4333-8333-333333333333',
    'f2e67fd0-1234-496a-ac02-a1ffcc6274ef',
    'demo-flight-logging',
    'completed',
    now() - interval '12 hours',
    now() - interval '12 hours' + interval '25 minutes',
    now(), now()
),
(
    '44444444-4444-4444-8444-444444444444',
    'f2e67fd0-1234-496a-ac02-a1ffcc6274ef',
    'demo-flight-multipolygon',
    'completed',
    now() - interval '6 hours',
    now() - interval '6 hours' + interval '20 minutes',
    now(), now()
)
ON CONFLICT (id) DO UPDATE SET
    company_id = EXCLUDED.company_id,
    external_id = EXCLUDED.external_id,
    status = EXCLUDED.status,
    flight_started_at = EXCLUDED.flight_started_at,
    flight_finished_at = EXCLUDED.flight_finished_at,
    updated_at = now();

INSERT INTO detections (
    id, telemetry_packet_id, flight_id, detected_at, class_type, company_id, score, severity, geometry_geo, geometry_image, image_path
) VALUES
(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    NULL,
    'demo-flight-fire',
    now() - interval '2 days' + interval '20 minutes',
    'fire',
    'f2e67fd0-1234-496a-ac02-a1ffcc6274ef',
    0.92,
    0.90,
    ST_GeomFromText('POLYGON((30.5520 60.1180,30.5660 60.1180,30.5660 60.1290,30.5520 60.1290,30.5520 60.1180))', 4326),
    '{"source":"dev-seed","note":"fire rendered as point via backend"}'::jsonb,
    '/uploads/dev/fire-1.jpg'
),
(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    NULL,
    'demo-flight-infection',
    now() - interval '1 day' + interval '10 minutes',
    'infection',
    'f2e67fd0-1234-496a-ac02-a1ffcc6274ef',
    0.64,
    0.50,
    ST_GeomFromText('POLYGON((30.7000 60.0900,30.7600 60.0820,30.7900 60.1120,30.7750 60.1480,30.7320 60.1620,30.6900 60.1400,30.7000 60.0900))', 4326),
    '{"source":"dev-seed","note":"complex infection polygon"}'::jsonb,
    '/uploads/dev/infection-1.jpg'
),
(
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
    NULL,
    'demo-flight-logging',
    now() - interval '12 hours' + interval '5 minutes',
    'logging',
    'f2e67fd0-1234-496a-ac02-a1ffcc6274ef',
    0.48,
    0.30,
    ST_GeomFromText('MULTIPOLYGON(((30.6200 60.1800,30.6550 60.1800,30.6550 60.2100,30.6200 60.2100,30.6200 60.1800)),((30.6680 60.2050,30.7000 60.2050,30.7000 60.2350,30.6680 60.2350,30.6680 60.2050)))', 4326),
    '{"source":"dev-seed","note":"logging multipolygon"}'::jsonb,
    '/uploads/dev/logging-1.jpg'
),
(
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd4',
    NULL,
    'demo-flight-multipolygon',
    now() - interval '6 hours' + interval '3 minutes',
    'disease',
    'f2e67fd0-1234-496a-ac02-a1ffcc6274ef',
    0.73,
    0.61,
    ST_GeomFromText('MULTIPOLYGON(((30.8200 60.0900,30.8550 60.0900,30.8550 60.1250,30.8200 60.1250,30.8200 60.0900)),((30.8700 60.1000,30.9020 60.1000,30.9020 60.1320,30.8700 60.1320,30.8700 60.1000)))', 4326),
    '{"source":"dev-seed","note":"disease multipolygon normalized to infection"}'::jsonb,
    '/uploads/dev/disease-1.jpg'
)
ON CONFLICT (id) DO UPDATE SET
    telemetry_packet_id = EXCLUDED.telemetry_packet_id,
    flight_id = EXCLUDED.flight_id,
    detected_at = EXCLUDED.detected_at,
    class_type = EXCLUDED.class_type,
    company_id = EXCLUDED.company_id,
    score = EXCLUDED.score,
    severity = EXCLUDED.severity,
    geometry_geo = EXCLUDED.geometry_geo,
    geometry_image = EXCLUDED.geometry_image,
    image_path = EXCLUDED.image_path;

COMMIT;
