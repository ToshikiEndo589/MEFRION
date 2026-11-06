begin;

alter table mefrion_private.report_reviews add column reviewer_id uuid references auth.users(id) default auth.uid();

-- Every workspace read is aggregate or limited to public posts. Family originals,
-- reporter identities and authentication secrets never enter these projections.
create table mefrion_private.operator_cases (
 id uuid primary key default gen_random_uuid(),
 subject text not null check (length(btrim(subject)) between 1 and 160),
 contact_email text not null default '' check (length(contact_email)<=254),
 detail text not null default '' check (length(detail)<=4000),
 source text not null default 'manual' check (source in ('manual','email')),
 priority text not null default 'normal' check (priority in ('normal','urgent')),
 state text not null default 'open' check (state in ('open','waiting','resolved')),
 due_at timestamptz,
 assigned_to uuid references auth.users(id),
 resolution text not null default '' check (length(resolution)<=2000),
 created_by uuid not null references auth.users(id),
 updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 version integer not null default 1
);
create index operator_cases_worklist on mefrion_private.operator_cases(state,due_at,created_at desc);
alter table mefrion_private.operator_cases enable row level security;
revoke all on mefrion_private.operator_cases from public,anon,authenticated,service_role;

create table mefrion_private.operator_case_history (
 id bigint generated always as identity primary key,
 case_id uuid not null references mefrion_private.operator_cases(id) on delete cascade,
 actor_id uuid not null references auth.users(id),
 action text not null,
 recorded_at timestamptz not null default now()
);
alter table mefrion_private.operator_case_history enable row level security;
revoke all on mefrion_private.operator_case_history from public,anon,authenticated,service_role;

create function public.mefrion_operator_workspace() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform mefrion_private.require_moderator();
 select jsonb_build_object(
  'pending_reports',(select count(*) from mefrion_private.reports where state='open'),
  'pending_posts',(select count(*) from mefrion_private.content_reviews r join mefrion_private.public_posts p on p.id=r.post_id where r.state='pending' and p.state='review'),
  'pending_posts_oldest',(select min(r.created_at) from mefrion_private.content_reviews r join mefrion_private.public_posts p on p.id=r.post_id where r.state='pending' and p.state='review'),
  'open_cases',(select count(*) from mefrion_private.operator_cases where state<>'resolved'),
  'overdue_cases',(select count(*) from mefrion_private.operator_cases where state<>'resolved' and due_at<now()),
  'signups_24h',(select count(*) from auth.users where created_at>=now()-interval '24 hours' and deleted_at is null),
  'signups_7d',(select count(*) from auth.users where created_at>=now()-interval '7 days' and deleted_at is null),
  'new_users_first_post_7d',(select count(*) from auth.users u where u.created_at>=now()-interval '7 days' and u.deleted_at is null
   and exists(select 1 from mefrion_private.public_posts p where p.actor_id=u.id and p.content_origin='user' and p.state='published')),
  'returning_posters_30d',(select count(*) from (select actor_id from mefrion_private.public_posts
   where content_origin='user' and state='published' and published_at>=now()-interval '30 days'
   group by actor_id having count(distinct (published_at at time zone 'Asia/Tokyo')::date)>=2) repeaters),
  'published_24h',(select count(*) from mefrion_private.public_posts where state='published' and published_at>=now()-interval '24 hours'),
  'published_total',(select count(*) from mefrion_private.public_posts where state='published'),
  'failed_jobs',(select count(*) from mefrion_private.cloud_jobs where state='failed'),
  'server_errors_24h',(select count(*) from mefrion_private.security_events where kind='server_error' and occurred_at>=now()-interval '24 hours' and not is_test),
  'storage_bytes',(select coalesce(sum((metadata->>'size')::bigint),0) from storage.objects),
  'database_bytes',pg_database_size(current_database()),
  'recent_actions',(select coalesce(jsonb_agg(to_jsonb(a) order by a.at desc),'[]'::jsonb) from (
    select '投稿' as category,case state when 'approved' then '公開' else '非公開' end as action,decided_at as at from mefrion_private.content_reviews where state<>'pending' and decided_at is not null
    union all select '通報',decision,created_at from mefrion_private.report_reviews
    union all select '問い合わせ',action,recorded_at from mefrion_private.operator_case_history
    order by at desc limit 12
  ) a)
 ) into result;
 return result;
end $$;

create function public.mefrion_operator_post_search(p_query text,p_limit integer default 30) returns jsonb
language plpgsql security definer set search_path='' as $$
declare term text; result jsonb;
begin
 perform mefrion_private.require_moderator();
 term:=left(btrim(coalesce(p_query,'')),80);
 if length(term)<2 or p_limit is null or p_limit not between 1 and 50 then raise exception 'search_invalid';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',q.id,'pet_name',q.pet_name,'body',q.body,'state',q.state,
  'created_at',q.created_at,'published_at',q.published_at,
  'review_state',q.review_state,'reviewed_at',q.reviewed_at,
  'reports',q.reports) order by q.created_at desc),'[]'::jsonb) into result
 from (select p.id,pet.name pet_name,p.body,p.state,p.created_at,p.published_at,
   r.state review_state,r.decided_at reviewed_at,
   (select count(*) from mefrion_private.reports report where report.post_id=p.id) reports
   from mefrion_private.public_posts p
   join mefrion_private.pets pet on pet.id=p.pet_id
   left join mefrion_private.content_reviews r on r.post_id=p.id
   where p.id::text=term or strpos(lower(pet.name),lower(term))>0
    or strpos(lower(p.body),lower(term))>0
   order by p.created_at desc limit p_limit) q;
 return result;
