begin;
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- A durable, leased unit of work. One media item per Edge invocation keeps
-- image CPU/memory bounded; a restart never loses an accepted publication.
create table mefrion_private.cloud_jobs (
 id uuid primary key default gen_random_uuid(),
 kind text not null check(kind in ('image','video','delete','retirement')),
 entity_id uuid not null,
 object_path text not null default '',
 payload jsonb not null,
 state text not null default 'pending' check(state in ('pending','processing','done','failed','cancelled')),
 attempts integer not null default 0,
 lease_token uuid,lease_until timestamptz,
 available_at timestamptz not null default now(),
 created_at timestamptz not null default now(),completed_at timestamptz,
 error_code text,
 unique(kind,entity_id,object_path)
);
create index cloud_jobs_due on mefrion_private.cloud_jobs(available_at,created_at) where state in ('pending','processing');
alter table mefrion_private.cloud_jobs enable row level security;
revoke all on mefrion_private.cloud_jobs from public,anon,authenticated;

create table mefrion_private.cloud_worker_health (
 name text primary key,last_started timestamptz,last_success timestamptz,
 last_failure timestamptz,runs bigint not null default 0,failures bigint not null default 0
);
alter table mefrion_private.cloud_worker_health enable row level security;
revoke all on mefrion_private.cloud_worker_health from public,anon,authenticated;

