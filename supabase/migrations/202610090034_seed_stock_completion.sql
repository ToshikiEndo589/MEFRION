begin;
create table mefrion_private.managed_photo_rights(photo_id uuid primary key references mefrion_private.photos(id),holder text not null,scope text not null,evidence text not null,checked_by uuid not null references auth.users(id),checked_at timestamptz not null default now(),expires_at timestamptz not null,allowed boolean not null);
alter table mefrion_private.managed_photo_rights enable row level security;revoke all on mefrion_private.managed_photo_rights from public,anon,authenticated;
alter table mefrion_private.seed_jobs add column planned_at timestamptz;
create table mefrion_private.seed_post_batches(actor_id uuid references auth.users(id),request_key uuid,payload jsonb not null,primary key(actor_id,request_key));
alter table mefrion_private.seed_post_batches enable row level security;revoke all on mefrion_private.seed_post_batches from public,anon,authenticated;
create function public.mefrion_seed_photo_rights(p_photo uuid,p_holder text,p_scope text,p_evidence text,p_until timestamptz,p_allowed boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare p mefrion_private.photos;job uuid;
begin
 perform mefrion_private.require_seed('approve');select * into p from mefrion_private.photos where id=p_photo for share;
 if not found or not mefrion_private.managed_family_access(p.pet_id) or p.state<>'ready' then raise exception 'managed_ready_photo_required' using errcode='42501';end if;
 if p_holder is null or length(btrim(p_holder)) not between 1 and 200 or p_scope is null or length(btrim(p_scope)) not between 1 and 1000 or p_evidence is null or length(btrim(p_evidence)) not between 1 and 1000 or p_until is null or p_until<=now() or p_until>now()+interval '366 days' or p_allowed is null then raise exception 'photo_rights_invalid';end if;
 insert into mefrion_private.managed_photo_rights values(p_photo,p_holder,p_scope,p_evidence,auth.uid(),now(),p_until,p_allowed) on conflict(photo_id) do update set holder=excluded.holder,scope=excluded.scope,evidence=excluded.evidence,checked_by=excluded.checked_by,checked_at=excluded.checked_at,expires_at=excluded.expires_at,allowed=excluded.allowed;
 for job in select id from mefrion_private.seed_jobs where p_photo=any(photos) for update loop
  perform mefrion_private.stop_publication((select post_id from mefrion_private.seed_jobs where id=job));
  update mefrion_private.seed_jobs set state='draft',approved_by=null,scheduled_at=null,post_id=gen_random_uuid(),version=version+1 where id=job;
 end loop;
 if not p_allowed then update mefrion_private.consents set allowed=false,version=version+1 where photo_id=p_photo;end if;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p.pet_id,'seed.photo.rights');return true;
end $$;
create function public.mefrion_seed_draft_batch(p_items jsonb,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb;ids uuid[];result jsonb:='[]';job uuid;index integer:=0;old_payload jsonb;planned timestamptz;
begin
 perform mefrion_private.require_seed('edit');
 if p_key is null or p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 20 or length(p_items::text)>30000 then raise exception 'batch_invalid';end if;
 perform pg_advisory_xact_lock(hashtextextended('seed-batch:'||auth.uid()::text||p_key::text,0));
 select payload into old_payload from mefrion_private.seed_post_batches where actor_id=auth.uid() and request_key=p_key;
 if found and old_payload<>p_items then raise exception 'idempotency_conflict';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(item)<>'object' or jsonb_typeof(item->'photos')<>'array' then raise exception 'batch_invalid';end if;
  select array_agg(value::uuid) into ids from jsonb_array_elements_text(item->'photos');
  planned:=nullif(item->>'planned_at','')::timestamptz;
  if old_payload is null and planned is not null and (planned<=now() or planned>now()+interval '366 days') then raise exception 'future_plan_required';end if;
  job:=public.mefrion_seed_draft((item->>'pet_id')::uuid,ids,coalesce(item->>'body',''),md5(p_key::text||':'||index::text)::uuid);
  if old_payload is null then update mefrion_private.seed_jobs set planned_at=planned where id=job;end if;
  result:=result||jsonb_build_array(job);index:=index+1;
 end loop;
 insert into mefrion_private.seed_post_batches values(auth.uid(),p_key,p_items) on conflict do nothing;return result;
end $$;
create function public.mefrion_seed_now(p_job uuid,p_version integer,p_explicit boolean) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_seed('schedule');return public.mefrion_seed_schedule(p_job,p_version,now(),p_explicit);
end $$;
create function public.mefrion_seed_cancel(p_job uuid,p_version integer,p_explicit boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare j mefrion_private.seed_jobs;
begin
 perform mefrion_private.require_seed('schedule');select * into j from mefrion_private.seed_jobs where id=p_job for update;
 if not found or j.version<>p_version or p_explicit is distinct from true then raise exception 'job_confirmation_or_version_required';end if;
 perform mefrion_private.stop_publication(j.post_id);
 update mefrion_private.seed_jobs set state='draft',approved_by=null,scheduled_at=null,post_id=gen_random_uuid(),version=version+1 where id=p_job;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),j.pet_id,'seed.job.cancel');return true;
