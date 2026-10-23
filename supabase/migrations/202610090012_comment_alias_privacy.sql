begin;
create or replace function mefrion_private.comment_visible(p_comment uuid,p_actor uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.social_comments c where c.id=p_comment and c.state in ('active','deleted')
 and mefrion_private.social_actor_visible(p_actor,c.actor_id)
 and (c.alias_pet is null or exists(select 1 from mefrion_private.public_profiles profile join mefrion_private.pets pet on pet.id=profile.pet_id where profile.pet_id=c.alias_pet and profile.enabled and pet.owner_id=c.actor_id))
 and (c.parent_id is null or exists(select 1 from mefrion_private.social_comments parent where parent.id=c.parent_id and parent.state in ('active','deleted') and mefrion_private.social_actor_visible(p_actor,parent.actor_id)
 and (parent.alias_pet is null or exists(select 1 from mefrion_private.public_profiles profile join mefrion_private.pets pet on pet.id=profile.pet_id where profile.pet_id=parent.alias_pet and profile.enabled and pet.owner_id=parent.actor_id)))))
$$;
revoke all on function mefrion_private.comment_visible(uuid,uuid) from public,anon,authenticated;

create or replace function public.mefrion_comments(p_post uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'body',case when c.state='deleted' then '' else c.body end,'parent',c.parent_id,'display_name',case when c.state='deleted' then '削除済み' else c.speaker_name end,'mine',c.actor_id=auth.uid(),'deleted',c.state='deleted','created_at',c.created_at) order by c.created_at,c.id),'[]'::jsonb)
 from mefrion_private.social_comments c where c.state in ('active','deleted') and c.post_id=p_post and mefrion_private.post_allowed(p_post,auth.uid()) and mefrion_private.social_actor_visible(auth.uid(),c.actor_id)
 and mefrion_private.comment_visible(c.id,auth.uid())
$$;
create or replace function mefrion_private.social_feed(p_limit integer,p_mode text,p_query text) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item order by published_at desc,id),'[]'::jsonb) from (
 select s.id,s.published_at,jsonb_build_object('id',s.id,'pet_id',pet.id,'name',pet.name,'species',pet.species,'breed',pet.breed,'body',s.body,'kind',s.kind,'published_at',s.published_at,
 'media',(select jsonb_agg(m.id order by m.position) from mefrion_private.public_media m where m.post_id=s.id),
 'likes',(select count(*) from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and mefrion_private.social_actor_visible(auth.uid(),r.actor_id)),
 'comments',(select count(*) from mefrion_private.social_comments c where c.post_id=s.id and c.state='active' and mefrion_private.comment_visible(c.id,auth.uid())),
 'liked',exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and r.actor_id=auth.uid()),
 'saved',exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid()),
 'following',exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())) item
 from mefrion_private.public_posts s join mefrion_private.pets pet on pet.id=s.pet_id
 where mefrion_private.post_allowed(s.id,auth.uid())
 and (p_mode='all' or (p_mode='saved' and exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid())) or (p_mode='following' and exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())))
 and (p_query='' or position(pg_catalog.normalize(lower(p_query),'NFKC') in pg_catalog.normalize(lower(pet.name||' '||pet.breed),'NFKC'))>0)
 order by s.published_at desc,s.id limit greatest(1,least(coalesce(p_limit,20),50))) visible
