begin;
-- Dedicated human operator identities are configured separately through a
-- private deployment step. Never publish the owner's login email in this file.
create table mefrion_private.operator_login_allowlist(email text primary key check(email=lower(btrim(email)) and length(email) between 3 and 254),created_at timestamptz not null default now());
alter table mefrion_private.operator_login_allowlist enable row level security;
revoke all on mefrion_private.operator_login_allowlist from public,anon,authenticated,service_role;
create function mefrion_private.operator_login_allowed(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u join mefrion_private.operator_login_allowlist a on a.email=lower(u.email) where u.id=p_user and u.email_confirmed_at is not null and u.deleted_at is null) and not exists(select 1 from mefrion_private.account_retirements where user_id=p_user)
$$;
revoke all on function mefrion_private.operator_login_allowed(uuid) from public,anon,authenticated,service_role;
create function public.mefrion_operator_login_eligible() returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return mefrion_private.operator_login_allowed(auth.uid());
end $$;
revoke all on function public.mefrion_operator_login_eligible() from public,anon,service_role;
grant execute on function public.mefrion_operator_login_eligible() to authenticated;

CREATE OR REPLACE FUNCTION mefrion_private.require_moderator()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform mefrion_private.require_registered();
 if not mefrion_private.operator_login_allowed(auth.uid()) then raise exception 'dedicated_operator_identity_required' using errcode='42501';end if;
 if auth.jwt()->>'aal' is distinct from 'aal2' or not exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified' and factor_type='totp') then raise exception 'moderator_mfa_required' using errcode='42501';end if;
 -- An otherwise valid JWT must not keep moderator access after Auth logout.
 if not exists(select 1 from auth.sessions where user_id=auth.uid() and id::text=auth.jwt()->>'session_id') then raise exception 'moderator_session_revoked' using errcode='42501';end if;
 perform 1 from mefrion_private.operators where user_id=auth.uid() and active and role in ('moderator','admin') and expires_at>now() for share;
 if not found then raise exception 'moderator_required' using errcode='42501';end if;
end $function$
;

CREATE OR REPLACE FUNCTION mefrion_private.seed_access(p_task text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select mefrion_private.operator_login_allowed(auth.uid()) and auth.uid() is not null and auth.jwt()->>'aal'='aal2'
 and not exists(select 1 from mefrion_private.account_retirements where user_id=auth.uid())
 and exists(select 1 from auth.sessions where user_id=auth.uid() and id::text=auth.jwt()->>'session_id')
 and exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified')
 and exists(select 1 from mefrion_private.operators where user_id=auth.uid() and active and expires_at>now() and (role='admin' or (p_task='edit' and role='editor') or (p_task='approve' and role='approver') or (p_task='view' and role in ('editor','approver'))))
$function$
;

CREATE OR REPLACE FUNCTION mefrion_private.active_report_operator(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select mefrion_private.operator_login_allowed(p_user) and exists(select 1 from mefrion_private.operators where user_id=p_user and active and role in ('moderator','admin') and expires_at>now()) and exists(select 1 from auth.mfa_factors where user_id=p_user and status='verified' and factor_type='totp') and not exists(select 1 from mefrion_private.account_retirements where user_id=p_user)
$function$
;

CREATE OR REPLACE FUNCTION public.mefrion_set_operator(p_user uuid, p_role text, p_active boolean, p_expires timestamp with time zone, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'service_required' using errcode='42501';end if;
 if p_role is null or p_role not in ('editor','approver','moderator','admin') or p_active is null or p_reason is null or length(btrim(p_reason)) not between 10 and 200 then raise exception 'operator_invalid';end if;
 if not exists(select 1 from auth.users where id=p_user and email_confirmed_at is not null and deleted_at is null) or exists(select 1 from mefrion_private.account_retirements where user_id=p_user) then raise exception 'active_identity_required';end if;
 if p_active and not mefrion_private.operator_login_allowed(p_user) then raise exception 'dedicated_operator_identity_required' using errcode='42501';end if;
 if p_active and (p_expires is null or p_expires<=now() or p_expires>now()+interval '90 days' or not exists(select 1 from auth.mfa_factors where user_id=p_user and status='verified' and factor_type='totp')) then raise exception 'mfa_and_limited_expiry_required';end if;
 insert into mefrion_private.operators(user_id,role,active,expires_at) values(p_user,p_role,p_active,p_expires) on conflict(user_id) do update set role=excluded.role,active=excluded.active,expires_at=excluded.expires_at;
 insert into mefrion_private.audit(actor_id,action) values(p_user,'operator.assignment.'||p_role||'.'||p_active::text||'.'||p_reason);
 return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.mefrion_grant_test_operator(p_user uuid, p_role text, p_active boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'service_required' using errcode='42501';end if;
 if p_role is null or p_role not in ('editor','approver','moderator','admin') or p_active is null or not exists(select 1 from auth.users where id=p_user and raw_user_meta_data->>'test_only'='true' and email like 'mefrion-test-%@example.invalid') then raise exception 'synthetic_fixture_required' using errcode='42501';end if;
 if p_active then insert into mefrion_private.operator_login_allowlist(email) select lower(email) from auth.users where id=p_user on conflict do nothing;else delete from mefrion_private.operator_login_allowlist where email=(select lower(email) from auth.users where id=p_user);end if;
 insert into mefrion_private.operators(user_id,role,active,expires_at) values(p_user,p_role,p_active,now()+interval '1 hour') on conflict(user_id) do update set role=excluded.role,active=excluded.active,expires_at=excluded.expires_at;
 insert into mefrion_private.audit(actor_id,action) values(null,'service.test_operator.'||p_role);
 return true;
end $function$
;


create function mefrion_private.guard_operator_login_identity() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.active and not mefrion_private.operator_login_allowed(new.user_id) then raise exception 'dedicated_operator_identity_required' using errcode='42501';end if;
 return new;
end $$;
revoke all on function mefrion_private.guard_operator_login_identity() from public,anon,authenticated,service_role;
create trigger operator_login_identity before insert or update of user_id,active,role on mefrion_private.operators for each row execute function mefrion_private.guard_operator_login_identity();
notify pgrst,'reload schema';
commit;
