begin;
create table mefrion_private.twins_feedback(search_id uuid not null references mefrion_private.twins_searches(id) on delete cascade,candidate_id uuid not null references mefrion_private.twins_candidates(id),actor_id uuid not null references auth.users(id),is_similar boolean not null,updated_at timestamptz not null default now(),primary key(search_id,candidate_id));
alter table mefrion_private.twins_feedback enable row level security;revoke all on mefrion_private.twins_feedback from public,anon,authenticated;
create function public.mefrion_twins_feedback(p_search uuid,p_candidate uuid,p_similar boolean) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 if p_similar is null or not exists(select 1 from mefrion_private.twins_searches where id=p_search and actor_id=auth.uid() and state='results' and p_candidate=any(candidates) and created_at>now()-interval '30 days') or not mefrion_private.twins_visible(p_candidate,auth.uid()) then raise exception 'own_visible_result_required' using errcode='42501';end if;
 insert into mefrion_private.twins_feedback values(p_search,p_candidate,auth.uid(),p_similar,now()) on conflict(search_id,candidate_id) do update set is_similar=excluded.is_similar,updated_at=excluded.updated_at;return true;
end $$;
create or replace function public.mefrion_twins_candidates(p_species text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_species not in ('dog','cat') or p_species is null then raise exception 'species_required';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'pet_id',p.id,'name',p.name,'species',p.species,'breed',case when 'breed'=any(p.public_fields) then p.breed else '' end,'demo_only',coalesce((u.raw_user_meta_data->>'test_only')='true',false)) order by t.created_at,t.id),'[]') from (select * from mefrion_private.twins_candidates where mefrion_private.twins_visible(id,auth.uid()) and owner_id is distinct from auth.uid() and pet_id in(select id from mefrion_private.pets where species=p_species) order by created_at,id limit 100) t join mefrion_private.pets p on p.id=t.pet_id join auth.users u on u.id=t.owner_id);
end $$;
create function public.mefrion_pet_recent_posts(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform public.mefrion_public_pet(p_pet);
 return (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'body',p.body,'media',(select jsonb_agg(m.id order by m.position) from mefrion_private.public_media m where m.post_id=p.id)) order by p.published_at desc,p.id),'[]') from (select * from mefrion_private.public_posts where pet_id=p_pet and kind='post' and mefrion_private.post_allowed(id,auth.uid()) order by published_at desc,id limit 12) p);
end $$;
revoke execute on function public.mefrion_twins_feedback(uuid,uuid,boolean) from public,anon;grant execute on function public.mefrion_twins_feedback(uuid,uuid,boolean) to authenticated;
revoke execute on function public.mefrion_pet_recent_posts(uuid) from public;grant execute on function public.mefrion_pet_recent_posts(uuid) to anon,authenticated;
commit;
