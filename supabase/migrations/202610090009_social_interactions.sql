begin;
create table mefrion_private.social_identities (
 user_id uuid primary key references auth.users(id), name text not null check(length(btrim(name)) between 1 and 40), last_pet uuid references mefrion_private.pets(id)
);
create table mefrion_private.reactions (
 actor_id uuid not null references auth.users(id), post_id uuid not null references mefrion_private.public_posts(id),
 kind text not null check(kind in ('like','save')), created_at timestamptz not null default now(), primary key(actor_id,post_id,kind)
);
create table mefrion_private.follows (
 actor_id uuid not null references auth.users(id), pet_id uuid not null references mefrion_private.pets(id), created_at timestamptz not null default now(), primary key(actor_id,pet_id)
);
create table mefrion_private.social_comments (
 id uuid primary key default gen_random_uuid(), actor_id uuid not null references auth.users(id), post_id uuid not null references mefrion_private.public_posts(id),
 parent_id uuid references mefrion_private.social_comments(id), alias_pet uuid references mefrion_private.pets(id), speaker_name text not null,
 body text not null check(length(body)<=500), request_key uuid not null, state text not null default 'active' check(state in ('active','deleted')),
 created_at timestamptz not null default now(), unique(actor_id,request_key)
);
create table mefrion_private.social_notifications (
 id uuid primary key default gen_random_uuid(), recipient_id uuid not null references auth.users(id), actor_id uuid not null references auth.users(id),
 kind text not null check(kind in ('like','follow','comment','reply')), pet_id uuid not null references mefrion_private.pets(id), post_id uuid references mefrion_private.public_posts(id),
 event_key text not null, created_at timestamptz not null default now(), unique(recipient_id,actor_id,kind,event_key),check(recipient_id<>actor_id)
);
alter table mefrion_private.social_identities enable row level security;
alter table mefrion_private.reactions enable row level security;
alter table mefrion_private.follows enable row level security;
alter table mefrion_private.social_comments enable row level security;
alter table mefrion_private.social_notifications enable row level security;
revoke all on mefrion_private.social_identities,mefrion_private.reactions,mefrion_private.follows,mefrion_private.social_comments,mefrion_private.social_notifications from public,anon,authenticated;
create index mefrion_social_comment_post on mefrion_private.social_comments(post_id,created_at);
create index mefrion_reaction_post on mefrion_private.reactions(post_id,kind);
create index mefrion_notice_recipient on mefrion_private.social_notifications(recipient_id,created_at);

create or replace function mefrion_private.social_actor_visible(p_actor uuid,p_other uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from mefrion_private.public_account_states where user_id=p_other and suspended)
 and not exists(select 1 from mefrion_private.social_blocks where (actor_id=p_actor and target_id=p_other) or (actor_id=p_other and target_id=p_actor))
$$;
create or replace function mefrion_private.social_rate() returns void
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_public_actor();
 if (select count(*) from mefrion_private.audit where actor_id=auth.uid() and action like 'social.write.%' and created_at>now()-interval '1 minute')>=120 then raise exception 'social_rate_limit';end if;
