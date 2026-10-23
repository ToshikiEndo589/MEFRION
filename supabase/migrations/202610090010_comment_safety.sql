begin;
alter table mefrion_private.reports add column comment_id uuid references mefrion_private.social_comments(id);
alter table mefrion_private.report_reviews drop constraint report_reviews_decision_check;
alter table mefrion_private.report_reviews add constraint report_reviews_decision_check check(decision in ('dismiss','hide_post','hide_comment','suspend_account','restore_account'));
alter table mefrion_private.social_comments drop constraint social_comments_state_check;
alter table mefrion_private.social_comments add constraint social_comments_state_check check(state in ('active','hidden','deleted'));
create or replace function public.mefrion_report_comment(p_comment uuid,p_reason text,p_note text,p_request_key uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_old mefrion_private.reports;v_comment mefrion_private.social_comments;v_pet uuid;v_id uuid;
begin
 perform mefrion_private.require_registered();
 if p_request_key is null or p_reason is null or p_reason not in ('spam','harassment','animal_welfare','impersonation','copyright','other') or p_note is null or length(p_note)>1000 then raise exception 'report_invalid';end if;
 perform 1 from auth.users where id=auth.uid() for update;
 select * into v_old from mefrion_private.reports where actor_id=auth.uid() and request_key=p_request_key;
 if found then
  if v_old.comment_id is distinct from p_comment or v_old.reason<>p_reason or v_old.note<>p_note then raise exception 'idempotency_conflict';end if;return v_old.id;
 end if;
 if (select count(*) from mefrion_private.reports where actor_id=auth.uid() and created_at>now()-interval '1 hour')>=10 then raise exception 'report_rate_limit';end if;
 select c.* into v_comment from mefrion_private.social_comments c where c.id=p_comment and c.state='active' and mefrion_private.post_allowed(c.post_id,auth.uid()) and mefrion_private.social_actor_visible(auth.uid(),c.actor_id);
 if not found then raise exception 'visible_comment_required' using errcode='42501';end if;
 select pet_id into v_pet from mefrion_private.public_posts where id=v_comment.post_id;
 insert into mefrion_private.reports(actor_id,request_key,post_id,pet_id,target_id,reason,note,snapshot,comment_id)
 values(auth.uid(),p_request_key,v_comment.post_id,v_pet,v_comment.actor_id,p_reason,p_note,jsonb_build_object('display_name',v_comment.speaker_name,'body',v_comment.body),p_comment) returning id into v_id;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v_pet,'report.comment');return v_id;
end $$;
-- A post report and comment report cannot share an idempotency key.
create or replace function public.mefrion_report(p_post uuid,p_pet uuid,p_reason text,p_note text,p_request_key uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_old mefrion_private.reports;v_pet mefrion_private.pets;v_body text;v_snapshot jsonb;v_id uuid;
begin
 perform mefrion_private.require_registered();
 if p_request_key is null or p_reason is null or p_reason not in ('spam','harassment','animal_welfare','impersonation','copyright','other') or p_note is null or length(p_note)>1000 then raise exception 'report_invalid';end if;
 -- Serialize intake and its hourly bound without publishing reporter identity.
 perform 1 from auth.users where id=auth.uid() for update;
 select * into v_old from mefrion_private.reports where actor_id=auth.uid() and request_key=p_request_key;
 if found then
  if v_old.comment_id is not null or v_old.post_id is distinct from p_post or v_old.pet_id is distinct from p_pet or v_old.reason<>p_reason or v_old.note<>p_note then raise exception 'idempotency_conflict';end if;
  return v_old.id;
 end if;
 if (select count(*) from mefrion_private.reports where actor_id=auth.uid() and created_at>now()-interval '1 hour')>=10 then raise exception 'report_rate_limit';end if;
 select pet.* into v_pet from mefrion_private.pets pet join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled where pet.id=p_pet;
 if not found then raise exception 'public_pet_required' using errcode='42501';end if;
 if p_post is not null then
  select body into v_body from mefrion_private.public_posts where id=p_post and pet_id=p_pet and mefrion_private.post_allowed(id,auth.uid());
  if not found then raise exception 'visible_post_required' using errcode='42501';end if;
 end if;
 v_snapshot:=jsonb_build_object('name',v_pet.name,'species',v_pet.species,'breed',v_pet.breed,'body',v_body);
 insert into mefrion_private.reports(actor_id,request_key,post_id,pet_id,target_id,reason,note,snapshot)
 values(auth.uid(),p_request_key,p_post,p_pet,v_pet.owner_id,p_reason,p_note,v_snapshot) returning id into v_id;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'report.create');
 return v_id;
