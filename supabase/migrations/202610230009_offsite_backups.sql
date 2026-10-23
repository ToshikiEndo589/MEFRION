begin;
create table mefrion_private.offsite_runs(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),completed_at timestamptz,state text not null default 'pending',snapshot_base64 text,inventory jsonb not null,snapshot_sha text,manifest_sha text,lease uuid,lease_until timestamptz,attempts integer not null default 0,error_code text);
create table mefrion_private.offsite_objects(fingerprint text primary key,bucket text not null,path text not null,bytes bigint not null,state text not null default 'pending',plain_sha text,cipher_sha text,last_seen timestamptz not null default now(),lease uuid,lease_until timestamptz,attempts integer not null default 0,error_code text);
alter table mefrion_private.offsite_runs enable row level security;
alter table mefrion_private.offsite_objects enable row level security;
revoke all on mefrion_private.offsite_runs,mefrion_private.offsite_objects from public,anon,authenticated;

-- All table rows and Storage metadata are read by ONE SQL statement. No media
-- bytes or plaintext account data are sent to the independent destination.
create function mefrion_private.offsite_capture() returns uuid language plpgsql security definer set search_path='' as $$
declare t record;parts text[]:=array[]::text[];tables jsonb;inventory jsonb;doc text;backup_key text;run_id uuid;obj jsonb;
begin
 for t in select schemaname,tablename from pg_catalog.pg_tables where
 (schemaname='mefrion_private' and tablename not in('cloud_jobs','cloud_worker_health','offsite_runs','offsite_objects')) or
 (schemaname='auth' and tablename in('users','identities','mfa_factors')) or
 (schemaname='storage' and tablename in('buckets','objects')) order by schemaname,tablename loop
  parts:=array_append(parts,format('select %L as name,coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) as rows from (select * from %I.%I%s) x',t.schemaname||'.'||t.tablename,t.schemaname,t.tablename,case when t.schemaname='storage' and t.tablename='objects' then ' where bucket_id in (''family-originals'',''public-derived'')' else '' end));
 end loop;
 execute 'select jsonb_object_agg(name,rows) from ('||array_to_string(parts,' union all ')||') tables' into tables;
 select coalesce(jsonb_agg(jsonb_build_object('fingerprint',encode(extensions.digest(x::text,'sha256'),'hex'),'bucket',x->>'bucket_id','path',x->>'name','bytes',coalesce((x->'metadata'->>'size')::bigint,0))),'[]') into inventory from jsonb_array_elements(tables->'storage.objects') x;
 doc:=jsonb_build_object('format','mefrion-offsite-v1','created_at',now(),'tables',tables)::text;
 if octet_length(doc)>8388608 then raise exception 'backup_snapshot_limit';end if;
 select decrypted_secret into backup_key from vault.decrypted_secrets where name='mefrion_database_backup_key';
 if backup_key is null then raise exception 'backup_key_missing';end if;
 insert into mefrion_private.offsite_runs(snapshot_base64,inventory) values(encode(extensions.pgp_sym_encrypt(doc,backup_key,'cipher-algo=aes256,compress-algo=1'),'base64'),inventory) returning id into run_id;
 for obj in select * from jsonb_array_elements(inventory) loop
  insert into mefrion_private.offsite_objects(fingerprint,bucket,path,bytes) values(obj->>'fingerprint',obj->>'bucket',obj->>'path',(obj->>'bytes')::bigint)
   on conflict(fingerprint) do update set last_seen=now();
 end loop;
 return run_id;
end $$;

create function public.mefrion_offsite_configuration() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 return (select jsonb_object_agg(name,decrypted_secret) from vault.decrypted_secrets where name in('mefrion_offsite_url','mefrion_offsite_token','mefrion_offsite_aes_key'));
end $$;

