begin;
-- New private objects must not accidentally inherit Supabase/public grants.
-- Existing RPC grants and public catalogue access remain unchanged.
alter default privileges for role postgres in schema mefrion_private revoke all on tables from public,anon,authenticated;
alter default privileges for role postgres in schema mefrion_private revoke all on sequences from public,anon,authenticated;
-- A schema-local REVOKE cannot override PostgreSQL's global default PUBLIC
-- EXECUTE grant. Remove that global default; new public RPCs must explicitly
-- grant their intended callers, as our application migrations already do.
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role postgres in schema mefrion_private revoke execute on functions from anon,authenticated;
commit;