end $$;
create function mefrion_private.seed_individual_rights(p_pet uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from mefrion_private.public_posts s join mefrion_private.public_media m on m.post_id=s.id left join mefrion_private.managed_photo_rights r on r.photo_id=m.source_id where s.pet_id=p_pet and s.content_origin='managed_seed' and s.state in ('pending','processing','published') and (r.allowed is distinct from true or r.expires_at<=now()))
$$;

create or replace function public.mefrion_seed_approve(p_job uuid,p_version integer,p_rights_note text,p_rights_until timestamptz) returns boolean language plpgsql security definer set search_path='' as $$
declare v mefrion_private.seed_jobs;
begin
 perform mefrion_private.require_seed('approve');select * into v from mefrion_private.seed_jobs where id=p_job for update;
 if not found or v.version<>p_version or v.state<>'draft' then raise exception 'seed_version_conflict';end if;
 if p_rights_note is null or length(btrim(p_rights_note)) not between 10 and 1000 or p_rights_until is null or p_rights_until<=now() or p_rights_until>now()+interval '366 days' then raise exception 'seed_rights_required';end if;
 if exists(select 1 from unnest(v.photos) i left join mefrion_private.managed_photo_rights r on r.photo_id=i where r.allowed is distinct from true or r.expires_at<=now() or r.expires_at<p_rights_until) then raise exception 'individual_photo_rights_required';end if;
 update mefrion_private.managed_pets set rights_note=p_rights_note,rights_until=p_rights_until,rights_verified=true,version=version+1,updated_by=auth.uid() where pet_id=v.pet_id;
 update mefrion_private.seed_jobs set state='approved',approved_by=auth.uid(),version=version+1 where id=p_job;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v.pet_id,'seed.approve');return true;
end $$;

create or replace function public.mefrion_seed_schedule(p_job uuid,p_version integer,p_when timestamptz,p_explicit boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare v mefrion_private.seed_jobs;
begin
 perform mefrion_private.require_seed('publish');select * into v from mefrion_private.seed_jobs where id=p_job for update;
 if not found or v.version<>p_version or v.state<>'approved' then raise exception 'seed_version_conflict';end if;
 if p_explicit is distinct from true or p_when is null or p_when<now() or p_when>now()+interval '366 days' then raise exception 'seed_schedule_invalid';end if;
 if not exists(select 1 from mefrion_private.managed_pets where pet_id=v.pet_id and active and rights_verified and rights_until>p_when and rights_until>now()) then raise exception 'seed_rights_expired';end if;
 update mefrion_private.seed_jobs set state='scheduled',scheduled_at=p_when,version=version+1 where id=p_job;
 insert into mefrion_private.public_profiles(pet_id,enabled) values(v.pet_id,true) on conflict(pet_id) do update set enabled=true;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v.pet_id,'seed.schedule');return true;
end $$;

create or replace function mefrion_private.managed_public_ready(p_pet uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from mefrion_private.managed_pets where pet_id=p_pet) or (mefrion_private.seed_individual_rights(p_pet) and exists(select 1 from mefrion_private.managed_pets m join mefrion_private.managed_publishers p on p.id=m.publisher_id and p.active where m.pet_id=p_pet and m.active and m.rights_verified and m.rights_until>now()))
$$;
create or replace function public.mefrion_seed_list() returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
 perform mefrion_private.require_seed('view');
 return jsonb_build_object('publishers',(select coalesce(jsonb_agg(id),'[]') from mefrion_private.managed_publishers where active),'pets',(select coalesce(jsonb_agg(jsonb_build_object('id',m.pet_id,'name',p.name,'species',p.species,'breed',p.breed,'introduction',p.introduction,'active',m.active,'key',m.external_key,'source',m.source_note,'rights',m.rights_note,'rights_until',m.rights_until,'rights_verified',m.rights_verified,'version',m.version,'updated_by',m.updated_by,'photos',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'state',state,'rights',(select jsonb_build_object('holder',holder,'scope',scope,'evidence',evidence,'checked_by',checked_by,'checked_at',checked_at,'expires_at',expires_at,'allowed',allowed) from mefrion_private.managed_photo_rights r where r.photo_id=mefrion_private.photos.id))),'[]') from mefrion_private.photos where pet_id=p.id and state<>'deleted'),'jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'body',j.body,'state',j.state,'version',j.version,'scheduled_at',j.scheduled_at,'planned_at',j.planned_at,'photos',j.photos)),'[]') from mefrion_private.seed_jobs j where j.pet_id=p.id)) order by p.created_at),'[]') from mefrion_private.managed_pets m join mefrion_private.pets p on p.id=m.pet_id));
end $$;
revoke execute on function mefrion_private.seed_individual_rights(uuid) from public,anon,authenticated;
revoke execute on function public.mefrion_seed_photo_rights(uuid,text,text,text,timestamptz,boolean),public.mefrion_seed_draft_batch(jsonb,uuid),public.mefrion_seed_now(uuid,integer,boolean),public.mefrion_seed_cancel(uuid,integer,boolean) from public,anon;
grant execute on function public.mefrion_seed_photo_rights(uuid,text,text,text,timestamptz,boolean),public.mefrion_seed_draft_batch(jsonb,uuid),public.mefrion_seed_now(uuid,integer,boolean),public.mefrion_seed_cancel(uuid,integer,boolean) to authenticated;
commit;
