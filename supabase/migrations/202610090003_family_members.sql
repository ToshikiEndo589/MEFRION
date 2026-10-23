begin;
create or replace function public.mefrion_family_access(p_pet uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(auth.jwt()->>'is_anonymous','false')<>'true' and exists(select 1 from mefrion_private.pets p where p.id=p_pet and
 (p.owner_id=auth.uid() or exists(select 1 from mefrion_private.members m where m.pet_id=p.id and m.user_id=auth.uid() and m.active)))
$$;
create or replace function public.mefrion_members(p_pet uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'role',role,'me',id=auth.uid())),'[]'::jsonb) from (
 select p.owner_id as id,'owner'::text as role from mefrion_private.pets p where p.id=p_pet
 union all select m.user_id,'family' from mefrion_private.members m where m.pet_id=p_pet and m.active
 ) u);
end $$;
revoke execute on function public.mefrion_members(uuid) from public,anon;
grant execute on function public.mefrion_members(uuid) to authenticated;
-- Anonymous Auth users are guests; creating a Pet or accepting family scope needs registration.
-- Add the gate through a reusable check called by the RPC wrappers.
create or replace function mefrion_private.require_registered() returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' then raise exception 'registration_required' using errcode='42501';end if;
end $$;
revoke execute on function mefrion_private.require_registered() from public,anon,authenticated;

create or replace function public.mefrion_create_pet(p_name text,p_species text,p_breed text default '',p_introduction text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_pet mefrion_private.pets; v_user uuid:=auth.uid();
begin
 perform mefrion_private.require_registered();
 if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text,0));
 if (select count(*) from mefrion_private.pets where owner_id=v_user)>=5 then raise exception 'pet_limit'; end if;
 if length(p_breed)>100 or length(p_introduction)>500 then raise exception 'profile_limit';end if;
 insert into mefrion_private.pets(owner_id,name,species,breed,introduction) values(v_user,btrim(p_name),p_species,p_breed,p_introduction) returning * into v_pet;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(v_user,v_pet.id,'pet.create');
 return jsonb_build_object('id',v_pet.id,'name',v_pet.name,'species',v_pet.species,'breed',v_pet.breed,'introduction',v_pet.introduction);
end $$;

create or replace function public.mefrion_accept_invite(p_token text,p_confirm_scope boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_inv mefrion_private.invites;v_owner uuid;
begin
 perform mefrion_private.require_registered();
 if auth.uid() is null then raise exception 'authentication_required' using errcode='42501';end if;
 if p_confirm_scope is distinct from true then raise exception 'scope_confirmation_required';end if;
 if p_token is null or length(p_token)<>64 then raise exception 'invalid_invitation';end if;
 select * into v_inv from mefrion_private.invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not found or v_inv.state<>'pending' or v_inv.expires_at<=now() then raise exception 'invalid_invitation';end if;
 select owner_id into v_owner from mefrion_private.pets where id=v_inv.pet_id for update;
 if v_owner=auth.uid() then raise exception 'already_owner';end if;
 if exists(select 1 from mefrion_private.members where pet_id=v_inv.pet_id and user_id=auth.uid() and active) then raise exception 'already_member';end if;
 update mefrion_private.invites set state='accepted' where id=v_inv.id;
 insert into mefrion_private.members(pet_id,user_id) values(v_inv.pet_id,auth.uid()) on conflict(pet_id,user_id) do update set active=true;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v_inv.pet_id,'invite.accept');
 return jsonb_build_object('pet_id',v_inv.pet_id,'role','family','external_publish',false);
end $$;

create or replace function public.mefrion_invite(p_pet uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_token text;v_id uuid;v_expires timestamptz;
begin
 perform mefrion_private.require_registered();
 perform 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid() for update;
 if not found then raise exception 'owner_required' using errcode='42501';end if;
 if (select count(*) from mefrion_private.invites where pet_id=p_pet and state='pending' and expires_at>now())>=5 then raise exception 'invitation_limit';end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into mefrion_private.invites(pet_id,token_hash) values(p_pet,encode(extensions.digest(v_token,'sha256'),'hex')) returning id,expires_at into v_id,v_expires;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'invite.create');
 return jsonb_build_object('id',v_id,'token',v_token,'expires_at',v_expires);
end $$;
commit;
