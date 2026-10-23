begin;
create table mefrion_private.report_assignments(report_id uuid primary key references mefrion_private.reports(id) on delete cascade,operator_id uuid references auth.users(id) on delete set null,version integer not null default 0,updated_at timestamptz not null default now());
alter table mefrion_private.report_assignments enable row level security;
revoke all on mefrion_private.report_assignments from public,anon,authenticated;
create function mefrion_private.active_report_operator(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.operators where user_id=p_user and active and role in ('moderator','admin') and expires_at>now()) and exists(select 1 from auth.mfa_factors where user_id=p_user and status='verified' and factor_type='totp') and not exists(select 1 from mefrion_private.account_retirements where user_id=p_user)
$$;
revoke all on function mefrion_private.active_report_operator(uuid) from public,anon,authenticated;
create function public.mefrion_operator_claim(p_report uuid,p_version integer,p_claim boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare a mefrion_private.report_assignments;
begin
 perform mefrion_private.require_moderator();
 perform 1 from mefrion_private.reports where id=p_report for update;if not found then raise exception 'report_required';end if;
 insert into mefrion_private.report_assignments(report_id) values(p_report) on conflict do nothing;
 select * into a from mefrion_private.report_assignments where report_id=p_report for update;
 if p_claim is null or p_version is null or p_version<>a.version then raise exception 'assignment_changed';end if;
 if a.operator_id is not null and a.operator_id<>auth.uid() and mefrion_private.active_report_operator(a.operator_id) then raise exception 'other_operator_assigned' using errcode='42501';end if;
 update mefrion_private.report_assignments set operator_id=case when p_claim then auth.uid() else null end,version=version+1,updated_at=now() where report_id=p_report returning * into a;
 insert into mefrion_private.audit(actor_id,action) values(auth.uid(),case when p_claim then 'operator.assignment.claim' else 'operator.assignment.release' end);
 return jsonb_build_object('version',a.version,'mine',a.operator_id=auth.uid(),'assigned',a.operator_id is not null);
end $$;
revoke execute on function public.mefrion_operator_claim(uuid,integer,boolean) from public,anon;
grant execute on function public.mefrion_operator_claim(uuid,integer,boolean) to authenticated;
alter function mefrion_private.report_queue_core() rename to report_queue_without_assignment;
create function mefrion_private.report_queue_core() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item || jsonb_build_object('assignment',jsonb_build_object('version',coalesce(a.version,0),'mine',coalesce(a.operator_id=auth.uid(),false) and mefrion_private.active_report_operator(a.operator_id),'assigned',mefrion_private.active_report_operator(a.operator_id)))),'[]'::jsonb)
 from jsonb_array_elements(mefrion_private.report_queue_without_assignment()) item left join mefrion_private.report_assignments a on a.report_id=(item->>'id')::uuid
$$;
revoke all on function mefrion_private.report_queue_core() from public,anon,authenticated;
create or replace function public.mefrion_operator_review(p_report uuid,p_decision text,p_note text,p_request_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a mefrion_private.report_assignments;
begin
 perform mefrion_private.require_moderator();
 perform 1 from mefrion_private.reports where id=p_report for update;if not found then raise exception 'report_required';end if;
 insert into mefrion_private.report_assignments(report_id) values(p_report) on conflict do nothing;
 select * into a from mefrion_private.report_assignments where report_id=p_report for update;
 if a.operator_id is not null and a.operator_id<>auth.uid() and mefrion_private.active_report_operator(a.operator_id) then raise exception 'other_operator_assigned' using errcode='42501';end if;
 if a.operator_id is distinct from auth.uid() then perform public.mefrion_operator_claim(p_report,a.version,true);end if;
 return mefrion_private.review_report_core(p_report,p_decision,p_note,p_request_key);
end $$;
commit;
