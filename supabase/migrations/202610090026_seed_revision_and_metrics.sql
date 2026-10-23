begin;
create table mefrion_private.seed_policy(singleton boolean primary key default true check(singleton),max_ratio numeric not null default 0.5 check(max_ratio between 0 and 1));
alter table mefrion_private.seed_policy enable row level security;revoke all on mefrion_private.seed_policy from public,anon,authenticated;
insert into mefrion_private.seed_policy values(true,0.5);
create function public.mefrion_seed_policy(p_ratio numeric) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_seed('publish');if p_ratio is null or p_ratio<0 or p_ratio>1 then raise exception 'ratio_invalid';end if;update mefrion_private.seed_policy set max_ratio=p_ratio;insert into mefrion_private.audit(actor_id,action) values(auth.uid(),'seed.ratio');return true;
end $$;
create function public.mefrion_seed_revise(p_job uuid,p_version integer,p_photos uuid[],p_body text) returns boolean language plpgsql security definer set search_path='' as $$
declare v mefrion_private.seed_jobs;
begin
 perform mefrion_private.require_seed('edit');select * into v from mefrion_private.seed_jobs where id=p_job for update;
 if not found or v.version<>p_version then raise exception 'seed_version_conflict';end if;
 if p_body is null or length(p_body)>500 or p_photos is null or cardinality(p_photos) not between 1 and 4 or cardinality(p_photos)<>(select count(distinct id) from unnest(p_photos) id) or (select count(*) from mefrion_private.photos where id=any(p_photos) and pet_id=v.pet_id and state='ready')<>cardinality(p_photos) then raise exception 'seed_draft_invalid';end if;
 if exists(select 1 from mefrion_private.public_posts where id=v.post_id) then perform mefrion_private.stop_publication(v.post_id);end if;
 update mefrion_private.seed_jobs set body=p_body,photos=p_photos,approved_by=null,scheduled_at=null,post_id=gen_random_uuid(),state='draft',version=version+1 where id=p_job;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v.pet_id,'seed.revise');return true;
end $$;
create function public.mefrion_seed_edit(p_pet uuid,p_version integer,p_name text,p_breed text,p_introduction text,p_source text,p_active boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare v mefrion_private.managed_pets;post uuid;
begin
 perform mefrion_private.require_seed('edit');select * into v from mefrion_private.managed_pets where pet_id=p_pet for update;
 if not found or v.version<>p_version then raise exception 'seed_version_conflict';end if;
 if p_name is null or length(btrim(p_name)) not between 1 and 40 or p_breed is null or length(p_breed)>100 or p_introduction is null or length(p_introduction)>500 or p_source is null or length(btrim(p_source)) not between 1 and 500 or p_active is null then raise exception 'seed_profile_invalid';end if;
 update mefrion_private.pets set name=btrim(p_name),breed=p_breed,introduction=p_introduction where id=p_pet;
 update mefrion_private.managed_pets set active=p_active,source_note=p_source,rights_verified=false,version=version+1,updated_by=auth.uid() where pet_id=p_pet;
 update mefrion_private.public_profiles set enabled=false where pet_id=p_pet;
 for post in select id from mefrion_private.public_posts where pet_id=p_pet loop perform mefrion_private.stop_publication(post);end loop;
 update mefrion_private.seed_jobs set state='draft',approved_by=null,scheduled_at=null,post_id=gen_random_uuid(),version=version+1 where pet_id=p_pet;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'seed.profile.edit');return true;
