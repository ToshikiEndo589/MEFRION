begin;

-- User media is processed privately, then held for an MFA-protected human
-- review. Managed catalogue posts retain their separate rights approval flow.
alter table mefrion_private.public_posts drop constraint public_posts_state_check;
alter table mefrion_private.public_posts add constraint public_posts_state_check
 check (state in ('pending','processing','review','published','stopped'));

create table mefrion_private.content_reviews (
 post_id uuid primary key references mefrion_private.public_posts(id) on delete cascade,
 state text not null default 'pending' check (state in ('pending','approved','rejected')),
 reviewer_id uuid references auth.users(id),
 note text,
 decided_at timestamptz,
 created_at timestamptz not null default now()
);
create index content_reviews_pending on mefrion_private.content_reviews(created_at) where state='pending';
alter table mefrion_private.content_reviews enable row level security;
revoke all on mefrion_private.content_reviews from public,anon,authenticated;

-- Normalize full-width characters and zero-width separators. This first-pass
-- text filter catches explicit abuse and contact/spam links before insertion;
-- user media itself is still held for human review.
create function mefrion_private.content_text_allowed(p_body text) returns boolean
language sql immutable security definer set search_path='' as $$
 select p_body is not null and length(p_body)<=500 and not (
  regexp_replace(
   replace(replace(replace(pg_catalog.lower(pg_catalog.normalize(p_body,'NFKC')),chr(8203),''),chr(8204),''),chr(8205),''),
   '[[:space:]]','','g')
    ~ '(https?://|www\.|[[:alnum:]_.%+-]+@[[:alnum:].-]+\.[a-z]{2,}|児童ポルノ|レイプ|殺す|死ね|自殺しろ|(^|[^a-z])(porn|nude|rape)([^a-z]|$))'
 )
$$;
revoke all on function mefrion_private.content_text_allowed(text) from public,anon,authenticated;

create function mefrion_private.content_text_gate() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if (tg_table_name='public_posts' and new.content_origin='user' or tg_table_name='social_comments')
    and not mefrion_private.content_text_allowed(new.body) then
  raise exception 'content_text_blocked' using errcode='22023';
 end if;
 return new;
end $$;
revoke all on function mefrion_private.content_text_gate() from public,anon,authenticated;
create trigger content_public_post_text before insert or update of body on mefrion_private.public_posts
 for each row execute function mefrion_private.content_text_gate();
create trigger content_comment_text before insert or update of body on mefrion_private.social_comments
 for each row execute function mefrion_private.content_text_gate();

create or replace function public.mefrion_publication_finish(p_post uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare post mefrion_private.public_posts;finished boolean;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 select * into post from mefrion_private.public_posts where id=p_post for update;
 if not found then return false;end if;
 if post.state='review' then return true;end if;
 if not mefrion_private.managed_public_ready(post.pet_id) then
  perform mefrion_private.stop_publication(p_post);return false;
 end if;
 finished:=mefrion_private.seed_publication_finish_core(p_post);
 if finished and post.content_origin='user' and post.state='processing' then
  update mefrion_private.public_posts set state='review',lease_until=null,published_at=null where id=p_post;
  insert into mefrion_private.content_reviews(post_id) values(p_post) on conflict do nothing;
 end if;
 return finished;
end $$;
revoke all on function public.mefrion_publication_finish(uuid) from public,anon,authenticated;
grant execute on function public.mefrion_publication_finish(uuid) to service_role;

create function public.mefrion_content_review_queue() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_moderator();
 return coalesce((select jsonb_agg(jsonb_build_object(
  'id',s.id,'pet_name',p.name,'body',s.body,'created_at',s.created_at,
  'media',(select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'kind',photo.media_kind) order by m.position),'[]'::jsonb)
   from mefrion_private.public_media m join mefrion_private.photos photo on photo.id=m.source_id where m.post_id=s.id))
  order by r.created_at,s.id)
  from (select r.post_id,r.created_at from mefrion_private.content_reviews r
   join mefrion_private.public_posts s on s.id=r.post_id and s.state='review'
   where r.state='pending' and not exists(select 1 from mefrion_private.account_retirements a where a.user_id=s.actor_id)
   and not exists(select 1 from mefrion_private.public_account_states a where a.user_id=s.actor_id and a.suspended)
   and mefrion_private.post_allowed_review(s.id)
   order by r.created_at,r.post_id limit 50) r
  join mefrion_private.public_posts s on s.id=r.post_id
  join mefrion_private.pets p on p.id=s.pet_id
  ),'[]'::jsonb);
