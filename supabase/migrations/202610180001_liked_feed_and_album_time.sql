-- Liked feed obeys the same post visibility and blocking policy as other feeds.
-- Album timestamps are only returned after family access is verified.
begin;
create or replace function mefrion_private.social_page(p_limit integer,p_mode text,p_query text,p_before timestamptz,p_before_id uuid,p_species text) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item order by published_at desc,id),'[]'::jsonb) from (
 select s.id,s.published_at,jsonb_build_object('id',s.id,'pet_id',pet.id,'name',pet.name,'species',pet.species,
 'breed',case when s.content_origin='managed_seed' and s.breed_label is not null then s.breed_label when 'breed'=any(pet.public_fields) then pet.breed else '' end,
 'body',s.body,'tags',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name) order by p.id),'[]') from mefrion_private.post_pet_tags t join mefrion_private.pets p on p.id=t.pet_id join mefrion_private.public_profiles f on f.pet_id=p.id and f.enabled where t.post_id=s.id),
 'kind',s.kind,'published_at',s.published_at,
 'media',(select jsonb_agg(m.id order by m.position) from mefrion_private.public_media m where m.post_id=s.id),
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
create or replace function public.mefrion_feed_page(p_mode text default 'all',p_query text default '',p_species text default 'all',p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 12,p_known_ids uuid[] default '{}') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;last_item jsonb;ordered jsonb;known jsonb;ratio numeric;user_count integer;
begin
 if p_mode is null or p_mode not in ('all','following','saved','liked') or p_species is null or p_species not in ('all','dog','cat') or p_query is null or length(p_query)>100 or cardinality(p_known_ids)>500 or (p_before is null)<>(p_before_id is null) then raise exception 'page_invalid';end if;
 if p_mode<>'all' then perform mefrion_private.require_registered();end if;
 items:=mefrion_private.social_page(p_limit,p_mode,btrim(p_query),p_before,p_before_id,p_species);
 last_item:=items->(jsonb_array_length(items)-1);
 -- Interleave available dog/cat posts within each chronological page without
 -- changing the keyset boundary; display order never becomes the next cursor.
 select max_ratio into ratio from mefrion_private.seed_policy;
 select count(*) into user_count from jsonb_array_elements(items) t(item) join mefrion_private.public_posts p on p.id=(item->>'id')::uuid where p.content_origin='user';
 select coalesce(jsonb_agg(item order by case when p_mode='all' then origin_rank else 0 end,case when p_mode='all' and p_species='all' then species_rank else ordinal end,ordinal),'[]') into ordered from (
 select item,ordinal,p.content_origin,case when p.content_origin='user' then 0 else 1 end origin_rank,row_number() over(partition by item->>'species',p.content_origin order by ordinal) species_rank,row_number() over(partition by p.content_origin order by ordinal) origin_position
 from jsonb_array_elements(items) with ordinality t(item,ordinal) join mefrion_private.public_posts p on p.id=(item->>'id')::uuid) q
 where p_mode<>'all' or content_origin='user' or user_count=0 or origin_position<=floor(jsonb_array_length(items)*ratio);
 select coalesce(jsonb_agg(known_id),'[]') into known from unnest(p_known_ids) t(known_id) where mefrion_private.post_allowed(known_id,auth.uid()) and (p_mode='all' or (p_mode='liked' and exists(select 1 from mefrion_private.reactions where post_id=known_id and actor_id=auth.uid() and kind='like')) or (p_mode='saved' and exists(select 1 from mefrion_private.reactions where post_id=known_id and actor_id=auth.uid() and kind='save')) or (p_mode='following' and exists(select 1 from mefrion_private.public_posts s join mefrion_private.follows f on f.pet_id=s.pet_id and f.actor_id=auth.uid() where s.id=known_id)));
 return jsonb_build_object('items',ordered,'next_date',case when jsonb_array_length(items)=greatest(1,least(coalesce(p_limit,20),50)) then last_item->>'published_at' else null end,'next_id',case when jsonb_array_length(items)=greatest(1,least(coalesce(p_limit,20),50)) then last_item->>'id' else null end,'valid_known_ids',known);
end $$;
create or replace function public.mefrion_album(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'path',object_path,'captured',captured,'created_at',created_at,'title',title,'mine',provider_id=auth.uid(),'event_kind',event_kind,'note',note,'provider_name',mefrion_private.family_display_name(p_pet,provider_id)) order by captured desc nulls last,created_at desc,id),'[]') from mefrion_private.photos where pet_id=p_pet and state='ready');
end $$;
commit;
