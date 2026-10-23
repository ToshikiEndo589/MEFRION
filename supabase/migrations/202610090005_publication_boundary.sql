-- Development only: public projections reference processed derivatives only.
-- No family originals, provider identities or internal approval records are exposed.
begin;
create table mefrion_private.public_profiles (
 pet_id uuid primary key references mefrion_private.pets(id), enabled boolean not null default false
);
create table mefrion_private.public_posts (
 id uuid primary key default gen_random_uuid(), pet_id uuid not null references mefrion_private.pets(id),
 actor_id uuid not null references auth.users(id), request_key uuid not null,
 body text not null default '' check(length(body)<=500), kind text not null check(kind in ('post','share')),
 state text not null default 'pending' check(state in ('pending','processing','published','stopped')),
 lease_until timestamptz, created_at timestamptz not null default now(), published_at timestamptz,
 unique(actor_id,request_key)
);
create table mefrion_private.public_media (
 id uuid primary key default gen_random_uuid(), post_id uuid not null references mefrion_private.public_posts(id),
 source_id uuid not null references mefrion_private.photos(id), consent_version integer not null,
 position integer not null check(position between 0 and 3),
 object_path text not null unique, unique(post_id,source_id),unique(post_id,position)
);
create table mefrion_private.social_blocks (
 actor_id uuid not null references auth.users(id), target_id uuid not null references auth.users(id),
 primary key(actor_id,target_id),check(actor_id<>target_id)
);
alter table mefrion_private.public_profiles enable row level security;
alter table mefrion_private.public_posts enable row level security;
alter table mefrion_private.public_media enable row level security;
alter table mefrion_private.social_blocks enable row level security;
revoke all on mefrion_private.public_profiles,mefrion_private.public_posts,mefrion_private.public_media,mefrion_private.social_blocks from public,anon,authenticated;
alter table mefrion_private.deletion_outbox add column bucket text not null default 'family-originals' check(bucket in ('family-originals','public-derived'));

create or replace function mefrion_private.post_allowed(p_post uuid,p_actor uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.public_posts s
 join mefrion_private.public_profiles profile on profile.pet_id=s.pet_id and profile.enabled
 join mefrion_private.pets pet on pet.id=s.pet_id
 where s.id=p_post and s.state='published'
 and not exists(select 1 from mefrion_private.social_blocks b where
  (b.actor_id=p_actor and b.target_id=pet.owner_id) or (b.actor_id=pet.owner_id and b.target_id=p_actor))
 and exists(select 1 from mefrion_private.public_media m where m.post_id=s.id)
 and not exists(select 1 from mefrion_private.public_media m
  left join mefrion_private.photos photo on photo.id=m.source_id
  left join mefrion_private.consents c on c.photo_id=photo.id and c.purpose=case when s.kind='post' then 'sns' else 'external_share' end
  where m.post_id=s.id and (photo.state is distinct from 'ready' or c.allowed is distinct from true or c.version is distinct from m.consent_version)))
$$;
revoke all on function mefrion_private.post_allowed(uuid,uuid) from public,anon,authenticated;