create function public.mefrion_cloud_worker_authorize(p_token text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.role()='service_role' and length(p_token)>=32 and exists(
  select 1 from vault.decrypted_secrets where name='mefrion_cloud_worker_token'
  and extensions.digest(decrypted_secret,'sha256')=extensions.digest(p_token,'sha256'))
$$;

create function public.mefrion_cloud_ingest_allowed(p_bucket text,p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.role()='service_role' and case p_bucket
 when 'reference-thumbnails' then exists(select 1 from public.mefrion_reference_assets where file=p_path and not active and withdrawn_at is null)
 when 'family-originals' then exists(select 1 from mefrion_private.photos p
  join mefrion_private.managed_pets m on m.pet_id=p.pet_id
  join mefrion_private.managed_publishers publisher on publisher.id=m.publisher_id and publisher.active
  where p.object_path=p_path and p.state='pending' and m.active and p.provider_id=m.publisher_id)
 else false end
$$;

create function mefrion_private.cloud_job_current(j mefrion_private.cloud_jobs) returns boolean
language sql stable security definer set search_path='' as $$
 select case j.payload->>'flow'
 when 'publication' then exists(
  select 1 from mefrion_private.public_posts s
  join mefrion_private.public_media m on m.post_id=s.id
  join mefrion_private.photos p on p.id=m.source_id
  join mefrion_private.consents c on c.photo_id=p.id and c.purpose=case when s.kind='post' then 'sns' else 'external_share' end
  join mefrion_private.public_profiles f on f.pet_id=s.pet_id and f.enabled
  where s.id=j.entity_id and s.state in ('pending','processing','published') and p.state='ready'
   and c.allowed and c.version=m.consent_version and m.object_path=j.object_path
   and p.object_path=j.payload->>'source_path'
 )
 when 'twins' then mefrion_private.twins_source_valid(j.entity_id)
 when 'twins_share' then mefrion_private.twins_share_other(j.entity_id,null)
 else true end
$$;

create function public.mefrion_cloud_work_get(p_id uuid,p_lease uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare j mefrion_private.cloud_jobs;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 select * into j from mefrion_private.cloud_jobs where id=p_id and lease_token=p_lease and state='processing' and lease_until>now();
 if not found then return null;end if;
 if not mefrion_private.cloud_job_current(j) then
  update mefrion_private.cloud_jobs set state='cancelled',completed_at=now() where id=j.id;
  return null;
 end if;
 return jsonb_build_object('id',j.id,'kind',j.kind,'entity_id',j.entity_id,'path',j.object_path,'payload',j.payload);
end $$;

create function public.mefrion_cloud_work_complete(p_id uuid,p_lease uuid,p_success boolean,p_error text default null,p_cursor integer default null) returns boolean
language plpgsql security definer set search_path='' as $$
declare j mefrion_private.cloud_jobs;finished boolean;flow text;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 select * into j from mefrion_private.cloud_jobs where id=p_id and lease_token=p_lease and state='processing' for update;
 if not found then return false;end if;
 if not p_success then
  update mefrion_private.cloud_jobs set state=case when attempts>=12 then 'failed' else 'pending' end,
   lease_until=null,available_at=now()+make_interval(secs=>least(3600,15*power(2,least(attempts,8))::integer)),
   error_code=left(regexp_replace(coalesce(p_error,'processing_failed'),'[^a-z0-9_]','','g'),80) where id=j.id;
  insert into mefrion_private.cloud_worker_health(name,last_failure,failures) values('process',now(),1)
   on conflict(name) do update set last_failure=now(),failures=mefrion_private.cloud_worker_health.failures+1;
  return true;
 end if;
 if p_cursor is not null then
  if j.kind<>'retirement' or p_cursor<=coalesce((j.payload->>'cursor')::integer,0) then raise exception 'cursor_invalid';end if;
  update mefrion_private.cloud_jobs set state='pending',lease_until=null,attempts=0,
   payload=jsonb_set(payload,'{cursor}',to_jsonb(p_cursor)),available_at=now() where id=j.id;
  return true;
 end if;
 if j.kind in ('image','video') and not mefrion_private.cloud_job_current(j) then
  -- The user may withdraw while a worker is writing, after an older deletion
  -- already ran. Queue the late write as a new deletion instead of orphaning it.
  insert into mefrion_private.deletion_outbox(object_path,bucket) values(j.object_path,'public-derived');
  if j.kind='video' then insert into mefrion_private.deletion_outbox(object_path,bucket) values(left(j.object_path,length(j.object_path)-4)||'.jpg','public-derived');end if;
  update mefrion_private.cloud_jobs set state='cancelled',lease_until=null,completed_at=now() where id=j.id;
  return true;
 end if;
 update mefrion_private.cloud_jobs set state='done',lease_until=null,completed_at=now(),error_code=null where id=j.id;
 flow:=j.payload->>'flow';
 if j.kind in ('image','video') then
  perform pg_advisory_xact_lock(hashtextextended(j.entity_id::text,23));
  if not exists(select 1 from mefrion_private.cloud_jobs where entity_id=j.entity_id and payload->>'flow'=flow and state<>'done') then
   if flow='publication' then finished:=public.mefrion_publication_finish(j.entity_id);
   elsif flow='twins' then finished:=public.mefrion_twins_ready(j.entity_id);
   elsif flow='twins_share' then finished:=public.mefrion_twins_share_ready(j.entity_id);
   end if;
   if finished is false then
    insert into mefrion_private.deletion_outbox(object_path,bucket)
     select object_path,'public-derived' from mefrion_private.cloud_jobs where entity_id=j.entity_id and kind in ('image','video');
    insert into mefrion_private.deletion_outbox(object_path,bucket)
     select left(object_path,length(object_path)-4)||'.jpg','public-derived' from mefrion_private.cloud_jobs where entity_id=j.entity_id and kind='video';
   end if;
  end if;
 end if;
 insert into mefrion_private.cloud_worker_health(name,last_success,runs) values('process',now(),1)
  on conflict(name) do update set last_success=now(),runs=mefrion_private.cloud_worker_health.runs+1;
 return true;
end $$;

create function mefrion_private.cloud_tick() returns jsonb
language plpgsql security definer set search_path='' as $$
declare batch jsonb;j jsonb;m jsonb;claimed mefrion_private.cloud_jobs;
 base text;token text;dispatched integer:=0;seeds integer;
 original_claims text:=current_setting('request.jwt.claims',true);
begin
 if current_setting('mefrion.cloud_tick_running',true)='true' then return jsonb_build_object('busy',true);end if;
 if not pg_try_advisory_xact_lock(230001) then return jsonb_build_object('busy',true);end if;
 select decrypted_secret into base from vault.decrypted_secrets where name='mefrion_project_url';
 select decrypted_secret into token from vault.decrypted_secrets where name='mefrion_cloud_worker_token';
 if base is null or token is null then raise exception 'cloud_worker_not_configured';end if;
 perform set_config('mefrion.cloud_tick_running','true',true);
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 seeds:=public.mefrion_seed_dispatch();
 for j in select * from jsonb_array_elements(public.mefrion_publication_batch()) loop
  for m in select * from jsonb_array_elements(j->'media') loop
   insert into mefrion_private.cloud_jobs(kind,entity_id,object_path,payload)
    values(case when m->>'kind'='video' then 'video' else 'image' end,(j->>'id')::uuid,m->>'path',m||jsonb_build_object('flow','publication')) on conflict do nothing;
  end loop;
 end loop;
 for j in select * from jsonb_array_elements(public.mefrion_twins_batch()) loop
  insert into mefrion_private.cloud_jobs(kind,entity_id,object_path,payload)
   values('image',(j->>'id')::uuid,j->>'path',j||jsonb_build_object('flow','twins')) on conflict do nothing;
 end loop;
 for j in select * from jsonb_array_elements(public.mefrion_twins_share_batch()) loop
  for m in select * from jsonb_array_elements(j->'media') loop
   insert into mefrion_private.cloud_jobs(kind,entity_id,object_path,payload)
    values('image',(j->>'id')::uuid,m->>'path',m||jsonb_build_object('flow','twins_share')) on conflict do nothing;
  end loop;
 end loop;
 for j in select * from jsonb_array_elements(public.mefrion_deletion_batch()) loop
  insert into mefrion_private.cloud_jobs(kind,entity_id,object_path,payload)
   values('delete',(j->>'id')::uuid,j->>'path',j) on conflict do nothing;
 end loop;
 for j in select * from jsonb_array_elements(public.mefrion_retirement_batch()) loop
  insert into mefrion_private.cloud_jobs(kind,entity_id,payload)
   values('retirement',(j->>'user_id')::uuid,j||jsonb_build_object('cursor',0)) on conflict do nothing;
 end loop;
 update mefrion_private.cloud_jobs set state='failed',error_code='lease_exhausted'
  where state='processing' and lease_until<now() and attempts>=12;
 for claimed in
  with picked as(select id from mefrion_private.cloud_jobs where (state='pending' or(state='processing' and lease_until<now())) and available_at<=now() and attempts<12
   order by case kind when 'retirement' then 0 when 'delete' then 1 else 2 end,created_at limit 12 for update skip locked)
  update mefrion_private.cloud_jobs set state='processing',lease_token=gen_random_uuid(),lease_until=now()+interval '3 minutes',attempts=attempts+1
   where id in(select id from picked) returning *
 loop
  perform net.http_post(url:=base||'/functions/v1/cloud-worker',
   headers:=jsonb_build_object('Content-Type','application/json','x-mefrion-worker',token),
   body:=jsonb_build_object('job_id',claimed.id,'lease',claimed.lease_token),timeout_milliseconds:=120000);
  dispatched:=dispatched+1;
 end loop;
 insert into mefrion_private.cloud_worker_health(name,last_started,last_success,runs) values('tick',now(),now(),1)
  on conflict(name) do update set last_started=now(),last_success=now(),runs=mefrion_private.cloud_worker_health.runs+1;
 perform set_config('request.jwt.claims',coalesce(original_claims,''),true);
 perform set_config('mefrion.cloud_tick_running','false',true);
 return jsonb_build_object('dispatched',dispatched,'seeds',seeds);
end $$;

-- Wake immediately after user intent; Cron also retries after network failures
-- or suspended function instances. No Mac or external scheduler participates.
create function mefrion_private.cloud_wake() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.cloud_tick();
 return null;
exception when others then
 -- An unavailable scheduler must never roll back the user's accepted post.
 insert into mefrion_private.cloud_worker_health(name,last_failure,failures) values('wake',now(),1)
  on conflict(name) do update set last_failure=now(),failures=mefrion_private.cloud_worker_health.failures+1;
 return null;
end $$;
-- Defer until all media of the post exist. Waking on public_posts INSERT would
-- see an incomplete carousel inside request_publication's transaction.
create constraint trigger cloud_publication_wake after insert on mefrion_private.public_media
 deferrable initially deferred for each row execute function mefrion_private.cloud_wake();
create trigger cloud_twins_wake after insert on mefrion_private.twins_candidates for each statement execute function mefrion_private.cloud_wake();
create trigger cloud_share_wake after insert on mefrion_private.twins_shares for each statement execute function mefrion_private.cloud_wake();
create trigger cloud_retirement_wake after insert on mefrion_private.account_retirements for each statement execute function mefrion_private.cloud_wake();

create function public.mefrion_cloud_worker_status() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 return jsonb_build_object('jobs',(select coalesce(jsonb_object_agg(state,n),'{}') from(select state,count(*) n from mefrion_private.cloud_jobs group by state) q),
  'health',(select coalesce(jsonb_agg(to_jsonb(h)),'[]') from mefrion_private.cloud_worker_health h),
  'oldest_pending',(select min(created_at) from mefrion_private.cloud_jobs where state in ('pending','processing','failed')));
end $$;
revoke all on function mefrion_private.cloud_job_current(mefrion_private.cloud_jobs),mefrion_private.cloud_tick(),mefrion_private.cloud_wake() from public,anon,authenticated;
revoke all on function public.mefrion_cloud_work_get(uuid,uuid),public.mefrion_cloud_work_complete(uuid,uuid,boolean,text,integer),public.mefrion_cloud_worker_status(),public.mefrion_cloud_worker_authorize(text),public.mefrion_cloud_ingest_allowed(text,text) from public,anon,authenticated;
grant execute on function public.mefrion_cloud_work_get(uuid,uuid),public.mefrion_cloud_work_complete(uuid,uuid,boolean,text,integer),public.mefrion_cloud_worker_status(),public.mefrion_cloud_worker_authorize(text),public.mefrion_cloud_ingest_allowed(text,text) to service_role;

select cron.schedule('mefrion-cloud-workers','* * * * *','select mefrion_private.cloud_tick();');
commit;
