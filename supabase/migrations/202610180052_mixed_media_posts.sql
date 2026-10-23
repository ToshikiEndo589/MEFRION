-- Photos and videos share the existing family consent/publication boundary.
-- Videos have a separate poster so existing image gateways and feed prefetching
-- continue to work without downloading a movie for every feed cell.
begin;
alter table mefrion_private.photos add column if not exists media_kind text not null default 'image' check (media_kind in ('image','video'));
alter table mefrion_private.photos add column if not exists duration_seconds numeric check (duration_seconds>0 and duration_seconds<=300);
alter table mefrion_private.photos add column if not exists preview_path text;
alter table mefrion_private.photos add constraint mefrion_video_metadata check
  ((media_kind='image' and duration_seconds is null and preview_path is null) or
   (media_kind='video' and duration_seconds is not null and preview_path is not null));
alter table mefrion_private.public_media drop constraint if exists public_media_position_check;
alter table mefrion_private.public_media add constraint public_media_position_check check(position between 0 and 9);
update storage.buckets set file_size_limit=52428800,allowed_mime_types=array['image/jpeg','video/mp4'] where id='family-originals';
update storage.buckets set file_size_limit=52428800,allowed_mime_types=array['image/jpeg','image/png','video/mp4'] where id='public-derived';
create function mefrion_private.queue_video_poster() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if right(new.object_path,4)='.mp4' then
   insert into mefrion_private.deletion_outbox(object_path,bucket)
   select left(new.object_path,length(new.object_path)-4)||case when new.bucket='family-originals' then '-preview.jpg' else '.jpg' end,new.bucket
   where not exists(select 1 from mefrion_private.deletion_outbox d where d.bucket=new.bucket and d.object_path=left(new.object_path,length(new.object_path)-4)||case when new.bucket='family-originals' then '-preview.jpg' else '.jpg' end and d.state='pending');
 end if;
 return new;
end $$;
create trigger mefrion_video_poster_cleanup after insert on mefrion_private.deletion_outbox for each row execute function mefrion_private.queue_video_poster();
revoke all on function mefrion_private.queue_video_poster() from public,anon,authenticated;

create or replace function public.mefrion_begin_video(p_pet uuid,p_request_key uuid,p_duration numeric)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item mefrion_private.photos;new_id uuid:=gen_random_uuid();
begin
 perform mefrion_private.require_registered();
 if p_request_key is null or p_duration is null or p_duration<=0 or p_duration>300 or not public.mefrion_family_access(p_pet) then raise exception 'video_invalid' using errcode='42501';end if;
 perform 1 from mefrion_private.pets where id=p_pet for update;
 select * into item from mefrion_private.photos where pet_id=p_pet and provider_id=auth.uid() and request_key=p_request_key;
 if found then
   if item.state='deleted' or item.media_kind<>'video' or item.duration_seconds<>p_duration then raise exception 'idempotency_conflict';end if;
 else
   insert into mefrion_private.photos(id,pet_id,provider_id,request_key,object_path,preview_path,media_kind,duration_seconds,title)
   values(new_id,p_pet,auth.uid(),p_request_key,p_pet::text||'/'||new_id::text||'.mp4',p_pet::text||'/'||new_id::text||'-preview.jpg','video',p_duration,'') returning * into item;
 end if;
 return jsonb_build_object('id',item.id,'path',item.object_path,'preview_path',item.preview_path,'state',item.state);
end $$;
revoke all on function public.mefrion_begin_video(uuid,uuid,numeric) from public,anon;
grant execute on function public.mefrion_begin_video(uuid,uuid,numeric) to authenticated;

create or replace function public.mefrion_upload_allowed(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.photos p where (p.object_path=p_path or p.preview_path=p_path) and p.state='pending' and
   ((p.provider_id=auth.uid() and public.mefrion_family_access(p.pet_id)) or
    (mefrion_private.seed_access('edit') and mefrion_private.managed_family_access(p.pet_id))))
$$;

