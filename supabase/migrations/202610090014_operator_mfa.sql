begin;
create table mefrion_private.operators(user_id uuid primary key references auth.users(id),role text not null check(role in ('editor','approver','moderator','admin')),active boolean not null default true);
alter table mefrion_private.operators enable row level security;
revoke all on mefrion_private.operators from public,anon,authenticated;
create or replace function mefrion_private.require_moderator() returns void
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 if auth.jwt()->>'aal' is distinct from 'aal2' or not exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified' and factor_type='totp') then raise exception 'moderator_mfa_required' using errcode='42501';end if;
 perform 1 from mefrion_private.operators where user_id=auth.uid() and active and role in ('moderator','admin') for share;
 if not found then raise exception 'moderator_required' using errcode='42501';end if;
end $$;
revoke all on function mefrion_private.require_moderator() from public,anon,authenticated;
create or replace function mefrion_private.review_report_core(p_report uuid,p_decision text,p_note text,p_request_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_report mefrion_private.reports;v_old mefrion_private.report_reviews;v_id uuid;v_post uuid;
begin
 if p_request_key is null or p_decision is null or p_decision not in ('dismiss','hide_post','hide_comment','suspend_account','restore_account') or p_note is null or length(btrim(p_note)) not between 1 and 1000 then raise exception 'review_invalid';end if;
 select * into v_report from mefrion_private.reports where id=p_report for update;
 if not found then raise exception 'report_required';end if;
 select * into v_old from mefrion_private.report_reviews where request_key=p_request_key;
 if found then
  if v_old.report_id<>p_report or v_old.decision<>p_decision or v_old.note<>p_note then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',v_old.id,'state','resolved');
 end if;
 if p_decision='hide_comment' then
  if v_report.comment_id is null then raise exception 'comment_required';end if;
  update mefrion_private.social_comments set state='deleted',body='' where id=v_report.comment_id;
  delete from mefrion_private.social_notifications where kind in ('comment','reply') and event_key=v_report.comment_id::text;
 elsif p_decision='hide_post' then
  if v_report.comment_id is not null then raise exception 'comment_decision_required';end if;
  if v_report.post_id is null then raise exception 'post_required';end if;
  perform mefrion_private.stop_publication(v_report.post_id);
 elsif p_decision in ('suspend_account','restore_account') then
  perform 1 from auth.users where id=v_report.target_id for update;
  insert into mefrion_private.public_account_states(user_id,suspended) values(v_report.target_id,p_decision='suspend_account') on conflict(user_id) do update set suspended=excluded.suspended;
  if p_decision='suspend_account' then
   update mefrion_private.social_comments set state='hidden' where actor_id=v_report.target_id and state='active';
   delete from mefrion_private.social_notifications where actor_id=v_report.target_id;
   update mefrion_private.public_profiles set enabled=false where pet_id in(select id from mefrion_private.pets where owner_id=v_report.target_id);
   for v_post in select s.id from mefrion_private.public_posts s join mefrion_private.pets p on p.id=s.pet_id where p.owner_id=v_report.target_id loop perform mefrion_private.stop_publication(v_post);end loop;
  end if;
 end if;
 insert into mefrion_private.report_reviews(report_id,request_key,decision,note) values(p_report,p_request_key,p_decision,p_note) returning id into v_id;
 update mefrion_private.reports set state='resolved' where id=p_report;
 -- service action, not a fabricated human operator identity.
 insert into mefrion_private.audit(actor_id,pet_id,action) values(case when auth.role()='service_role' then null else auth.uid() end,v_report.pet_id,case when auth.role()='service_role' then 'service.review.' else 'operator.review.' end||p_decision);
 return jsonb_build_object('id',v_id,'state','resolved');
end $$;
create or replace function mefrion_private.report_queue_core() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'post_id',post_id,'comment_id',comment_id,'pet_id',pet_id,'reason',reason,'note',note,'snapshot',snapshot,'state',state,'created_at',created_at,
 'reviews',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'decision',v.decision,'note',v.note,'created_at',v.created_at)),'[]'::jsonb) from mefrion_private.report_reviews v where v.report_id=queue.id),
 'appeals',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'note',a.note,'created_at',a.created_at)),'[]'::jsonb) from mefrion_private.appeals a where a.report_id=queue.id))),'[]'::jsonb)
 from (select * from mefrion_private.reports order by created_at desc limit 50) queue);
end $$;
revoke all on function mefrion_private.review_report_core(uuid,text,text,uuid),mefrion_private.report_queue_core() from public,anon,authenticated;
create or replace function public.mefrion_review_report(p_report uuid,p_decision text,p_note text,p_request_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'operator_required' using errcode='42501';end if;
 return mefrion_private.review_report_core(p_report,p_decision,p_note,p_request_key);
end $$;
create or replace function public.mefrion_report_queue() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'operator_required' using errcode='42501';end if;
 return mefrion_private.report_queue_core();
end $$;
create or replace function public.mefrion_operator_queue() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_moderator();return mefrion_private.report_queue_core();
end $$;
create or replace function public.mefrion_operator_review(p_report uuid,p_decision text,p_note text,p_request_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_moderator();
 return mefrion_private.review_report_core(p_report,p_decision,p_note,p_request_key);
end $$;
-- Development fixtures only: this service RPC cannot grant a human account a role.
create or replace function public.mefrion_grant_test_operator(p_user uuid,p_role text,p_active boolean) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'service_required' using errcode='42501';end if;
 if p_role is null or p_role not in ('editor','approver','moderator','admin') or p_active is null or not exists(select 1 from auth.users where id=p_user and raw_user_meta_data->>'test_only'='true' and email like 'mefrion-test-%@example.invalid') then raise exception 'synthetic_fixture_required' using errcode='42501';end if;
 insert into mefrion_private.operators values(p_user,p_role,p_active) on conflict(user_id) do update set role=excluded.role,active=excluded.active;
 insert into mefrion_private.audit(actor_id,action) values(null,'service.test_operator.'||p_role);
 return true;
end $$;
revoke execute on function public.mefrion_grant_test_operator(uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.mefrion_grant_test_operator(uuid,text,boolean) to service_role;
revoke execute on function public.mefrion_operator_queue(),public.mefrion_operator_review(uuid,text,text,uuid) from public,anon;
grant execute on function public.mefrion_operator_queue(),public.mefrion_operator_review(uuid,text,text,uuid) to authenticated;
commit;
