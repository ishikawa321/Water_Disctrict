-- Read-only catalog inspection: no operational row data or credentials.
-- Run in an authorized SQL session. The CLI also enforces a read-only transaction.
SELECT jsonb_pretty(jsonb_build_object(
  'columns', (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.table_name, c.ordinal_position)
    FROM (SELECT table_schema, table_name, column_name, ordinal_position, data_type,
      udt_name, is_nullable, column_default
      FROM information_schema.columns WHERE table_schema = 'public') c),
  'constraints', (SELECT jsonb_agg(to_jsonb(c)) FROM (
    SELECT t.relname AS table_name, c.conname AS name, c.contype AS type,
      pg_get_constraintdef(c.oid) AS definition
    FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace WHERE n.nspname = 'public') c),
  'indexes', (SELECT jsonb_agg(to_jsonb(i)) FROM (
    SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = 'public') i),
  'policies', (SELECT jsonb_agg(to_jsonb(p)) FROM (
    SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
    FROM pg_policies WHERE schemaname = 'public') p),
  'row_security', (SELECT jsonb_agg(to_jsonb(r)) FROM (
    SELECT c.relname AS table_name, c.relrowsecurity AS enabled, c.relforcerowsecurity AS forced
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r') r),
  'grants', (SELECT jsonb_agg(to_jsonb(g)) FROM (
    SELECT table_name, grantee, privilege_type FROM information_schema.table_privileges
    WHERE table_schema = 'public') g),
  'triggers', (SELECT jsonb_agg(to_jsonb(t)) FROM (
    SELECT c.relname AS table_name, t.tgname AS name, pg_get_triggerdef(t.oid) AS definition
    FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND NOT t.tgisinternal) t),
  'enums', (SELECT jsonb_agg(to_jsonb(e)) FROM (
    SELECT t.typname AS name, e.enumlabel AS value, e.enumsortorder AS position
    FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
    JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public') e)
));
