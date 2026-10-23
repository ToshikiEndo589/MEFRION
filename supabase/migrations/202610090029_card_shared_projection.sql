begin;
create table mefrion_private.card_publications(card_id uuid references mefrion_private.cards(id) on delete cascade,post_id uuid primary key references mefrion_private.public_posts(id));
alter table mefrion_private.card_publications enable row level security;
revoke all on mefrion_private.card_publications from public,anon,authenticated;
create function public.mefrion_share_card(p_card uuid,p_key uuid,p_explicit boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare c mefrion_private.cards;v jsonb;
begin
 perform public.mefrion_authorize_card_export(p_card,p_explicit);
 select * into c from mefrion_private.cards where id=p_card for share;
 v:=public.mefrion_request_publication(c.pet_id,array[c.first_id,c.second_id],coalesce(c.layout->>'text',''),'share',p_key,p_explicit);
 insert into mefrion_private.card_publications values(p_card,(v->>'id')::uuid) on conflict do nothing;return v;
end $$;
create function mefrion_private.stop_card_publications() returns trigger language plpgsql security definer set search_path='' as $$
declare p uuid;
begin
 for p in select post_id from mefrion_private.card_publications where card_id=old.id loop perform mefrion_private.stop_publication(p);end loop;return old;
end $$;
create trigger mefrion_card_publication_deleted before delete on mefrion_private.cards for each row execute function mefrion_private.stop_card_publications();
create function public.mefrion_shared_projection(p_post uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',s.id,'name',pet.name,'kind','card','text',s.body,'layout',c.layout,'media',(select jsonb_agg(jsonb_build_object('id',m.id,'captured',photo.captured) order by m.position) from mefrion_private.public_media m join mefrion_private.photos photo on photo.id=m.source_id where m.post_id=s.id))
 from mefrion_private.public_posts s join mefrion_private.pets pet on pet.id=s.pet_id join mefrion_private.card_publications cp on cp.post_id=s.id join mefrion_private.cards c on c.id=cp.card_id where s.id=p_post and s.kind='share' and mefrion_private.post_allowed(s.id,auth.uid())
$$;
revoke execute on function mefrion_private.stop_card_publications() from public,anon,authenticated;
revoke execute on function public.mefrion_share_card(uuid,uuid,boolean) from public,anon;grant execute on function public.mefrion_share_card(uuid,uuid,boolean) to authenticated;
revoke execute on function public.mefrion_shared_projection(uuid) from public;grant execute on function public.mefrion_shared_projection(uuid) to anon,authenticated;

create or replace function public.mefrion_seed_list() returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
 perform mefrion_private.require_seed('view');
 return jsonb_build_object('publishers',(select coalesce(jsonb_agg(id),'[]') from mefrion_private.managed_publishers where active),'pets',(select coalesce(jsonb_agg(jsonb_build_object('id',m.pet_id,'name',p.name,'species',p.species,'breed',p.breed,'introduction',p.introduction,'active',m.active,'key',m.external_key,'source',m.source_note,'rights',m.rights_note,'rights_until',m.rights_until,'rights_verified',m.rights_verified,'version',m.version,'updated_by',m.updated_by,'photos',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'state',state)),'[]') from mefrion_private.photos where pet_id=p.id and state<>'deleted'),'jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'body',j.body,'state',j.state,'version',j.version,'scheduled_at',j.scheduled_at,'photos',j.photos)),'[]') from mefrion_private.seed_jobs j where j.pet_id=p.id)) order by p.created_at),'[]') from mefrion_private.managed_pets m join mefrion_private.pets p on p.id=m.pet_id));
end $$;

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
 where s.kind='post' and mefrion_private.post_allowed(s.id,auth.uid())
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
 where s.kind='post' and mefrion_private.post_allowed(s.id,auth.uid())
 and (p_before is null or (s.published_at,s.id)<(p_before,p_before_id))
 and (p_species='all' or pet.species=p_species)
 and (p_mode='all' or (p_mode='saved' and exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid())) or (p_mode='following' and exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())))
 and (p_query='' or position(pg_catalog.normalize(lower(p_query),'NFKC') in pg_catalog.normalize(lower(pet.name||' '||case when 'breed'=any(pet.public_fields) then pet.breed else '' end),'NFKC'))>0)
 order by s.published_at desc,s.id limit greatest(1,least(coalesce(p_limit,20),50))) visible
$$;



commit;
