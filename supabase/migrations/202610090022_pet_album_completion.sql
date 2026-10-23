begin;
alter table mefrion_private.pets add column details jsonb not null default '{}';
alter table mefrion_private.pets add column public_fields text[] not null default array['breed','introduction'];
alter table mefrion_private.photos add column fingerprint text;
alter table mefrion_private.photos add column event_kind text;
alter table mefrion_private.photos add column note text not null default '';
create table mefrion_private.pet_events(id uuid primary key default gen_random_uuid(),pet_id uuid not null references mefrion_private.pets(id) on delete cascade,actor_id uuid not null references auth.users(id),request_key uuid not null,captured text,title text not null,event_kind text not null,note text not null default '',unique(pet_id,actor_id,request_key));
create table mefrion_private.pet_notification_settings(pet_id uuid references mefrion_private.pets(id) on delete cascade,user_id uuid references auth.users(id),frequency text not null default 'off' check(frequency in ('off','immediate','batched')),milestones boolean not null default false,paused_until timestamptz,primary key(pet_id,user_id));
alter table mefrion_private.pet_events enable row level security;
alter table mefrion_private.pet_notification_settings enable row level security;
revoke all on mefrion_private.pet_events,mefrion_private.pet_notification_settings from public,anon,authenticated;
create function mefrion_private.valid_partial_date(p_value text) returns boolean language plpgsql immutable set search_path='' as $$
begin
 if p_value is null then return true;end if;
 if p_value ~ '^[0-9]{4}$' then perform make_date(p_value::integer,1,1);
 elsif p_value ~ '^[0-9]{4}-[0-9]{2}$' then perform make_date(split_part(p_value,'-',1)::integer,split_part(p_value,'-',2)::integer,1);
 elsif p_value ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then perform make_date(split_part(p_value,'-',1)::integer,split_part(p_value,'-',2)::integer,split_part(p_value,'-',3)::integer);
 else return false;end if;return true;
 exception when others then return false;
end $$;
create function public.mefrion_update_pet(p_pet uuid,p_name text,p_breed text,p_introduction text,p_details jsonb,p_public_fields text[]) returns boolean language plpgsql security definer set search_path='' as $$
declare k text;v_photo uuid;
begin
 perform mefrion_private.require_registered();
 perform 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid() for update;
 if not found then raise exception 'owner_required' using errcode='42501';end if;
 if p_name is null or length(btrim(p_name)) not between 1 and 40 or p_breed is null or length(p_breed)>100 or p_introduction is null or length(p_introduction)>500 then raise exception 'profile_invalid';end if;
 if p_details is null or jsonb_typeof(p_details)<>'object' or length(p_details::text)>4000 or exists(select 1 from jsonb_object_keys(p_details) t(key) where key not in ('sex','birthday','arrival','age_basis','temperament','life_status','icon_photo','cover_photo')) then raise exception 'details_invalid';end if;
 if coalesce(p_details->>'sex','unknown') not in ('unknown','male','female') or coalesce(p_details->>'life_status','living') not in ('living','senior','deceased') then raise exception 'profile_invalid';end if;
 if not mefrion_private.valid_partial_date(p_details->>'birthday') or not mefrion_private.valid_partial_date(p_details->>'arrival') or length(coalesce(p_details->>'temperament',''))>200 or length(coalesce(p_details->>'age_basis',''))>100 then raise exception 'profile_invalid';end if;
 if p_public_fields is null or not p_public_fields <@ array['breed','introduction','sex','birthday','arrival','age_basis','temperament','life_status'] then raise exception 'public_fields_invalid';end if;
 foreach k in array array['icon_photo','cover_photo'] loop
  if p_details->>k is not null then
   v_photo:=(p_details->>k)::uuid;
   if not exists(select 1 from mefrion_private.photos where id=v_photo and pet_id=p_pet and state='ready') then raise exception 'profile_photo_scope';end if;
  end if;
 end loop;
 update mefrion_private.pets set name=btrim(p_name),breed=p_breed,introduction=p_introduction,details=p_details,public_fields=p_public_fields where id=p_pet;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'pet.update');return true;