create or replace function mefrion_private.stop_publication(p_post uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 update mefrion_private.public_posts set state='stopped',lease_until=null where id=p_post;
 insert into mefrion_private.deletion_outbox(object_path,bucket)
 select object_path,'public-derived' from mefrion_private.public_media where post_id=p_post
 and not exists(select 1 from mefrion_private.deletion_outbox o where o.object_path=mefrion_private.public_media.object_path and o.bucket='public-derived' and o.state='pending');
end $$;
revoke all on function mefrion_private.stop_publication(uuid) from public,anon,authenticated;

create or replace function mefrion_private.invalidate_publication() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_post uuid;v_source uuid;v_purpose text;
begin
 if tg_table_name='consents' then v_source:=new.photo_id;v_purpose:=new.purpose;else v_source:=new.id;end if;
 for v_post in select distinct m.post_id from mefrion_private.public_media m join mefrion_private.public_posts s on s.id=m.post_id
 where m.source_id=v_source and (v_purpose is null or (s.kind='post' and v_purpose='sns') or (s.kind='share' and v_purpose='external_share')) loop
  perform mefrion_private.stop_publication(v_post);
 end loop;
 return new;
end $$;
-- Every consent version change invalidates the old derivative, including regrant.
create trigger mefrion_public_consent_changed after update on mefrion_private.consents for each row when(old.allowed is distinct from new.allowed or old.version is distinct from new.version) execute function mefrion_private.invalidate_publication();
create trigger mefrion_public_photo_deleted after update on mefrion_private.photos for each row when(new.state='deleted' and old.state<>'deleted') execute function mefrion_private.invalidate_publication();

create or replace function public.mefrion_set_public_profile(p_pet uuid,p_enabled boolean,p_explicit boolean default false) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_post uuid;
begin
 perform mefrion_private.require_registered();
 perform 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid() for update;
 if not found or p_enabled is null then raise exception 'owner_required' using errcode='42501';end if;
 if p_enabled and p_explicit is distinct from true then raise exception 'explicit_publication_required';end if;
 insert into mefrion_private.public_profiles values(p_pet,p_enabled) on conflict(pet_id) do update set enabled=excluded.enabled;
 if not p_enabled then
  for v_post in select id from mefrion_private.public_posts where pet_id=p_pet loop perform mefrion_private.stop_publication(v_post);end loop;
 end if;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'profile.public.'||p_enabled::text);
 return p_enabled;
end $$;

create or replace function public.mefrion_request_publication(p_pet uuid,p_photos uuid[],p_body text,p_kind text,p_request_key uuid,p_explicit boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_post mefrion_private.public_posts;v_photo uuid;v_version integer;v_index integer:=0;v_media uuid;v_purpose text;
begin
 perform mefrion_private.require_registered();
 if p_explicit is distinct from true then raise exception 'explicit_publication_required';end if;
 if p_request_key is null or p_body is null or length(p_body)>500 or p_kind not in ('post','share') or p_kind is null or p_photos is null or cardinality(p_photos) not between 1 and 4 or (p_kind='share' and cardinality(p_photos)<>2) or cardinality(p_photos)<>(select count(distinct id) from unnest(p_photos) id) then raise exception 'publication_invalid';end if;
 perform 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid() for update;
 if not found then raise exception 'owner_required' using errcode='42501';end if;
 if not exists(select 1 from mefrion_private.public_profiles where pet_id=p_pet and enabled) then raise exception 'profile_private';end if;
 select * into v_post from mefrion_private.public_posts where actor_id=auth.uid() and request_key=p_request_key;
 if found then
  if v_post.pet_id<>p_pet or v_post.body<>p_body or v_post.kind<>p_kind or (select array_agg(source_id order by position) from mefrion_private.public_media where post_id=v_post.id) is distinct from p_photos then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',v_post.id,'state',v_post.state);
 end if;
 v_purpose:=case when p_kind='post' then 'sns' else 'external_share' end;
 insert into mefrion_private.public_posts(pet_id,actor_id,request_key,body,kind) values(p_pet,auth.uid(),p_request_key,p_body,p_kind) returning * into v_post;
 foreach v_photo in array p_photos loop
  -- Lock consent/photo together with publication: a simultaneous withdrawal
  -- either precedes this snapshot or invalidates the committed job afterward.
  select c.version into v_version from mefrion_private.photos photo join mefrion_private.consents c on c.photo_id=photo.id
  where photo.id=v_photo and photo.pet_id=p_pet and photo.state='ready' and c.purpose=v_purpose and c.allowed for update of photo,c;
  if not found then raise exception 'provider_consent_required' using errcode='42501';end if;
  v_media:=gen_random_uuid();
  insert into mefrion_private.public_media(id,post_id,source_id,consent_version,position,object_path) values(v_media,v_post.id,v_photo,v_version,v_index,v_media::text||'.jpg');
  v_index:=v_index+1;
 end loop;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'publication.request');
 return jsonb_build_object('id',v_post.id,'state',v_post.state);
end $$;

