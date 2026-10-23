begin;
create or replace function mefrion_private.require_moderator() returns void
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 if auth.jwt()->>'aal' is distinct from 'aal2' or not exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified' and factor_type='totp') then raise exception 'moderator_mfa_required' using errcode='42501';end if;
 -- An otherwise valid JWT must not keep moderator access after Auth logout.
 if not exists(select 1 from auth.sessions where user_id=auth.uid() and id::text=auth.jwt()->>'session_id') then raise exception 'moderator_session_revoked' using errcode='42501';end if;
 perform 1 from mefrion_private.operators where user_id=auth.uid() and active and role in ('moderator','admin') and expires_at>now() for share;
 if not found then raise exception 'moderator_required' using errcode='42501';end if;
end $$;
commit;