end $$;
create or replace function public.mefrion_list_pets() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'species',p.species,'breed',p.breed,'introduction',p.introduction,'details',p.details,'public_fields',p.public_fields,'role',case when p.owner_id=auth.uid() then 'owner' else 'family' end) order by p.created_at,p.id),'[]'::jsonb) from mefrion_private.pets p where public.mefrion_family_access(p.id));
end $$;
create function public.mefrion_public_pet(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p mefrion_private.pets;v jsonb;f text;
begin
 select pet.* into p from mefrion_private.pets pet join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled where pet.id=p_pet and not exists(select 1 from mefrion_private.account_retirements where user_id=pet.owner_id) and mefrion_private.social_actor_visible(auth.uid(),pet.owner_id);
 if not found then raise exception 'profile_unavailable' using errcode='42501';end if;
 v:=jsonb_build_object('id',p.id,'name',p.name,'species',p.species);
 foreach f in array p.public_fields loop
  if f='breed' then v:=v||jsonb_build_object(f,p.breed);elsif f='introduction' then v:=v||jsonb_build_object(f,p.introduction);elsif p.details ? f then v:=v||jsonb_build_object(f,p.details->f);end if;
 end loop;return v;
end $$;
create function public.mefrion_edit_photo(p_photo uuid,p_captured text,p_title text,p_event_kind text,p_note text) returns boolean language plpgsql security definer set search_path='' as $$
declare p mefrion_private.photos;
begin
 perform mefrion_private.require_registered();select * into p from mefrion_private.photos where id=p_photo for update;
 if not found or p.provider_id<>auth.uid() or p.state<>'ready' or not public.mefrion_family_access(p.pet_id) then raise exception 'provider_required' using errcode='42501';end if;
 if not mefrion_private.valid_partial_date(p_captured) or p_title is null or length(p_title)>200 or p_note is null or length(p_note)>200 or (p_event_kind is not null and p_event_kind not in ('birthday','anniversary','arrival','hospital','other')) then raise exception 'photo_metadata_invalid';end if;
 update mefrion_private.photos set captured=p_captured,title=p_title,event_kind=p_event_kind,note=p_note where id=p_photo;return true;
end $$;
create function public.mefrion_record_fingerprint(p_photo uuid,p_fingerprint text) returns jsonb language plpgsql security definer set search_path='' as $$
declare p mefrion_private.photos;matches jsonb;
begin
 perform mefrion_private.require_registered();select * into p from mefrion_private.photos where id=p_photo and provider_id=auth.uid() and state in ('pending','ready') for update;
 if not found or not public.mefrion_family_access(p.pet_id) then raise exception 'provider_required' using errcode='42501';end if;
 if p_fingerprint is null or p_fingerprint !~ '^[a-f0-9]{64}$' then raise exception 'fingerprint_invalid';end if;
 if p.fingerprint is not null and p.fingerprint<>p_fingerprint then raise exception 'idempotency_conflict';end if;
 update mefrion_private.photos set fingerprint=p_fingerprint where id=p.id;
 select coalesce(jsonb_agg(id),'[]') into matches from mefrion_private.photos where pet_id=p.pet_id and id<>p.id and fingerprint=p_fingerprint and state='ready';
 return matches;
end $$;
create or replace function public.mefrion_album(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'path',object_path,'captured',captured,'title',title,'mine',provider_id=auth.uid(),'event_kind',event_kind,'note',note) order by captured desc nulls last,created_at desc,id),'[]') from mefrion_private.photos where pet_id=p_pet and state='ready');
end $$;
create function public.mefrion_save_event(p_pet uuid,p_key uuid,p_captured text,p_title text,p_kind text,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
declare v mefrion_private.pet_events;
begin
 perform mefrion_private.require_registered();perform 1 from mefrion_private.pets where id=p_pet for share;
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 if p_key is null or not mefrion_private.valid_partial_date(p_captured) or p_title is null or length(btrim(p_title)) not between 1 and 30 or p_kind is null or p_kind not in ('birthday','anniversary','arrival','hospital','other') or p_note is null or length(p_note)>200 then raise exception 'event_invalid';end if;
 select * into v from mefrion_private.pet_events where pet_id=p_pet and actor_id=auth.uid() and request_key=p_key for update;
 if found then
  if v.captured is distinct from p_captured or v.title<>btrim(p_title) or v.event_kind<>p_kind or v.note<>p_note then raise exception 'idempotency_conflict';end if;return v.id;
 end if;
 insert into mefrion_private.pet_events(pet_id,actor_id,request_key,captured,title,event_kind,note) values(p_pet,auth.uid(),p_key,p_captured,btrim(p_title),p_kind,p_note) returning * into v;return v.id;
end $$;
create function public.mefrion_events(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'captured',captured,'title',title,'kind',event_kind,'note',note,'mine',actor_id=auth.uid()) order by captured desc nulls last,id),'[]') from mefrion_private.pet_events where pet_id=p_pet);
end $$;
create function public.mefrion_delete_event(p_event uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare v mefrion_private.pet_events;
begin
 perform mefrion_private.require_registered();select * into v from mefrion_private.pet_events where id=p_event for update;
 if not found or not public.mefrion_family_access(v.pet_id) or v.actor_id<>auth.uid() then raise exception 'provider_required' using errcode='42501';end if;
 delete from mefrion_private.pet_events where id=p_event;return true;
end $$;
create function public.mefrion_pet_notifications(p_pet uuid,p_frequency text,p_milestones boolean,p_paused_until timestamptz) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();perform 1 from mefrion_private.pets where id=p_pet for share;
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 if p_frequency is null or p_frequency not in ('off','immediate','batched') or p_milestones is null or (p_paused_until is not null and (p_paused_until<now() or p_paused_until>now()+interval '366 days')) then raise exception 'notification_setting_invalid';end if;
 insert into mefrion_private.pet_notification_settings values(p_pet,auth.uid(),p_frequency,p_milestones,p_paused_until) on conflict(pet_id,user_id) do update set frequency=excluded.frequency,milestones=excluded.milestones,paused_until=excluded.paused_until;return true;
end $$;
create function public.mefrion_get_pet_notifications(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return coalesce((select jsonb_build_object('frequency',frequency,'milestones',milestones,'paused_until',paused_until) from mefrion_private.pet_notification_settings where pet_id=p_pet and user_id=auth.uid()),'{"frequency":"off","milestones":false,"paused_until":null}'::jsonb);
end $$;
create function mefrion_private.album_retirement_scrub() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update mefrion_private.pets set details='{}',public_fields='{}' where owner_id=new.user_id;
 delete from mefrion_private.pet_events where actor_id=new.user_id or pet_id in (select id from mefrion_private.pets where owner_id=new.user_id);
 delete from mefrion_private.pet_notification_settings where user_id=new.user_id or pet_id in (select id from mefrion_private.pets where owner_id=new.user_id);
 delete from mefrion_private.notification_preferences where user_id=new.user_id;
 return new;
end $$;
create trigger mefrion_album_retirement after insert on mefrion_private.account_retirements for each row execute function mefrion_private.album_retirement_scrub();
create function mefrion_private.clear_profile_photo() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.state='deleted' then update mefrion_private.pets set details=details-case when details->>'icon_photo'=new.id::text then 'icon_photo' else '_none' end-case when details->>'cover_photo'=new.id::text then 'cover_photo' else '_none' end where id=new.pet_id;end if;return new;
end $$;
create trigger mefrion_profile_photo_deleted after update of state on mefrion_private.photos for each row execute function mefrion_private.clear_profile_photo();
revoke execute on all functions in schema mefrion_private from public,anon,authenticated;
revoke execute on function public.mefrion_update_pet(uuid,text,text,text,jsonb,text[]),public.mefrion_edit_photo(uuid,text,text,text,text),public.mefrion_record_fingerprint(uuid,text),public.mefrion_save_event(uuid,uuid,text,text,text,text),public.mefrion_events(uuid),public.mefrion_delete_event(uuid),public.mefrion_pet_notifications(uuid,text,boolean,timestamptz),public.mefrion_get_pet_notifications(uuid) from public,anon;
grant execute on function public.mefrion_update_pet(uuid,text,text,text,jsonb,text[]),public.mefrion_edit_photo(uuid,text,text,text,text),public.mefrion_record_fingerprint(uuid,text),public.mefrion_save_event(uuid,uuid,text,text,text,text),public.mefrion_events(uuid),public.mefrion_delete_event(uuid),public.mefrion_pet_notifications(uuid,text,boolean,timestamptz),public.mefrion_get_pet_notifications(uuid) to authenticated;
revoke execute on function public.mefrion_public_pet(uuid) from public;
grant execute on function public.mefrion_public_pet(uuid) to anon,authenticated;
commit;
