begin;
create table mefrion_private.twins_candidates(id uuid primary key default gen_random_uuid(),pet_id uuid not null references mefrion_private.pets(id),source_id uuid not null references mefrion_private.photos(id),owner_id uuid not null references auth.users(id),consent_version integer not null,request_key uuid not null,state text not null default 'pending' check(state in ('pending','processing','ready','stopped')),object_path text not null unique,lease_until timestamptz,created_at timestamptz not null default now(),unique(owner_id,request_key));
create table mefrion_private.twins_searches(id uuid primary key default gen_random_uuid(),actor_id uuid not null references auth.users(id),request_key uuid not null,input_hash text not null check(input_hash~'^[a-f0-9]{64}$'),species text not null check(species in ('dog','cat')),state text not null default 'pending' check(state in ('pending','results','insufficient','poor_photo','failure')),candidates uuid[] not null default '{}',created_at timestamptz not null default now(),unique(actor_id,request_key));
alter table mefrion_private.twins_candidates enable row level security;alter table mefrion_private.twins_searches enable row level security;
revoke all on mefrion_private.twins_candidates,mefrion_private.twins_searches from public,anon,authenticated;
create function mefrion_private.twins_source_valid(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.twins_candidates t join mefrion_private.pets p on p.id=t.pet_id join mefrion_private.photos photo on photo.id=t.source_id and photo.state='ready' join mefrion_private.consents c on c.photo_id=photo.id and c.purpose='twins' and c.allowed and c.version=t.consent_version join mefrion_private.public_profiles profile on profile.pet_id=p.id and profile.enabled where t.id=p_id and t.state<>'stopped' and mefrion_private.social_actor_visible(null,p.owner_id) and not exists(select 1 from mefrion_private.account_retirements where user_id=p.owner_id) and mefrion_private.managed_public_ready(p.id))
$$;
create function mefrion_private.twins_visible(p_id uuid,p_actor uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.twins_candidates t where t.id=p_id and t.state='ready' and mefrion_private.twins_source_valid(t.id) and mefrion_private.social_actor_visible(p_actor,t.owner_id))
$$;
create function mefrion_private.stop_twins(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 update mefrion_private.twins_candidates set state='stopped',lease_until=null where id=p_id;
 insert into mefrion_private.deletion_outbox(object_path,bucket) select object_path,'public-derived' from mefrion_private.twins_candidates t where id=p_id and not exists(select 1 from mefrion_private.deletion_outbox d where d.object_path=t.object_path and d.bucket='public-derived' and d.state='pending');
end $$;
create function public.mefrion_twins_enroll(p_pet uuid,p_photo uuid,p_key uuid,p_explicit boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare t mefrion_private.twins_candidates;v integer;old_id uuid;new_id uuid:=gen_random_uuid();
begin
 perform mefrion_private.require_registered();
 if p_explicit is distinct from true or p_key is null then raise exception 'explicit_twins_enrollment_required';end if;
 perform 1 from mefrion_private.pets p join mefrion_private.public_profiles f on f.pet_id=p.id and f.enabled where p.id=p_pet and p.owner_id=auth.uid() for update of p;
 if not found then raise exception 'owned_public_pet_required' using errcode='42501';end if;
 select c.version into v from mefrion_private.photos photo join mefrion_private.consents c on c.photo_id=photo.id and c.purpose='twins' and c.allowed where photo.id=p_photo and photo.pet_id=p_pet and photo.state='ready' for share of photo,c;
 if not found then raise exception 'provider_twins_consent_required' using errcode='42501';end if;
 select * into t from mefrion_private.twins_candidates where owner_id=auth.uid() and request_key=p_key;
 if found then if t.pet_id<>p_pet or t.source_id<>p_photo or t.consent_version<>v then raise exception 'idempotency_conflict';end if;return jsonb_build_object('id',t.id,'state',t.state);end if;
 for old_id in select id from mefrion_private.twins_candidates where pet_id=p_pet and state<>'stopped' for update loop perform mefrion_private.stop_twins(old_id);end loop;
 insert into mefrion_private.twins_candidates(id,pet_id,source_id,owner_id,consent_version,request_key,object_path) values(new_id,p_pet,p_photo,auth.uid(),v,p_key,'twins-'||new_id::text||'.jpg');
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'twins.enroll');return jsonb_build_object('id',new_id,'state','pending');
end $$;
create function public.mefrion_twins_withdraw(p_pet uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare i uuid;
begin
 perform mefrion_private.require_registered();perform 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid() for share;
 if not found then raise exception 'owner_required' using errcode='42501';end if;
 for i in select id from mefrion_private.twins_candidates where pet_id=p_pet for update loop perform mefrion_private.stop_twins(i);end loop;return true;
end $$;
create function public.mefrion_twins_candidates(p_species text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_species not in ('dog','cat') or p_species is null then raise exception 'species_required';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'pet_id',p.id,'name',p.name,'species',p.species,'breed',case when 'breed'=any(p.public_fields) then p.breed else '' end) order by t.created_at,t.id),'[]') from (select * from mefrion_private.twins_candidates where mefrion_private.twins_visible(id,auth.uid()) and owner_id is distinct from auth.uid() and pet_id in(select id from mefrion_private.pets where species=p_species) order by created_at,id limit 100) t join mefrion_private.pets p on p.id=t.pet_id and p.species=p_species join mefrion_private.photos photo on photo.id=t.source_id);
end $$;
create function mefrion_private.require_twins_actor() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or exists(select 1 from mefrion_private.account_retirements where user_id=auth.uid()) or exists(select 1 from mefrion_private.public_account_states where user_id=auth.uid() and suspended) then raise exception 'active_actor_required' using errcode='42501';end if;
end $$;
create function public.mefrion_twins_begin(p_key uuid,p_hash text,p_species text) returns jsonb language plpgsql security definer set search_path='' as $$
declare t mefrion_private.twins_searches;cap integer;used integer;new_id uuid;
begin
 perform mefrion_private.require_twins_actor();
 if p_key is null or p_hash is null or p_hash!~'^[a-f0-9]{64}$' or p_species is null or p_species not in ('dog','cat') then raise exception 'search_invalid';end if;
 perform pg_advisory_xact_lock(hashtextextended('twins:'||auth.uid()::text,0));
 select * into t from mefrion_private.twins_searches where actor_id=auth.uid() and request_key=p_key;
 if found then if t.input_hash<>p_hash or t.species<>p_species then raise exception 'idempotency_conflict';end if;return jsonb_build_object('id',t.id,'state',t.state);end if;
 cap:=case when coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then 1 else 5 end;
 select count(*) into used from mefrion_private.twins_searches where actor_id=auth.uid() and (cap=1 or (created_at at time zone 'Asia/Tokyo')::date=(now() at time zone 'Asia/Tokyo')::date);
 if used>=cap then raise exception 'daily_search_limit' using errcode='P0001';end if;
 insert into mefrion_private.twins_searches(actor_id,request_key,input_hash,species) values(auth.uid(),p_key,p_hash,p_species) returning id into new_id;
 return jsonb_build_object('id',new_id,'state','pending','remaining',cap-used-1);
