-- Approved development project: human-account blocking and private report intake.
begin;
alter table mefrion_private.social_blocks add column target_pet uuid references mefrion_private.pets(id);
alter table mefrion_private.social_blocks add column label text not null default '';
create table mefrion_private.reports (
 id uuid primary key default gen_random_uuid(), actor_id uuid not null references auth.users(id),
 request_key uuid not null, post_id uuid references mefrion_private.public_posts(id),
 pet_id uuid not null references mefrion_private.pets(id), target_id uuid not null references auth.users(id),
 reason text not null check(reason in ('spam','harassment','animal_welfare','impersonation','copyright','other')),
 note text not null default '' check(length(note)<=1000),
 snapshot jsonb not null, created_at timestamptz not null default now(), state text not null default 'open' check(state in ('open','resolved')),
 unique(actor_id,request_key)
);
alter table mefrion_private.reports enable row level security;
revoke all on mefrion_private.reports from public,anon,authenticated;

create or replace function public.mefrion_block_pet(p_pet uuid,p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_target uuid;v_label text;
begin
 perform mefrion_private.require_registered();
 if p_enabled is null then raise exception 'block_invalid';end if;
 if p_enabled then
  select pet.owner_id,pet.name into v_target,v_label from mefrion_private.pets pet join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled where pet.id=p_pet;
  if not found then raise exception 'public_pet_required' using errcode='42501';end if;
  if v_target=auth.uid() then raise exception 'self_block_invalid';end if;
  insert into mefrion_private.social_blocks(actor_id,target_id,target_pet,label) values(auth.uid(),v_target,p_pet,v_label) on conflict(actor_id,target_id) do nothing;
 else
  -- Resolve an existing block only; no lookup of a now-private Pet's profile.
  delete from mefrion_private.social_blocks where actor_id=auth.uid() and target_pet=p_pet;
 end if;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'social.block.'||p_enabled::text);
 return p_enabled;
end $$;
create or replace function public.mefrion_blocked_pets() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',target_pet,'name',label)),'[]'::jsonb) from mefrion_private.social_blocks where actor_id=auth.uid());
end $$;

create or replace function public.mefrion_report(p_post uuid,p_pet uuid,p_reason text,p_note text,p_request_key uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_old mefrion_private.reports;v_pet mefrion_private.pets;v_body text;v_snapshot jsonb;v_id uuid;
begin
 perform mefrion_private.require_registered();
 if p_request_key is null or p_reason is null or p_reason not in ('spam','harassment','animal_welfare','impersonation','copyright','other') or p_note is null or length(p_note)>1000 then raise exception 'report_invalid';end if;
 -- Serialize intake and its hourly bound without publishing reporter identity.
 perform 1 from auth.users where id=auth.uid() for update;
 select * into v_old from mefrion_private.reports where actor_id=auth.uid() and request_key=p_request_key;
 if found then
  if v_old.post_id is distinct from p_post or v_old.pet_id is distinct from p_pet or v_old.reason<>p_reason or v_old.note<>p_note then raise exception 'idempotency_conflict';end if;
  return v_old.id;
 end if;
 if (select count(*) from mefrion_private.reports where actor_id=auth.uid() and created_at>now()-interval '1 hour')>=10 then raise exception 'report_rate_limit';end if;
 select pet.* into v_pet from mefrion_private.pets pet join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled where pet.id=p_pet;
 if not found then raise exception 'public_pet_required' using errcode='42501';end if;
 if p_post is not null then
  select body into v_body from mefrion_private.public_posts where id=p_post and pet_id=p_pet and mefrion_private.post_allowed(id,auth.uid());
  if not found then raise exception 'visible_post_required' using errcode='42501';end if;
 end if;
 v_snapshot:=jsonb_build_object('name',v_pet.name,'species',v_pet.species,'breed',v_pet.breed,'body',v_body);
 insert into mefrion_private.reports(actor_id,request_key,post_id,pet_id,target_id,reason,note,snapshot)
 values(auth.uid(),p_request_key,p_post,p_pet,v_pet.owner_id,p_reason,p_note,v_snapshot) returning id into v_id;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'report.create');
 return v_id;
end $$;
-- Service-only intake for the forthcoming authenticated operator interface.
-- Reporter identity, family originals and source paths are excluded even here.
create or replace function public.mefrion_report_queue() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'operator_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'post_id',post_id,'pet_id',pet_id,'reason',reason,'note',note,'snapshot',snapshot,'state',state,'created_at',created_at)),'[]'::jsonb) from (select * from mefrion_private.reports order by created_at desc limit 50) queue);
end $$;
revoke execute on function public.mefrion_block_pet(uuid,boolean),public.mefrion_blocked_pets(),public.mefrion_report(uuid,uuid,text,text,uuid) from public,anon;
grant execute on function public.mefrion_block_pet(uuid,boolean),public.mefrion_blocked_pets(),public.mefrion_report(uuid,uuid,text,text,uuid) to authenticated;
revoke execute on function public.mefrion_report_queue() from public,anon,authenticated;
grant execute on function public.mefrion_report_queue() to service_role;
commit;
