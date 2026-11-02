-- Disposable identities only; no changes survive this suite.
begin;
create temporary table invite_capacity_result(name text,passed boolean);
create function pg_temp.capacity_assert(label text,ok boolean) returns void language plpgsql security definer as $$
begin
 if ok is distinct from true then raise exception 'capacity assertion failed: %',label;end if;
 insert into invite_capacity_result values(label,true);
end $$;
grant execute on function pg_temp.capacity_assert(text,boolean) to authenticated;
do $$
declare owner_id uuid:=gen_random_uuid();people uuid[]:='{}';u uuid;pet uuid;inv jsonb;extra jsonb;j integer;denied boolean;
begin
 insert into auth.users(id,aud,role,email) values(owner_id,'authenticated','authenticated',owner_id||'@example.invalid');
 for j in 1..11 loop
  u:=gen_random_uuid();people:=array_append(people,u);
  insert into auth.users(id,aud,role,email) values(u,'authenticated','authenticated',u||'@example.invalid');
 end loop;
 perform pg_temp.capacity_assert('claims not directly readable',not has_table_privilege('authenticated','mefrion_private.invite_claims','select'));
 perform pg_temp.capacity_assert('anonymous cannot accept',not has_function_privilege('anon','public.mefrion_accept_invite(text,boolean)','execute'));
 perform set_config('request.jwt.claim.sub',owner_id::text,true);perform set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 pet:=(public.mefrion_create_pet('10人招待ロールバック試験','dog')->>'id')::uuid;
 inv:=public.mefrion_invite(pet);extra:=public.mefrion_invite(pet);
 denied:=false;begin perform public.mefrion_accept_invite(inv->>'token',true);exception when raise_exception then denied:=sqlerrm='already_owner';end;
 perform pg_temp.capacity_assert('owner is not an invited seat',denied);
 execute 'reset role';
 for j in 1..10 loop
  u:=people[j];
  perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if j=1 then
   denied:=false;begin perform public.mefrion_accept_invite(inv->>'token',false);exception when raise_exception then denied:=sqlerrm='scope_confirmation_required';end;
   perform pg_temp.capacity_assert('scope confirmation preserved',denied);
  end if;
  perform public.mefrion_accept_invite(inv->>'token',true);
  perform public.mefrion_accept_invite(inv->>'token',true);
  perform pg_temp.capacity_assert('same link joins person '||j,public.mefrion_family_access(pet));
  execute 'reset role';
  perform pg_temp.capacity_assert('retry consumes no extra place '||j,(select used_count=j from mefrion_private.invites where id=(inv->>'id')::uuid));
 end loop;
 perform pg_temp.capacity_assert('exactly ten claims',(select count(*)=10 from mefrion_private.invite_claims where invite_id=(inv->>'id')::uuid));
 u:=people[11];perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 denied:=false;begin perform public.mefrion_accept_invite(inv->>'token',true);exception when raise_exception then denied:=sqlerrm='invitation_full';end;
 perform pg_temp.capacity_assert('eleventh person denied',denied);
 perform pg_temp.capacity_assert('eleventh person has no family access',not public.mefrion_family_access(pet));
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',owner_id::text,true);perform set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 perform pg_temp.capacity_assert('owner plus ten family members',jsonb_array_length(public.mefrion_members(pet))=11);
 perform pg_temp.capacity_assert('full link excluded from cached usable links',not exists(select 1 from jsonb_array_elements(public.mefrion_pending_invites(pet)) x where x->>'id'=inv->>'id'));
 perform public.mefrion_remove_member(pet,people[1]);
 perform public.mefrion_revoke_invite((extra->>'id')::uuid);
 extra:=public.mefrion_invite(pet);
 execute 'reset role';
 u:=people[1];perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 denied:=false;begin perform public.mefrion_accept_invite(inv->>'token',true);exception when raise_exception then denied:=sqlerrm='invalid_invitation';end;
 perform pg_temp.capacity_assert('removed member cannot replay redeemed link',denied);
 perform public.mefrion_accept_invite(extra->>'token',true);
 perform pg_temp.capacity_assert('owner can reinvite removed person using new link',public.mefrion_family_access(pet));
 execute 'reset role';
 update mefrion_private.invites set expires_at=now()-interval '1 second' where id=(extra->>'id')::uuid;
 u:=people[11];perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 denied:=false;begin perform public.mefrion_accept_invite(extra->>'token',true);exception when raise_exception then denied:=sqlerrm='invalid_invitation';end;
 perform pg_temp.capacity_assert('expired partially used link denied',denied);
 execute 'reset role';
 update mefrion_private.invites set state='revoked',expires_at=now()+interval '1 day' where id=(extra->>'id')::uuid;
 execute 'set local role authenticated';
 denied:=false;begin perform public.mefrion_accept_invite(extra->>'token',true);exception when raise_exception then denied:=sqlerrm='invalid_invitation';end;
 perform pg_temp.capacity_assert('revoked partially used link denied',denied);
 execute 'reset role';
end $$;
select count(*) as checks,bool_and(passed) as passed from invite_capacity_result;
rollback;
