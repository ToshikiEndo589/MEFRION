begin;
-- Bind destructive intent to the identity shown before reauthentication.
alter function public.mefrion_request_retirement(uuid,boolean) set schema mefrion_private;
alter function mefrion_private.mefrion_request_retirement(uuid,boolean) rename to request_retirement_impl;
revoke all on function mefrion_private.request_retirement_impl(uuid,boolean) from public,anon,authenticated;
create function public.mefrion_request_retirement(p_request_key uuid,p_explicit boolean,p_expected_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if p_expected_user is null or auth.uid() is distinct from p_expected_user then raise exception 'retirement_identity_mismatch' using errcode='42501';end if;
 return mefrion_private.request_retirement_impl(p_request_key,p_explicit);
end $$;
revoke all on function public.mefrion_request_retirement(uuid,boolean,uuid) from public,anon;
grant execute on function public.mefrion_request_retirement(uuid,boolean,uuid) to authenticated;
commit;
