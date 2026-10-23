begin;
create table mefrion_private.twins_shares(id uuid primary key default gen_random_uuid(),actor_id uuid not null references auth.users(id),search_id uuid not null references mefrion_private.twins_searches(id) on delete cascade,query_pet uuid not null references mefrion_private.pets(id),query_source uuid not null references mefrion_private.photos(id),candidate_id uuid not null references mefrion_private.twins_candidates(id),query_version integer not null,candidate_version integer not null,request_key uuid not null,state text not null default 'pending' check(state in ('pending','processing','published','stopped')),lease_until timestamptz,created_at timestamptz not null default now(),unique(actor_id,request_key));
create table mefrion_private.twins_share_media(id uuid primary key default gen_random_uuid(),share_id uuid not null references mefrion_private.twins_shares(id) on delete cascade,source_id uuid not null references mefrion_private.photos(id),position integer not null check(position in (0,1)),object_path text not null unique,unique(share_id,position));
alter table mefrion_private.twins_shares enable row level security;alter table mefrion_private.twins_share_media enable row level security;revoke all on mefrion_private.twins_shares,mefrion_private.twins_share_media from public,anon,authenticated;
create function mefrion_private.twins_share_base(p_id uuid,p_actor uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.twins_shares s join mefrion_private.photos q on q.id=s.query_source and q.state='ready' join mefrion_private.consents c on c.photo_id=q.id and c.purpose='external_share' and c.allowed and c.version=s.query_version join mefrion_private.public_profiles f on f.pet_id=s.query_pet and f.enabled where s.id=p_id and s.state<>'stopped' and mefrion_private.social_actor_visible(p_actor,s.actor_id) and not exists(select 1 from mefrion_private.account_retirements where user_id=s.actor_id) and mefrion_private.managed_public_ready(s.query_pet))
$$;
create function mefrion_private.twins_share_other(p_id uuid,p_actor uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from mefrion_private.twins_shares s join mefrion_private.twins_candidates t on t.id=s.candidate_id join mefrion_private.photos photo on photo.id=t.source_id and photo.state='ready' join mefrion_private.consents c on c.photo_id=photo.id and c.purpose='external_share' and c.allowed and c.version=s.candidate_version where s.id=p_id and mefrion_private.twins_share_base(s.id,p_actor) and mefrion_private.twins_visible(t.id,p_actor))
$$;
create function mefrion_private.stop_twins_share(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 update mefrion_private.twins_shares set state='stopped',lease_until=null where id=p_id;
 insert into mefrion_private.deletion_outbox(object_path,bucket) select object_path,'public-derived' from mefrion_private.twins_share_media m where share_id=p_id and not exists(select 1 from mefrion_private.deletion_outbox d where d.object_path=m.object_path and d.bucket='public-derived' and d.state='pending');
end $$;
create function public.mefrion_share_twins(p_search uuid,p_query uuid,p_candidate uuid,p_key uuid,p_explicit boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare search mefrion_private.twins_searches;candidate mefrion_private.twins_candidates;query mefrion_private.photos;old mefrion_private.twins_shares;v_query integer;v_other integer;id uuid:=gen_random_uuid();media uuid;
begin
 perform mefrion_private.require_registered();
 if p_explicit is distinct from true or p_key is null then raise exception 'explicit_share_required';end if;
 select * into search from mefrion_private.twins_searches where twins_searches.id=p_search and actor_id=auth.uid() and state='results' and p_candidate=any(candidates) for share;
 if not found then raise exception 'own_result_required' using errcode='42501';end if;
 select photo.* into query from mefrion_private.photos photo join mefrion_private.pets p on p.id=photo.pet_id and p.owner_id=auth.uid() join mefrion_private.public_profiles f on f.pet_id=p.id and f.enabled where photo.id=p_query and photo.state='ready' for share of photo,p;
 if not found then raise exception 'owned_public_query_photo_required' using errcode='42501';end if;
 select * into candidate from mefrion_private.twins_candidates where twins_candidates.id=p_candidate and owner_id<>auth.uid() and mefrion_private.twins_visible(twins_candidates.id,auth.uid()) for share;
 if not found then raise exception 'current_candidate_required' using errcode='42501';end if;
 select version into v_query from mefrion_private.consents where photo_id=p_query and purpose='external_share' and allowed for share;
 select version into v_other from mefrion_private.consents where photo_id=candidate.source_id and purpose='external_share' and allowed for share;
 if v_query is null or v_other is null then raise exception 'both_external_consents_required' using errcode='42501';end if;
 select * into old from mefrion_private.twins_shares where actor_id=auth.uid() and request_key=p_key;
 if found then if old.search_id<>p_search or old.query_source<>p_query or old.candidate_id<>p_candidate or old.query_version<>v_query or old.candidate_version<>v_other then raise exception 'idempotency_conflict';end if;return jsonb_build_object('id',old.id,'state',old.state);end if;
 insert into mefrion_private.twins_shares(id,actor_id,search_id,query_pet,query_source,candidate_id,query_version,candidate_version,request_key) values(id,auth.uid(),p_search,query.pet_id,p_query,p_candidate,v_query,v_other,p_key);
 media:=gen_random_uuid();insert into mefrion_private.twins_share_media values(media,id,p_query,0,'twins-share-'||media::text||'.jpg');media:=gen_random_uuid();insert into mefrion_private.twins_share_media values(media,id,candidate.source_id,1,'twins-share-'||media::text||'.jpg');
 return jsonb_build_object('id',id,'state','pending');
end $$;
create function public.mefrion_stop_twins_share(p_share uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();perform 1 from mefrion_private.twins_shares where id=p_share and actor_id=auth.uid() for update;
 if not found then raise exception 'owner_required' using errcode='42501';end if;perform mefrion_private.stop_twins_share(p_share);return true;
end $$;
create function public.mefrion_twins_share_batch() returns jsonb language plpgsql security definer set search_path='' as $$
declare ids uuid[];i uuid;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 for i in select id from mefrion_private.twins_shares where state<>'stopped' and not mefrion_private.twins_share_base(id,null) for update loop perform mefrion_private.stop_twins_share(i);end loop;
 with picked as(select id from mefrion_private.twins_shares where state='pending' or (state='processing' and lease_until<now()) order by created_at limit 10 for update skip locked),updated as(update mefrion_private.twins_shares set state='processing',lease_until=now()+interval '5 minutes' where id in(select id from picked) returning id) select array_agg(id) into ids from updated;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'media',(select jsonb_agg(jsonb_build_object('source_path',p.object_path,'path',m.object_path) order by m.position) from mefrion_private.twins_share_media m join mefrion_private.photos p on p.id=m.source_id where m.share_id=s.id))),'[]') from mefrion_private.twins_shares s where s.id=any(ids));
