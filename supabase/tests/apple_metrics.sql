begin;
do $$
declare t text:=repeat('x',64);bad boolean:=false;r jsonb;
begin
 if has_table_privilege('anon','mefrion_private.apple_report_days','SELECT') or has_table_privilege('authenticated','mefrion_private.apple_sync_settings','SELECT') then raise exception 'apple sync secrets exposed';end if;
 update mefrion_private.apple_sync_settings set token_hash=extensions.digest(t,'sha256') where singleton;
 execute 'set local role anon';
 begin perform public.mefrion_apple_metrics_ingest('wrong','[]','ok');exception when insufficient_privilege then bad:=true;end;
 if not bad then raise exception 'unprotected apple ingestion';end if;
 r:=jsonb_build_array(jsonb_build_object('day',current_date-2,'processed',current_date-1,'kind','downloads','first',3,'again',1,'installs',0));
 perform public.mefrion_apple_metrics_ingest(t,r,'ok');perform public.mefrion_apple_metrics_ingest(t,r,'ok');
 r:=jsonb_build_array(jsonb_build_object('day',current_date-2,'processed',current_date,'kind','downloads','first',5,'again',2,'installs',0));
 perform public.mefrion_apple_metrics_ingest(t,r,'ok');execute 'reset role';
 if (select first_downloads from mefrion_private.apple_report_days where day=current_date-2 and kind='downloads')<>5 then raise exception 'Apple revisions double counted';end if;
end$$;
-- Verify the protected summary without persisting any guard or fixtures.
create or replace function mefrion_private.require_moderator() returns void language plpgsql security definer set search_path='' as $$begin return;end$$;
select public.mefrion_operator_apple_metrics(30)->>'status'='ok' as apple_aggregation_ok;
rollback;