end $$;
create function public.mefrion_twins_finish(p_search uuid,p_state text,p_candidates uuid[]) returns boolean language plpgsql security definer set search_path='' as $$
declare t mefrion_private.twins_searches;
begin
 perform mefrion_private.require_twins_actor();select * into t from mefrion_private.twins_searches where id=p_search and actor_id=auth.uid() for update;
 if not found or t.created_at<now()-interval '1 day' then raise exception 'own_recent_search_required' using errcode='42501';end if;
 if p_state is null or p_state not in ('results','insufficient','poor_photo','failure') or p_candidates is null or cardinality(p_candidates)>3 or cardinality(p_candidates)<>(select count(distinct id) from unnest(p_candidates) id) or (p_state='results' and cardinality(p_candidates)=0) or (p_state<>'results' and cardinality(p_candidates)>0) then raise exception 'result_invalid';end if;
 if exists(select 1 from unnest(p_candidates) q(id) left join mefrion_private.twins_candidates c on c.id=q.id left join mefrion_private.pets p on p.id=c.pet_id where not coalesce(mefrion_private.twins_visible(q.id,auth.uid()),false) or c.owner_id=auth.uid() or p.species<>t.species) then raise exception 'current_candidate_required' using errcode='42501';end if;
 if t.state not in ('pending','failure') then if t.state<>p_state or t.candidates<>p_candidates then raise exception 'idempotency_conflict';end if;return true;end if;
 update mefrion_private.twins_searches set state=p_state,candidates=p_candidates where id=p_search;return true;