create function public.mefrion_offsite_next() returns jsonb language plpgsql security definer set search_path='' set statement_timeout='60s' as $$
declare r mefrion_private.offsite_runs;o mefrion_private.offsite_objects;l uuid:=gen_random_uuid();result jsonb;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 if not pg_try_advisory_xact_lock(230009) then return null;end if;
 update mefrion_private.offsite_runs set state='failed',error_code='attempts_exhausted' where state in('pending','snapshot_done') and attempts>=12 and coalesce(lease_until,now())<=now();
 update mefrion_private.offsite_objects set state='failed',error_code='attempts_exhausted' where state='pending' and attempts>=12 and coalesce(lease_until,now())<=now();
 update mefrion_private.offsite_runs rr set state='failed',error_code='object_failed' where state='snapshot_done' and exists(select 1 from mefrion_private.offsite_objects ob where ob.state='failed' and rr.inventory @> jsonb_build_array(jsonb_build_object('fingerprint',ob.fingerprint)));
 if not exists(select 1 from mefrion_private.offsite_runs where created_at>now()-interval '1 day') then perform mefrion_private.offsite_capture();end if;
 select * into r from mefrion_private.offsite_runs where state in('pending','snapshot_done') order by created_at limit 1 for update;
 if found then
  if r.state='pending' then
   if r.lease_until>now() then return null;end if;
   update mefrion_private.offsite_runs set lease=l,lease_until=now()+interval '3 minutes',attempts=attempts+1 where id=r.id;
   return jsonb_build_object('kind','snapshot','id',r.id,'lease',l,'key','production/snapshots/'||r.id||'.bin','snapshot',r.snapshot_base64);
  end if;
  select ob.* into o from mefrion_private.offsite_objects ob where ob.fingerprint in(select x->>'fingerprint' from jsonb_array_elements(r.inventory) x) and ob.state='pending' and coalesce(ob.lease_until,now())<=now() and ob.attempts<12 order by ob.bytes limit 1 for update;
  if found then
   update mefrion_private.offsite_objects set lease=l,lease_until=now()+interval '3 minutes',attempts=attempts+1 where fingerprint=o.fingerprint;
   return jsonb_build_object('kind','object','id',o.fingerprint,'lease',l,'key','production/objects/'||o.fingerprint||'.bin','bucket',o.bucket,'path',o.path,'bytes',o.bytes);
  end if;
  if exists(select 1 from mefrion_private.offsite_objects ob where ob.fingerprint in(select x->>'fingerprint' from jsonb_array_elements(r.inventory) x) and ob.state<>'done') then return null;end if;
  if r.lease_until>now() then return null;end if;
  update mefrion_private.offsite_runs set lease=l,lease_until=now()+interval '3 minutes',attempts=attempts+1 where id=r.id;
  select coalesce(jsonb_agg(x||jsonb_build_object('key','production/objects/'||ob.fingerprint||'.bin','plain_sha',ob.plain_sha,'cipher_sha',ob.cipher_sha) order by ob.fingerprint),'[]') into result from jsonb_array_elements(r.inventory) x join mefrion_private.offsite_objects ob on ob.fingerprint=x->>'fingerprint';
  return jsonb_build_object('kind','manifest','id',r.id,'lease',l,'key','production/manifests/'||r.id||'.bin','manifest',jsonb_build_object('format','mefrion-offsite-v1','id',r.id,'created_at',r.created_at,'snapshot_key','production/snapshots/'||r.id||'.bin','snapshot_sha',r.snapshot_sha,'objects',result));
 end if;
 -- Bound retention to seven days, even after an account or photo is deleted.
 select * into r from mefrion_private.offsite_runs where created_at<now()-interval '7 days' and coalesce(lease_until,now())<=now() order by created_at limit 1 for update;
 if found then
  update mefrion_private.offsite_runs set lease=l,lease_until=now()+interval '3 minutes' where id=r.id;
  return jsonb_build_object('kind','prune_run','id',r.id,'lease',l,'keys',jsonb_build_array('production/snapshots/'||r.id||'.bin','production/manifests/'||r.id||'.bin'));
 end if;
 select * into o from mefrion_private.offsite_objects ob where last_seen<now()-interval '7 days' and coalesce(lease_until,now())<=now() and not exists(select 1 from mefrion_private.offsite_runs rr where rr.inventory @> jsonb_build_array(jsonb_build_object('fingerprint',ob.fingerprint))) limit 1 for update;
 if found then
  update mefrion_private.offsite_objects set lease=l,lease_until=now()+interval '3 minutes' where fingerprint=o.fingerprint;
  return jsonb_build_object('kind','prune_object','id',o.fingerprint,'lease',l,'keys',jsonb_build_array('production/objects/'||o.fingerprint||'.bin'));
 end if;
 return null;
