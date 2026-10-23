-- MEFRION-development only. No seed imagery or human production data.
-- Private originals are never put in a public bucket or signed URL.
begin;
create schema if not exists mefrion_private;
revoke all on schema mefrion_private from public, anon, authenticated;
create table if not exists mefrion_private.pets (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
 name text not null check(length(btrim(name)) between 1 and 40), species text not null check(species in ('dog','cat')),
 breed text not null default '', introduction text not null default '', created_at timestamptz not null default now()
);
create table if not exists mefrion_private.members (
 pet_id uuid references mefrion_private.pets(id) on delete cascade, user_id uuid references auth.users(id),
 active boolean not null default true, frequency text not null default 'batched' check(frequency in ('off','immediate','batched')),
 primary key(pet_id,user_id)
);
create table if not exists mefrion_private.invites (
 id uuid primary key default gen_random_uuid(), pet_id uuid not null references mefrion_private.pets(id) on delete cascade,
 token_hash text not null unique, expires_at timestamptz not null default now()+interval '7 days', state text not null default 'pending' check(state in ('pending','accepted','revoked'))
);
create table if not exists mefrion_private.photos (
 id uuid primary key default gen_random_uuid(), pet_id uuid not null references mefrion_private.pets(id) on delete cascade,
 provider_id uuid not null references auth.users(id), object_path text not null unique,
 request_key uuid not null, captured text, title text not null default '' check(length(title)<=200),
 state text not null default 'pending' check(state in ('pending','ready','deleted')), created_at timestamptz not null default now(),
 unique(pet_id,provider_id,request_key)
);
create table if not exists mefrion_private.consents (
 photo_id uuid references mefrion_private.photos(id) on delete cascade,
 purpose text check(purpose in ('sns','twins','external_share')), allowed boolean not null default false,
 version integer not null default 1, updated_at timestamptz not null default now(), primary key(photo_id,purpose)
);
create table if not exists mefrion_private.cards (
 id uuid primary key default gen_random_uuid(), pet_id uuid references mefrion_private.pets(id) on delete cascade,
 first_id uuid not null references mefrion_private.photos(id) on delete cascade,
 second_id uuid not null references mefrion_private.photos(id) on delete cascade,
 layout jsonb not null default '{}', check(first_id<>second_id)
);
create table if not exists mefrion_private.deletion_outbox (
 id uuid primary key default gen_random_uuid(), object_path text not null, state text not null default 'pending', created_at timestamptz not null default now()
);
create table if not exists mefrion_private.audit (
 id bigint generated always as identity primary key, actor_id uuid, pet_id uuid, action text not null, created_at timestamptz not null default now()
);
-- Deny every direct application-table operation. Authenticated RPCs enforce scope.
alter table mefrion_private.pets enable row level security;
alter table mefrion_private.members enable row level security;
alter table mefrion_private.invites enable row level security;
alter table mefrion_private.photos enable row level security;
alter table mefrion_private.consents enable row level security;
alter table mefrion_private.cards enable row level security;
alter table mefrion_private.deletion_outbox enable row level security;
alter table mefrion_private.audit enable row level security;
revoke all on all tables in schema mefrion_private from public,anon,authenticated;
revoke all on all sequences in schema mefrion_private from public,anon,authenticated;
alter default privileges in schema mefrion_private revoke all on tables from public,anon,authenticated;

create or replace function public.mefrion_family_access(p_pet uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from mefrion_private.pets p where p.id=p_pet and
 (p.owner_id=auth.uid() or exists(select 1 from mefrion_private.members m where m.pet_id=p.id and m.user_id=auth.uid() and m.active)))
$$;
create or replace function public.mefrion_create_pet(p_name text,p_species text,p_breed text default '',p_introduction text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_pet mefrion_private.pets; v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text,0));
 if (select count(*) from mefrion_private.pets where owner_id=v_user)>=5 then raise exception 'pet_limit'; end if;
 if length(p_breed)>100 or length(p_introduction)>500 then raise exception 'profile_limit';end if;
 insert into mefrion_private.pets(owner_id,name,species,breed,introduction) values(v_user,btrim(p_name),p_species,p_breed,p_introduction) returning * into v_pet;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(v_user,v_pet.id,'pet.create');
 return jsonb_build_object('id',v_pet.id,'name',v_pet.name,'species',v_pet.species,'breed',v_pet.breed,'introduction',v_pet.introduction);
end $$;
create or replace function public.mefrion_list_pets() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'species',p.species,'breed',p.breed,'introduction',p.introduction,'role',case when p.owner_id=auth.uid() then 'owner' else 'family' end) order by p.created_at),'[]'::jsonb)
 from mefrion_private.pets p where public.mefrion_family_access(p.id)
