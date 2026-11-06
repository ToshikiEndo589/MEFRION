begin;
create or replace function public.mefrion_product_events(p_install uuid,p_events jsonb) returns boolean
language plpgsql security definer set search_path='' as $$
declare item jsonb;inst text;ident uuid;n text;d text;ms integer;v text;
begin
 if p_install is null or p_events is null or jsonb_typeof(p_events)<>'array' or jsonb_array_length(p_events)>20 or pg_column_size(p_events)>16000 then raise exception 'events_invalid';end if;
 inst:=encode(extensions.digest(p_install::text,'sha256'),'hex');
 -- Client-reported observations, not trusted billing/security evidence.
 if not pg_try_advisory_xact_lock(613004) then return false;end if;
 if (select count(*) from mefrion_private.product_events)>300000 then return false;end if;
 if (select count(*) from mefrion_private.product_events where installation=inst and created_at>now()-interval '1 hour')+jsonb_array_length(p_events)>1000 then return false;end if;
 if (select count(*) from mefrion_private.product_events where created_at>now()-interval '1 day')>20000 then return false;end if;
 for item in select * from jsonb_array_elements(p_events) loop
  ident:=(item->>'id')::uuid;n:=item->>'name';d:=coalesce(item->>'detail','');v:=coalesce(item->>'version','unknown');
  if ident is null or n is null or n not in ('first_open','session','active','tab','signup_start','signup_success','post_start','post_success','post_failure','album_open','album_save','twins_start','twins_success','twins_failure','share_open','share_visit','share_complete','image_ready','image_failure','video_ready','video_failure','request_success','request_failure') or d not in ('','home','album','post','twins','profile','instagram','x','system','feed','search','signup','upload','delete','video','image') or length(v)>30 then raise exception 'event_invalid';end if;
  ms:=case when item->>'ms' is null then null else greatest(0,least(300000,(item->>'ms')::integer)) end;
  insert into mefrion_private.product_events(id,installation,actor,name,detail,duration_ms,app_version)
   values(ident,inst,(select id from auth.users where id=auth.uid() and id::text=item->>'actor' and not is_anonymous),n,d,ms,v) on conflict(id) do nothing;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_events) x where x->>'name' in ('session','active','first_open')) then
 insert into mefrion_private.product_installations(installation) values(inst) on conflict(installation) do update set last_seen=now();end if;
 return true;
end $$;
create or replace function public.mefrion_operator_product_analytics(p_days integer default 30) returns jsonb
language plpgsql security definer set search_path='' as $$
declare since timestamptz;result jsonb;
begin
 perform mefrion_private.require_moderator();
 if p_days is null or p_days not in (7,30,90) then raise exception 'period_invalid';end if;
 since:=now()-make_interval(days=>p_days);
 select jsonb_build_object(
 'started_at',(select min(first_seen) from mefrion_private.product_installations),
 'devices',jsonb_build_object(
 'dau',(select count(distinct installation) from mefrion_private.product_events where name in ('session','active') and created_at>=date_trunc('day',now() at time zone 'Asia/Tokyo') at time zone 'Asia/Tokyo'),
 'wau',(select count(distinct installation) from mefrion_private.product_events where name in ('session','active') and created_at>=now()-interval '7 days'),
 'mau',(select count(distinct installation) from mefrion_private.product_events where name in ('session','active') and created_at>=now()-interval '30 days')),
 'registered',jsonb_build_object(
 'total',(select count(*) from auth.users where deleted_at is null and not is_anonymous and raw_user_meta_data->>'test_only' is distinct from 'true'),
 'dau',(select count(distinct actor) from mefrion_private.product_events where name in ('session','active') and created_at>=date_trunc('day',now() at time zone 'Asia/Tokyo') at time zone 'Asia/Tokyo'),
 'wau',(select count(distinct actor) from mefrion_private.product_events where name in ('session','active') and created_at>=now()-interval '7 days'),
 'mau',(select count(distinct actor) from mefrion_private.product_events where name in ('session','active') and created_at>=now()-interval '30 days')),
 'daily',(select coalesce(jsonb_agg(to_jsonb(q) order by day),'[]') from (
 select (created_at at time zone 'Asia/Tokyo')::date as day,count(distinct installation) devices,count(distinct actor) members,count(*) filter(where name='session') sessions,count(*) filter(where name='first_open') first_opens from mefrion_private.product_events where created_at>=since and name in ('session','active','first_open') group by 1) q),
 'hourly',(select coalesce(jsonb_agg(to_jsonb(q) order by hour),'[]') from (
 select date_trunc('hour',created_at at time zone 'Asia/Tokyo') as hour,count(distinct installation) devices,count(*) filter(where name='session') sessions,count(*) events from mefrion_private.product_events where created_at>=now()-interval '48 hours' group by 1) q),
 'events',(select coalesce(jsonb_agg(to_jsonb(q)),'[]') from (select name,detail,count(*) n,count(distinct installation) devices,percentile_cont(0.5) within group(order by duration_ms) p50_ms,percentile_cont(0.95) within group(order by duration_ms) p95_ms from mefrion_private.product_events where created_at>=since group by name,detail) q),
 'versions',(select coalesce(jsonb_agg(to_jsonb(q)),'[]') from (select app_version,count(distinct installation) devices,count(*) filter(where name like '%failure') failures from mefrion_private.product_events where created_at>=since and app_version<>'web' group by app_version) q),
 'retention',(select jsonb_agg(jsonb_build_object('day',offset_days,'eligible',eligible,'returned',returned)) from (
 select offset_days,count(*) eligible,count(*) filter(where exists(select 1 from mefrion_private.product_events e where e.installation=i.installation and e.name in ('session','active') and (e.created_at at time zone 'Asia/Tokyo')::date=(i.first_seen at time zone 'Asia/Tokyo')::date+offset_days)) returned
 from mefrion_private.product_installations i cross join unnest(array[1,7,30]) offset_days
 where i.first_seen>=since and (i.first_seen at time zone 'Asia/Tokyo')::date+offset_days<(now() at time zone 'Asia/Tokyo')::date group by offset_days) q),
 'album',jsonb_build_object('devices',(select count(distinct installation) from mefrion_private.product_events where name='album_open' and created_at>=since),'returning',(select count(*) from(select installation from mefrion_private.product_events where name='album_open' and created_at>=since group by installation having count(distinct (created_at at time zone 'Asia/Tokyo')::date)>=2) q)),
 'funnel',(select jsonb_build_object('first_open',count(*) filter(where first_open is not null),'registered_after_open',count(*) filter(where registered>=first_open),'posted_after_registration',count(*) filter(where posted>=registered and registered>=first_open)) from(select installation,min(created_at) filter(where name='first_open') first_open,min(created_at) filter(where name='signup_success') registered,min(created_at) filter(where name='post_success') posted from mefrion_private.product_events where created_at>=since group by installation) q),
 'content',jsonb_build_object('user_posts',(select count(*) from mefrion_private.public_posts where content_origin='user' and state='published' and published_at>=since),'managed_posts',(select count(*) from mefrion_private.public_posts where content_origin='managed_seed' and state='published' and published_at>=since),'user_posters',(select count(distinct actor_id) from mefrion_private.public_posts where content_origin='user' and state='published' and published_at>=since)),
 'store',(select coalesce(jsonb_agg(to_jsonb(s) order by day),'[]') from (select day,first_downloads,redownloads,installations from mefrion_private.store_metrics where day>=since::date) s)
 ) into result;return result;
end $$;
commit;