end $$;
create or replace function mefrion_private.social_notify(p_recipient uuid,p_kind text,p_pet uuid,p_post uuid,p_key text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if p_recipient=auth.uid() or not mefrion_private.social_actor_visible(p_recipient,auth.uid()) then return;end if;
 insert into mefrion_private.social_notifications(recipient_id,actor_id,kind,pet_id,post_id,event_key) values(p_recipient,auth.uid(),p_kind,p_pet,p_post,p_key) on conflict do nothing;
end $$;
revoke all on function mefrion_private.social_actor_visible(uuid,uuid),mefrion_private.social_rate(),mefrion_private.social_notify(uuid,text,uuid,uuid,text) from public,anon,authenticated;

create or replace function public.mefrion_set_social_name(p_name text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 if p_name is null or length(btrim(p_name)) not between 1 and 40 then raise exception 'name_invalid';end if;
 insert into mefrion_private.social_identities(user_id,name) values(auth.uid(),btrim(p_name)) on conflict(user_id) do update set name=excluded.name;
 return true;
end $$;
create or replace function public.mefrion_react(p_post uuid,p_kind text,p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_pet uuid;v_owner uuid;
begin
 perform mefrion_private.require_registered();
 if p_kind is null or p_kind not in ('like','save') or p_enabled is null then raise exception 'reaction_invalid';end if;
 if p_enabled then
  perform mefrion_private.social_rate();
  select s.pet_id,p.owner_id into v_pet,v_owner from mefrion_private.public_posts s join mefrion_private.pets p on p.id=s.pet_id where s.id=p_post and mefrion_private.post_allowed(s.id,auth.uid());
  if not found then raise exception 'visible_post_required' using errcode='42501';end if;
  insert into mefrion_private.reactions values(auth.uid(),p_post,p_kind,now()) on conflict do nothing;
  if p_kind='like' then perform mefrion_private.social_notify(v_owner,'like',v_pet,p_post,p_post::text);end if;
  insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v_pet,'social.write.'||p_kind);
 else
  delete from mefrion_private.reactions where actor_id=auth.uid() and post_id=p_post and kind=p_kind;
  if p_kind='like' then delete from mefrion_private.social_notifications where actor_id=auth.uid() and kind='like' and post_id=p_post;end if;
 end if;
 return p_enabled;
end $$;
create or replace function public.mefrion_follow(p_pet uuid,p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_owner uuid;
begin
 perform mefrion_private.require_registered();
 if p_enabled is null then raise exception 'follow_invalid';end if;
 if p_enabled then
  perform mefrion_private.social_rate();
  select pet.owner_id into v_owner from mefrion_private.pets pet join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled where pet.id=p_pet and mefrion_private.social_actor_visible(auth.uid(),pet.owner_id);
  if not found or v_owner=auth.uid() then raise exception 'public_pet_required' using errcode='42501';end if;
  insert into mefrion_private.follows values(auth.uid(),p_pet,now()) on conflict do nothing;
  perform mefrion_private.social_notify(v_owner,'follow',p_pet,null,p_pet::text);
  insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'social.write.follow');
 else
  delete from mefrion_private.follows where actor_id=auth.uid() and pet_id=p_pet;
  delete from mefrion_private.social_notifications where actor_id=auth.uid() and kind='follow' and pet_id=p_pet;
 end if;
 return p_enabled;
end $$;

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
  select * into v_parent from mefrion_private.social_comments where id=p_parent and post_id=p_post and parent_id is null and state='active' and mefrion_private.social_actor_visible(auth.uid(),actor_id);
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
create or replace function public.mefrion_comments(p_post uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'body',case when c.state='deleted' then '' else c.body end,'parent',c.parent_id,'display_name',case when c.state='deleted' then '削除済み' else c.speaker_name end,'mine',c.actor_id=auth.uid(),'deleted',c.state='deleted','created_at',c.created_at) order by c.created_at,c.id),'[]'::jsonb)
 from mefrion_private.social_comments c where c.post_id=p_post and mefrion_private.post_allowed(p_post,auth.uid()) and mefrion_private.social_actor_visible(auth.uid(),c.actor_id)
 and (c.parent_id is null or exists(select 1 from mefrion_private.social_comments parent where parent.id=c.parent_id and mefrion_private.social_actor_visible(auth.uid(),parent.actor_id)))
$$;
create or replace function public.mefrion_delete_comment(p_comment uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 update mefrion_private.social_comments c set state='deleted',body='' where c.id=p_comment and (c.actor_id=auth.uid() or exists(select 1 from mefrion_private.public_posts s join mefrion_private.pets p on p.id=s.pet_id where s.id=c.post_id and p.owner_id=auth.uid()));
 if not found then raise exception 'comment_author_required' using errcode='42501';end if;
 delete from mefrion_private.social_notifications where kind in ('comment','reply') and event_key=p_comment::text;
 return true;
end $$;

create or replace function mefrion_private.social_feed(p_limit integer,p_mode text,p_query text) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(item order by published_at desc,id),'[]'::jsonb) from (
 select s.id,s.published_at,jsonb_build_object('id',s.id,'pet_id',pet.id,'name',pet.name,'species',pet.species,'breed',pet.breed,'body',s.body,'kind',s.kind,'published_at',s.published_at,
 'media',(select jsonb_agg(m.id order by m.position) from mefrion_private.public_media m where m.post_id=s.id),
 'likes',(select count(*) from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and mefrion_private.social_actor_visible(auth.uid(),r.actor_id)),
 'comments',(select count(*) from mefrion_private.social_comments c where c.post_id=s.id and c.state='active' and mefrion_private.social_actor_visible(auth.uid(),c.actor_id) and (c.parent_id is null or exists(select 1 from mefrion_private.social_comments parent where parent.id=c.parent_id and parent.state in ('active','deleted') and mefrion_private.social_actor_visible(auth.uid(),parent.actor_id)))),
 'liked',exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='like' and r.actor_id=auth.uid()),
 'saved',exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid()),
 'following',exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())) item
 from mefrion_private.public_posts s join mefrion_private.pets pet on pet.id=s.pet_id
 where mefrion_private.post_allowed(s.id,auth.uid())
 and (p_mode='all' or (p_mode='saved' and exists(select 1 from mefrion_private.reactions r where r.post_id=s.id and r.kind='save' and r.actor_id=auth.uid())) or (p_mode='following' and exists(select 1 from mefrion_private.follows f where f.pet_id=pet.id and f.actor_id=auth.uid())))
 and (p_query='' or position(pg_catalog.normalize(lower(p_query),'NFKC') in pg_catalog.normalize(lower(pet.name||' '||pet.breed),'NFKC'))>0)
 order by s.published_at desc,s.id limit greatest(1,least(coalesce(p_limit,20),50))) visible
