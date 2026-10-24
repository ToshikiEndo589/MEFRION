begin;
-- Small thumbnails only. Keep images out of Auth metadata/JWTs and prevent
-- avatar reads from revealing authentication identifiers or private album media.
create table if not exists mefrion_private.profile_icons (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 pet_id uuid unique references mefrion_private.pets(id) on delete cascade,
 jpeg bytea not null check(octet_length(jpeg) between 4 and 16384),
 updated_at timestamptz not null default now()
);
create unique index if not exists profile_icons_account on mefrion_private.profile_icons(owner_id) where pet_id is null;
alter table mefrion_private.profile_icons enable row level security;
revoke all on mefrion_private.profile_icons from public,anon,authenticated;

create or replace function mefrion_private.profile_icon_value(p_pet uuid,p_owner uuid default null) returns text
language sql stable security definer set search_path='' as $$
 select replace(encode(i.jpeg,'base64'),E'\n','') from mefrion_private.profile_icons i
 where ((p_pet is null and i.pet_id is null and i.owner_id=p_owner)
 or (p_pet is not null and i.pet_id=p_pet and (p_owner is null or i.owner_id=p_owner)
 and exists(select 1 from mefrion_private.pets p where p.id=i.pet_id and p.owner_id=i.owner_id)))
 and not exists(select 1 from mefrion_private.account_retirements r where r.user_id=i.owner_id)
$$;
create or replace function mefrion_private.set_profile_icon(p_pet uuid,p_jpeg text) returns void
language plpgsql security definer set search_path='' as $$
declare bytes bytea;
begin
 perform mefrion_private.require_registered();
 if p_pet is not null and not exists(select 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid()) then
  raise exception 'owner_required' using errcode='42501';
 end if;
 if p_jpeg is null then
  delete from mefrion_private.profile_icons where owner_id=auth.uid() and pet_id is not distinct from p_pet;
  return;
 end if;
 if length(p_jpeg)>22500 then raise exception 'icon_invalid';end if;
 begin bytes:=decode(p_jpeg,'base64');exception when others then raise exception 'icon_invalid';end;
 if octet_length(bytes) not between 4 and 16384 or substring(bytes from 1 for 3)<>decode('ffd8ff','hex')
 or substring(bytes from octet_length(bytes)-1 for 2)<>decode('ffd9','hex') then raise exception 'icon_invalid';end if;
 if p_pet is null then
  insert into mefrion_private.profile_icons(owner_id,jpeg) values(auth.uid(),bytes)
  on conflict(owner_id) where pet_id is null do update set jpeg=excluded.jpeg,updated_at=now();
 else
  insert into mefrion_private.profile_icons(owner_id,pet_id,jpeg) values(auth.uid(),p_pet,bytes)
  on conflict(pet_id) do update set owner_id=excluded.owner_id,jpeg=excluded.jpeg,updated_at=now();
 end if;
end $$;
create or replace function public.mefrion_account_profile() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return jsonb_build_object('name',coalesce((select name from mefrion_private.social_identities where user_id=auth.uid()),''),
 'icon',mefrion_private.profile_icon_value(null,auth.uid()));
end $$;
create or replace function public.mefrion_set_account_profile(p_name text,p_icon text,p_icon_changed boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.social_rate();
 if p_name is not null then perform public.mefrion_set_social_name(p_name);end if;
 if p_icon_changed is true then perform mefrion_private.set_profile_icon(null,p_icon);end if;
 insert into mefrion_private.audit(actor_id,action) values(auth.uid(),'social.write.account_profile');
 return public.mefrion_account_profile();
end $$;
create or replace function public.mefrion_my_pet_icon(p_pet uuid) returns text
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 if not public.mefrion_family_access(p_pet) then raise exception 'family_required' using errcode='42501';end if;
 return mefrion_private.profile_icon_value(p_pet);
end $$;
create or replace function public.mefrion_update_pet_profile(p_pet uuid,p_name text,p_breed text,p_introduction text,
 p_details jsonb,p_public_fields text[],p_icon text,p_icon_changed boolean) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.social_rate();
 perform public.mefrion_update_pet(p_pet,p_name,p_breed,p_introduction,p_details,p_public_fields);
 if p_icon_changed is true then perform mefrion_private.set_profile_icon(p_pet,p_icon);end if;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'social.write.pet_profile');
 return true;
end $$;

