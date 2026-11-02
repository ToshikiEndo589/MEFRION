begin;
-- Existing unused links keep their token and expiry. Previously consumed links
-- stay closed: reopening old shared secrets could restore removed members.
alter table mefrion_private.invites add column if not exists used_count integer not null default 0 check(used_count between 0 and 10);
update mefrion_private.invites set used_count=10 where state='accepted' and used_count=0;
create table mefrion_private.invite_claims (
 invite_id uuid not null references mefrion_private.invites(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 joined_at timestamptz not null default now(), primary key(invite_id,user_id)
);
alter table mefrion_private.invite_claims enable row level security;
revoke all on mefrion_private.invite_claims from public,anon,authenticated;

create or replace function public.mefrion_accept_invite(p_token text,p_confirm_scope boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_inv mefrion_private.invites;v_pet uuid;v_owner uuid;
begin
 perform mefrion_private.require_registered();
 if p_confirm_scope is distinct from true then raise exception 'scope_confirmation_required';end if;
 if p_token is null or length(p_token)<>64 then raise exception 'invalid_invitation';end if;
 select pet_id into v_pet from mefrion_private.invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 if not found then raise exception 'invalid_invitation';end if;
 -- All membership writers / invite replacement lock the pet first. Consistent
 -- ordering prevents deadlocks and makes accepting the last place atomic.
 select owner_id into v_owner from mefrion_private.pets where id=v_pet for update;
 select * into v_inv from mefrion_private.invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not found or v_inv.state='revoked' or v_inv.expires_at<=now() then raise exception 'invalid_invitation';end if;
 if v_owner=auth.uid() then raise exception 'already_owner';end if;
 if exists(select 1 from mefrion_private.members where pet_id=v_pet and user_id=auth.uid() and active) then
  return jsonb_build_object('pet_id',v_pet,'role','family','external_publish',false);
 end if;
 -- A removed person cannot reuse a previously redeemed link to undo removal.
 if exists(select 1 from mefrion_private.invite_claims where invite_id=v_inv.id and user_id=auth.uid()) then raise exception 'invalid_invitation';end if;
 if v_inv.state<>'pending' or v_inv.used_count>=10 then raise exception 'invitation_full';end if;
 insert into mefrion_private.invite_claims(invite_id,user_id) values(v_inv.id,auth.uid());
 update mefrion_private.invites set used_count=used_count+1,state=case when used_count+1=10 then 'accepted' else 'pending' end where id=v_inv.id;
 insert into mefrion_private.members(pet_id,user_id) values(v_pet,auth.uid()) on conflict(pet_id,user_id) do update set active=true;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v_pet,'invite.accept');
 return jsonb_build_object('pet_id',v_pet,'role','family','external_publish',false);
end $$;

create or replace function public.mefrion_pending_invites(p_pet uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 if not exists(select 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid()) then raise exception 'owner_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'expires_at',expires_at,'used_count',used_count) order by id),'[]'::jsonb)
 from mefrion_private.invites where pet_id=p_pet and state='pending' and used_count<10 and expires_at>now());
end $$;
-- Preserve the existing owner-only creation / cancellation / replacement RPCs.
revoke execute on function public.mefrion_accept_invite(text,boolean),public.mefrion_pending_invites(uuid) from public,anon;
grant execute on function public.mefrion_accept_invite(text,boolean),public.mefrion_pending_invites(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
