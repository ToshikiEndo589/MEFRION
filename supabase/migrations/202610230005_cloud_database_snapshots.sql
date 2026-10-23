begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('system-backups','system-backups',false,16777216,array['application/octet-stream']) on conflict(id) do nothing;

-- A transaction-consistent encrypted logical snapshot of account/application
-- rows. Stock vectors are reproducible and excluded. Storage file bytes are
-- NOT included: this is not an independent disaster-recovery backup.
create function public.mefrion_cloud_database_snapshot() returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='60s' as $$
declare t record;rows jsonb;tables jsonb:='{}';counts jsonb:='{}';document text;key text;encrypted bytea;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 select decrypted_secret into key from vault.decrypted_secrets where name='mefrion_database_backup_key';
 if key is null then raise exception 'backup_key_missing';end if;
 for t in select schemaname,tablename from pg_catalog.pg_tables
  where (schemaname='mefrion_private' and tablename not in ('cloud_jobs','cloud_worker_health'))
    or(schemaname='auth' and tablename in ('users','identities','mfa_factors'))
  order by schemaname,tablename
 loop
  execute format('select coalesce(jsonb_agg(to_jsonb(source)),''[]''::jsonb) from %I.%I source',t.schemaname,t.tablename) into rows;
  tables:=tables||jsonb_build_object(t.schemaname||'.'||t.tablename,rows);
  counts:=counts||jsonb_build_object(t.schemaname||'.'||t.tablename,jsonb_array_length(rows));
  if octet_length(tables::text)>8388608 then raise exception 'backup_size_limit';end if;
 end loop;
 document:=jsonb_build_object('format','mefrion-database-v1','created_at',now(),'tables',tables)::text;
 encrypted:=extensions.pgp_sym_encrypt(document,key,'cipher-algo=aes256,compress-algo=1');
 return jsonb_build_object('encrypted_base64',encode(encrypted,'base64'),'table_counts',counts,'plaintext_bytes',octet_length(document));
end $$;

create function public.mefrion_cloud_backup_finish(p_success boolean,p_bytes integer default 0) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 if p_success then
  insert into mefrion_private.cloud_worker_health(name,last_success,runs) values('database-snapshot',now(),1)
   on conflict(name) do update set last_success=now(),runs=mefrion_private.cloud_worker_health.runs+1;
 else
  insert into mefrion_private.cloud_worker_health(name,last_failure,failures) values('database-snapshot',now(),1)
   on conflict(name) do update set last_failure=now(),failures=mefrion_private.cloud_worker_health.failures+1;
 end if;
end $$;

create function mefrion_private.cloud_backup_dispatch() returns bigint
language plpgsql security definer set search_path='' as $$
declare base text;token text;
begin
 select decrypted_secret into base from vault.decrypted_secrets where name='mefrion_project_url';
 select decrypted_secret into token from vault.decrypted_secrets where name='mefrion_cloud_worker_token';
 if base is null or token is null then raise exception 'cloud_worker_not_configured';end if;
 return net.http_post(url:=base||'/functions/v1/database-backup',headers:=jsonb_build_object('Content-Type','application/json','x-mefrion-worker',token),body:='{}',timeout_milliseconds:=120000);
end $$;
revoke all on function public.mefrion_cloud_database_snapshot(),public.mefrion_cloud_backup_finish(boolean,integer),mefrion_private.cloud_backup_dispatch() from public,anon,authenticated;
grant execute on function public.mefrion_cloud_database_snapshot(),public.mefrion_cloud_backup_finish(boolean,integer) to service_role;
select cron.schedule('mefrion-database-snapshot','30 18 * * *','select mefrion_private.cloud_backup_dispatch();');
commit;