$$;
create or replace function public.mefrion_comment(p_post uuid,p_body text,p_parent uuid,p_alias_pet uuid,p_request_key uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_old mefrion_private.social_comments;v_pet uuid;v_owner uuid;v_parent mefrion_private.social_comments;v_name text;v_id uuid;
begin
 perform mefrion_private.social_rate();
 if p_request_key is null or p_body is null or length(btrim(p_body)) not between 1 and 500 then raise exception 'comment_invalid';end if;
 select * into v_old from mefrion_private.social_comments where actor_id=auth.uid() and request_key=p_request_key;
 if found then
  if v_old.post_id<>p_post or v_old.body<>btrim(p_body) or v_old.parent_id is distinct from p_parent or v_old.alias_pet is distinct from p_alias_pet then raise exception 'idempotency_conflict';end if;
  return v_old.id;
 end if;
 select s.pet_id,p.owner_id into v_pet,v_owner from mefrion_private.public_posts s join mefrion_private.pets p on p.id=s.pet_id where s.id=p_post and mefrion_private.post_allowed(s.id,auth.uid());
 if not found then raise exception 'visible_post_required' using errcode='42501';end if;
 if p_parent is not null then
  select * into v_parent from mefrion_private.social_comments where id=p_parent and post_id=p_post and parent_id is null and state='active' and mefrion_private.comment_visible(id,auth.uid());
  if not found then raise exception 'root_reply_required';end if;
 end if;
 if p_alias_pet is null then select name into v_name from mefrion_private.social_identities where user_id=auth.uid();
 else
  select pet.name into v_name from mefrion_private.pets pet join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled where pet.id=p_alias_pet and pet.owner_id=auth.uid();
 end if;
 if v_name is null then raise exception 'speaker_required' using errcode='42501';end if;
 insert into mefrion_private.social_comments(actor_id,post_id,parent_id,alias_pet,speaker_name,body,request_key) values(auth.uid(),p_post,p_parent,p_alias_pet,v_name,btrim(p_body),p_request_key) returning id into v_id;
 update mefrion_private.social_identities set last_pet=p_alias_pet where user_id=auth.uid();
 perform mefrion_private.social_notify(v_owner,'comment',v_pet,p_post,v_id::text);
 if p_parent is not null and v_parent.actor_id<>v_owner then perform mefrion_private.social_notify(v_parent.actor_id,'reply',v_pet,p_post,v_id::text);end if;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v_pet,'social.write.comment');
 return v_id;
end $$;
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
 select c.* into v_comment from mefrion_private.social_comments c where c.id=p_comment and c.state='active' and mefrion_private.post_allowed(c.post_id,auth.uid()) and mefrion_private.comment_visible(c.id,auth.uid());
 if not found then raise exception 'visible_comment_required' using errcode='42501';end if;
 select pet_id into v_pet from mefrion_private.public_posts where id=v_comment.post_id;
 insert into mefrion_private.reports(actor_id,request_key,post_id,pet_id,target_id,reason,note,snapshot,comment_id)
 values(auth.uid(),p_request_key,v_comment.post_id,v_pet,v_comment.actor_id,p_reason,p_note,jsonb_build_object('display_name',v_comment.speaker_name,'body',v_comment.body),p_comment) returning id into v_id;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v_pet,'report.comment');return v_id;
end $$;
create or replace function public.mefrion_social_notifications() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',n.id,'kind',n.kind,'name',case when n.kind in ('comment','reply') then (select speaker_name from mefrion_private.social_comments c where c.id::text=n.event_key) else coalesce(i.name,'ユーザー') end,'pet_name',p.name,'pet_id',p.id,'post_id',n.post_id,'created_at',n.created_at) order by n.created_at desc),'[]'::jsonb)
 from (select * from mefrion_private.social_notifications where recipient_id=auth.uid() order by created_at desc limit 50) n
 join mefrion_private.pets p on p.id=n.pet_id join mefrion_private.public_profiles profile on profile.pet_id=p.id and profile.enabled
 left join mefrion_private.social_identities i on i.user_id=n.actor_id
 where mefrion_private.social_actor_visible(auth.uid(),n.actor_id) and (n.post_id is null or mefrion_private.post_allowed(n.post_id,auth.uid())) and (n.kind not in ('comment','reply') or exists(select 1 from mefrion_private.social_comments c where c.id::text=n.event_key and c.state='active' and mefrion_private.comment_visible(c.id,auth.uid()))));
end $$;
commit;
