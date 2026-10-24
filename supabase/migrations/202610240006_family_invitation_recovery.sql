begin;
-- Owners can validate a locally cached secret without exposing token hashes or members.
create or replace function public.mefrion_pending_invites(p_pet uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 if not exists(select 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid()) then
  raise exception 'owner_required' using errcode='42501';
 end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'expires_at',expires_at) order by created_order),'[]'::jsonb)
 from (select id,expires_at,id::text as created_order from mefrion_private.invites where pet_id=p_pet and state='pending' and expires_at>now()) i);
end $$;
-- Explicit in-app confirmation is required; existing members and accepted invites stay intact.
create or replace function public.mefrion_replace_invites(p_pet uuid,p_explicit boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 if p_explicit is distinct from true then raise exception 'confirmation_required' using errcode='42501';end if;
 perform 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid() for update;
 if not found then raise exception 'owner_required' using errcode='42501';end if;
 update mefrion_private.invites set state='revoked' where pet_id=p_pet and state='pending';
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'invite.replace');
 return public.mefrion_invite(p_pet);
end $$;
revoke execute on function public.mefrion_pending_invites(uuid),public.mefrion_replace_invites(uuid,boolean) from public,anon;
grant execute on function public.mefrion_pending_invites(uuid),public.mefrion_replace_invites(uuid,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
