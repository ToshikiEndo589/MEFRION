begin;
create function public.mefrion_cloud_reference_ingest_allowed(p_paths text[]) returns text[]
language sql stable security definer set search_path='' as $$
 select case when auth.role()='service_role' and cardinality(p_paths) between 1 and 20 then
  array(select file from public.mefrion_reference_assets where file=any(p_paths) and not active and withdrawn_at is null)
 else '{}'::text[] end
$$;
revoke all on function public.mefrion_cloud_reference_ingest_allowed(text[]) from public,anon,authenticated;
grant execute on function public.mefrion_cloud_reference_ingest_allowed(text[]) to service_role;
commit;
