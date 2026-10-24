begin;
-- Private, operator-configured catalogue. No client may add/approve stock assets.
create table mefrion_private.stock_policy(
 singleton boolean primary key default true check(singleton),enabled boolean not null default false,
 publisher uuid references auth.users(id),target integer not null default 1000 check(target between 1 and 2000),
 daily integer not null default 100 check(daily between 0 and 200),initialized boolean not null default false,
 last_day date,updated_at timestamptz not null default now());
insert into mefrion_private.stock_policy(singleton) values(true);
create table mefrion_private.stock_catalog(
 asset_id text primary key references public.mefrion_reference_assets(id),name text not null check(length(name) between 1 and 40),
 breed text not null default '' check(length(breed)<=100),rights_until timestamptz not null,
 evidence text not null,enabled boolean not null default true,last_used timestamptz,pet_id uuid references mefrion_private.pets(id));
create table mefrion_private.stock_runs(
 id uuid primary key default gen_random_uuid(),day date not null,kind text not null check(kind in('bootstrap','daily')),
 goal integer not null check(goal between 0 and 2000),state text not null default 'working' check(state in('working','done')),
 created_at timestamptz not null default now(),completed_at timestamptz,unique(day,kind));
create table mefrion_private.stock_tasks(
 id uuid primary key default gen_random_uuid(),run_id uuid not null references mefrion_private.stock_runs(id),
 asset_id text not null references mefrion_private.stock_catalog(asset_id),pet_id uuid not null references mefrion_private.pets(id),
 photo_id uuid not null default gen_random_uuid(),post_id uuid not null default gen_random_uuid(),media_id uuid not null default gen_random_uuid(),
 state text not null default 'pending' check(state in('pending','processing','done','cancelled','failed')),
 lease uuid,lease_until timestamptz,attempts integer not null default 0,error_code text,
 victim uuid references mefrion_private.public_posts(id),created_at timestamptz not null default now(),completed_at timestamptz,
 unique(run_id,asset_id),unique(post_id));
create unique index stock_asset_inflight on mefrion_private.stock_tasks(asset_id) where state in('pending','processing');
create index stock_due on mefrion_private.stock_tasks(created_at) where state in('pending','processing');
alter table mefrion_private.stock_policy enable row level security;
alter table mefrion_private.stock_catalog enable row level security;
alter table mefrion_private.stock_runs enable row level security;
alter table mefrion_private.stock_tasks enable row level security;
revoke all on mefrion_private.stock_policy,mefrion_private.stock_catalog,mefrion_private.stock_runs,mefrion_private.stock_tasks from public,anon,authenticated;