$$;
revoke all on function mefrion_private.social_feed(integer,text,text) from public,anon,authenticated;
create or replace function public.mefrion_public_feed(p_limit integer default 20) returns jsonb
language sql stable security definer set search_path='' as $$select mefrion_private.social_feed(p_limit,'all','')$$;
create or replace function public.mefrion_saved_feed(p_limit integer default 20) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin perform mefrion_private.require_registered();return mefrion_private.social_feed(p_limit,'saved','');end $$;
create or replace function public.mefrion_following_feed(p_limit integer default 20) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin perform mefrion_private.require_registered();return mefrion_private.social_feed(p_limit,'following','');end $$;
create or replace function public.mefrion_search_feed(p_query text,p_limit integer default 20) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin if p_query is null or length(p_query)>100 then raise exception 'query_invalid';end if;return mefrion_private.social_feed(p_limit,'all',btrim(p_query));end $$;

create or replace function mefrion_private.block_social_cleanup() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 delete from mefrion_private.follows f using mefrion_private.pets p where f.pet_id=p.id and ((f.actor_id=new.actor_id and p.owner_id=new.target_id) or (f.actor_id=new.target_id and p.owner_id=new.actor_id));
 delete from mefrion_private.social_notifications where (actor_id=new.actor_id and recipient_id=new.target_id) or (actor_id=new.target_id and recipient_id=new.actor_id);
 return new;
end $$;
revoke all on function mefrion_private.block_social_cleanup() from public,anon,authenticated;
create trigger mefrion_block_social_cleanup after insert on mefrion_private.social_blocks for each row execute function mefrion_private.block_social_cleanup();
create or replace function public.mefrion_social_notifications() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',n.id,'kind',n.kind,'name',coalesce(i.name,'ユーザー'),'pet_name',p.name,'pet_id',p.id,'post_id',n.post_id,'created_at',n.created_at) order by n.created_at desc),'[]'::jsonb)
 from (select * from mefrion_private.social_notifications where recipient_id=auth.uid() order by created_at desc limit 50) n
 join mefrion_private.pets p on p.id=n.pet_id join mefrion_private.public_profiles profile on profile.pet_id=p.id and profile.enabled
 left join mefrion_private.social_identities i on i.user_id=n.actor_id
 where mefrion_private.social_actor_visible(auth.uid(),n.actor_id) and (n.post_id is null or mefrion_private.post_allowed(n.post_id,auth.uid())));
end $$;
revoke execute on function public.mefrion_set_social_name(text),public.mefrion_react(uuid,text,boolean),public.mefrion_follow(uuid,boolean),public.mefrion_comment(uuid,text,uuid,uuid,uuid),public.mefrion_delete_comment(uuid),public.mefrion_saved_feed(integer),public.mefrion_following_feed(integer),public.mefrion_social_notifications() from public,anon;
grant execute on function public.mefrion_set_social_name(text),public.mefrion_react(uuid,text,boolean),public.mefrion_follow(uuid,boolean),public.mefrion_comment(uuid,text,uuid,uuid,uuid),public.mefrion_delete_comment(uuid),public.mefrion_saved_feed(integer),public.mefrion_following_feed(integer),public.mefrion_social_notifications() to authenticated;
revoke execute on function public.mefrion_comments(uuid),public.mefrion_search_feed(text,integer) from public;
grant execute on function public.mefrion_comments(uuid),public.mefrion_search_feed(text,integer) to anon,authenticated;
commit;