end $$;
create function public.mefrion_seed_delete_photo(p_photo uuid,p_explicit boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare p mefrion_private.photos;
begin
 perform mefrion_private.require_seed('edit');select * into p from mefrion_private.photos where id=p_photo for update;
 if p_explicit is distinct from true or not found or not mefrion_private.managed_family_access(p.pet_id) then raise exception 'managed_photo_required' using errcode='42501';end if;
 if p.state='deleted' then return true;end if;
 update mefrion_private.photos set state='deleted' where id=p_photo;
 update mefrion_private.consents set allowed=false,version=version+1 where photo_id=p_photo;
 delete from mefrion_private.cards where first_id=p_photo or second_id=p_photo;
 insert into mefrion_private.deletion_outbox(object_path) values(p.object_path);
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p.pet_id,'seed.photo.delete');return true;
end $$;
create function public.mefrion_seed_audit() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_seed('view');return (select coalesce(jsonb_agg(jsonb_build_object('action',action,'pet_id',pet_id,'actor_id',actor_id,'created_at',created_at) order by id desc),'[]') from (select * from mefrion_private.audit where action like 'seed.%' or action like 'service.seed.%' order by id desc limit 100) a);
end $$;
create function public.mefrion_seed_metrics() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_seed('view');return jsonb_build_object('max_seed_ratio',(select max_ratio from mefrion_private.seed_policy),'real_registered_users',(select count(*) from auth.users where not is_anonymous and coalesce(raw_user_meta_data->>'test_only','false')<>'true' and coalesce(raw_user_meta_data->>'managed_publisher','false')<>'true' and deleted_at is null),'ugc_posts',(select count(*) from mefrion_private.public_posts s join auth.users u on u.id=s.actor_id where s.content_origin='user' and s.state='published' and coalesce(u.raw_user_meta_data->>'test_only','false')<>'true'),'managed_posts',(select count(*) from mefrion_private.public_posts s join auth.users u on u.id=s.actor_id where s.content_origin='managed_seed' and s.state='published' and coalesce(u.raw_user_meta_data->>'test_only','false')<>'true'),'synthetic_posts',(select count(*) from mefrion_private.public_posts s join auth.users u on u.id=s.actor_id where s.state='published' and u.raw_user_meta_data->>'test_only'='true'));
end $$;
revoke execute on function public.mefrion_seed_policy(numeric),public.mefrion_seed_revise(uuid,integer,uuid[],text),public.mefrion_seed_edit(uuid,integer,text,text,text,text,boolean),public.mefrion_seed_delete_photo(uuid,boolean),public.mefrion_seed_audit(),public.mefrion_seed_metrics() from public,anon;
grant execute on function public.mefrion_seed_policy(numeric),public.mefrion_seed_revise(uuid,integer,uuid[],text),public.mefrion_seed_edit(uuid,integer,text,text,text,text,boolean),public.mefrion_seed_delete_photo(uuid,boolean),public.mefrion_seed_audit(),public.mefrion_seed_metrics() to authenticated;
create or replace function mefrion_private.require_seed(p_task text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();if not mefrion_private.seed_access(p_task) then raise exception 'seed_role_and_mfa_required' using errcode='42501';end if;
 perform 1 from mefrion_private.operators where user_id=auth.uid() and active and expires_at>now() and (role='admin' or (p_task='edit' and role='editor') or (p_task='approve' and role='approver') or (p_task='view' and role in ('editor','approver'))) for share;
 if not found then raise exception 'seed_role_and_mfa_required' using errcode='42501';end if;
end $$;

create or replace function public.mefrion_public_pet(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p mefrion_private.pets;v jsonb;f text;
begin
 select pet.* into p from mefrion_private.pets pet join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled where pet.id=p_pet and mefrion_private.managed_public_ready(pet.id) and not exists(select 1 from mefrion_private.account_retirements where user_id=pet.owner_id) and mefrion_private.social_actor_visible(auth.uid(),pet.owner_id);
 if not found then raise exception 'profile_unavailable' using errcode='42501';end if;
 v:=jsonb_build_object('id',p.id,'name',p.name,'species',p.species);
 foreach f in array p.public_fields loop
  if f='breed' then v:=v||jsonb_build_object(f,p.breed);elsif f='introduction' then v:=v||jsonb_build_object(f,p.introduction);elsif p.details ? f then v:=v||jsonb_build_object(f,p.details->f);end if;
 end loop;return v;
end $$;
create or replace function public.mefrion_feed_page(p_mode text default 'all',p_query text default '',p_species text default 'all',p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 12,p_known_ids uuid[] default '{}') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;last_item jsonb;ordered jsonb;known jsonb;ratio numeric;user_count integer;
begin
 if p_mode is null or p_mode not in ('all','following','saved') or p_species is null or p_species not in ('all','dog','cat') or p_query is null or length(p_query)>100 or cardinality(p_known_ids)>500 or (p_before is null)<>(p_before_id is null) then raise exception 'page_invalid';end if;
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
 select coalesce(jsonb_agg(known_id),'[]') into known from unnest(p_known_ids) t(known_id) where mefrion_private.post_allowed(known_id,auth.uid()) and (p_mode='all' or (p_mode='saved' and exists(select 1 from mefrion_private.reactions where post_id=known_id and actor_id=auth.uid() and kind='save')) or (p_mode='following' and exists(select 1 from mefrion_private.public_posts s join mefrion_private.follows f on f.pet_id=s.pet_id and f.actor_id=auth.uid() where s.id=known_id)));
 return jsonb_build_object('items',ordered,'next_date',case when jsonb_array_length(items)=greatest(1,least(coalesce(p_limit,20),50)) then last_item->>'published_at' else null end,'next_id',case when jsonb_array_length(items)=greatest(1,least(coalesce(p_limit,20),50)) then last_item->>'id' else null end,'valid_known_ids',known);
end $$;
commit;
