create or replace function public.mefrion_operator_alert_claim() returns jsonb
language plpgsql security definer set search_path='' as $$
declare delivery mefrion_private.operator_alert_delivery;reports_n bigint;posts_n bigint;cases_n bigint;jobs_n bigint;errors_n bigint;oldest timestamptz;
 signature text;claim uuid;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 select * into delivery from mefrion_private.operator_alert_delivery where singleton for update;
 if delivery.lease_until>now() or delivery.retry_after>now() then return null;end if;
 select count(*),max(created_at) into reports_n,oldest from mefrion_private.reports where state='open';
 select count(*) into posts_n from mefrion_private.content_reviews r join mefrion_private.public_posts p on p.id=r.post_id
  where r.state='pending' and p.state='review' and r.created_at<now()-interval '30 minutes';
 select count(*) into cases_n from mefrion_private.operator_cases where state<>'resolved' and due_at<now();
 select count(*) into jobs_n from mefrion_private.cloud_jobs where state='failed';
 select count(*) into errors_n from mefrion_private.security_events where kind='server_error' and occurred_at>=now()-interval '1 hour' and not is_test;
 if reports_n+posts_n+cases_n+jobs_n=0 and errors_n<3 then return null;end if;
 signature:=md5(concat_ws(':',reports_n,coalesce(oldest::text,''),posts_n,cases_n,jobs_n,errors_n));
 if (delivery.last_signature=signature and delivery.last_sent_at>now()-interval '24 hours')
  or delivery.last_sent_at>now()-interval '1 hour' then return null;end if;
 claim:=gen_random_uuid();
 update mefrion_private.operator_alert_delivery set lease_id=claim,lease_until=now()+interval '3 minutes',pending_signature=signature where singleton;
 return jsonb_build_object('claim',claim,'reports',reports_n,'posts',posts_n,'cases',cases_n,'jobs',jobs_n,'server_errors',errors_n);
end $$;

