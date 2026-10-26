begin;
alter table mefrion_private.security_settings add column window_start timestamptz not null default date_trunc('minute',now()),add column window_events integer not null default 0;
create or replace function mefrion_private.security_record(p_source text,p_event jsonb,p_ip text default null,p_lost integer default 0) returns boolean
language plpgsql security definer set search_path='' as $$
declare t timestamptz:=clock_timestamp(); k text;v text;o text;dest text;code integer;
 ident uuid;sk text;pep bytea;address inet;country text;trace text;inserted boolean;amount bigint;
begin
 if p_source is null or p_source not in('vercel','edge:private-image','edge:private-video','edge:public-image','edge:public-video','edge:shared-page','edge:cloud-worker','edge:stock-worker','edge:asset-ingest','edge:database-backup','edge:offsite-backup','app_audit') then raise exception 'invalid_security_source';end if;
 if p_lost is null or p_lost not between 0 and 100000 then raise exception 'invalid_loss_count';end if;
 if not pg_try_advisory_xact_lock(260026) then return false;end if;
 insert into mefrion_private.security_sources(source,last_seen,lost) values(p_source,t,p_lost)
 on conflict(source) do update set last_seen=t,lost=mefrion_private.security_sources.lost+excluded.lost;
 if p_event is null or p_event='null'::jsonb then return true;end if;
 -- Global per-minute budget bounds storage/aggregation under distributed noise.
 update mefrion_private.security_settings set window_start=date_trunc('minute',t),window_events=0 where singleton and window_start<date_trunc('minute',t);
 update mefrion_private.security_settings set window_events=window_events+1 where singleton and window_events<6000;
 if not found then return false;end if;
 if pg_column_size(p_event)>4000 then raise exception 'event_too_large';end if;
 k:=p_event->>'kind';v:=p_event->>'severity';o:=p_event->>'outcome';dest:=p_event->>'target';
 if k is null or v is null or o is null or k not in('secret_probe','path_traversal','injection_probe','auth_denied','access_denied','rate_limited','not_found','method_denied','server_error','profile_changed','account_retirement','operator_changed') or v not in('info','low','medium','high','critical') or o not in('observed','denied','limited','failed','allowed') then raise exception 'event_invalid';end if;
 if dest is null or dest not in('/','/privacy','/terms','/console','/console/config.json','/console/cloud.js','/console/security.js','/console/security.css','/console/security','/healthz','/cloud-shared/:id','/cloud-development-shared/:id','/[unknown]','/[secret-probe]','/[traversal]','/[injection]','/functions/private-image','/functions/private-video','/functions/public-image','/functions/public-video','/functions/shared-page','/functions/cloud-worker','/functions/stock-worker','/functions/asset-ingest','/functions/database-backup','/functions/offsite-backup','/account','/profile','/operator') then raise exception 'invalid_security_target';end if;
 begin ident:=(p_event->>'id')::uuid;code:=(p_event->>'status')::integer;
 exception when others then raise exception 'event_invalid';end;
 if ident is null or code is null or code not between 100 and 599 then raise exception 'event_invalid';end if;
 select pepper into pep from mefrion_private.security_settings where singleton;
 begin address:=nullif(left(p_ip,64),'')::inet;exception when others then address:=null;end;
 sk:=case when address is null then 'unavailable' else 'src_'||left(encode(extensions.hmac(convert_to((date_trunc('week',t) at time zone 'UTC')::date::text||':'||case when family(address)=6 then set_masklen(address,64)::cidr::text else host(address) end,'UTF8'),pep,'sha256'),'hex'),24) end;
 country:=p_event->>'country';if country!~'^[A-Z]{2}$' then country:=null;end if;
 trace:=p_event->>'request_id';if trace is null or trace!~'^[A-Za-z0-9:._-]{1,120}$' then trace:=null;end if;
 insert into mefrion_private.security_events(id,occurred_at,source,kind,severity,outcome,status,target,source_key,country,request_id)
 values(ident,t,p_source,k,v,o,code,dest,sk,country,trace) on conflict(id) do nothing;
 get diagnostics amount=row_count;inserted:=amount=1;if not inserted then return true;end if;
 insert into mefrion_private.security_hourly(bucket,source,kind,severity,outcome,target,n) values(date_trunc('hour',t),p_source,k,v,o,dest,1)
 on conflict(bucket,source,kind,severity,outcome,target,is_test) do update set n=mefrion_private.security_hourly.n+1;
 update mefrion_private.security_sources set accepted=accepted+1,last_signal=t where source=p_source;
 -- Correlation is an attention signal, never automatic attribution or blocking.
 if k in('secret_probe','path_traversal','injection_probe','auth_denied','access_denied','rate_limited') and sk<>'unavailable' then
  select count(*) into amount from mefrion_private.security_events where source_key=sk and occurred_at>t-interval '5 minutes' and kind in('secret_probe','path_traversal','injection_probe','auth_denied','access_denied','rate_limited') and not is_test;
  if amount>=10 then
   insert into mefrion_private.security_incidents(source_key,bucket,kind,severity,events)
   values(sk,date_trunc('hour',t)+make_interval(mins=>(floor(extract(minute from t)/5)::integer)*5),'repeated_signals',case when amount>=50 then 'high' else 'medium' end,amount)
   on conflict(source_key,bucket,kind,is_test) do update set events=greatest(mefrion_private.security_incidents.events,excluded.events),updated_at=t,severity=excluded.severity;
  end if;
 elsif code>=500 then
  insert into mefrion_private.security_incidents(source_key,bucket,kind,severity,events)
  values(p_source,date_trunc('hour',t),'server_error','high',1)
  on conflict(source_key,bucket,kind,is_test) do update set events=mefrion_private.security_incidents.events+1,updated_at=t;
 end if;
 return true;
end $$;
commit;
