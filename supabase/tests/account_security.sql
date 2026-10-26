-- Synthetic identities and all probe objects roll back. No customer reads.
begin;
create temporary table account_security_results(name text,passed boolean);
create function pg_temp.account_assert(label text,ok boolean) returns void language plpgsql security definer as $$
begin if ok is distinct from true then raise exception 'account security assertion failed: %',label;end if;insert into account_security_results values(label,true);end $$;
grant execute on function pg_temp.account_assert(text,boolean) to anon,authenticated;
create function mefrion_private.account_security_default_probe() returns boolean language sql as $$select true$$;
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();pet uuid;other_pet uuid;invite jsonb;v jsonb;denied boolean;r text;t text;claims jsonb;
 marker_a text:=gen_random_uuid()||'@private-qa.invalid';marker_b text:=gen_random_uuid()||'@private-qa.invalid';
 password_marker text:='NOT_A_REAL_PASSWORD_'||gen_random_uuid();
begin
 for r in select unnest(array['anon','authenticated']) loop
  for t in select unnest(array['users','identities','sessions','refresh_tokens','mfa_factors']) loop
   perform pg_temp.account_assert(r||' cannot read auth.'||t,not has_table_privilege(r,format('auth.%I',t),'SELECT'));
  end loop;
  perform pg_temp.account_assert(r||' cannot execute newly created private helper',not has_function_privilege(r,'mefrion_private.account_security_default_probe()','execute'));
  perform pg_temp.account_assert(r||' has no private table DML',not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='mefrion_private' and c.relkind='r' and has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE')));
 end loop;
 perform pg_temp.account_assert('all private tables use RLS',not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='mefrion_private' and c.relkind='r' and not c.relrowsecurity));
 perform pg_temp.account_assert('all app definer functions fix search_path',not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','mefrion_private') and p.prosecdef and not exists(select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')));
 insert into auth.users(id,aud,role,email,encrypted_password,phone,email_confirmed_at) values
 (a,'authenticated','authenticated',marker_a,password_marker,'19990000001',now()),(b,'authenticated','authenticated',marker_b,password_marker,'19990000002',now());
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','aal','aal1')::text,true);
 execute 'set local role authenticated';
 pet:=(public.mefrion_create_pet('QA privacy dog','dog')->>'id')::uuid;
 invite:=public.mefrion_invite(pet);
 perform public.mefrion_set_public_profile(pet,true,true);
 v:=jsonb_build_array(public.mefrion_list_pets(),public.mefrion_account_profile(),public.mefrion_members(pet),public.mefrion_family_activity(pet),public.mefrion_public_pet(pet),public.mefrion_social_identity());
 perform pg_temp.account_assert('own projections do not return Auth email/phone/hash',v::text not like '%'||marker_a||'%' and v::text not like '%'||password_marker||'%' and v::text not like '%19990000001%');
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',b::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','aal','aal1')::text,true);
 execute 'set local role authenticated';
 other_pet:=(public.mefrion_create_pet('QA privacy cat','cat')->>'id')::uuid;
 perform public.mefrion_accept_invite(invite->>'token',true);
 v:=jsonb_build_array(public.mefrion_members(pet),public.mefrion_list_pets(),public.mefrion_family_activity(pet),public.mefrion_public_pet(pet),public.mefrion_social_connections('followers',10),public.mefrion_social_connections('following',10));
 perform pg_temp.account_assert('family/social projections do not disclose private contact or hash',v::text not like '%'||marker_a||'%' and v::text not like '%'||marker_b||'%' and v::text not like '%'||password_marker||'%' and v::text not like '%19990000001%' and v::text not like '%19990000002%');
 denied:=false;begin perform public.mefrion_update_pet(pet,'ATTACK','','','{}','{}');exception when insufficient_privilege then denied:=true;end;
 perform pg_temp.account_assert('family cannot overwrite owner profile',denied);
 execute 'reset role';
 insert into mefrion_private.operator_login_allowlist(email) values(lower(marker_b));
 insert into mefrion_private.operators(user_id,role,active,expires_at) values(b,'admin',true,now()+interval '1 hour');
 execute 'set local role authenticated';
 denied:=false;begin perform public.mefrion_operator_queue();exception when insufficient_privilege then denied:=true;end;
 perform pg_temp.account_assert('operator with password-only session is denied',denied);
 execute 'reset role';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','aal','aal2')::text,true);
 execute 'set local role authenticated';
 denied:=false;begin perform public.mefrion_operator_queue();exception when insufficient_privilege then denied:=true;end;
 perform pg_temp.account_assert('aal2 claim without verified MFA factor is denied',denied);
 execute 'reset role';
 perform set_config('request.jwt.claim.sub','',true);perform set_config('request.jwt.claims','{"role":"anon"}',true);
 execute 'set local role anon';
 v:=jsonb_build_array(public.mefrion_public_pet(pet),public.mefrion_feed_page('all','QA privacy','all',null,null,5,'{}'));
 perform pg_temp.account_assert('anonymous projections do not disclose private contact or hash',v::text not like '%'||marker_a||'%' and v::text not like '%'||marker_b||'%' and v::text not like '%'||password_marker||'%' and v::text not like '%19990000001%' and v::text not like '%19990000002%');
 execute 'reset role';
end $$;
select * from account_security_results;
rollback;