end $$;
create function public.mefrion_twins_history() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();return (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'state',s.state,'species',s.species,'created_at',s.created_at,'candidates',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'pet_id',p.id,'name',p.name,'species',p.species)),'[]') from unnest(s.candidates) i join mefrion_private.twins_candidates c on c.id=i join mefrion_private.pets p on p.id=c.pet_id where mefrion_private.twins_visible(c.id,auth.uid()))) order by s.created_at desc),'[]') from (select * from mefrion_private.twins_searches where actor_id=auth.uid() and created_at>now()-interval '30 days' order by created_at desc limit 50) s);
end $$;
create function public.mefrion_twins_batch() returns jsonb language plpgsql security definer set search_path='' as $$
declare picked uuid[];i uuid;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 for i in select id from mefrion_private.twins_candidates where state<>'stopped' and not mefrion_private.twins_source_valid(id) for update loop perform mefrion_private.stop_twins(i);end loop;
 with claim as (select id from mefrion_private.twins_candidates where state='pending' or (state='processing' and lease_until<now()) order by created_at limit 10 for update skip locked),updated as (update mefrion_private.twins_candidates set state='processing',lease_until=now()+interval '5 minutes' where id in(select id from claim) returning id) select array_agg(id) into picked from updated;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'source_path',p.object_path,'path',t.object_path)),'[]') from mefrion_private.twins_candidates t join mefrion_private.photos p on p.id=t.source_id where t.id=any(picked));
end $$;
create function public.mefrion_twins_ready(p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 perform 1 from mefrion_private.twins_candidates where id=p_id for update;
 if not mefrion_private.twins_source_valid(p_id) or not exists(select 1 from mefrion_private.twins_candidates t join storage.objects o on o.bucket_id='public-derived' and o.name=t.object_path where t.id=p_id) then perform mefrion_private.stop_twins(p_id);return false;end if;
 update mefrion_private.twins_candidates set state='ready',lease_until=null where id=p_id;return true;
end $$;
create or replace function public.mefrion_public_image_path(p_media uuid,p_actor uuid default null) returns text language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'gateway_required' using errcode='42501';end if;
 return coalesce((select m.object_path from mefrion_private.public_media m where m.id=p_media and mefrion_private.post_allowed(m.post_id,p_actor)),(select object_path from mefrion_private.twins_candidates where id=p_media and mefrion_private.twins_visible(id,p_actor)));
end $$;
create function mefrion_private.invalidate_twins() returns trigger language plpgsql security definer set search_path='' as $$
declare i uuid;
begin
 for i in select id from mefrion_private.twins_candidates where state<>'stopped' and not mefrion_private.twins_source_valid(id) for update loop perform mefrion_private.stop_twins(i);end loop;return new;
end $$;
create trigger twins_photo_changes after update of state on mefrion_private.photos for each statement execute function mefrion_private.invalidate_twins();
create trigger twins_consent_changes after update on mefrion_private.consents for each statement execute function mefrion_private.invalidate_twins();
create trigger twins_profile_changes after update on mefrion_private.public_profiles for each statement execute function mefrion_private.invalidate_twins();
create function mefrion_private.retire_twins() returns trigger language plpgsql security definer set search_path='' as $$
declare i uuid;
begin
 for i in select id from mefrion_private.twins_candidates where owner_id=new.user_id for update loop perform mefrion_private.stop_twins(i);end loop;delete from mefrion_private.twins_searches where actor_id=new.user_id;return new;
end $$;
create trigger twins_retire after insert on mefrion_private.account_retirements for each row execute function mefrion_private.retire_twins();
revoke execute on function mefrion_private.twins_source_valid(uuid),mefrion_private.twins_visible(uuid,uuid),mefrion_private.stop_twins(uuid),mefrion_private.require_twins_actor(),mefrion_private.invalidate_twins(),mefrion_private.retire_twins() from public,anon,authenticated;
revoke execute on function public.mefrion_twins_enroll(uuid,uuid,uuid,boolean),public.mefrion_twins_withdraw(uuid),public.mefrion_twins_begin(uuid,text,text),public.mefrion_twins_finish(uuid,text,uuid[]),public.mefrion_twins_history() from public,anon;grant execute on function public.mefrion_twins_enroll(uuid,uuid,uuid,boolean),public.mefrion_twins_withdraw(uuid),public.mefrion_twins_begin(uuid,text,text),public.mefrion_twins_finish(uuid,text,uuid[]),public.mefrion_twins_history() to authenticated;
revoke execute on function public.mefrion_twins_candidates(text) from public;grant execute on function public.mefrion_twins_candidates(text) to anon,authenticated;
revoke execute on function public.mefrion_twins_batch(),public.mefrion_twins_ready(uuid) from public,anon,authenticated;grant execute on function public.mefrion_twins_batch(),public.mefrion_twins_ready(uuid) to service_role;
commit;