end $$;
create function public.mefrion_twins_share_ready(p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'worker_required' using errcode='42501';end if;
 perform 1 from mefrion_private.twins_shares where id=p_id for update;
 if not mefrion_private.twins_share_other(p_id,null) or (select count(*) from mefrion_private.twins_share_media m join storage.objects o on o.bucket_id='public-derived' and o.name=m.object_path where share_id=p_id)<>2 then perform mefrion_private.stop_twins_share(p_id);return false;end if;
 update mefrion_private.twins_shares set state='published',lease_until=null where id=p_id;return true;
end $$;
create function mefrion_private.invalidate_twins_shares() returns trigger language plpgsql security definer set search_path='' as $$
declare i uuid;
begin
 for i in select id from mefrion_private.twins_shares where state<>'stopped' and not mefrion_private.twins_share_base(id,null) for update loop perform mefrion_private.stop_twins_share(i);end loop;
 insert into mefrion_private.deletion_outbox(object_path,bucket) select m.object_path,'public-derived' from mefrion_private.twins_share_media m join mefrion_private.twins_shares s on s.id=m.share_id where m.position=1 and not mefrion_private.twins_share_other(s.id,null) and not exists(select 1 from mefrion_private.deletion_outbox d where d.object_path=m.object_path and d.bucket='public-derived' and d.state='pending');return new;
end $$;
create trigger twins_shares_photo_changes after update of state on mefrion_private.photos for each statement execute function mefrion_private.invalidate_twins_shares();
create trigger twins_shares_consent_changes after update on mefrion_private.consents for each statement execute function mefrion_private.invalidate_twins_shares();
create trigger twins_shares_profile_changes after update on mefrion_private.public_profiles for each statement execute function mefrion_private.invalidate_twins_shares();
create trigger twins_shares_candidate_changes after update of state on mefrion_private.twins_candidates for each statement execute function mefrion_private.invalidate_twins_shares();
create function mefrion_private.delete_twins_share() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into mefrion_private.deletion_outbox(object_path,bucket) select object_path,'public-derived' from mefrion_private.twins_share_media m where share_id=old.id and not exists(select 1 from mefrion_private.deletion_outbox d where d.object_path=m.object_path and d.bucket='public-derived' and d.state='pending');return old;
end $$;
create trigger twins_shares_deleted before delete on mefrion_private.twins_shares for each row execute function mefrion_private.delete_twins_share();

create or replace function public.mefrion_shared_projection(p_post uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',s.id,'name',pet.name,'kind','card','text',s.body,'layout',c.layout,'media',(select jsonb_agg(jsonb_build_object('id',m.id,'captured',photo.captured) order by m.position) from mefrion_private.public_media m join mefrion_private.photos photo on photo.id=m.source_id where m.post_id=s.id))
 from mefrion_private.public_posts s join mefrion_private.pets pet on pet.id=s.pet_id join mefrion_private.card_publications cp on cp.post_id=s.id join mefrion_private.cards c on c.id=cp.card_id where s.id=p_post and s.kind='share' and mefrion_private.post_allowed(s.id,auth.uid())
 union all
 select jsonb_build_object('id',s.id,'name',p.name,'kind','twins','text',case when mefrion_private.twins_share_other(s.id,auth.uid()) then 'そっくりな子との出会い' else '相手の掲載は終了しました' end,'candidate_name',case when mefrion_private.twins_share_other(s.id,auth.uid()) then (select pet.name from mefrion_private.twins_candidates t join mefrion_private.pets pet on pet.id=t.pet_id where t.id=s.candidate_id) else null end,'layout','{}'::jsonb,'media',(select jsonb_agg(jsonb_build_object('id',m.id,'captured',case when m.position=0 then photo.captured else null end) order by m.position) from mefrion_private.twins_share_media m join mefrion_private.photos photo on photo.id=m.source_id where m.share_id=s.id and (m.position=0 or mefrion_private.twins_share_other(s.id,auth.uid()))))
 from mefrion_private.twins_shares s join mefrion_private.pets p on p.id=s.query_pet where s.id=p_post and s.state='published' and mefrion_private.twins_share_base(s.id,auth.uid())
$$;
create or replace function public.mefrion_public_image_path(p_media uuid,p_actor uuid default null) returns text language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'gateway_required' using errcode='42501';end if;
 return coalesce((select m.object_path from mefrion_private.public_media m where m.id=p_media and mefrion_private.post_allowed(m.post_id,p_actor)),(select object_path from mefrion_private.twins_candidates where id=p_media and mefrion_private.twins_visible(id,p_actor)),(select m.object_path from mefrion_private.twins_share_media m join mefrion_private.twins_shares s on s.id=m.share_id and s.state='published' where m.id=p_media and mefrion_private.twins_share_base(s.id,p_actor) and (m.position=0 or mefrion_private.twins_share_other(s.id,p_actor))));
end $$;
revoke execute on function mefrion_private.twins_share_base(uuid,uuid),mefrion_private.twins_share_other(uuid,uuid),mefrion_private.stop_twins_share(uuid),mefrion_private.invalidate_twins_shares(),mefrion_private.delete_twins_share() from public,anon,authenticated;
revoke execute on function public.mefrion_share_twins(uuid,uuid,uuid,uuid,boolean),public.mefrion_stop_twins_share(uuid) from public,anon;grant execute on function public.mefrion_share_twins(uuid,uuid,uuid,uuid,boolean),public.mefrion_stop_twins_share(uuid) to authenticated;
revoke execute on function public.mefrion_twins_share_batch(),public.mefrion_twins_share_ready(uuid) from public,anon,authenticated;grant execute on function public.mefrion_twins_share_batch(),public.mefrion_twins_share_ready(uuid) to service_role;

create function mefrion_private.retirement_twins_paths() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket,'path',path)),'[]') into new.paths from (
 select distinct bucket,path from (
 select value->>'bucket' bucket,value->>'path' path from jsonb_array_elements(new.paths)
 union all select 'public-derived',t.object_path from mefrion_private.twins_candidates t join mefrion_private.photos photo on photo.id=t.source_id join mefrion_private.pets pet on pet.id=photo.pet_id where photo.provider_id=new.user_id or pet.owner_id=new.user_id
 union all select 'public-derived',m.object_path from mefrion_private.twins_share_media m join mefrion_private.twins_shares s on s.id=m.share_id join mefrion_private.photos photo on photo.id=m.source_id join mefrion_private.pets pet on pet.id=photo.pet_id where s.actor_id=new.user_id or photo.provider_id=new.user_id or pet.owner_id=new.user_id
 ) merged) unique_paths;return new;
end $$;
create trigger retirement_twins_paths before insert on mefrion_private.account_retirements for each row execute function mefrion_private.retirement_twins_paths();
revoke execute on function mefrion_private.retirement_twins_paths() from public,anon,authenticated;
commit;