end $$;

create function public.mefrion_offsite_complete(p_kind text,p_id text,p_lease uuid,p_success boolean,p_plain_sha text default null,p_cipher_sha text default null) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 if p_kind in('object','prune_object') then
  perform 1 from mefrion_private.offsite_objects where fingerprint=p_id and lease=p_lease for update;if not found then return false;end if;
  if p_success and p_kind='prune_object' then delete from mefrion_private.offsite_objects where fingerprint=p_id;
  else update mefrion_private.offsite_objects set state=case when p_success then 'done' else 'pending' end,plain_sha=p_plain_sha,cipher_sha=p_cipher_sha,error_code=case when p_success then null else 'transfer_failed' end,lease=null,lease_until=case when p_success then null else now()+interval '5 minutes' end where fingerprint=p_id;end if;
 else
  perform 1 from mefrion_private.offsite_runs where id=p_id::uuid and lease=p_lease for update;if not found then return false;end if;
  if p_success and p_kind='prune_run' then delete from mefrion_private.offsite_runs where id=p_id::uuid;
  else update mefrion_private.offsite_runs set state=case when not p_success then state when p_kind='snapshot' then 'snapshot_done' else 'complete' end,snapshot_sha=case when p_kind='snapshot' then p_cipher_sha else snapshot_sha end,manifest_sha=case when p_kind='manifest' then p_cipher_sha else manifest_sha end,snapshot_base64=case when p_success and p_kind='manifest' then null else snapshot_base64 end,completed_at=case when p_success and p_kind='manifest' then now() else completed_at end,error_code=case when p_success then null else 'transfer_failed' end,lease=null,lease_until=case when p_success then null else now()+interval '5 minutes' end where id=p_id::uuid;end if;
 end if;
 if p_success and p_kind='manifest' then insert into mefrion_private.cloud_worker_health(name,last_success,runs) values('offsite-backup',now(),1) on conflict(name) do update set last_success=now(),runs=mefrion_private.cloud_worker_health.runs+1;end if;
 if not p_success then insert into mefrion_private.cloud_worker_health(name,last_failure,failures) values('offsite-backup',now(),1) on conflict(name) do update set last_failure=now(),failures=mefrion_private.cloud_worker_health.failures+1;end if;
 return true;
end $$;
create function mefrion_private.offsite_dispatch() returns bigint language plpgsql security definer set search_path='' as $$
declare base text;token text;
begin
 select decrypted_secret into base from vault.decrypted_secrets where name='mefrion_project_url';
 select decrypted_secret into token from vault.decrypted_secrets where name='mefrion_cloud_worker_token';
 return net.http_post(url:=base||'/functions/v1/offsite-backup',headers:=jsonb_build_object('Content-Type','application/json','x-mefrion-worker',token),body:='{}',timeout_milliseconds:=120000);
end $$;
revoke all on function mefrion_private.offsite_capture(),mefrion_private.offsite_dispatch(),public.mefrion_offsite_configuration(),public.mefrion_offsite_next(),public.mefrion_offsite_complete(text,text,uuid,boolean,text,text) from public,anon,authenticated;
grant execute on function public.mefrion_offsite_configuration(),public.mefrion_offsite_next(),public.mefrion_offsite_complete(text,text,uuid,boolean,text,text) to service_role;
-- Enable scheduling only after the destination passes a real upload/readback.
commit;
