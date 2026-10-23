begin;
create table mefrion_private.post_pet_tags(post_id uuid references mefrion_private.public_posts(id) on delete cascade,pet_id uuid references mefrion_private.pets(id),primary key(post_id,pet_id));
create table mefrion_private.post_tag_requests(post_id uuid primary key references mefrion_private.public_posts(id) on delete cascade,tags uuid[] not null);
alter table mefrion_private.post_pet_tags enable row level security;alter table mefrion_private.post_tag_requests enable row level security;
revoke all on mefrion_private.post_pet_tags,mefrion_private.post_tag_requests from public,anon,authenticated;
create function public.mefrion_request_tagged_publication(p_pet uuid,p_photos uuid[],p_tags uuid[],p_body text,p_request_key uuid,p_explicit boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare tags uuid[];v jsonb;old_tags uuid[];
begin
 perform mefrion_private.require_registered();
 if p_tags is null or cardinality(p_tags) not between 1 and 5 or not p_pet=any(p_tags) or cardinality(p_tags)<>(select count(distinct id) from unnest(p_tags) id) then raise exception 'tags_invalid';end if;
 select array_agg(id order by id) into tags from unnest(p_tags) id;
 perform 1 from mefrion_private.pets where id=any(tags) order by id for share;
 if (select count(*) from mefrion_private.pets p join mefrion_private.public_profiles f on f.pet_id=p.id and f.enabled where p.id=any(tags) and p.owner_id=auth.uid())<>cardinality(tags) then raise exception 'owned_public_tags_required' using errcode='42501';end if;
 v:=public.mefrion_request_publication(p_pet,p_photos,p_body,'post',p_request_key,p_explicit);
 select r.tags into old_tags from mefrion_private.post_tag_requests r where post_id=(v->>'id')::uuid;
 if found then if old_tags<>tags then raise exception 'idempotency_conflict';end if;
 else insert into mefrion_private.post_tag_requests values((v->>'id')::uuid,tags);insert into mefrion_private.post_pet_tags select (v->>'id')::uuid,id from unnest(tags) id;end if;
 return v;
end $$;
create function mefrion_private.invalidate_pet_tags() returns trigger language plpgsql security definer set search_path='' as $$
declare p uuid;
begin
 if old.enabled and not new.enabled then for p in select post_id from mefrion_private.post_pet_tags where pet_id=new.pet_id loop perform mefrion_private.stop_publication(p);end loop;end if;return new;
end $$;
create trigger mefrion_tag_profile_withdrawn after update of enabled on mefrion_private.public_profiles for each row execute function mefrion_private.invalidate_pet_tags();
revoke execute on function mefrion_private.invalidate_pet_tags() from public,anon,authenticated;
revoke execute on function public.mefrion_request_tagged_publication(uuid,uuid[],uuid[],text,uuid,boolean) from public,anon;grant execute on function public.mefrion_request_tagged_publication(uuid,uuid[],uuid[],text,uuid,boolean) to authenticated;

create or replace function mefrion_private.post_allowed(p_post uuid,p_actor uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.public_posts s
 join mefrion_private.public_profiles profile on profile.pet_id=s.pet_id and profile.enabled
 join mefrion_private.pets pet on pet.id=s.pet_id
 where s.id=p_post and s.state='published' and not exists(select 1 from mefrion_private.post_pet_tags t left join mefrion_private.public_profiles f on f.pet_id=t.pet_id where t.post_id=s.id and f.enabled is distinct from true) and mefrion_private.managed_public_ready(s.pet_id)
 and not exists(select 1 from mefrion_private.account_retirements where user_id=pet.owner_id)
 and not exists(select 1 from mefrion_private.public_account_states state where state.user_id=pet.owner_id and state.suspended)
 and not exists(select 1 from mefrion_private.social_blocks b where
  (b.actor_id=p_actor and b.target_id=pet.owner_id) or (b.actor_id=pet.owner_id and b.target_id=p_actor))
 and exists(select 1 from mefrion_private.public_media m where m.post_id=s.id)
 and not exists(select 1 from mefrion_private.public_media m
  left join mefrion_private.photos photo on photo.id=m.source_id
  left join mefrion_private.consents c on c.photo_id=photo.id and c.purpose=case when s.kind='post' then 'sns' else 'external_share' end
  where m.post_id=s.id and (photo.state is distinct from 'ready' or c.allowed is distinct from true or c.version is distinct from m.consent_version)))
$$;
create or replace function mefrion_private.social_feed(p_limit integer,p_mode text,p_query text) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item order by published_at desc,id),'[]'::jsonb) from (
 select s.id,s.published_at,jsonb_build_object('id',s.id,'pet_id',pet.id,'name',pet.name,'species',pet.species,'breed',case when 'breed'=any(pet.public_fields) then pet.breed else '' end,'body',s.body,'tags',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name) order by p.id),'[]') from mefrion_private.post_pet_tags t join mefrion_private.pets p on p.id=t.pet_id join mefrion_private.public_profiles f on f.pet_id=p.id and f.enabled where t.post_id=s.id),'kind',s.kind,'published_at',s.published_at,
 'media',(select jsonb_agg(m.id order by m.position) from mefrion_private.public_media m where m.post_id=s.id),
 'likes',(select count(*) from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and mefrion_private.social_actor_visible(auth.uid(),r.actor_id)),
 'comments',(select count(*) from mefrion_private.social_comments c where c.post_id=s.id and c.state='active' and mefrion_private.social_actor_visible(auth.uid(),c.actor_id) and (c.parent_id is null or exists(select 1 from mefrion_private.social_comments parent where parent.id=c.parent_id and parent.state in ('active','deleted') and mefrion_private.social_actor_visible(auth.uid(),parent.actor_id)))),
 'liked',exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and r.actor_id=auth.uid()),
 'saved',exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid()),
 'following',exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())) item
 from mefrion_private.public_posts s join mefrion_private.pets pet on pet.id=s.pet_id
 where mefrion_private.post_allowed(s.id,auth.uid())
 and (p_mode='all' or (p_mode='saved' and exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid())) or (p_mode='following' and exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())))
 and (p_query='' or position(pg_catalog.normalize(lower(p_query),'NFKC') in pg_catalog.normalize(lower(pet.name||' '||case when 'breed'=any(pet.public_fields) then pet.breed else '' end),'NFKC'))>0)
 order by s.published_at desc,s.id limit greatest(1,least(coalesce(p_limit,20),50))) visible
