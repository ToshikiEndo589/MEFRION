-- Security signals are observations, not a claim that every denial is an attack.
begin;
create table mefrion_private.security_settings(
 singleton boolean primary key default true check(singleton),
 pepper bytea not null default extensions.gen_random_bytes(32),
 started_at timestamptz not null default now()
);
insert into mefrion_private.security_settings(singleton) values(true);
create table mefrion_private.security_sources(
 source text primary key, first_seen timestamptz not null default now(),
 last_seen timestamptz not null default now(),last_signal timestamptz,
 accepted bigint not null default 0,lost bigint not null default 0,
 details_omitted bigint not null default 0
);
create table mefrion_private.security_events(
 id uuid primary key, occurred_at timestamptz not null default now(),
 source text not null,kind text not null,severity text not null,
 outcome text not null,status integer not null,target text not null,
 source_key text not null,country text,request_id text,is_test boolean not null default false
);
create index security_events_time on mefrion_private.security_events(occurred_at desc,id desc);
create index security_events_source_time on mefrion_private.security_events(source_key,occurred_at desc);
create index security_events_filter on mefrion_private.security_events(kind,severity,occurred_at desc);
create table mefrion_private.security_hourly(
 bucket timestamptz not null,source text not null,kind text not null,severity text not null,
 outcome text not null,target text not null,is_test boolean not null default false,n bigint not null,
 primary key(bucket,source,kind,severity,outcome,target,is_test)
);
create table mefrion_private.security_incidents(
 id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),source_key text not null,
 bucket timestamptz not null,kind text not null,severity text not null,
 state text not null default 'open' check(state in('open','acknowledged','resolved')),
 events bigint not null default 0,version integer not null default 0,
 note text not null default '',is_test boolean not null default false,
 unique(source_key,bucket,kind,is_test)
);
create table mefrion_private.security_console_audit(
 id bigint generated always as identity primary key,actor uuid not null,
 action text not null,incident uuid,created_at timestamptz not null default now()
);
create table mefrion_private.security_import_cursor(name text primary key,last_id bigint not null default 0);
insert into mefrion_private.security_import_cursor(name) values('app_audit');
-- Explicitly private, including for service_role; only the narrow RPCs below work.
alter table mefrion_private.security_settings enable row level security;
alter table mefrion_private.security_sources enable row level security;
alter table mefrion_private.security_events enable row level security;
alter table mefrion_private.security_hourly enable row level security;
alter table mefrion_private.security_incidents enable row level security;
alter table mefrion_private.security_console_audit enable row level security;
alter table mefrion_private.security_import_cursor enable row level security;
revoke all on mefrion_private.security_settings,mefrion_private.security_sources,
 mefrion_private.security_events,mefrion_private.security_hourly,
 mefrion_private.security_incidents,mefrion_private.security_console_audit,
 mefrion_private.security_import_cursor from public,anon,authenticated,service_role;

create function mefrion_private.security_record(p_source text,p_event jsonb,p_ip text default null,p_lost integer default 0) returns boolean
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
revoke all on function mefrion_private.security_record(text,jsonb,text,integer) from public,anon,authenticated,service_role;

create function public.mefrion_security_ingest(p_source text,p_event jsonb default null,p_ip text default null,p_lost integer default 0) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'service_required' using errcode='42501';end if;
 return mefrion_private.security_record(p_source,p_event,p_ip,p_lost);
end $$;
revoke all on function public.mefrion_security_ingest(text,jsonb,text,integer) from public,anon,authenticated;
grant execute on function public.mefrion_security_ingest(text,jsonb,text,integer) to service_role;