create or replace function public.mefrion_finish_video(p_photo uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare item mefrion_private.photos;video_size bigint;
begin
 perform mefrion_private.require_registered();
 select * into item from mefrion_private.photos where id=p_photo and provider_id=auth.uid() and media_kind='video' for update;
 if not found or item.state='deleted' or not public.mefrion_family_access(item.pet_id) then raise exception 'permission_required' using errcode='42501';end if;
 if item.state='ready' then return true;end if;
 select (metadata->>'size')::bigint into video_size from storage.objects where bucket_id='family-originals' and name=item.object_path;
 if video_size is null or video_size<=0 or video_size>52428800 or
    not exists(select 1 from storage.objects where bucket_id='family-originals' and name=item.preview_path) then raise exception 'upload_incomplete';end if;
 update mefrion_private.photos set state='ready' where id=p_photo;
 return true;
end $$;
revoke all on function public.mefrion_finish_video(uuid) from public,anon;
grant execute on function public.mefrion_finish_video(uuid) to authenticated;

create or replace function public.mefrion_album(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'path',object_path,'captured',captured,'created_at',created_at,'title',title,'mine',provider_id=auth.uid(),'event_kind',event_kind,'note',note,'provider_name',mefrion_private.family_display_name(p_pet,provider_id),'media_kind',media_kind,'duration_seconds',duration_seconds) order by captured desc nulls last,created_at desc,id),'[]') from mefrion_private.photos where pet_id=p_pet and state='ready');
end $$;
create or replace function public.mefrion_photo(p_photo uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare item mefrion_private.photos;
begin
 select * into item from mefrion_private.photos where id=p_photo and state='ready';
 if not found or not public.mefrion_family_access(item.pet_id) then raise exception 'permission_required' using errcode='42501';end if;
 return jsonb_build_object('id',item.id,'path',item.object_path,'preview_path',item.preview_path,'media_kind',item.media_kind,'duration_seconds',item.duration_seconds,'captured',item.captured,'title',item.title,'mine',item.provider_id=auth.uid());
end $$;

create or replace function public.mefrion_request_publication(p_pet uuid,p_photos uuid[],p_body text,p_kind text,p_request_key uuid,p_explicit boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare item mefrion_private.public_posts;photo_id uuid;version integer;v_index integer:=0;media_id uuid;purpose text;kind text;
begin
 perform mefrion_private.require_registered();
 if p_explicit is distinct from true then raise exception 'explicit_publication_required';end if;
 if p_request_key is null or p_body is null or length(p_body)>500 or p_kind not in ('post','share') or p_photos is null or cardinality(p_photos) not between 1 and 10 or (p_kind='share' and cardinality(p_photos)<>2) or cardinality(p_photos)<>(select count(distinct id) from unnest(p_photos) id) then raise exception 'publication_invalid';end if;
 perform 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid() for update;
 if not found then raise exception 'owner_required' using errcode='42501';end if;
 if not exists(select 1 from mefrion_private.public_profiles where pet_id=p_pet and enabled) then raise exception 'profile_private';end if;
 select * into item from mefrion_private.public_posts where actor_id=auth.uid() and request_key=p_request_key;
 if found then
  if item.pet_id<>p_pet or item.body<>p_body or item.kind<>p_kind or (select array_agg(source_id order by position) from mefrion_private.public_media where post_id=item.id) is distinct from p_photos then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',item.id,'state',item.state);
 end if;
 purpose:=case when p_kind='post' then 'sns' else 'external_share' end;
 insert into mefrion_private.public_posts(pet_id,actor_id,request_key,body,kind) values(p_pet,auth.uid(),p_request_key,p_body,p_kind) returning * into item;
 foreach photo_id in array p_photos loop
  select c.version,p.media_kind into version,kind from mefrion_private.photos p join mefrion_private.consents c on c.photo_id=p.id
  where p.id=photo_id and p.pet_id=p_pet and p.state='ready' and c.purpose=purpose and c.allowed for update of p,c;
  if not found or (p_kind='share' and kind='video') then raise exception 'provider_consent_required' using errcode='42501';end if;
  media_id:=gen_random_uuid();
  insert into mefrion_private.public_media(id,post_id,source_id,consent_version,position,object_path)
  values(media_id,item.id,photo_id,version,v_index,media_id::text||case when kind='video' then '.mp4' else '.jpg' end);
  v_index:=v_index+1;
 end loop;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'publication.request');
 return jsonb_build_object('id',item.id,'state',item.state);
end $$;

create or replace function public.mefrion_publication_batch() returns jsonb language plpgsql security definer set search_path='' as $$
declare selected uuid[];
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 with picked as (select id from mefrion_private.public_posts where state='pending' or (state='processing' and lease_until<now()) order by created_at limit 10 for update skip locked),
 claimed as (update mefrion_private.public_posts set state='processing',lease_until=now()+interval '5 minutes' where id in(select id from picked) returning id)
 select array_agg(id) into selected from claimed;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'media',(select jsonb_agg(jsonb_build_object('id',m.id,'source_path',p.object_path,'path',m.object_path,'kind',p.media_kind,'duration',p.duration_seconds) order by m.position) from mefrion_private.public_media m join mefrion_private.photos p on p.id=m.source_id where m.post_id=s.id))),'[]'::jsonb) from mefrion_private.public_posts s where s.id=any(selected));
end $$;

-- The image gateway returns the poster for a video; the video gateway serves
-- the .mp4 path after the same visibility check.
create or replace function public.mefrion_public_image_path(p_media uuid,p_actor uuid default null) returns text language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'gateway_required' using errcode='42501';end if;
 return coalesce((select case when right(m.object_path,4)='.mp4' then left(m.object_path,length(m.object_path)-4)||'.jpg' else m.object_path end
   from mefrion_private.public_media m where m.id=p_media and mefrion_private.post_allowed(m.post_id,p_actor)),
   (select object_path from mefrion_private.twins_candidates where id=p_media and mefrion_private.twins_visible(id,p_actor)),
   (select m.object_path from mefrion_private.twins_share_media m join mefrion_private.twins_shares s on s.id=m.share_id and s.state='published' where m.id=p_media and mefrion_private.twins_share_base(s.id,p_actor) and (m.position=0 or mefrion_private.twins_share_other(s.id,p_actor))));
