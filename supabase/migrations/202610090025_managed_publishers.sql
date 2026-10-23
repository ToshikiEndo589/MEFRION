begin;
alter table mefrion_private.public_posts add column content_origin text not null default 'user' check(content_origin in ('user','managed_seed'));
create table mefrion_private.managed_publishers(id uuid primary key references auth.users(id),active boolean not null default true);
create table mefrion_private.managed_pets(pet_id uuid primary key references mefrion_private.pets(id),publisher_id uuid not null references mefrion_private.managed_publishers(id),external_key text not null,source_note text not null,rights_note text not null default '',rights_until timestamptz,rights_verified boolean not null default false,active boolean not null default true,version integer not null default 1,updated_by uuid not null references auth.users(id),unique(publisher_id,external_key));
create table mefrion_private.seed_batches(actor_id uuid references auth.users(id),request_key uuid,payload jsonb not null,result jsonb not null,primary key(actor_id,request_key));
create table mefrion_private.seed_jobs(id uuid primary key default gen_random_uuid(),pet_id uuid not null references mefrion_private.managed_pets(pet_id),created_by uuid not null references auth.users(id),request_key uuid not null,body text not null,photos uuid[] not null,state text not null default 'draft' check(state in ('draft','approved','scheduled','dispatching','published','stopped')),version integer not null default 1,approved_by uuid references auth.users(id),scheduled_at timestamptz,post_id uuid not null default gen_random_uuid(),unique(created_by,request_key),unique(post_id));
alter table mefrion_private.managed_publishers enable row level security;alter table mefrion_private.managed_pets enable row level security;alter table mefrion_private.seed_batches enable row level security;alter table mefrion_private.seed_jobs enable row level security;
revoke all on mefrion_private.managed_publishers,mefrion_private.managed_pets,mefrion_private.seed_batches,mefrion_private.seed_jobs from public,anon,authenticated;
create function mefrion_private.seed_access(p_task text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and auth.jwt()->>'aal'='aal2'
 and not exists(select 1 from mefrion_private.account_retirements where user_id=auth.uid())
 and exists(select 1 from auth.sessions where user_id=auth.uid() and id::text=auth.jwt()->>'session_id')
 and exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified')
 and exists(select 1 from mefrion_private.operators where user_id=auth.uid() and active and expires_at>now() and (role='admin' or (p_task='edit' and role='editor') or (p_task='approve' and role='approver') or (p_task='view' and role in ('editor','approver'))))
$$;
create function mefrion_private.require_seed(p_task text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();if not mefrion_private.seed_access(p_task) then raise exception 'seed_role_and_mfa_required' using errcode='42501';end if;
end $$;
create function public.mefrion_register_test_publisher(p_publisher uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'service_required' using errcode='42501';end if;
 if not exists(select 1 from auth.users where id=p_publisher and email like 'mefrion-test-%@example.invalid' and raw_user_meta_data->>'test_only'='true' and raw_user_meta_data->>'managed_publisher'='true') then raise exception 'reserved_technical_fixture_required';end if;
 insert into mefrion_private.managed_publishers(id) values(p_publisher) on conflict(id) do nothing;return true;
end $$;
-- This is a separate technical publisher, never one credential/account per Pet.
-- Staff role removal therefore leaves the publisher and its posts intact.
create function public.mefrion_seed_create(p_publisher uuid,p_items jsonb,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_old mefrion_private.seed_batches;item jsonb;pet uuid;result jsonb:='[]';
begin
 perform mefrion_private.require_seed('edit');perform pg_advisory_xact_lock(hashtextextended(p_publisher::text,0));
 if p_key is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 20 or length(p_items::text)>40000 then raise exception 'seed_batch_invalid';end if;
 if not exists(select 1 from mefrion_private.managed_publishers where id=p_publisher and active) then raise exception 'publisher_required';end if;
 select * into v_old from mefrion_private.seed_batches where actor_id=auth.uid() and request_key=p_key;
 if found then if v_old.payload<>jsonb_build_object('publisher',p_publisher,'items',p_items) then raise exception 'idempotency_conflict';end if;return v_old.result;end if;
 if (select count(*) from mefrion_private.managed_pets where publisher_id=p_publisher)+jsonb_array_length(p_items)>500 then raise exception 'managed_limit';end if;
 for item in select * from jsonb_array_elements(p_items) loop
  if length(btrim(coalesce(item->>'key',''))) not between 1 and 80 or length(btrim(coalesce(item->>'name',''))) not between 1 and 40 or item->>'species' not in ('dog','cat') or item->>'species' is null or length(coalesce(item->>'breed',''))>100 or length(coalesce(item->>'introduction',''))>500 or length(btrim(coalesce(item->>'source',''))) not between 1 and 500 then raise exception 'seed_profile_invalid';end if;
  insert into mefrion_private.pets(owner_id,name,species,breed,introduction) values(p_publisher,btrim(item->>'name'),item->>'species',coalesce(item->>'breed',''),coalesce(item->>'introduction','')) returning id into pet;
  insert into mefrion_private.managed_pets(pet_id,publisher_id,external_key,source_note,updated_by) values(pet,p_publisher,item->>'key',item->>'source',auth.uid());
  insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),pet,'seed.create');result:=result||jsonb_build_array(jsonb_build_object('id',pet,'name',item->>'name'));
 end loop;
 insert into mefrion_private.seed_batches values(auth.uid(),p_key,jsonb_build_object('publisher',p_publisher,'items',p_items),result);return result;
end $$;
create function mefrion_private.managed_family_access(p_pet uuid) returns boolean language sql stable security definer set search_path='' as $$
 select mefrion_private.seed_access('view') and exists(select 1 from mefrion_private.managed_pets m join mefrion_private.managed_publishers p on p.id=m.publisher_id and p.active where m.pet_id=p_pet and m.active)
$$;
-- Preserve the previously tested ordinary family boundary, extending only newly
-- created managed assets to active staff with MFA; no access to private UGC.
alter function public.mefrion_family_access(uuid) rename to mefrion_ordinary_family_access;
revoke execute on function public.mefrion_ordinary_family_access(uuid) from public,anon,authenticated;
create function public.mefrion_family_access(p_pet uuid) returns boolean language sql stable security definer set search_path='' as $$select public.mefrion_ordinary_family_access(p_pet) or mefrion_private.managed_family_access(p_pet)$$;
revoke execute on function public.mefrion_family_access(uuid) from public,anon;grant execute on function public.mefrion_family_access(uuid) to authenticated;
create function public.mefrion_seed_begin_photo(p_pet uuid,p_key uuid,p_title text) returns jsonb language plpgsql security definer set search_path='' as $$
declare publisher uuid;p mefrion_private.photos;
begin
 perform mefrion_private.require_seed('edit');select publisher_id into publisher from mefrion_private.managed_pets where pet_id=p_pet and active for update;
 if not found or p_key is null or p_title is null or length(p_title)>200 then raise exception 'seed_photo_invalid';end if;
 select * into p from mefrion_private.photos where pet_id=p_pet and provider_id=publisher and request_key=p_key;
 if found then if p.state='deleted' or p.title<>p_title then raise exception 'idempotency_conflict';end if;
 else
  p.id:=gen_random_uuid();insert into mefrion_private.photos(id,pet_id,provider_id,request_key,title,object_path) values(p.id,p_pet,publisher,p_key,p_title,p_pet::text||'/'||p.id::text||'.jpg') returning * into p;
  insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'seed.photo.reserve');
 end if;
 return jsonb_build_object('id',p.id,'path',p.object_path,'state',p.state);
end $$;
create or replace function public.mefrion_upload_allowed(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.photos p where p.object_path=p_path and p.state='pending' and ((p.provider_id=auth.uid() and public.mefrion_family_access(p.pet_id)) or (mefrion_private.seed_access('edit') and mefrion_private.managed_family_access(p.pet_id))))
$$;
create function public.mefrion_seed_finish_photo(p_photo uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare p mefrion_private.photos;
begin
 perform mefrion_private.require_seed('edit');select * into p from mefrion_private.photos where id=p_photo for update;
 if not found or p.state='deleted' or not mefrion_private.managed_family_access(p.pet_id) or not exists(select 1 from storage.objects where bucket_id='family-originals' and name=p.object_path) then raise exception 'seed_photo_incomplete';end if;
 update mefrion_private.photos set state='ready' where id=p_photo;insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p.pet_id,'seed.photo.ready');return true;
end $$;
create function public.mefrion_seed_draft(p_pet uuid,p_photos uuid[],p_body text,p_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare v mefrion_private.seed_jobs;
begin
 perform mefrion_private.require_seed('edit');perform 1 from mefrion_private.managed_pets where pet_id=p_pet and active for update;
 if not found or p_key is null or p_body is null or length(p_body)>500 or cardinality(p_photos) not between 1 and 4 or p_photos is null or cardinality(p_photos)<>(select count(distinct id) from unnest(p_photos) id) then raise exception 'seed_draft_invalid';end if;
 if (select count(*) from mefrion_private.photos where id=any(p_photos) and pet_id=p_pet and state='ready')<>cardinality(p_photos) then raise exception 'seed_photo_scope';end if;
 select * into v from mefrion_private.seed_jobs where created_by=auth.uid() and request_key=p_key;
 if found then if v.pet_id<>p_pet or v.photos<>p_photos or v.body<>p_body then raise exception 'idempotency_conflict';end if;return v.id;end if;
 insert into mefrion_private.seed_jobs(pet_id,created_by,request_key,body,photos) values(p_pet,auth.uid(),p_key,p_body,p_photos) returning * into v;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'seed.draft');return v.id;
end $$;
create function public.mefrion_seed_approve(p_job uuid,p_version integer,p_rights_note text,p_rights_until timestamptz) returns boolean language plpgsql security definer set search_path='' as $$
declare v mefrion_private.seed_jobs;
begin
 perform mefrion_private.require_seed('approve');select * into v from mefrion_private.seed_jobs where id=p_job for update;
 if not found or v.version<>p_version or v.state<>'draft' then raise exception 'seed_version_conflict';end if;
 if p_rights_note is null or length(btrim(p_rights_note)) not between 10 and 1000 or p_rights_until is null or p_rights_until<=now() or p_rights_until>now()+interval '366 days' then raise exception 'seed_rights_required';end if;
 update mefrion_private.managed_pets set rights_note=p_rights_note,rights_until=p_rights_until,rights_verified=true,version=version+1,updated_by=auth.uid() where pet_id=v.pet_id;
 update mefrion_private.seed_jobs set state='approved',approved_by=auth.uid(),version=version+1 where id=p_job;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v.pet_id,'seed.approve');return true;
