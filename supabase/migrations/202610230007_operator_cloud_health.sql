begin;
create function public.mefrion_operator_cloud_health() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_moderator();
 return jsonb_build_object(
  'jobs',(select coalesce(jsonb_object_agg(state,n),'{}') from(select state,count(*) n from mefrion_private.cloud_jobs group by state) q),
  'health',(select coalesce(jsonb_agg(jsonb_build_object('name',name,'last_success',last_success,'last_failure',last_failure,'runs',runs,'failures',failures)),'[]') from mefrion_private.cloud_worker_health where name<>'finalization-check'),
  'database_bytes',pg_database_size(current_database()),
  'storage_bytes',(select coalesce(sum((metadata->>'size')::bigint),0) from storage.objects),
  'cron_failures_last_day',(select count(*) from cron.job_run_details where status='failed' and start_time>now()-interval '1 day' and jobid in(select jobid from cron.job where jobname like 'mefrion-%')),
  'oldest_pending',(select min(created_at) from mefrion_private.cloud_jobs where state in ('pending','processing','failed')));
end $$;
revoke all on function public.mefrion_operator_cloud_health() from public,anon;
grant execute on function public.mefrion_operator_cloud_health() to authenticated;
commit;
