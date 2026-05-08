-- Default company for local/dev startup.
INSERT INTO companies (id, name, code, status, created_at, updated_at)
VALUES ('f2e67fd0-1234-496a-ac02-a1ffcc6274ef', 'Test Company', 'TEST', 'active', now(), now())
ON CONFLICT DO NOTHING;

-- Dev users are linked to Test Company explicitly.
-- keycloak_user_id is stable on a fresh Keycloak import. If an existing Keycloak
-- volume already generated different `sub` values, the backend re-binds the
-- matching seeded user by email on first request, preserving the company_users link.
INSERT INTO users (id, keycloak_user_id, email, full_name, status, created_at, updated_at)
VALUES
    ('11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'viewer@example.local', 'Viewer User', 'active', now(), now()),
    ('22222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222', 'admin@example.local', 'Admin User', 'active', now(), now()),
    ('33333333-3333-4333-8333-333333333333', '33333333-3333-4333-8333-333333333333', 'drone@example.local', 'Drone Service', 'active', now(), now())
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    status = EXCLUDED.status,
    updated_at = now();

INSERT INTO company_users (id, company_id, user_id, role, status, joined_at, created_at, updated_at)
VALUES
    ('aaaaaaaa-1111-4111-8111-111111111111', 'f2e67fd0-1234-496a-ac02-a1ffcc6274ef', '11111111-1111-4111-8111-111111111111', 'viewer', 'active', now(), now(), now()),
    ('aaaaaaaa-2222-4222-8222-222222222222', 'f2e67fd0-1234-496a-ac02-a1ffcc6274ef', '22222222-2222-4222-8222-222222222222', 'admin', 'active', now(), now(), now()),
    ('aaaaaaaa-3333-4333-8333-333333333333', 'f2e67fd0-1234-496a-ac02-a1ffcc6274ef', '33333333-3333-4333-8333-333333333333', 'drone', 'active', now(), now(), now())
ON CONFLICT (id) DO UPDATE SET
    role = EXCLUDED.role,
    status = EXCLUDED.status,
    updated_at = now();

