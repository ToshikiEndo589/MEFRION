-- Discovery searches public pet names separately from post content. Every result
-- still passes the same publication, consent, retirement and block checks as feed.
begin;

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
 and (p_query='' or position(pg_catalog.normalize(lower(p_query),'NFKC') in pg_catalog.normalize(lower(pet.name||' '||case when s.content_origin='managed_seed' and s.breed_label is not null then s.breed_label when 'breed'=any(pet.public_fields) then pet.breed else '' end||' '||s.body),'NFKC'))>0
      or exists(select 1 from mefrion_private.post_pet_tags t join mefrion_private.pets tag on tag.id=t.pet_id join mefrion_private.public_profiles f on f.pet_id=tag.id and f.enabled where t.post_id=s.id and position(pg_catalog.normalize(lower(p_query),'NFKC') in pg_catalog.normalize(lower(tag.name),'NFKC'))>0))
 order by s.published_at desc,s.id limit greatest(1,least(coalesce(p_limit,20),50))) visible
$$;

create function public.mefrion_search_pets(p_query text,p_limit integer default 8) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare term text;
begin
 term:=btrim(coalesce(p_query,''));
 if length(term)>100 or p_limit is null or p_limit<1 or p_limit>20 then raise exception 'query_invalid';end if;
 if term='' then return '[]'::jsonb;end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',result.id,'name',result.name,'breed',result.breed) order by result.rank,result.name,result.id)
 from (select pet.id,pet.name,
   case when 'breed'=any(pet.public_fields) then pet.breed else '' end breed,
   case when pg_catalog.normalize(lower(pet.name),'NFKC')=pg_catalog.normalize(lower(term),'NFKC') then 0 else 1 end rank
   from mefrion_private.pets pet
   join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled
   where position(pg_catalog.normalize(lower(term),'NFKC') in pg_catalog.normalize(lower(pet.name),'NFKC'))>0
   and exists(select 1 from mefrion_private.public_posts post where post.pet_id=pet.id and post.kind='post' and mefrion_private.post_allowed(post.id,auth.uid()))
   order by rank,pet.name,pet.id limit p_limit) result),'[]'::jsonb);
end $$;
revoke execute on function public.mefrion_search_pets(text,integer) from public;
grant execute on function public.mefrion_search_pets(text,integer) to anon,authenticated;
commit;
