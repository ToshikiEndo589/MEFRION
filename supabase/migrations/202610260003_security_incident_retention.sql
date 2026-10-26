begin;
create or replace function mefrion_private.security_maintenance() returns void
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
 delete from mefrion_private.security_incidents where updated_at<now()-interval '90 days';
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
commit;