end $$;
create function public.mefrion_seed_schedule(p_job uuid,p_version integer,p_when timestamptz,p_explicit boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare v mefrion_private.seed_jobs;
begin
 perform mefrion_private.require_seed('publish');select * into v from mefrion_private.seed_jobs where id=p_job for update;
 if not found or v.version<>p_version or v.state<>'approved' then raise exception 'seed_version_conflict';end if;
 if p_explicit is distinct from true or p_when is null or p_when<now()-interval '1 minute' or p_when>now()+interval '366 days' then raise exception 'seed_schedule_invalid';end if;
 if not exists(select 1 from mefrion_private.managed_pets where pet_id=v.pet_id and active and rights_verified and rights_until>p_when and rights_until>now()) then raise exception 'seed_rights_expired';end if;
 update mefrion_private.seed_jobs set state='scheduled',scheduled_at=p_when,version=version+1 where id=p_job;
 insert into mefrion_private.public_profiles(pet_id,enabled) values(v.pet_id,true) on conflict(pet_id) do update set enabled=true;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v.pet_id,'seed.schedule');return true;
end $$;
create function public.mefrion_seed_stop(p_pets uuid[],p_withdraw_rights boolean) returns integer language plpgsql security definer set search_path='' as $$
declare pet uuid;post uuid;count integer:=0;
begin
 perform mefrion_private.require_seed('publish');if cardinality(p_pets) not between 1 and 100 or p_pets is null or p_withdraw_rights is null then raise exception 'seed_stop_invalid';end if;
 foreach pet in array p_pets loop
  perform 1 from mefrion_private.managed_pets where pet_id=pet for update;if not found then raise exception 'managed_pet_required';end if;
  update mefrion_private.seed_jobs set state='stopped',version=version+1 where pet_id=pet and state<>'stopped';
  update mefrion_private.public_profiles set enabled=false where pet_id=pet;
  if p_withdraw_rights then update mefrion_private.consents set allowed=false,version=version+1 where photo_id in(select id from mefrion_private.photos where pet_id=pet);update mefrion_private.managed_pets set rights_verified=false,version=version+1,updated_by=auth.uid() where pet_id=pet;end if;
  for post in select id from mefrion_private.public_posts where pet_id=pet loop perform mefrion_private.stop_publication(post);end loop;
  insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),pet,case when p_withdraw_rights then 'seed.rights.withdraw' else 'seed.stop' end);count:=count+1;
 end loop;return count;
