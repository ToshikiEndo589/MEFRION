begin;
do $$
declare install uuid:=gen_random_uuid();event uuid:=gen_random_uuid();payload jsonb;ok boolean;result jsonb;denied boolean:=false;
begin
 if has_table_privilege('anon','mefrion_private.product_events','SELECT') or has_table_privilege('authenticated','mefrion_private.product_events','SELECT') then raise exception 'analytics raw table exposed';end if;
 payload:=jsonb_build_array(jsonb_build_object('id',event,'name','session','detail','','version','test','password','DO-NOT-STORE'));
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 execute 'set local role anon';
 ok:=public.mefrion_product_events(install,payload);
 if not ok then raise exception 'valid anonymous event rejected';end if;
 perform public.mefrion_product_events(install,payload);
 begin perform public.mefrion_operator_product_analytics();exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'anonymous analytics access';end if;
 execute 'reset role';
 if (select count(*) from mefrion_private.product_events where id=event)<>1 then raise exception 'duplicate event counted';end if;
 if exists(select 1 from mefrion_private.product_events e where id=event and to_jsonb(e)::text like '%DO-NOT-STORE%') then raise exception 'unknown input persisted';end if;
 denied:=false;begin perform public.mefrion_product_events(install,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'name','arbitrary-private-body','version','test')));exception when others then denied:=true;end;
 if not denied then raise exception 'unknown event accepted';end if;
end $$;
do $$
declare inst uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();event uuid:=gen_random_uuid();bad boolean:=false;
begin
 insert into auth.users(id,aud,role,email,email_confirmed_at) values(a,'authenticated','authenticated',gen_random_uuid()||'@analytics-fixture.invalid',now()),(b,'authenticated','authenticated',gen_random_uuid()||'@analytics-fixture.invalid',now());
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','aal','aal1')::text,true);
 execute 'set local role authenticated';
 begin perform public.mefrion_operator_product_analytics();exception when insufficient_privilege then bad:=true;end;
 if not bad then raise exception 'ordinary account can read operator analytics';end if;
 bad:=false;begin perform public.mefrion_operator_store_metric(current_date,1,2,3);exception when insufficient_privilege then bad:=true;end;
 if not bad then raise exception 'ordinary account can overwrite store counts';end if;
 perform public.mefrion_product_events(inst,jsonb_build_array(jsonb_build_object('id',event,'name','share_visit','detail','x','actor',b,'version','web')));
 execute 'reset role';
 if exists(select 1 from mefrion_private.product_events where id=event and actor is not null) then raise exception 'spoofed account attributed';end if;
 if exists(select 1 from mefrion_private.product_installations where installation=encode(extensions.digest(inst::text,'sha256'),'hex')) then raise exception 'web arrival counted as app installation';end if;
 execute 'set local role authenticated';
 perform public.mefrion_product_events(inst,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'name','active','actor',a,'version','test')));
 execute 'reset role';
 if not exists(select 1 from mefrion_private.product_events where installation=encode(extensions.digest(inst::text,'sha256'),'hex') and actor=a) then raise exception 'authenticated account attribution failed';end if;
end$$;
-- Exercise all aggregation expressions in this isolated, rolled-back transaction.
create or replace function mefrion_private.require_moderator() returns void language plpgsql security definer set search_path='' as $$begin return;end$$;
select public.mefrion_operator_product_analytics(30) is not null as aggregation_ok;
rollback;