$$;
create or replace function mefrion_private.social_page(p_limit integer,p_mode text,p_query text,p_before timestamptz,p_before_id uuid,p_species text) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item order by published_at desc,id),'[]'::jsonb) from (
 select s.id,s.published_at,jsonb_build_object('id',s.id,'pet_id',pet.id,'name',pet.name,'species',pet.species,'breed',case when 'breed'=any(pet.public_fields) then pet.breed else '' end,'body',s.body,'tags',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name) order by p.id),'[]') from mefrion_private.post_pet_tags t join mefrion_private.pets p on p.id=t.pet_id join mefrion_private.public_profiles f on f.pet_id=p.id and f.enabled where t.post_id=s.id),'kind',s.kind,'published_at',s.published_at,
 'media',(select jsonb_agg(m.id order by m.position) from mefrion_private.public_media m where m.post_id=s.id),
 'likes',(select count(*) from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and mefrion_private.social_actor_visible(auth.uid(),r.actor_id)),
 'comments',(select count(*) from mefrion_private.social_comments c where c.post_id=s.id and c.state='active' and mefrion_private.social_actor_visible(auth.uid(),c.actor_id) and (c.parent_id is null or exists(select 1 from mefrion_private.social_comments parent where parent.id=c.parent_id and parent.state in ('active','deleted') and mefrion_private.social_actor_visible(auth.uid(),parent.actor_id)))),
 'liked',exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and r.actor_id=auth.uid()),
 'saved',exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid()),
 'following',exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())) item
 from mefrion_private.public_posts s join mefrion_private.pets pet on pet.id=s.pet_id
 where mefrion_private.post_allowed(s.id,auth.uid())
 and (p_before is null or (s.published_at,s.id)<(p_before,p_before_id))
 and (p_species='all' or pet.species=p_species)
 and (p_mode='all' or (p_mode='saved' and exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid())) or (p_mode='following' and exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())))
 and (p_query='' or position(pg_catalog.normalize(lower(p_query),'NFKC') in pg_catalog.normalize(lower(pet.name||' '||case when 'breed'=any(pet.public_fields) then pet.breed else '' end),'NFKC'))>0)
 order by s.published_at desc,s.id limit greatest(1,least(coalesce(p_limit,20),50))) visible
$$;


commit;