-- Share row locks with rotation before testing visibility. A racing like/comment
-- either protects the old post, or sees its committed removal and is rejected.
alter function public.mefrion_react(uuid,text,boolean) set schema mefrion_private;
alter function mefrion_private.mefrion_react(uuid,text,boolean) rename to stock_react_core;
revoke all on function mefrion_private.stock_react_core(uuid,text,boolean) from public,anon,authenticated;
create function public.mefrion_react(p_post uuid,p_kind text,p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 perform 1 from mefrion_private.public_posts where id=p_post for update;
 return mefrion_private.stock_react_core(p_post,p_kind,p_enabled);
end $$;
alter function public.mefrion_comment(uuid,text,uuid,uuid,uuid) set schema mefrion_private;
alter function mefrion_private.mefrion_comment(uuid,text,uuid,uuid,uuid) rename to stock_comment_core;
revoke all on function mefrion_private.stock_comment_core(uuid,text,uuid,uuid,uuid) from public,anon,authenticated;
create function public.mefrion_comment(p_post uuid,p_body text,p_parent uuid,p_alias_pet uuid,p_request_key uuid) returns uuid
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 perform 1 from mefrion_private.public_posts where id=p_post for update;
 return mefrion_private.stock_comment_core(p_post,p_body,p_parent,p_alias_pet,p_request_key);
end $$;
revoke all on function public.mefrion_react(uuid,text,boolean),public.mefrion_comment(uuid,text,uuid,uuid,uuid) from public,anon;
grant execute on function public.mefrion_react(uuid,text,boolean),public.mefrion_comment(uuid,text,uuid,uuid,uuid) to authenticated;

-- Service may enable only profiles reserved by the reviewed stock catalogue.
create or replace function mefrion_private.public_write_gate() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='public_posts' then
  if auth.role()='service_role' and new.content_origin='managed_seed' then
   if not exists(select 1 from mefrion_private.seed_jobs j join mefrion_private.managed_pets m on m.pet_id=j.pet_id where j.post_id=new.id and j.state='dispatching' and j.pet_id=new.pet_id and j.body=new.body and new.kind='post' and new.actor_id=m.publisher_id and mefrion_private.managed_public_ready(m.pet_id)) then raise exception 'approved_seed_dispatch_required';end if;
  else perform mefrion_private.require_public_actor();end if;
 elsif new.enabled then
  if not (auth.role()='service_role' and exists(select 1 from mefrion_private.stock_tasks t
    join mefrion_private.stock_catalog c on c.asset_id=t.asset_id and c.enabled and c.rights_until>now()
    join mefrion_private.stock_policy policy on policy.singleton and policy.enabled
    join mefrion_private.managed_pets m on m.pet_id=t.pet_id and m.publisher_id=policy.publisher
    where t.pet_id=new.pet_id and t.state='processing')) then perform mefrion_private.require_public_actor();end if;
 end if;
 return new;
end $$;

create function mefrion_private.stock_cancel(p_task uuid) returns void
language plpgsql security definer set search_path='' as $$
declare t mefrion_private.stock_tasks;
begin
 select * into t from mefrion_private.stock_tasks where id=p_task for update;
 if not found or t.state in('done','cancelled') then return;end if;
 update mefrion_private.stock_tasks set state='cancelled',completed_at=now(),lease_until=null where id=t.id;
 insert into mefrion_private.deletion_outbox(object_path,bucket) values
  (t.pet_id::text||'/'||t.photo_id::text||'.jpg','family-originals'),(t.media_id::text||'.jpg','public-derived');
end $$;
revoke all on function mefrion_private.stock_cancel(uuid) from public,anon,authenticated;

create function mefrion_private.stock_zero(p_post uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.public_posts p where p.id=p_post and p.content_origin='managed_seed' and p.kind='post' and p.state='published')
 and not exists(select 1 from mefrion_private.reactions where post_id=p_post and kind='like')
 and not exists(select 1 from mefrion_private.social_comments where post_id=p_post and state='active')
$$;

create function mefrion_private.stock_plan() returns void
language plpgsql security definer set search_path='' as $$
declare policy mefrion_private.stock_policy;r mefrion_private.stock_runs;a record;pet uuid;live integer;n integer;today date:=(now() at time zone 'Asia/Tokyo')::date;
begin
 if not pg_try_advisory_xact_lock(240001) then return;end if;
 select * into policy from mefrion_private.stock_policy where singleton for update;
 if not policy.enabled or policy.publisher is null then return;end if;
 -- Fail closed before Free plan safety margins; never upgrades a plan.
 if pg_database_size(current_database())>350*1024*1024 or (select coalesce(sum((metadata->>'size')::bigint),0) from storage.objects)>800*1024*1024 then return;end if;
 select * into r from mefrion_private.stock_runs where state='working' order by created_at limit 1;
 if not found then
  select count(*) into live from mefrion_private.public_posts p where p.content_origin='managed_seed' and p.kind='post' and mefrion_private.post_allowed(p.id,null);
  if (not policy.initialized) or (live<policy.target and not exists(select 1 from mefrion_private.stock_runs where day=today and kind='bootstrap')) then
   n:=greatest(0,policy.target-live);
   insert into mefrion_private.stock_runs(day,kind,goal) values(today,'bootstrap',n) returning * into r;
   update mefrion_private.stock_policy set initialized=true,last_day=today where singleton;
  elsif today>policy.last_day and (now() at time zone 'Asia/Tokyo')::time>='00:05' then
   select least(policy.daily,count(*)) into n from mefrion_private.public_posts p where mefrion_private.stock_zero(p.id);
   insert into mefrion_private.stock_runs(day,kind,goal) values(today,'daily',n) returning * into r;
   update mefrion_private.stock_policy set last_day=today where singleton;
  else return;end if;
 end if;
 -- Retried tasks are counted, so re-entering a minute cannot add duplicates.
 select r.goal-count(*) into n from mefrion_private.stock_tasks where run_id=r.id;
 for a in select c.*,ref.species from mefrion_private.stock_catalog c join public.mefrion_reference_assets ref on ref.id=c.asset_id
   where c.enabled and c.rights_until>now() and ref.active and ref.withdrawn_at is null and ref.species in('dog','cat')
   and exists(select 1 from storage.objects o where o.bucket_id='reference-thumbnails' and o.name=ref.file)
   and not exists(select 1 from mefrion_private.stock_tasks t where t.asset_id=c.asset_id and
    (t.state in('pending','processing') or (t.state='done' and exists(select 1 from mefrion_private.public_posts p where p.id=t.post_id and p.state='published'))))
   and not exists(select 1 from mefrion_private.stock_tasks t where t.asset_id=c.asset_id and t.run_id=r.id)
   order by c.last_used nulls first,md5(c.asset_id||r.id::text) limit greatest(0,least(n,40))
 loop
  pet:=a.pet_id;
  if pet is null then
   insert into mefrion_private.pets(owner_id,name,species,breed,introduction) values(policy.publisher,a.name,a.species,a.breed,'') returning id into pet;
   insert into mefrion_private.managed_pets(pet_id,publisher_id,external_key,source_note,rights_note,rights_until,rights_verified,updated_by)
    values(pet,policy.publisher,'stock-cycle-'||a.asset_id,a.evidence,'Owner-approved licensed Pexels stock catalogue',a.rights_until,true,policy.publisher);
   update mefrion_private.stock_catalog set pet_id=pet where asset_id=a.asset_id;
  end if;
  insert into mefrion_private.stock_tasks(run_id,asset_id,pet_id) values(r.id,a.asset_id,pet);
 end loop;
 if not exists(select 1 from mefrion_private.stock_tasks where run_id=r.id and state in('pending','processing','failed'))
  and (select count(*) from mefrion_private.stock_tasks where run_id=r.id)>=r.goal then
   update mefrion_private.stock_runs set state='done',completed_at=now() where id=r.id;
 end if;
end $$;

create function public.mefrion_stock_batch() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 perform mefrion_private.stock_plan();
 with picked as(select id from mefrion_private.stock_tasks where state='pending' or(state='processing' and lease_until<now() and attempts<12) order by created_at limit 20 for update skip locked),
 claimed as(update mefrion_private.stock_tasks set state='processing',lease=gen_random_uuid(),lease_until=now()+interval '3 minutes',attempts=attempts+1 where id in(select id from picked) returning *)
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'lease',t.lease,'reference_path',a.file,
  'original_path',t.pet_id::text||'/'||t.photo_id::text||'.jpg','public_path',t.media_id::text||'.jpg')),'[]') into result
 from claimed t join public.mefrion_reference_assets a on a.id=t.asset_id;
 return result;
