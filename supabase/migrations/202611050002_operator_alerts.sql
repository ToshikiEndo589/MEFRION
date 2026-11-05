begin;

create table mefrion_private.operator_alert_delivery (
 singleton boolean primary key default true check(singleton),
 lease_id uuid,
 lease_until timestamptz,
 retry_after timestamptz,
 pending_signature text,
 last_signature text,
 last_sent_at timestamptz,
 last_failure_at timestamptz,
 failures integer not null default 0
);
insert into mefrion_private.operator_alert_delivery(singleton) values(true);
alter table mefrion_private.operator_alert_delivery enable row level security;
revoke all on mefrion_private.operator_alert_delivery from public,anon,authenticated,service_role;

create function public.mefrion_operator_alert_claim() returns jsonb
language plpgsql security definer set search_path='' as $$
declare state mefrion_private.operator_alert_delivery;reports_n bigint;posts_n bigint;cases_n bigint;jobs_n bigint;errors_n bigint;oldest timestamptz;
 signature text;claim uuid;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 select * into state from mefrion_private.operator_alert_delivery where singleton for update;
 if state.lease_until>now() or state.retry_after>now() then return null;end if;
 select count(*),max(created_at) into reports_n,oldest from mefrion_private.reports where state='open';
 select count(*) into posts_n from mefrion_private.content_reviews r join mefrion_private.public_posts p on p.id=r.post_id
  where r.state='pending' and p.state='review' and r.created_at<now()-interval '30 minutes';
 select count(*) into cases_n from mefrion_private.operator_cases where state<>'resolved' and due_at<now();
 select count(*) into jobs_n from mefrion_private.cloud_jobs where state='failed';
 select count(*) into errors_n from mefrion_private.security_events where kind='server_error' and occurred_at>=now()-interval '1 hour' and not is_test;
 if reports_n+posts_n+cases_n+jobs_n=0 and errors_n<3 then return null;end if;
 signature:=md5(concat_ws(':',reports_n,coalesce(oldest::text,''),posts_n,cases_n,jobs_n,errors_n));
 if (state.last_signature=signature and state.last_sent_at>now()-interval '24 hours')
  or state.last_sent_at>now()-interval '1 hour' then return null;end if;
 claim:=gen_random_uuid();
 update mefrion_private.operator_alert_delivery set lease_id=claim,lease_until=now()+interval '3 minutes',pending_signature=signature where singleton;
 return jsonb_build_object('claim',claim,'reports',reports_n,'posts',posts_n,'cases',cases_n,'jobs',jobs_n,'server_errors',errors_n);
end $$;

create function public.mefrion_operator_alert_finish(p_claim uuid,p_sent boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare updated integer;
begin
 if auth.role() is distinct from 'service_role' or p_claim is null or p_sent is null then raise exception 'worker_required' using errcode='42501';end if;
 update mefrion_private.operator_alert_delivery set lease_id=null,lease_until=null,
  last_signature=case when p_sent then pending_signature else last_signature end,
  pending_signature=null,
  last_sent_at=case when p_sent then now() else last_sent_at end,
  last_failure_at=case when p_sent then last_failure_at else now() end,
  retry_after=case when p_sent then null else now()+interval '15 minutes' end,
  failures=case when p_sent then failures else failures+1 end
 where singleton and lease_id=p_claim;
 get diagnostics updated=row_count;
 return updated=1;
end $$;

create function public.mefrion_operator_alert_status() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_moderator();
 return (select jsonb_build_object('last_sent_at',last_sent_at,'last_failure_at',last_failure_at,'failures',failures)
  from mefrion_private.operator_alert_delivery where singleton);
end $$;

create function mefrion_private.operator_alert_tick() returns void
language plpgsql security definer set search_path='' as $$
declare base text;token text;
begin
 select decrypted_secret into base from vault.decrypted_secrets where name='mefrion_project_url';
 select decrypted_secret into token from vault.decrypted_secrets where name='mefrion_cloud_worker_token';
 if base is null or token is null then return;end if;
 perform net.http_post(url:=base||'/functions/v1/operator-alerts',
  headers:=jsonb_build_object('Content-Type','application/json','x-mefrion-worker',token),
  body:='{}'::jsonb,timeout_milliseconds:=10000);
end $$;
revoke all on function mefrion_private.operator_alert_tick() from public,anon,authenticated,service_role;
revoke all on function public.mefrion_operator_alert_claim(),public.mefrion_operator_alert_finish(uuid,boolean) from public,anon,authenticated;
grant execute on function public.mefrion_operator_alert_claim(),public.mefrion_operator_alert_finish(uuid,boolean) to service_role;
revoke all on function public.mefrion_operator_alert_status() from public,anon;
grant execute on function public.mefrion_operator_alert_status() to authenticated;
-- Enable the 5-minute schedule after the Brevo API key is configured and a
-- delivery smoke test succeeds: select cron.schedule('mefrion-operator-alerts','*/5 * * * *','select mefrion_private.operator_alert_tick()');
commit;