end $$;
create function mefrion_private.managed_public_ready(p_pet uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from mefrion_private.managed_pets where pet_id=p_pet) or exists(select 1 from mefrion_private.managed_pets m join mefrion_private.managed_publishers p on p.id=m.publisher_id and p.active where m.pet_id=p_pet and m.active and m.rights_verified and m.rights_until>now())
$$;
create or replace function mefrion_private.public_write_gate() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='public_posts' then
 if auth.role()='service_role' and new.content_origin='managed_seed' then
  if not exists(select 1 from mefrion_private.seed_jobs j join mefrion_private.managed_pets m on m.pet_id=j.pet_id where j.post_id=new.id and j.state='dispatching' and j.pet_id=new.pet_id and j.body=new.body and new.kind='post' and new.actor_id=m.publisher_id and mefrion_private.managed_public_ready(m.pet_id)) then raise exception 'approved_seed_dispatch_required';end if;
 else perform mefrion_private.require_public_actor();end if;
 elsif new.enabled then perform mefrion_private.require_public_actor();end if;return new;
end $$;
create function public.mefrion_seed_dispatch() returns integer language plpgsql security definer set search_path='' as $$
declare j mefrion_private.seed_jobs;publisher uuid;photo uuid;v integer;position integer;media uuid;count integer:=0;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 for j in select * from mefrion_private.seed_jobs where state='scheduled' and scheduled_at<=now() order by scheduled_at,id limit 10 for update skip locked loop
  if not mefrion_private.managed_public_ready(j.pet_id) or (select count(*) from mefrion_private.photos where id=any(j.photos) and state='ready' and pet_id=j.pet_id)<>cardinality(j.photos) or not exists(select 1 from mefrion_private.public_profiles where pet_id=j.pet_id and enabled) then update mefrion_private.seed_jobs set state='stopped',version=version+1 where id=j.id;continue;end if;
  select publisher_id into publisher from mefrion_private.managed_pets where pet_id=j.pet_id;
  update mefrion_private.seed_jobs set state='dispatching',version=version+1 where id=j.id;
  insert into mefrion_private.public_posts(id,pet_id,actor_id,request_key,body,kind,content_origin) values(j.post_id,j.pet_id,publisher,j.request_key,j.body,'post','managed_seed');position:=0;
  foreach photo in array j.photos loop
   insert into mefrion_private.consents(photo_id,purpose,allowed) values(photo,'sns',true) on conflict(photo_id,purpose) do update set allowed=true,version=mefrion_private.consents.version+1 returning version into v;
   media:=gen_random_uuid();insert into mefrion_private.public_media(id,post_id,source_id,consent_version,position,object_path) values(media,j.post_id,photo,v,position,media::text||'.jpg');position:=position+1;
  end loop;
  insert into mefrion_private.audit(actor_id,pet_id,action) values(null,j.pet_id,'service.seed.dispatch');count:=count+1;
 end loop;return count;
