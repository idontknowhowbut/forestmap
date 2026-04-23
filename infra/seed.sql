-- Test Company
INSERT INTO companies (id, name, code, status, created_at, updated_at)
VALUES ('f2e67fd0-1234-496a-ac02-a1ffcc6274ef', 'Test Company', 'TEST', 'active', now(), now())
ON CONFLICT DO NOTHING;

-- Test User
INSERT INTO users (id, keycloak_user_id, email, full_name, status, created_at, updated_at)
VALUES ('f2e67fd0-1234-496a-ac02-a1ffcc6274ef', 'test-keycloak-id', 'test@forestmap.com', 'Test User', 'active', now(), now())
ON CONFLICT DO NOTHING;
