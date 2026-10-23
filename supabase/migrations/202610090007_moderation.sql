-- Development moderation engine. No operator secret is placed in an app/browser.
-- Production operator Auth/MFA and accountable staff identity are separate gates.
begin;
create table mefrion_private.public_account_states (
 user_id uuid primary key references auth.users(id), suspended boolean not null default false
);
create table mefrion_private.report_reviews (
 id uuid primary key default gen_random_uuid(), report_id uuid not null references mefrion_private.reports(id),
 request_key uuid not null unique, decision text not null check(decision in ('dismiss','hide_post','suspend_account','restore_account')),
 note text not null check(length(note) between 1 and 1000), created_at timestamptz not null default now()
);
create table mefrion_private.appeals (
 id uuid primary key default gen_random_uuid(), report_id uuid not null references mefrion_private.reports(id),
 actor_id uuid not null references auth.users(id), note text not null check(length(note) between 1 and 1000),
 created_at timestamptz not null default now(), unique(report_id,actor_id)
);
alter table mefrion_private.public_account_states enable row level security;
alter table mefrion_private.report_reviews enable row level security;
alter table mefrion_private.appeals enable row level security;
revoke all on mefrion_private.public_account_states,mefrion_private.report_reviews,mefrion_private.appeals from public,anon,authenticated;

create or replace function mefrion_private.require_public_actor() returns void
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 -- Same lock as suspension/recovery, so a second Pet cannot race past the gate.
 perform 1 from auth.users where id=auth.uid() for update;
 if exists(select 1 from mefrion_private.public_account_states where user_id=auth.uid() and suspended) then raise exception 'account_suspended' using errcode='42501';end if;
end $$;
revoke execute on function mefrion_private.require_public_actor() from public,anon,authenticated;
create or replace function mefrion_private.public_write_gate() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='public_posts' then perform mefrion_private.require_public_actor();
 elsif new.enabled then perform mefrion_private.require_public_actor();end if;
 return new;
end $$;
revoke execute on function mefrion_private.public_write_gate() from public,anon,authenticated;
create trigger mefrion_public_post_write before insert on mefrion_private.public_posts for each row execute function mefrion_private.public_write_gate();
create trigger mefrion_public_profile_write before insert or update on mefrion_private.public_profiles for each row execute function mefrion_private.public_write_gate();
create or replace function mefrion_private.post_allowed(p_post uuid,p_actor uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.public_posts s
 join mefrion_private.public_profiles profile on profile.pet_id=s.pet_id and profile.enabled
 join mefrion_private.pets pet on pet.id=s.pet_id
 where s.id=p_post and s.state='published'
 and not exists(select 1 from mefrion_private.public_account_states state where state.user_id=pet.owner_id and state.suspended)
 and not exists(select 1 from mefrion_private.social_blocks b where
  (b.actor_id=p_actor and b.target_id=pet.owner_id) or (b.actor_id=pet.owner_id and b.target_id=p_actor))
 and exists(select 1 from mefrion_private.public_media m where m.post_id=s.id)
 and not exists(select 1 from mefrion_private.public_media m
  left join mefrion_private.photos photo on photo.id=m.source_id
  left join mefrion_private.consents c on c.photo_id=photo.id and c.purpose=case when s.kind='post' then 'sns' else 'external_share' end
  where m.post_id=s.id and (photo.state is distinct from 'ready' or c.allowed is distinct from true or c.version is distinct from m.consent_version)))
$$;
revoke all on function mefrion_private.post_allowed(uuid,uuid) from public,anon,authenticated;

