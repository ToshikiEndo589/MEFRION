begin;

-- The random request key is a receipt capability kept only on the requesting
-- device. No user ID, email, paths or other account data are exposed after
-- sign-out. The worker sets done only after verified storage/Auth deletion.
create function public.mefrion_retirement_status(p_request_key uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if p_request_key is null then return jsonb_build_object('state','unknown');end if;
 return coalesce((select jsonb_build_object('state',state,'completed_at',completed_at)
  from mefrion_private.account_retirements where request_key=p_request_key),
  jsonb_build_object('state','unknown'));
end $$;
revoke all on function public.mefrion_retirement_status(uuid) from public;
grant execute on function public.mefrion_retirement_status(uuid) to anon,authenticated;

commit;
