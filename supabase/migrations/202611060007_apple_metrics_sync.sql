begin;
create table mefrion_private.apple_sync_settings(singleton boolean primary key default true check(singleton),token_hash bytea,last_attempt timestamptz,last_success timestamptz,status text not null default 'not_configured');
insert into mefrion_private.apple_sync_settings(singleton) values(true);
create table mefrion_private.apple_report_days(day date,kind text check(kind in ('downloads','installs')),processing_date date not null,first_downloads integer,redownloads integer,installations integer,updated_at timestamptz not null default now(),primary key(day,kind));
alter table mefrion_private.apple_sync_settings enable row level security;
alter table mefrion_private.apple_report_days enable row level security;
revoke all on mefrion_private.apple_sync_settings,mefrion_private.apple_report_days from public,anon,authenticated,service_role;
create function public.mefrion_apple_metrics_ingest(p_token text,p_rows jsonb,p_status text) returns boolean
language plpgsql security definer set search_path='' as $$
declare r jsonb;d date;processed date;k text;a integer;b integer;c integer;
begin
 if p_token is null or length(p_token)<32 or not exists(select 1 from mefrion_private.apple_sync_settings where token_hash=extensions.digest(p_token,'sha256')) then raise insufficient_privilege using message='sync_denied';end if;
 if p_status is null or p_status not in ('ok','awaiting_reports','request_required','not_configured','apple_auth','apple_api','download','integrity','schema','origin','size','budget','pagination','sync_failure') or p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>500 or pg_column_size(p_rows)>200000 then raise exception 'sync_invalid';end if;
 if not pg_try_advisory_xact_lock(613007) then return false;end if;
 update mefrion_private.apple_sync_settings set last_attempt=now(),status=p_status,last_success=case when p_status='ok' then now() else last_success end where singleton;
 for r in select * from jsonb_array_elements(p_rows) loop
 d:=(r->>'day')::date;processed:=(r->>'processed')::date;k:=r->>'kind';a:=(r->>'first')::integer;b:=(r->>'again')::integer;c:=(r->>'installs')::integer;
 if d is null or processed is null or d<current_date-365 or d>current_date+1 or processed<d or processed>current_date+1 or k is null or k not in('downloads','installs') or a is null or b is null or c is null or a not between 0 and 1000000000 or b not between 0 and 1000000000 or c not between 0 and 1000000000 then raise exception 'sync_row_invalid';end if;
 insert into mefrion_private.apple_report_days(day,kind,processing_date,first_downloads,redownloads,installations)
 values(d,k,processed,case when k='downloads' then a end,case when k='downloads' then b end,case when k='installs' then c end)
 on conflict(day,kind) do update set processing_date=excluded.processing_date,first_downloads=excluded.first_downloads,redownloads=excluded.redownloads,installations=excluded.installations,updated_at=now() where excluded.processing_date>=mefrion_private.apple_report_days.processing_date;
 end loop;return true;
end $$;
revoke all on function public.mefrion_apple_metrics_ingest(text,jsonb,text) from public;
grant execute on function public.mefrion_apple_metrics_ingest(text,jsonb,text) to anon;
create function public.mefrion_operator_apple_metrics(p_days integer default 30) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform mefrion_private.require_moderator();
 if p_days is null or p_days not in (7,30,90) then raise exception 'period_invalid';end if;
 select jsonb_build_object('status',status,'last_attempt',last_attempt,'last_success',last_success,'days',(select coalesce(jsonb_agg(to_jsonb(q) order by day),'[]') from (select coalesce(d.day,i.day) as day,d.first_downloads,d.redownloads,i.installations,d.processing_date download_processed,i.processing_date install_processed from (select * from mefrion_private.apple_report_days where kind='downloads') d full join (select * from mefrion_private.apple_report_days where kind='installs') i on d.day=i.day where coalesce(d.day,i.day)>=current_date-p_days+1) q)) into result from mefrion_private.apple_sync_settings where singleton;return result;
end $$;
revoke all on function public.mefrion_operator_apple_metrics(integer) from public,anon;
grant execute on function public.mefrion_operator_apple_metrics(integer) to authenticated;
commit;
