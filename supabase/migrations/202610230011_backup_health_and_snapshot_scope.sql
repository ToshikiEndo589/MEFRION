begin;
create function public.mefrion_offsite_failure() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 insert into mefrion_private.cloud_worker_health(name,last_failure,failures) values('offsite-backup',now(),1)
 on conflict(name) do update set last_failure=now(),failures=mefrion_private.cloud_worker_health.failures+1;
end $$;
revoke all on function public.mefrion_offsite_failure() from public,anon,authenticated;
grant execute on function public.mefrion_offsite_failure() to service_role;
-- Do not recursively include encrypted backup payloads or transfer queues in
-- the same-project DB snapshots retained for quick operational recovery.
do $migration$
declare definition text;original text;
begin
 original:=pg_get_functiondef('public.mefrion_cloud_database_snapshot()'::regprocedure);
 definition:=replace(original,'tablename not in (''cloud_jobs'',''cloud_worker_health'')','tablename not in (''cloud_jobs'',''cloud_worker_health'',''offsite_runs'',''offsite_objects'')');
 if original=definition then raise exception 'snapshot_definition_changed';end if;
 execute definition;
end $migration$;
commit;