end $$;
create function public.mefrion_public_video_path(p_media uuid,p_actor uuid default null) returns text language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'gateway_required' using errcode='42501';end if;
 return (select m.object_path from mefrion_private.public_media m where m.id=p_media and right(m.object_path,4)='.mp4' and mefrion_private.post_allowed(m.post_id,p_actor));
end $$;
revoke all on function public.mefrion_public_video_path(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mefrion_public_video_path(uuid,uuid) to service_role;

create or replace function mefrion_private.social_page(p_limit integer,p_mode text,p_query text,p_before timestamptz,p_before_id uuid,p_species text) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item order by published_at desc,id),'[]'::jsonb) from (
 select s.id,s.published_at,jsonb_build_object('id',s.id,'pet_id',pet.id,'name',pet.name,'species',pet.species,
 'breed',case when s.content_origin='managed_seed' and s.breed_label is not null then s.breed_label when 'breed'=any(pet.public_fields) then pet.breed else '' end,
 'body',s.body,'tags',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name) order by p.id),'[]') from mefrion_private.post_pet_tags t join mefrion_private.pets p on p.id=t.pet_id join mefrion_private.public_profiles f on f.pet_id=p.id and f.enabled where t.post_id=s.id),
 'kind',s.kind,'published_at',s.published_at,
 'media',(select jsonb_agg(m.id order by m.position) from mefrion_private.public_media m where m.post_id=s.id),
 'video_media',(select coalesce(jsonb_agg(m.id order by m.position),'[]'::jsonb) from mefrion_private.public_media m join mefrion_private.photos photo on photo.id=m.source_id where m.post_id=s.id and photo.media_kind='video'),
 'likes',(select count(*) from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and mefrion_private.social_actor_visible(auth.uid(),r.actor_id)),
 'comments',(select count(*) from mefrion_private.social_comments c where c.post_id=s.id and c.state='active' and mefrion_private.social_actor_visible(auth.uid(),c.actor_id) and (c.parent_id is null or exists(select 1 from mefrion_private.social_comments parent where parent.id=c.parent_id and parent.state in ('active','deleted') and mefrion_private.social_actor_visible(auth.uid(),parent.actor_id)))),
 'liked',exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and r.actor_id=auth.uid()),
 'saved',exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid()),
 'following',exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())) item
 from mefrion_private.public_posts s join mefrion_private.pets pet on pet.id=s.pet_id
 where s.kind='post' and mefrion_private.post_allowed(s.id,auth.uid())
 and (p_before is null or (s.published_at,s.id)<(p_before,p_before_id))
 and (p_species='all' or pet.species=p_species)
 and (p_mode='all' or (p_mode='liked' and exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and r.actor_id=auth.uid())) or (p_mode='saved' and exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid())) or (p_mode='following' and exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())))
 and (p_query='' or position(pg_catalog.normalize(lower(p_query),'NFKC') in pg_catalog.normalize(lower(pet.name||' '||case when s.content_origin='managed_seed' and s.breed_label is not null then s.breed_label when 'breed'=any(pet.public_fields) then pet.breed else '' end),'NFKC'))>0)
 order by s.published_at desc,s.id limit greatest(1,least(coalesce(p_limit,20),50))) visible
$$;

create or replace function public.mefrion_my_publications(p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return coalesce((select jsonb_agg(jsonb_build_object(
 'id',s.id,'pet_id',s.pet_id,'pet_name',pet.name,'body',s.body,'state',s.state,'created_at',s.created_at,
 'preview_photo',(select photo.id from mefrion_private.public_media m join mefrion_private.photos photo on photo.id=m.source_id and photo.state='ready' where m.post_id=s.id order by m.position limit 1),
 'media',case when s.state='published' and mefrion_private.post_allowed(s.id,auth.uid()) then
   (select coalesce(jsonb_agg(m.id order by m.position),'[]'::jsonb) from mefrion_private.public_media m where m.post_id=s.id) else '[]'::jsonb end,
 'video_media',(select coalesce(jsonb_agg(m.id order by m.position),'[]'::jsonb) from mefrion_private.public_media m join mefrion_private.photos p on p.id=m.source_id where m.post_id=s.id and p.media_kind='video')
 ) order by s.created_at desc,s.id desc)
 from (select * from mefrion_private.public_posts where actor_id=auth.uid() and kind='post' and state<>'stopped' order by created_at desc,id desc limit least(greatest(coalesce(p_limit,50),1),100)) s
 join mefrion_private.pets pet on pet.id=s.pet_id and pet.owner_id=auth.uid()),'[]'::jsonb);
end $$;
commit;