end $$;
create function public.mefrion_seed_list() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_seed('view');
 return jsonb_build_object('publishers',(select coalesce(jsonb_agg(id),'[]') from mefrion_private.managed_publishers where active),'pets',(select coalesce(jsonb_agg(jsonb_build_object('id',m.pet_id,'name',p.name,'species',p.species,'key',m.external_key,'source',m.source_note,'rights',m.rights_note,'rights_until',m.rights_until,'rights_verified',m.rights_verified,'version',m.version,'updated_by',m.updated_by,'photos',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'state',state)),'[]') from mefrion_private.photos where pet_id=p.id and state<>'deleted'),'jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'body',j.body,'state',j.state,'version',j.version,'scheduled_at',j.scheduled_at,'photos',j.photos)),'[]') from mefrion_private.seed_jobs j where j.pet_id=p.id)) order by p.created_at),'[]') from mefrion_private.managed_pets m join mefrion_private.pets p on p.id=m.pet_id));
end $$;

create or replace function mefrion_private.post_allowed(p_post uuid,p_actor uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.public_posts s
 join mefrion_private.public_profiles profile on profile.pet_id=s.pet_id and profile.enabled
 join mefrion_private.pets pet on pet.id=s.pet_id
 where s.id=p_post and s.state='published' and mefrion_private.managed_public_ready(s.pet_id)
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
alter function public.mefrion_publication_finish(uuid) set schema mefrion_private;
alter function mefrion_private.mefrion_publication_finish(uuid) rename to seed_publication_finish_core;
create function public.mefrion_publication_finish(p_post uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 if exists(select 1 from mefrion_private.public_posts where id=p_post and not mefrion_private.managed_public_ready(pet_id)) then perform mefrion_private.stop_publication(p_post);return false;end if;
 return mefrion_private.seed_publication_finish_core(p_post);
end $$;
revoke execute on function public.mefrion_publication_finish(uuid) from public,anon,authenticated;grant execute on function public.mefrion_publication_finish(uuid) to service_role;
create function mefrion_private.seed_publication_state() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.content_origin='managed_seed' and new.state in ('published','stopped') then update mefrion_private.seed_jobs set state=new.state,version=version+1 where post_id=new.id and state<>new.state;end if;return new;
end $$;
create trigger mefrion_seed_publication_state after update of state on mefrion_private.public_posts for each row execute function mefrion_private.seed_publication_state();

revoke execute on all functions in schema mefrion_private from public,anon,authenticated;
revoke execute on function public.mefrion_register_test_publisher(uuid),public.mefrion_seed_dispatch() from public,anon,authenticated;grant execute on function public.mefrion_register_test_publisher(uuid),public.mefrion_seed_dispatch() to service_role;
revoke execute on function public.mefrion_seed_create(uuid,jsonb,uuid),public.mefrion_seed_begin_photo(uuid,uuid,text),public.mefrion_seed_finish_photo(uuid),public.mefrion_seed_draft(uuid,uuid[],text,uuid),public.mefrion_seed_approve(uuid,integer,text,timestamptz),public.mefrion_seed_schedule(uuid,integer,timestamptz,boolean),public.mefrion_seed_stop(uuid[],boolean),public.mefrion_seed_list() from public,anon;
grant execute on function public.mefrion_seed_create(uuid,jsonb,uuid),public.mefrion_seed_begin_photo(uuid,uuid,text),public.mefrion_seed_finish_photo(uuid),public.mefrion_seed_draft(uuid,uuid[],text,uuid),public.mefrion_seed_approve(uuid,integer,text,timestamptz),public.mefrion_seed_schedule(uuid,integer,timestamptz,boolean),public.mefrion_seed_stop(uuid[],boolean),public.mefrion_seed_list() to authenticated;
commit;
