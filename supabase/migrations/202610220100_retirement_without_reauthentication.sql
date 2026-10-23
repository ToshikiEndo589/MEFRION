begin;
-- An authenticated session and explicit confirmation remain mandatory. The
-- additional five-minute sign-in requirement prevented account deletion from
-- the in-app account page after a normal, longer-lived session.
do $$
declare
  definition text;
  recent_login_check text := ' if coalesce((auth.jwt()->>''iat'')::bigint,0)<extract(epoch from now())-300 then raise exception ''recent_login_required'' using errcode=''42501'';end if;';
begin
  definition := pg_get_functiondef('mefrion_private.request_retirement_impl(uuid,boolean)'::regprocedure);
  if position(recent_login_check in definition)=0 then
    raise exception 'request_retirement_impl changed; review required before removing recent-login check';
  end if;
  execute replace(definition,recent_login_check,'');
end $$;
commit;