end $$;
create or replace function public.mefrion_review_report(p_report uuid,p_decision text,p_note text,p_request_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_report mefrion_private.reports;v_old mefrion_private.report_reviews;v_id uuid;v_post uuid;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'operator_required' using errcode='42501';end if;
 if p_request_key is null or p_decision is null or p_decision not in ('dismiss','hide_post','hide_comment','suspend_account','restore_account') or p_note is null or length(btrim(p_note)) not between 1 and 1000 then raise exception 'review_invalid';end if;
 select * into v_report from mefrion_private.reports where id=p_report for update;
 if not found then raise exception 'report_required';end if;
 select * into v_old from mefrion_private.report_reviews where request_key=p_request_key;
 if found then
  if v_old.report_id<>p_report or v_old.decision<>p_decision or v_old.note<>p_note then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',v_old.id,'state','resolved');
 end if;
 if p_decision='hide_comment' then
  if v_report.comment_id is null then raise exception 'comment_required';end if;
  update mefrion_private.social_comments set state='deleted',body='' where id=v_report.comment_id;
  delete from mefrion_private.social_notifications where kind in ('comment','reply') and event_key=v_report.comment_id::text;
 elsif p_decision='hide_post' then
  if v_report.comment_id is not null then raise exception 'comment_decision_required';end if;
  if v_report.post_id is null then raise exception 'post_required';end if;
  perform mefrion_private.stop_publication(v_report.post_id);
 elsif p_decision in ('suspend_account','restore_account') then
  perform 1 from auth.users where id=v_report.target_id for update;
  insert into mefrion_private.public_account_states(user_id,suspended) values(v_report.target_id,p_decision='suspend_account') on conflict(user_id) do update set suspended=excluded.suspended;
  if p_decision='suspend_account' then
   update mefrion_private.social_comments set state='hidden' where actor_id=v_report.target_id and state='active';
   delete from mefrion_private.social_notifications where actor_id=v_report.target_id;
   update mefrion_private.public_profiles set enabled=false where pet_id in(select id from mefrion_private.pets where owner_id=v_report.target_id);
   for v_post in select s.id from mefrion_private.public_posts s join mefrion_private.pets p on p.id=s.pet_id where p.owner_id=v_report.target_id loop perform mefrion_private.stop_publication(v_post);end loop;
  end if;
 end if;
 insert into mefrion_private.report_reviews(report_id,request_key,decision,note) values(p_report,p_request_key,p_decision,p_note) returning id into v_id;
 update mefrion_private.reports set state='resolved' where id=p_report;
 -- service action, not a fabricated human operator identity.
 insert into mefrion_private.audit(actor_id,pet_id,action) values(null,v_report.pet_id,'service.review.'||p_decision);
 return jsonb_build_object('id',v_id,'state','resolved');
end $$;
create or replace function public.mefrion_comments(p_post uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'body',case when c.state='deleted' then '' else c.body end,'parent',c.parent_id,'display_name',case when c.state='deleted' then '削除済み' else c.speaker_name end,'mine',c.actor_id=auth.uid(),'deleted',c.state='deleted','created_at',c.created_at) order by c.created_at,c.id),'[]'::jsonb)
 from mefrion_private.social_comments c where c.state in ('active','deleted') and c.post_id=p_post and mefrion_private.post_allowed(p_post,auth.uid()) and mefrion_private.social_actor_visible(auth.uid(),c.actor_id)
 and (c.parent_id is null or exists(select 1 from mefrion_private.social_comments parent where parent.state in ('active','deleted') and parent.id=c.parent_id and mefrion_private.social_actor_visible(auth.uid(),parent.actor_id)))
$$;
create or replace function public.mefrion_report_queue() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'operator_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'post_id',post_id,'comment_id',comment_id,'pet_id',pet_id,'reason',reason,'note',note,'snapshot',snapshot,'state',state,'created_at',created_at,
 'reviews',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'decision',v.decision,'note',v.note,'created_at',v.created_at)),'[]'::jsonb) from mefrion_private.report_reviews v where v.report_id=queue.id),
 'appeals',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'note',a.note,'created_at',a.created_at)),'[]'::jsonb) from mefrion_private.appeals a where a.report_id=queue.id))),'[]'::jsonb)
 from (select * from mefrion_private.reports order by created_at desc limit 50) queue);
end $$;
create or replace function public.mefrion_my_moderation() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'decision',v.decision,'note',
 case v.decision when 'hide_comment' then '運営確認によりコメントを非表示にしました。' when 'hide_post' then '運営確認により投稿を非表示にしました。' when 'suspend_account' then '運営確認により公開活動を停止しています。私的写真の管理と同意撤回は引き続き利用できます。' when 'restore_account' then '公開活動の停止を解除しました。以前の投稿は自動で再公開しません。' else '運営による確認を終了しました。' end,
 'created_at',v.created_at)),'[]'::jsonb) from mefrion_private.reports r
 join lateral(select * from mefrion_private.report_reviews where report_id=r.id order by created_at desc,id limit 1) v on true where r.target_id=auth.uid());
end $$;
create or replace function public.mefrion_social_identity() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select jsonb_build_object('name',name,'last_pet',last_pet) from mefrion_private.social_identities where user_id=auth.uid());
end $$;
revoke execute on function public.mefrion_report_comment(uuid,text,text,uuid),public.mefrion_social_identity() from public,anon;
grant execute on function public.mefrion_report_comment(uuid,text,text,uuid),public.mefrion_social_identity() to authenticated;
commit;