end $$;

create function public.mefrion_stock_complete(p_task uuid,p_lease uuid,p_success boolean,p_error text default null) returns boolean
language plpgsql security definer set search_path='' as $$
declare t mefrion_private.stock_tasks;a mefrion_private.stock_catalog;ref public.mefrion_reference_assets;r mefrion_private.stock_runs;publisher uuid;v_victim uuid;v integer;old_running text:=current_setting('mefrion.cloud_tick_running',true);source_path text;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(240001);
 select * into t from mefrion_private.stock_tasks where id=p_task and lease=p_lease for update;
 if not found then return false;end if;
 if t.state='done' then return true;end if;
 if t.state<>'processing' or t.lease_until<now() then return false;end if;
 if not p_success then
  update mefrion_private.stock_tasks set state=case when attempts>=12 then 'failed' else 'pending' end,lease_until=null,error_code=left(regexp_replace(coalesce(p_error,'copy_failed'),'[^a-z0-9_]','','g'),80) where id=t.id;
  return false;
 end if;
 select * into a from mefrion_private.stock_catalog where asset_id=t.asset_id;
 select * into ref from public.mefrion_reference_assets where id=t.asset_id;
 select * into r from mefrion_private.stock_runs where id=t.run_id;
 select p.publisher into publisher from mefrion_private.stock_policy p where singleton and enabled;
 if publisher is null or not a.enabled or a.rights_until<=now() or not ref.active or ref.withdrawn_at is not null then
  perform mefrion_private.stock_cancel(t.id);return false;
 end if;
 source_path:=t.pet_id::text||'/'||t.photo_id::text||'.jpg';
 if not exists(select 1 from storage.objects where bucket_id='family-originals' and name=source_path and (metadata->>'size')::bigint between 100 and 200000)
  or not exists(select 1 from storage.objects where bucket_id='public-derived' and name=t.media_id::text||'.jpg' and (metadata->>'size')::bigint between 100 and 200000) then raise exception 'stock_objects_missing';end if;
 if r.kind='daily' then
  select p.id into v_victim from mefrion_private.public_posts p where mefrion_private.stock_zero(p.id) and p.published_at<=r.created_at order by p.published_at,p.id limit 1 for update;
  -- Re-evaluate after acquiring the same lock used by react/comment RPCs.
  if v_victim is null or not mefrion_private.stock_zero(v_victim) then
   perform mefrion_private.stock_cancel(t.id);return false;
  end if;
 else
  if (select count(*) from mefrion_private.public_posts p where p.content_origin='managed_seed' and p.kind='post' and mefrion_private.post_allowed(p.id,null)) >= (select target from mefrion_private.stock_policy where singleton) then
   perform mefrion_private.stock_cancel(t.id);return false;
  end if;
 end if;
 perform set_config('mefrion.cloud_tick_running','true',true);
 insert into mefrion_private.photos(id,pet_id,provider_id,object_path,request_key,captured,title,state,ready_at,album_visible)
  values(t.photo_id,t.pet_id,publisher,source_path,t.id,(now() at time zone 'Asia/Tokyo')::date::text,left(ref.credit,200),'ready',now(),false);
 insert into mefrion_private.managed_photo_rights(photo_id,holder,scope,evidence,checked_by,expires_at,allowed)
  values(t.photo_id,left(ref.credit,200),'Licensed stock photo in MEFRION public feed',a.evidence,publisher,a.rights_until,true);
 insert into mefrion_private.seed_jobs(pet_id,created_by,request_key,body,photos,state,approved_by,post_id)
  values(t.pet_id,publisher,t.id,'',array[t.photo_id],'dispatching',publisher,t.post_id);
 insert into mefrion_private.public_profiles(pet_id,enabled) values(t.pet_id,true) on conflict(pet_id) do update set enabled=true;
 insert into mefrion_private.public_posts(id,pet_id,actor_id,request_key,body,kind,state,content_origin)
  values(t.post_id,t.pet_id,publisher,t.id,'','post','processing','managed_seed');
 insert into mefrion_private.consents(photo_id,purpose,allowed) values(t.photo_id,'sns',true) returning version into v;
 insert into mefrion_private.public_media(id,post_id,source_id,consent_version,position,object_path)
  values(t.media_id,t.post_id,t.photo_id,v,0,t.media_id::text||'.jpg');
 if not public.mefrion_publication_finish(t.post_id) then raise exception 'stock_publication_failed';end if;
 if v_victim is not null then
  perform mefrion_private.stop_publication(v_victim);
  -- Only retired managed originals, never a customer's family media.
  insert into mefrion_private.deletion_outbox(object_path,bucket)
   select p.object_path,'family-originals' from mefrion_private.photos p join mefrion_private.public_media m on m.source_id=p.id
   where m.post_id=v_victim and not exists(select 1 from mefrion_private.public_media other join mefrion_private.public_posts live on live.id=other.post_id where other.source_id=p.id and live.state in('published','pending','processing'));
  update mefrion_private.photos p set state='deleted' where p.id in(select source_id from mefrion_private.public_media where post_id=v_victim)
   and not exists(select 1 from mefrion_private.public_media other join mefrion_private.public_posts live on live.id=other.post_id where other.source_id=p.id and live.state in('published','pending','processing'));
 end if;
 update mefrion_private.stock_tasks set state='done',victim=v_victim,completed_at=now(),lease_until=null,error_code=null where id=t.id;
 update mefrion_private.stock_catalog set last_used=now() where asset_id=t.asset_id;
 perform set_config('mefrion.cloud_tick_running',coalesce(old_running,'false'),true);
 return true;
end $$;

create function mefrion_private.stock_tick() returns void
language plpgsql security definer set search_path='' as $$
declare base text;token text;
begin
 if not exists(select 1 from mefrion_private.stock_policy where singleton and enabled) then return;end if;
 select decrypted_secret into base from vault.decrypted_secrets where name='mefrion_project_url';
 select decrypted_secret into token from vault.decrypted_secrets where name='mefrion_cloud_worker_token';
 if base is null or token is null then raise exception 'stock_worker_not_configured';end if;
 perform net.http_post(url:=base||'/functions/v1/stock-worker',headers:=jsonb_build_object('Content-Type','application/json','x-mefrion-worker',token),body:='{}'::jsonb,timeout_milliseconds:=120000);
end $$;
revoke all on function mefrion_private.stock_zero(uuid),mefrion_private.stock_plan(),mefrion_private.stock_tick() from public,anon,authenticated;
revoke all on function public.mefrion_stock_batch(),public.mefrion_stock_complete(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.mefrion_stock_batch(),public.mefrion_stock_complete(uuid,uuid,boolean,text) to service_role;
select cron.schedule('mefrion-stock-cycle','* * * * *','select mefrion_private.stock_tick()');
commit;