-- Preserve the existing visibility/block/retirement rules and only decorate
-- rows those projections already allow. Older apps safely ignore the new key.
do $$ begin
 if to_regprocedure('mefrion_private.profile_list_pets_base()') is null then
  alter function public.mefrion_list_pets() set schema mefrion_private;
  alter function mefrion_private.mefrion_list_pets() rename to profile_list_pets_base;
 end if;
 if to_regprocedure('mefrion_private.profile_feed_page_base(text,text,text,timestamptz,uuid,integer,uuid[])') is null then
  alter function public.mefrion_feed_page(text,text,text,timestamptz,uuid,integer,uuid[]) set schema mefrion_private;
  alter function mefrion_private.mefrion_feed_page(text,text,text,timestamptz,uuid,integer,uuid[]) rename to profile_feed_page_base;
 end if;
 if to_regprocedure('mefrion_private.profile_comments_base(uuid)') is null then
  alter function public.mefrion_comments(uuid) set schema mefrion_private;
  alter function mefrion_private.mefrion_comments(uuid) rename to profile_comments_base;
 end if;
 if to_regprocedure('mefrion_private.profile_public_pet_base(uuid)') is null then
  alter function public.mefrion_public_pet(uuid) set schema mefrion_private;
  alter function mefrion_private.mefrion_public_pet(uuid) rename to profile_public_pet_base;
 end if;
end $$;
create or replace function public.mefrion_list_pets() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item||jsonb_build_object('icon',mefrion_private.profile_icon_value((item->>'id')::uuid)) order by ordinal),'[]'::jsonb)
 from jsonb_array_elements(mefrion_private.profile_list_pets_base()) with ordinality as a(item,ordinal)
$$;
create or replace function public.mefrion_feed_page(p_mode text default 'all',p_query text default '',p_species text default 'all',
 p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 12,p_known_ids uuid[] default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare page jsonb;items jsonb;
begin
 page:=mefrion_private.profile_feed_page_base(p_mode,p_query,p_species,p_before,p_before_id,p_limit,p_known_ids);
 select coalesce(jsonb_agg(item||jsonb_build_object('icon',mefrion_private.profile_icon_value((item->>'pet_id')::uuid)) order by ordinal),'[]'::jsonb)
 into items from jsonb_array_elements(page->'items') with ordinality as a(item,ordinal);
 return jsonb_set(page,'{items}',items);
end $$;
create or replace function public.mefrion_comments(p_post uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item||jsonb_build_object('icon',case when c.state='active' then
 mefrion_private.profile_icon_value(c.alias_pet,c.actor_id) else null end) order by ordinal),'[]'::jsonb)
 from jsonb_array_elements(mefrion_private.profile_comments_base(p_post)) with ordinality as a(item,ordinal)
 join mefrion_private.social_comments c on c.id=(item->>'id')::uuid
$$;
create or replace function public.mefrion_public_pet(p_pet uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select mefrion_private.profile_public_pet_base(p_pet)||jsonb_build_object('icon',mefrion_private.profile_icon_value(p_pet))
$$;

create or replace function mefrion_private.retire_profile_icons() returns trigger
language plpgsql security definer set search_path='' as $$
begin delete from mefrion_private.profile_icons where owner_id=new.user_id;return new;end $$;
drop trigger if exists retire_profile_icons on mefrion_private.account_retirements;
create trigger retire_profile_icons after insert on mefrion_private.account_retirements for each row execute function mefrion_private.retire_profile_icons();

revoke all on function mefrion_private.profile_icon_value(uuid,uuid),mefrion_private.set_profile_icon(uuid,text),
 mefrion_private.profile_feed_page_base(text,text,text,timestamptz,uuid,integer,uuid[]),
 mefrion_private.profile_list_pets_base(),mefrion_private.profile_comments_base(uuid),mefrion_private.profile_public_pet_base(uuid),mefrion_private.retire_profile_icons()
 from public,anon,authenticated;
revoke all on function public.mefrion_account_profile(),public.mefrion_set_account_profile(text,text,boolean),
 public.mefrion_my_pet_icon(uuid),public.mefrion_update_pet_profile(uuid,text,text,text,jsonb,text[],text,boolean),
 public.mefrion_list_pets(),public.mefrion_feed_page(text,text,text,timestamptz,uuid,integer,uuid[]),public.mefrion_comments(uuid),public.mefrion_public_pet(uuid)
 from public,anon,authenticated;
grant execute on function public.mefrion_account_profile(),public.mefrion_set_account_profile(text,text,boolean),
 public.mefrion_my_pet_icon(uuid),public.mefrion_update_pet_profile(uuid,text,text,text,jsonb,text[],text,boolean),
 public.mefrion_list_pets(),public.mefrion_comments(uuid) to authenticated;
grant execute on function public.mefrion_feed_page(text,text,text,timestamptz,uuid,integer,uuid[]),public.mefrion_public_pet(uuid) to anon,authenticated;
notify pgrst,'reload schema';
commit;