end $$;

create function mefrion_private.post_allowed_review(p_post uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.public_posts s join mefrion_private.public_profiles f on f.pet_id=s.pet_id and f.enabled
  where s.id=p_post and s.state='review'
  and not exists(select 1 from mefrion_private.account_retirements a where a.user_id=s.actor_id)
  and not exists(select 1 from mefrion_private.public_account_states a where a.user_id=s.actor_id and a.suspended)
  and not exists(select 1 from mefrion_private.public_media m
   left join mefrion_private.photos photo on photo.id=m.source_id
   left join mefrion_private.consents c on c.photo_id=photo.id and c.purpose=case when s.kind='post' then 'sns' else 'external_share' end
   where m.post_id=s.id and (photo.state is distinct from 'ready' or c.allowed is distinct from true or c.version is distinct from m.consent_version))
  and exists(select 1 from mefrion_private.public_media m where m.post_id=s.id))
$$;
revoke all on function mefrion_private.post_allowed_review(uuid) from public,anon,authenticated;

create function public.mefrion_content_review_media(p_media uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_moderator();
 return (select jsonb_build_object('path',m.object_path,'kind',photo.media_kind,'post_id',s.id)
  from mefrion_private.public_media m join mefrion_private.public_posts s on s.id=m.post_id
  join mefrion_private.content_reviews r on r.post_id=s.id and r.state='pending'
  join mefrion_private.photos photo on photo.id=m.source_id
  where m.id=p_media and s.state='review' and mefrion_private.post_allowed_review(s.id)
  and exists(select 1 from storage.objects o where o.bucket_id='public-derived' and o.name=m.object_path));
end $$;

create function public.mefrion_content_review_decide(p_post uuid,p_approve boolean,p_note text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare review mefrion_private.content_reviews;
begin
 perform mefrion_private.require_moderator();
 if p_approve is null or p_note is null or length(btrim(p_note)) not between 1 and 500 then raise exception 'review_invalid';end if;
 select * into review from mefrion_private.content_reviews where post_id=p_post for update;
 if not found then raise exception 'review_required';end if;
 if review.state<>'pending' then return jsonb_build_object('state',review.state);end if;
 perform 1 from mefrion_private.public_posts where id=p_post and state='review' for update;
 if not found then raise exception 'post_not_reviewable';end if;
 if p_approve and mefrion_private.post_allowed_review(p_post) and not exists(
  select 1 from mefrion_private.public_media m where m.post_id=p_post
  and not exists(select 1 from storage.objects o where o.bucket_id='public-derived' and o.name=m.object_path)) then
  update mefrion_private.public_posts set state='published',published_at=now() where id=p_post;
  update mefrion_private.content_reviews set state='approved',reviewer_id=auth.uid(),note=btrim(p_note),decided_at=now() where post_id=p_post;
 else
  perform mefrion_private.stop_publication(p_post);
  update mefrion_private.content_reviews set state='rejected',reviewer_id=auth.uid(),note=btrim(p_note),decided_at=now() where post_id=p_post;
 end if;
 insert into mefrion_private.audit(actor_id,action) values(auth.uid(),case when p_approve then 'content.review.approve' else 'content.review.reject' end);
 return jsonb_build_object('state',(select state from mefrion_private.content_reviews where post_id=p_post));
end $$;
revoke all on function public.mefrion_content_review_queue(),public.mefrion_content_review_media(uuid),public.mefrion_content_review_decide(uuid,boolean,text) from public,anon;
grant execute on function public.mefrion_content_review_queue(),public.mefrion_content_review_media(uuid),public.mefrion_content_review_decide(uuid,boolean,text) to authenticated;

commit;