create function public.mefrion_security_dashboard(p_hours integer default 24,p_kind text default null,p_severity text default null,p_source text default null,p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$
declare since timestamptz;result jsonb;rows jsonb;
begin
 perform mefrion_private.require_moderator();
 if p_hours is null or p_limit is null or p_hours not in(24,168,720) or p_limit not between 1 and 100 or coalesce(length(p_kind),0)>40 or coalesce(length(p_severity),0)>20 or coalesce(length(p_source),0)>40 then raise exception 'invalid_security_filter';end if;
 since:=date_trunc('hour',now())-make_interval(hours=>p_hours-1);
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into rows from(
  select id,occurred_at,source,kind,severity,outcome,status,target,source_key,country,request_id from mefrion_private.security_events
  where occurred_at>=since and not is_test and (p_kind is null or kind=p_kind) and(p_severity is null or severity=p_severity) and(p_source is null or source=p_source)
  and(p_before is null or occurred_at<p_before or(occurred_at=p_before and p_before_id is not null and id<p_before_id))
  order by occurred_at desc,id desc limit p_limit+1
 )q;
 select jsonb_build_object(
  'generated_at',now(),'started_at',(select started_at from mefrion_private.security_settings where singleton),
  'retention_days',30,'hours',p_hours,'test_data_excluded',true,
  'summary',(select jsonb_build_object('signals',coalesce(sum(n),0),'suspected',coalesce(sum(n)filter(where kind in('secret_probe','path_traversal','injection_probe')),0),'denied',coalesce(sum(n)filter(where outcome in('denied','limited')),0),'errors',coalesce(sum(n)filter(where kind='server_error'),0)) from mefrion_private.security_hourly where bucket>=date_trunc('hour',since) and not is_test),
  'open_incidents',(select count(*) from mefrion_private.security_incidents where state<>'resolved' and not is_test),
  'timeline',(select coalesce(jsonb_agg(jsonb_build_object('at',b,'signals',n,'suspected',suspect) order by b),'[]') from(select date_trunc(case when p_hours>168 then 'day' else 'hour' end,bucket) b,sum(n)n,sum(n)filter(where kind in('secret_probe','path_traversal','injection_probe'))suspect from mefrion_private.security_hourly where bucket>=date_trunc('hour',since) and not is_test group by 1) t),
  'types',(select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'count',n) order by n desc),'[]') from(select kind,sum(n)n from mefrion_private.security_hourly where bucket>=date_trunc('hour',since) and not is_test group by kind)t),
  'targets',(select coalesce(jsonb_agg(jsonb_build_object('target',target,'count',n) order by n desc),'[]') from(select target,sum(n)n from mefrion_private.security_hourly where bucket>=date_trunc('hour',since) and not is_test group by target order by sum(n)desc limit 10)t),
  'sources',(select coalesce(jsonb_agg(to_jsonb(t) order by n desc),'[]') from(select source_key,count(*)n,max(occurred_at)last_seen from mefrion_private.security_events where occurred_at>=since and not is_test and source_key<>'unavailable' group by source_key order by count(*)desc limit 10)t),
  'coverage',(select coalesce(jsonb_agg(to_jsonb(q) order by source),'[]') from(select source,first_seen,last_seen,last_signal,accepted,lost,details_omitted from mefrion_private.security_sources)q),
  'limitations',jsonb_build_array('Vercel Firewallで到達前に遮断された通信は、外部ログ連携なしでは含められません。','Supabase Auth・DB REST・Storageへの直接通信の拒否ログは別のログ連携が必要です。','検知シグナルは攻撃の確定ではありません。認証ミスや正当なアクセス拒否を含みます。','接続元識別子は週単位で変わります。同じ利用者や個人を特定する情報ではありません。'),
  'events',rows,
  'incidents',(select coalesce(jsonb_agg(to_jsonb(q) order by updated_at desc),'[]') from(select id,created_at,updated_at,source_key,kind,severity,state,events,version,note from mefrion_private.security_incidents where not is_test order by case when state='open' then 0 when state='acknowledged' then 1 else 2 end,updated_at desc limit 100)q)
 ) into result;
 return result;
end $$;
revoke all on function public.mefrion_security_dashboard(integer,text,text,text,timestamptz,uuid,integer) from public,anon;
grant execute on function public.mefrion_security_dashboard(integer,text,text,text,timestamptz,uuid,integer) to authenticated;

create function public.mefrion_security_incident_update(p_id uuid,p_state text,p_version integer,p_note text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare r mefrion_private.security_incidents;
begin
 perform mefrion_private.require_moderator();
 if p_state is null or p_state not in('open','acknowledged','resolved') or p_version is null or p_note is null or length(p_note)>400 then raise exception 'incident_invalid';end if;
 update mefrion_private.security_incidents set state=p_state,note=btrim(p_note),version=version+1,updated_at=now() where id=p_id and version=p_version returning * into r;
 if not found then raise exception 'incident_changed_reload' using errcode='40001';end if;
 insert into mefrion_private.security_console_audit(actor,action,incident) values(auth.uid(),'incident.'||p_state,p_id);
 return jsonb_build_object('id',r.id,'state',r.state,'version',r.version);
end $$;
revoke all on function public.mefrion_security_incident_update(uuid,text,integer,text) from public,anon;
grant execute on function public.mefrion_security_incident_update(uuid,text,integer,text) to authenticated;

create function mefrion_private.security_maintenance() returns void
language plpgsql security definer set search_path='' as $$
declare cap bigint;row record;last bigint;
begin
 delete from mefrion_private.security_events where occurred_at<now()-interval '30 days';
 -- Detail cap protects the database; aggregate counts remain and omission is shown.
 select count(*)-100000 into cap from mefrion_private.security_events;
 if cap>0 then
  with gone as(delete from mefrion_private.security_events where id in(select id from mefrion_private.security_events order by occurred_at limit least(cap,10000)) returning source)
  update mefrion_private.security_sources s set details_omitted=details_omitted+g.n from(select source,count(*)n from gone group by source)g where s.source=g.source;
 end if;
 delete from mefrion_private.security_hourly where bucket<now()-interval '90 days';
 delete from mefrion_private.security_incidents where updated_at<now()-interval '90 days' and state='resolved';
 delete from mefrion_private.security_console_audit where created_at<now()-interval '90 days';
 -- Import only coarse, allowlisted successful app audit actions. No emails/notes.
 select last_id into last from mefrion_private.security_import_cursor where name='app_audit' for update;
 for row in select id,action from mefrion_private.audit where id>last order by id limit 2000 loop
  if row.action='account.retirement.request' or row.action like 'operator.assignment.%' then
   perform mefrion_private.security_record('app_audit',jsonb_build_object('id',gen_random_uuid(),'kind',case when row.action='account.retirement.request' then 'account_retirement' else 'operator_changed' end,'severity','info','outcome','allowed','status',200,'target',case when row.action='account.retirement.request' then '/account' else '/operator' end));
  end if;
  last:=row.id;
 end loop;
 update mefrion_private.security_import_cursor set last_id=last where name='app_audit';
end $$;
revoke all on function mefrion_private.security_maintenance() from public,anon,authenticated,service_role;
-- Do not backfill historic actions as newly occurring events.
update mefrion_private.security_import_cursor set last_id=coalesce((select max(id) from mefrion_private.audit),0) where name='app_audit';
select cron.schedule('mefrion-security-maintenance','* * * * *','select mefrion_private.security_maintenance()');
notify pgrst,'reload schema';
commit;
