-- Default company for local/dev startup.
INSERT INTO companies (id, name, code, status, created_at, updated_at)
VALUES ('f2e67fd0-1234-496a-ac02-a1ffcc6274ef', 'Test Company', 'TEST', 'active', now(), now())
ON CONFLICT DO NOTHING;