create or replace function public.mefrion_public_feed(p_limit integer default 20) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item order by published_at desc,id),'[]'::jsonb) from (
 select s.id,s.published_at,jsonb_build_object('id',s.id,'pet_id',pet.id,'name',pet.name,'species',pet.species,'breed',pet.breed,'body',s.body,'kind',s.kind,'published_at',s.published_at,
 'media',(select jsonb_agg(m.id order by m.position) from mefrion_private.public_media m where m.post_id=s.id)) item
 from mefrion_private.public_posts s join mefrion_private.pets pet on pet.id=s.pet_id
 where mefrion_private.post_allowed(s.id,auth.uid()) order by s.published_at desc,s.id limit greatest(1,least(coalesce(p_limit,20),50))) visible
$$;

create or replace function public.mefrion_stop_publication(p_post uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 perform 1 from mefrion_private.public_posts where id=p_post and actor_id=auth.uid() for update;
 if not found then raise exception 'owner_required' using errcode='42501';end if;
 perform mefrion_private.stop_publication(p_post);return true;
end $$;

-- Worker and gateway are service-only. Originals never leave these RPCs.
create or replace function public.mefrion_publication_batch() returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_posts uuid[];
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 with picked as (select id from mefrion_private.public_posts where state='pending' or (state='processing' and lease_until<now()) order by created_at limit 10 for update skip locked), claimed as (update mefrion_private.public_posts set state='processing',lease_until=now()+interval '5 minutes' where id in(select id from picked) returning id) select array_agg(id) into v_posts from claimed;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'media',(select jsonb_agg(jsonb_build_object('id',m.id,'source_path',p.object_path,'path',m.object_path) order by m.position) from mefrion_private.public_media m join mefrion_private.photos p on p.id=m.source_id where m.post_id=s.id))),'[]'::jsonb) from mefrion_private.public_posts s where s.id=any(v_posts));
end $$;

create or replace function public.mefrion_publication_finish(p_post uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_post mefrion_private.public_posts;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 select * into v_post from mefrion_private.public_posts where id=p_post for update;
 if not found then return false;end if;
 if v_post.state='published' then return mefrion_private.post_allowed(p_post);end if;
 if v_post.state<>'processing' then perform mefrion_private.stop_publication(p_post);return false;end if;
 if not exists(select 1 from mefrion_private.public_profiles where pet_id=v_post.pet_id and enabled) or
 not exists(select 1 from mefrion_private.public_media where post_id=p_post) or
 exists(select 1 from mefrion_private.public_media m left join mefrion_private.photos photo on photo.id=m.source_id
 left join mefrion_private.consents c on c.photo_id=photo.id and c.purpose=case when v_post.kind='post' then 'sns' else 'external_share' end
 where m.post_id=p_post and (photo.state is distinct from 'ready' or c.allowed is distinct from true or c.version is distinct from m.consent_version or not exists(select 1 from storage.objects o where o.bucket_id='public-derived' and o.name=m.object_path))) then
 perform mefrion_private.stop_publication(p_post);return false;end if;
 update mefrion_private.public_posts set state='published',lease_until=null,published_at=now() where id=p_post;
 return true;
end $$;

create or replace function public.mefrion_public_image_path(p_media uuid,p_actor uuid default null) returns text
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'gateway_required' using errcode='42501';end if;
 return (select m.object_path from mefrion_private.public_media m where m.id=p_media and mefrion_private.post_allowed(m.post_id,p_actor));
end $$;
create or replace function public.mefrion_deletion_batch() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'path',object_path,'bucket',bucket)),'[]'::jsonb) from (select * from mefrion_private.deletion_outbox where state='pending' order by created_at limit 20) jobs);
end $$;
revoke execute on function public.mefrion_set_public_profile(uuid,boolean,boolean),public.mefrion_request_publication(uuid,uuid[],text,text,uuid,boolean),public.mefrion_stop_publication(uuid) from public,anon;
grant execute on function public.mefrion_set_public_profile(uuid,boolean,boolean),public.mefrion_request_publication(uuid,uuid[],text,text,uuid,boolean),public.mefrion_stop_publication(uuid) to authenticated;
revoke execute on function public.mefrion_public_feed(integer) from public;
grant execute on function public.mefrion_public_feed(integer) to anon,authenticated;
revoke execute on function public.mefrion_publication_batch(),public.mefrion_publication_finish(uuid),public.mefrion_public_image_path(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mefrion_publication_batch(),public.mefrion_publication_finish(uuid),public.mefrion_public_image_path(uuid,uuid) to service_role;
commit;