end $$;

create function public.mefrion_operator_post_history(p_post uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform mefrion_private.require_moderator();
 if not exists(select 1 from mefrion_private.public_posts where id=p_post) then raise exception 'post_not_found';end if;
 select jsonb_build_object(
  'review',(select jsonb_build_object('state',r.state,'note',r.note,'decided_at',r.decided_at,'reviewer',coalesce(u.email,'記録なし'))
   from mefrion_private.content_reviews r left join auth.users u on u.id=r.reviewer_id where r.post_id=p_post),
  'reports',(select coalesce(jsonb_agg(jsonb_build_object('reason',reason,'state',state,'created_at',created_at) order by created_at desc),'[]'::jsonb) from mefrion_private.reports where post_id=p_post),
  'decisions',(select coalesce(jsonb_agg(jsonb_build_object('decision',v.decision,'note',v.note,'created_at',v.created_at,'reviewer',coalesce(u.email,'記録なし')) order by v.created_at desc),'[]'::jsonb)
   from mefrion_private.report_reviews v join mefrion_private.reports r on r.id=v.report_id left join auth.users u on u.id=v.reviewer_id where r.post_id=p_post)
 ) into result;
 return result;
end $$;

create function public.mefrion_operator_case_list() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_moderator();
 return (select coalesce(jsonb_agg(to_jsonb(c) order by (c.state='resolved'),c.due_at nulls last,c.created_at desc),'[]'::jsonb)
  from (select cases.id,cases.subject,cases.contact_email,cases.detail,cases.source,cases.priority,cases.state,cases.due_at,
   cases.assigned_to,assignee.email assigned_email,(cases.assigned_to=auth.uid()) mine,cases.resolution,cases.created_at,cases.updated_at,cases.version
   from mefrion_private.operator_cases cases left join auth.users assignee on assignee.id=cases.assigned_to
   order by cases.created_at desc limit 200) c);
end $$;

create function public.mefrion_operator_case_create(p_subject text,p_contact_email text,p_detail text,p_priority text,p_due_at timestamptz) returns uuid
language plpgsql security definer set search_path='' as $$
declare ident uuid;
begin
 perform mefrion_private.require_moderator();
 if length(btrim(coalesce(p_subject,''))) not between 1 and 160 or length(coalesce(p_detail,''))>4000
  or p_priority not in ('normal','urgent') or length(coalesce(p_contact_email,''))>254
  or (coalesce(p_contact_email,'')<>'' and p_contact_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then raise exception 'case_invalid';end if;
 insert into mefrion_private.operator_cases(subject,contact_email,detail,source,priority,due_at,created_by,updated_by)
 values(btrim(p_subject),btrim(coalesce(p_contact_email,'')),coalesce(p_detail,''),'manual',p_priority,p_due_at,auth.uid(),auth.uid()) returning id into ident;
 insert into mefrion_private.operator_case_history(case_id,actor_id,action) values(ident,auth.uid(),'受付');
 return ident;
end $$;

create function public.mefrion_operator_case_update(p_id uuid,p_version integer,p_state text,p_priority text,p_due_at timestamptz,p_resolution text,p_assign_to_me boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare old_case mefrion_private.operator_cases;
begin
 perform mefrion_private.require_moderator();
 if p_state not in ('open','waiting','resolved') or p_priority not in ('normal','urgent') or p_assign_to_me is null or length(coalesce(p_resolution,''))>2000
  or (p_state='resolved' and length(btrim(coalesce(p_resolution,'')))<1) then raise exception 'case_invalid';end if;
 select * into old_case from mefrion_private.operator_cases where id=p_id for update;
 if not found or old_case.version<>p_version then raise exception 'case_changed';end if;
 if old_case.assigned_to is not null and old_case.assigned_to<>auth.uid() then raise exception 'case_assigned';end if;
 update mefrion_private.operator_cases set state=p_state,priority=p_priority,due_at=p_due_at,
  resolution=coalesce(p_resolution,''),assigned_to=case when p_assign_to_me then auth.uid() else null end,
  updated_by=auth.uid(),updated_at=now(),version=version+1 where id=p_id;
 insert into mefrion_private.operator_case_history(case_id,actor_id,action)
 values(p_id,auth.uid(),case p_state when 'resolved' then '解決' when 'waiting' then '回答待ち' else '対応中' end);
 return true;
end $$;

revoke all on function public.mefrion_operator_workspace(),public.mefrion_operator_post_search(text,integer),
 public.mefrion_operator_post_history(uuid),public.mefrion_operator_case_list(),
 public.mefrion_operator_case_create(text,text,text,text,timestamptz),
 public.mefrion_operator_case_update(uuid,integer,text,text,timestamptz,text,boolean) from public,anon;
grant execute on function public.mefrion_operator_workspace(),public.mefrion_operator_post_search(text,integer),
 public.mefrion_operator_post_history(uuid),public.mefrion_operator_case_list(),
 public.mefrion_operator_case_create(text,text,text,text,timestamptz),
 public.mefrion_operator_case_update(uuid,integer,text,text,timestamptz,text,boolean) to authenticated;
commit;