$$;
create or replace function public.mefrion_invite(p_pet uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_token text;v_id uuid;v_expires timestamptz;
begin
 perform 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid() for update;
 if not found then raise exception 'owner_required' using errcode='42501';end if;
 if (select count(*) from mefrion_private.invites where pet_id=p_pet and state='pending' and expires_at>now())>=5 then raise exception 'invitation_limit';end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into mefrion_private.invites(pet_id,token_hash) values(p_pet,encode(extensions.digest(v_token,'sha256'),'hex')) returning id,expires_at into v_id,v_expires;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'invite.create');
 return jsonb_build_object('id',v_id,'token',v_token,'expires_at',v_expires);
end $$;
create or replace function public.mefrion_accept_invite(p_token text,p_confirm_scope boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_inv mefrion_private.invites;v_owner uuid;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='42501';end if;
 if p_confirm_scope is distinct from true then raise exception 'scope_confirmation_required';end if;
 if p_token is null or length(p_token)<>64 then raise exception 'invalid_invitation';end if;
 select * into v_inv from mefrion_private.invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not found or v_inv.state<>'pending' or v_inv.expires_at<=now() then raise exception 'invalid_invitation';end if;
 select owner_id into v_owner from mefrion_private.pets where id=v_inv.pet_id for update;
 if v_owner=auth.uid() then raise exception 'already_owner';end if;
 if exists(select 1 from mefrion_private.members where pet_id=v_inv.pet_id and user_id=auth.uid() and active) then raise exception 'already_member';end if;
 update mefrion_private.invites set state='accepted' where id=v_inv.id;
 insert into mefrion_private.members(pet_id,user_id) values(v_inv.pet_id,auth.uid()) on conflict(pet_id,user_id) do update set active=true;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v_inv.pet_id,'invite.accept');
 return jsonb_build_object('pet_id',v_inv.pet_id,'role','family','external_publish',false);
end $$;
create or replace function public.mefrion_revoke_invite(p_invite uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 update mefrion_private.invites i set state='revoked' where i.id=p_invite and exists(select 1 from mefrion_private.pets p where p.id=i.pet_id and p.owner_id=auth.uid());
 if not found then raise exception 'owner_required' using errcode='42501';end if;
 return true;
end $$;
create or replace function public.mefrion_remove_member(p_pet uuid,p_user uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_owner uuid;
begin
 select owner_id into v_owner from mefrion_private.pets where id=p_pet for update;
 if not public.mefrion_family_access(p_pet) or (auth.uid()<>v_owner and auth.uid()<>p_user) then raise exception 'permission_required' using errcode='42501';end if;
 if p_user=v_owner then raise exception 'owner_cannot_leave';end if;
 update mefrion_private.members set active=false where pet_id=p_pet and user_id=p_user;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'member.remove');
 return true;
end $$;
create or replace function public.mefrion_begin_photo(p_pet uuid,p_request_key uuid,p_captured text default null,p_title text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_photo mefrion_private.photos;v_id uuid:=gen_random_uuid();
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 if p_request_key is null then raise exception 'request_key_required';end if;
 if p_captured is not null then
  if p_captured ~ '^[0-9]{4}$' then perform make_date(p_captured::integer,1,1);
  elsif p_captured ~ '^[0-9]{4}-[0-9]{2}$' then perform (p_captured||'-01')::date;
  elsif p_captured ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then perform p_captured::date;
  else raise exception 'invalid_date';end if;
 end if;
 perform 1 from mefrion_private.pets where id=p_pet for update;
 select * into v_photo from mefrion_private.photos where pet_id=p_pet and provider_id=auth.uid() and request_key=p_request_key;
 if found then
  if v_photo.state='deleted' or v_photo.captured is distinct from p_captured or v_photo.title is distinct from p_title then raise exception 'idempotency_conflict';end if;
 else
  insert into mefrion_private.photos(id,pet_id,provider_id,object_path,request_key,captured,title) values(v_id,p_pet,auth.uid(),p_pet::text||'/'||v_id::text||'.jpg',p_request_key,p_captured,p_title) returning * into v_photo;
 end if;
 return jsonb_build_object('id',v_photo.id,'path',v_photo.object_path,'state',v_photo.state);
end $$;
create or replace function public.mefrion_upload_allowed(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.photos p where p.object_path=p_path and p.provider_id=auth.uid() and p.state='pending' and public.mefrion_family_access(p.pet_id))
$$;
create or replace function public.mefrion_download_allowed(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.photos p where p.object_path=p_path and p.state='ready' and public.mefrion_family_access(p.pet_id))
$$;
create or replace function public.mefrion_finish_photo(p_photo uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_photo mefrion_private.photos;
begin
 select * into v_photo from mefrion_private.photos where id=p_photo and provider_id=auth.uid() for update;
 if not found or v_photo.state='deleted' or not public.mefrion_family_access(v_photo.pet_id) then raise exception 'permission_required' using errcode='42501';end if;
 if not exists(select 1 from storage.objects where bucket_id='family-originals' and name=v_photo.object_path) then raise exception 'upload_incomplete';end if;
 update mefrion_private.photos set state='ready' where id=p_photo;
 return true;
end $$;
create or replace function public.mefrion_album(p_pet uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'path',object_path,'captured',captured,'title',title,'mine',provider_id=auth.uid()) order by captured nulls last),'[]'::jsonb) from mefrion_private.photos where pet_id=p_pet and state='ready');
end $$;
create or replace function public.mefrion_photo(p_photo uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_photo mefrion_private.photos;
begin
 select * into v_photo from mefrion_private.photos where id=p_photo and state='ready';
 if not found or not public.mefrion_family_access(v_photo.pet_id) then raise exception 'permission_required' using errcode='42501';end if;
 return jsonb_build_object('id',v_photo.id,'path',v_photo.object_path,'captured',v_photo.captured,'title',v_photo.title,'mine',v_photo.provider_id=auth.uid());
end $$;
create or replace function public.mefrion_consent(p_photo uuid,p_purpose text,p_allowed boolean) returns integer
language plpgsql security definer set search_path='' as $$
declare v_photo mefrion_private.photos;v_version integer;
begin
 select * into v_photo from mefrion_private.photos where id=p_photo and provider_id=auth.uid() and state='ready' for update;
 if not found or p_allowed is null or (p_allowed and not public.mefrion_family_access(v_photo.pet_id)) then raise exception 'provider_permission_required' using errcode='42501';end if;
 insert into mefrion_private.consents(photo_id,purpose,allowed) values(p_photo,p_purpose,p_allowed) on conflict(photo_id,purpose) do update set allowed=excluded.allowed,version=mefrion_private.consents.version+1,updated_at=now() returning version into v_version;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v_photo.pet_id,'consent.'||p_purpose||'.'||p_allowed::text);
 return v_version;
