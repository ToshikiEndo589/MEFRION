begin;
alter table mefrion_private.operators add column expires_at timestamptz;
create or replace function mefrion_private.require_moderator() returns void
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 if auth.jwt()->>'aal' is distinct from 'aal2' or not exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified' and factor_type='totp') then raise exception 'moderator_mfa_required' using errcode='42501';end if;
 perform 1 from mefrion_private.operators where user_id=auth.uid() and active and role in ('moderator','admin') and expires_at>now() for share;
 if not found then raise exception 'moderator_required' using errcode='42501';end if;
end $$;
create or replace function public.mefrion_grant_test_operator(p_user uuid,p_role text,p_active boolean) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'service_required' using errcode='42501';end if;
 if p_role is null or p_role not in ('editor','approver','moderator','admin') or p_active is null or not exists(select 1 from auth.users where id=p_user and raw_user_meta_data->>'test_only'='true' and email like 'mefrion-test-%@example.invalid') then raise exception 'synthetic_fixture_required' using errcode='42501';end if;
 insert into mefrion_private.operators(user_id,role,active,expires_at) values(p_user,p_role,p_active,now()+interval '1 hour') on conflict(user_id) do update set role=excluded.role,active=excluded.active,expires_at=excluded.expires_at;
 insert into mefrion_private.audit(actor_id,action) values(null,'service.test_operator.'||p_role);
 return true;
end $$;
-- No human role is granted by this migration. Bootstrap is a separate reviewed
-- service operation for an identified, confirmed, MFA-enrolled human account.
create or replace function public.mefrion_set_operator(p_user uuid,p_role text,p_active boolean,p_expires timestamptz,p_reason text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'service_required' using errcode='42501';end if;
 if p_role is null or p_role not in ('editor','approver','moderator','admin') or p_active is null or p_reason is null or length(btrim(p_reason)) not between 10 and 200 then raise exception 'operator_invalid';end if;
 if not exists(select 1 from auth.users where id=p_user and email_confirmed_at is not null and deleted_at is null) or exists(select 1 from mefrion_private.account_retirements where user_id=p_user) then raise exception 'active_identity_required';end if;
 if p_active and (p_expires is null or p_expires<=now() or p_expires>now()+interval '90 days' or not exists(select 1 from auth.mfa_factors where user_id=p_user and status='verified' and factor_type='totp')) then raise exception 'mfa_and_limited_expiry_required';end if;
 insert into mefrion_private.operators(user_id,role,active,expires_at) values(p_user,p_role,p_active,p_expires) on conflict(user_id) do update set role=excluded.role,active=excluded.active,expires_at=excluded.expires_at;
 insert into mefrion_private.audit(actor_id,action) values(p_user,'operator.assignment.'||p_role||'.'||p_active::text||'.'||p_reason);
 return true;
end $$;
revoke execute on function public.mefrion_set_operator(uuid,text,boolean,timestamptz,text) from public,anon,authenticated;
grant execute on function public.mefrion_set_operator(uuid,text,boolean,timestamptz,text) to service_role;
create or replace function public.mefrion_retirement_ack(p_user uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_paths jsonb;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'service_required' using errcode='42501';end if;
 select paths into v_paths from mefrion_private.account_retirements where user_id=p_user for update;
 if not found then return false;end if;
 update mefrion_private.deletion_outbox o set state='done' where exists(select 1 from jsonb_array_elements(v_paths) p where p->>'path'=o.object_path and p->>'bucket'=o.bucket);
 update mefrion_private.account_retirements set state='done',completed_at=coalesce(completed_at,now()) where user_id=p_user;
 return true;
end $$;
commit;
