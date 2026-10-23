begin;
-- Read operations acquire the operator row's permission lock through
-- require_seed. PostgreSQL disallows that lock in STABLE functions.
alter function public.mefrion_seed_permissions() volatile;
alter function public.mefrion_seed_rights_history(uuid) volatile;
alter function public.mefrion_seed_audit() volatile;
alter function public.mefrion_seed_metrics() volatile;
commit;