end $$;
create or replace function public.mefrion_delete_photo(p_photo uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_photo mefrion_private.photos;
begin
 select * into v_photo from mefrion_private.photos where id=p_photo for update;
 if not found or not public.mefrion_family_access(v_photo.pet_id) or not (v_photo.provider_id=auth.uid() or exists(select 1 from mefrion_private.pets where id=v_photo.pet_id and owner_id=auth.uid())) then raise exception 'permission_required' using errcode='42501';end if;
 if v_photo.state='deleted' then return true;end if;
 update mefrion_private.photos set state='deleted' where id=p_photo;
 update mefrion_private.consents set allowed=false,version=version+1 where photo_id=p_photo;
 delete from mefrion_private.cards where first_id=p_photo or second_id=p_photo;
 insert into mefrion_private.deletion_outbox(object_path) values(v_photo.object_path);
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v_photo.pet_id,'photo.delete');
 return true;
end $$;
-- Explicit RPC allowlist; the schema remains inaccessible through direct REST.
revoke execute on function public.mefrion_family_access(uuid), public.mefrion_create_pet(text,text,text,text), public.mefrion_list_pets(), public.mefrion_invite(uuid), public.mefrion_accept_invite(text,boolean), public.mefrion_revoke_invite(uuid), public.mefrion_remove_member(uuid,uuid), public.mefrion_begin_photo(uuid,uuid,text,text), public.mefrion_upload_allowed(text), public.mefrion_download_allowed(text), public.mefrion_finish_photo(uuid), public.mefrion_album(uuid), public.mefrion_consent(uuid,text,boolean), public.mefrion_delete_photo(uuid), public.mefrion_photo(uuid) from public,anon;
grant execute on function public.mefrion_family_access(uuid), public.mefrion_create_pet(text,text,text,text), public.mefrion_list_pets(), public.mefrion_invite(uuid), public.mefrion_accept_invite(text,boolean), public.mefrion_revoke_invite(uuid), public.mefrion_remove_member(uuid,uuid), public.mefrion_begin_photo(uuid,uuid,text,text), public.mefrion_upload_allowed(text), public.mefrion_download_allowed(text), public.mefrion_finish_photo(uuid), public.mefrion_album(uuid), public.mefrion_consent(uuid,text,boolean), public.mefrion_delete_photo(uuid), public.mefrion_photo(uuid) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('family-originals','family-originals',false,20971520,array['image/jpeg']),('public-derived','public-derived',false,20971520,array['image/jpeg','image/png']) on conflict(id) do nothing;
-- Original reads go ONLY through the private-image gateway.
-- No authenticated SELECT means both direct downloads and signed URLs are denied.
-- No UPDATE, DELETE, anonymous download or operator shortcut.
create policy mefrion_original_insert on storage.objects for insert to authenticated with check(bucket_id='family-originals' and public.mefrion_upload_allowed(name));
commit;
