begin;
create or replace function public.mefrion_cloud_ingest_allowed(p_bucket text,p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.role()='service_role' and case p_bucket
 when 'reference-thumbnails' then exists(select 1 from public.mefrion_reference_assets where file=p_path and not active and withdrawn_at is null)
 when 'family-originals' then exists(select 1 from mefrion_private.photos p
  join mefrion_private.managed_pets m on m.pet_id=p.pet_id
  join mefrion_private.managed_publishers publisher on publisher.id=m.publisher_id and publisher.active
  where (p.object_path=p_path or p.preview_path=p_path) and p.state='pending' and m.active and p.provider_id=m.publisher_id)
 else false end
$$;

create function mefrion_private.cloud_maintenance() returns void
language plpgsql security definer set search_path='' as $$
begin
 delete from public.mefrion_reference_retries where expires<=now();
 delete from public.mefrion_resemblance_retries where expires<=now();
 delete from public.mefrion_reference_usage where day<(now() at time zone 'Asia/Tokyo')::date-2;
 delete from mefrion_private.cloud_jobs where state in ('done','cancelled') and completed_at<now()-interval '30 days';
 delete from mefrion_private.deletion_outbox where state='done' and created_at<now()-interval '30 days';
 delete from cron.job_run_details where jobid in(select jobid from cron.job where jobname like 'mefrion-%') and end_time<now()-interval '7 days';
 insert into mefrion_private.cloud_worker_health(name,last_success,runs) values('maintenance',now(),1)
  on conflict(name) do update set last_success=now(),runs=mefrion_private.cloud_worker_health.runs+1;
end $$;
revoke all on function mefrion_private.cloud_maintenance() from public,anon,authenticated;
select cron.schedule('mefrion-cloud-maintenance','15 * * * *','select mefrion_private.cloud_maintenance();');
commit;
