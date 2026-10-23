begin;
create or replace function mefrion_private.social_feed(p_limit integer,p_mode text,p_query text) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item order by published_at desc,id),'[]'::jsonb) from (
 select s.id,s.published_at,jsonb_build_object('id',s.id,'pet_id',pet.id,'name',pet.name,'species',pet.species,'breed',case when 'breed'=any(pet.public_fields) then pet.breed else '' end,'body',s.body,'kind',s.kind,'published_at',s.published_at,
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
 select s.id,s.published_at,jsonb_build_object('id',s.id,'pet_id',pet.id,'name',pet.name,'species',pet.species,'breed',case when 'breed'=any(pet.public_fields) then pet.breed else '' end,'body',s.body,'kind',s.kind,'published_at',s.published_at,
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

create function public.mefrion_feed_page(p_mode text default 'all',p_query text default '',p_species text default 'all',p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 12,p_known_ids uuid[] default '{}') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;last_item jsonb;ordered jsonb;known jsonb;
begin
 if p_mode is null or p_mode not in ('all','following','saved') or p_species is null or p_species not in ('all','dog','cat') or p_query is null or length(p_query)>100 or cardinality(p_known_ids)>500 or (p_before is null)<>(p_before_id is null) then raise exception 'page_invalid';end if;
 if p_mode<>'all' then perform mefrion_private.require_registered();end if;
 items:=mefrion_private.social_page(p_limit,p_mode,btrim(p_query),p_before,p_before_id,p_species);
 last_item:=items->(jsonb_array_length(items)-1);
 -- Interleave available dog/cat posts within each chronological page without
 -- changing the keyset boundary; display order never becomes the next cursor.
 select coalesce(jsonb_agg(item order by case when p_mode='all' and p_species='all' then species_rank else ordinal end,ordinal),'[]') into ordered from (select item,ordinal,row_number() over(partition by item->>'species' order by ordinal) species_rank from jsonb_array_elements(items) with ordinality t(item,ordinal)) q;
 select coalesce(jsonb_agg(known_id),'[]') into known from unnest(p_known_ids) t(known_id) where mefrion_private.post_allowed(known_id,auth.uid()) and (p_mode='all' or (p_mode='saved' and exists(select 1 from mefrion_private.reactions where post_id=known_id and actor_id=auth.uid() and kind='save')) or (p_mode='following' and exists(select 1 from mefrion_private.public_posts s join mefrion_private.follows f on f.pet_id=s.pet_id and f.actor_id=auth.uid() where s.id=known_id)));
 return jsonb_build_object('items',ordered,'next_date',case when jsonb_array_length(items)=greatest(1,least(coalesce(p_limit,20),50)) then last_item->>'published_at' else null end,'next_id',case when jsonb_array_length(items)=greatest(1,least(coalesce(p_limit,20),50)) then last_item->>'id' else null end,'valid_known_ids',known);
end $$;
revoke execute on function mefrion_private.social_page(integer,text,text,timestamptz,uuid,text) from public,anon,authenticated;
revoke execute on function public.mefrion_feed_page(text,text,text,timestamptz,uuid,integer,uuid[]) from public;
grant execute on function public.mefrion_feed_page(text,text,text,timestamptz,uuid,integer,uuid[]) to anon,authenticated;
commit;