create or replace function public.mefrion_review_report(p_report uuid,p_decision text,p_note text,p_request_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_report mefrion_private.reports;v_old mefrion_private.report_reviews;v_id uuid;v_post uuid;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'operator_required' using errcode='42501';end if;
 if p_request_key is null or p_decision is null or p_decision not in ('dismiss','hide_post','suspend_account','restore_account') or p_note is null or length(btrim(p_note)) not between 1 and 1000 then raise exception 'review_invalid';end if;
 select * into v_report from mefrion_private.reports where id=p_report for update;
 if not found then raise exception 'report_required';end if;
 select * into v_old from mefrion_private.report_reviews where request_key=p_request_key;
 if found then
  if v_old.report_id<>p_report or v_old.decision<>p_decision or v_old.note<>p_note then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',v_old.id,'state','resolved');
 end if;
 if p_decision='hide_post' then
  if v_report.post_id is null then raise exception 'post_required';end if;
  perform mefrion_private.stop_publication(v_report.post_id);
 elsif p_decision in ('suspend_account','restore_account') then
  perform 1 from auth.users where id=v_report.target_id for update;
  insert into mefrion_private.public_account_states(user_id,suspended) values(v_report.target_id,p_decision='suspend_account') on conflict(user_id) do update set suspended=excluded.suspended;
  if p_decision='suspend_account' then
   update mefrion_private.public_profiles set enabled=false where pet_id in(select id from mefrion_private.pets where owner_id=v_report.target_id);
   for v_post in select s.id from mefrion_private.public_posts s join mefrion_private.pets p on p.id=s.pet_id where p.owner_id=v_report.target_id loop perform mefrion_private.stop_publication(v_post);end loop;
  end if;
 end if;
 insert into mefrion_private.report_reviews(report_id,request_key,decision,note) values(p_report,p_request_key,p_decision,p_note) returning id into v_id;
 update mefrion_private.reports set state='resolved' where id=p_report;
 -- service action, not a fabricated human operator identity.
 insert into mefrion_private.audit(actor_id,pet_id,action) values(null,v_report.pet_id,'service.review.'||p_decision);
 return jsonb_build_object('id',v_id,'state','resolved');
end $$;
create or replace function public.mefrion_appeal(p_report uuid,p_note text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform mefrion_private.require_registered();
 if p_note is null or length(btrim(p_note)) not between 1 and 1000 then raise exception 'appeal_invalid';end if;
 perform 1 from mefrion_private.reports where id=p_report and target_id=auth.uid() and state='resolved';
 if not found then raise exception 'target_required' using errcode='42501';end if;
 insert into mefrion_private.appeals(report_id,actor_id,note) values(p_report,auth.uid(),p_note) on conflict(report_id,actor_id) do nothing returning id into v_id;
 if v_id is null then
  select id into v_id from mefrion_private.appeals where report_id=p_report and actor_id=auth.uid() and note=p_note;
  if not found then raise exception 'appeal_already_submitted';end if;
 end if;
 return v_id;
end $$;
create or replace function public.mefrion_my_moderation() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'decision',v.decision,'note',v.note,'created_at',v.created_at)),'[]'::jsonb) from mefrion_private.reports r
 join lateral(select * from mefrion_private.report_reviews where report_id=r.id order by created_at desc,id limit 1) v on true where r.target_id=auth.uid());
end $$;
create or replace function public.mefrion_report_queue() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'operator_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'post_id',post_id,'pet_id',pet_id,'reason',reason,'note',note,'snapshot',snapshot,'state',state,'created_at',created_at,
 'reviews',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'decision',v.decision,'note',v.note,'created_at',v.created_at)),'[]'::jsonb) from mefrion_private.report_reviews v where v.report_id=queue.id),
 'appeals',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'note',a.note,'created_at',a.created_at)),'[]'::jsonb) from mefrion_private.appeals a where a.report_id=queue.id))),'[]'::jsonb)
 from (select * from mefrion_private.reports order by created_at desc limit 50) queue);
end $$;
revoke execute on function public.mefrion_review_report(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.mefrion_review_report(uuid,text,text,uuid) to service_role;
revoke execute on function public.mefrion_appeal(uuid,text),public.mefrion_my_moderation() from public,anon;
grant execute on function public.mefrion_appeal(uuid,text),public.mefrion_my_moderation() to authenticated;
commit;
