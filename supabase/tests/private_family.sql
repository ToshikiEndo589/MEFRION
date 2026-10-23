-- Cloud PostgreSQL policy suite. JWT claims/roles are simulated in a transaction.
-- This is NOT proof of real Auth tokens or downloadable uploaded image behavior.
begin;
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();c uuid:=gen_random_uuid();
 pet uuid; photo uuid;invite jsonb;record jsonb;replayed jsonb;denied boolean;checks integer:=0;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
 (a,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',a::text||'@example.invalid',now(),now()),
 (b,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',b::text||'@example.invalid',now(),now()),
 (c,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',c::text||'@example.invalid',now(),now());
 if exists(select 1 from pg_class cl join pg_namespace n on n.oid=cl.relnamespace where n.nspname='mefrion_private' and cl.relkind='r' and not cl.relrowsecurity) then raise exception 'RLS missing';end if;checks:=checks+1;
 if exists(select 1 from storage.buckets where id in ('family-originals','public-derived') and public) then raise exception 'public bucket';end if;checks:=checks+1;
 if has_schema_privilege('authenticated','mefrion_private','usage') or has_schema_privilege('anon','mefrion_private','usage') then raise exception 'schema exposed';end if;checks:=checks+1;
 if has_function_privilege('anon','public.mefrion_create_pet(text,text,text,text)','execute') then raise exception 'anonymous RPC granted';end if;checks:=checks+1;
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated','is_anonymous',true)::text,true);
 denied:=false;begin perform public.mefrion_create_pet('guest','dog');exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'anonymous Auth guest created pet';end if;checks:=checks+1;
 perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
 record:=public.mefrion_create_pet('試験専用の犬','dog');pet:=(record->>'id')::uuid;
 if not public.mefrion_family_access(pet) then raise exception 'owner denied';end if;checks:=checks+1;
 denied:=false;begin perform count(*) from mefrion_private.pets;exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'direct private table exposed';end if;checks:=checks+1;
 invite:=public.mefrion_invite(pet);
 record:=public.mefrion_begin_photo(pet,gen_random_uuid(),'2020','合成試験');photo:=(record->>'id')::uuid;
 denied:=false;begin perform public.mefrion_finish_photo(photo);exception when others then if sqlerrm='upload_incomplete' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'unfinished upload accepted';end if;checks:=checks+1;
 execute 'reset role';
 update mefrion_private.photos set state='ready' where id=photo;
 perform set_config('request.jwt.claim.sub',c::text,true);perform set_config('request.jwt.claims',json_build_object('sub',c,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 if public.mefrion_family_access(pet) then raise exception 'third party access';end if;
 denied:=false;begin perform public.mefrion_photo(photo);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'third party photo exposed';end if;checks:=checks+1;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',b::text,true);perform set_config('request.jwt.claims',json_build_object('sub',b,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 denied:=false;begin perform public.mefrion_accept_invite(invite->>'token',false);exception when others then if sqlerrm='scope_confirmation_required' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'scope confirmation bypass';end if;checks:=checks+1;
 perform public.mefrion_accept_invite(invite->>'token',true);
 if not public.mefrion_family_access(pet) or jsonb_array_length(public.mefrion_album(pet))<>1 then raise exception 'family album denied';end if;checks:=checks+1;
 if jsonb_array_length(public.mefrion_members(pet))<>2 then raise exception 'family membership list incorrect';end if;checks:=checks+1;
 denied:=false;begin perform public.mefrion_accept_invite(invite->>'token',true);exception when others then if sqlerrm='invalid_invitation' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'invite reused';end if;checks:=checks+1;
 denied:=false;begin perform public.mefrion_consent(photo,'sns',true);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'another provider consent';end if;checks:=checks+1;
 perform public.mefrion_remove_member(pet,b);
 if public.mefrion_family_access(pet) then raise exception 'removed family access';end if;
 denied:=false;begin perform public.mefrion_photo(photo);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'removed family original metadata';end if;checks:=checks+1;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 if public.mefrion_consent(photo,'sns',true)<>1 or public.mefrion_consent(photo,'sns',false)<>2 then raise exception 'consent version wrong';end if;checks:=checks+1;
 perform public.mefrion_delete_photo(photo);
 if public.mefrion_download_allowed(record->>'path') then raise exception 'deleted original permission';end if;
 if jsonb_array_length(public.mefrion_album(pet))<>0 then raise exception 'deleted album row';end if;checks:=checks+1;
 execute 'reset role';
 if (select count(*) from mefrion_private.deletion_outbox where object_path=record->>'path')<>1 then raise exception 'deletion outbox missing';end if;checks:=checks+1;
 -- No client SELECT policy is permitted for the original bucket: signed URLs are a bypass risk.
 if exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'mefrion%' and cmd in ('SELECT','ALL')) then raise exception 'direct storage select granted';end if;checks:=checks+1;
 perform set_config('mefrion.policy_checks',checks::text,true);
end $$;
select current_setting('mefrion.policy_checks') as passed_policy_checks, 'transactional simulated roles; real Auth/media E2E pending' as scope;
rollback;
