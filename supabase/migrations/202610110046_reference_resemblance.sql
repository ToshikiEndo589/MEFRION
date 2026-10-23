-- Versioned DINOv2 stock descriptors. Legacy clients keep their existing endpoint.
begin;
create table if not exists public.mefrion_reference_resemblance (
 id text primary key references public.mefrion_reference_assets(id) on delete cascade,
 species text not null check(species in ('dog','cat')),
 algorithm text not null check(algorithm='dinov2-small-subject-v1'),
 embedding extensions.vector(384) not null,
 color extensions.vector(64) not null,
 crop_kind text not null check(crop_kind in ('head','animal')),
 check(extensions.vector_norm(embedding) between 0.98 and 1.02),
 check(extensions.vector_norm(color) between 0.98 and 1.02)
);
alter table public.mefrion_reference_resemblance enable row level security;
revoke all on public.mefrion_reference_resemblance from public,anon,authenticated;
grant all on public.mefrion_reference_resemblance to service_role;
create index if not exists mefrion_resemblance_dog on public.mefrion_reference_resemblance using hnsw(embedding extensions.vector_cosine_ops) where species='dog';
create index if not exists mefrion_resemblance_cat on public.mefrion_reference_resemblance using hnsw(embedding extensions.vector_cosine_ops) where species='cat';
create table if not exists public.mefrion_resemblance_retries (
 id uuid primary key, actor text not null, species text not null,
 candidates text[] not null, expires timestamptz not null
);
alter table public.mefrion_resemblance_retries enable row level security;
revoke all on public.mefrion_resemblance_retries from public,anon,authenticated;
grant all on public.mefrion_resemblance_retries to service_role;

create or replace function public.mefrion_reference_stats_v2(p_species text)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('count',(select count(*) from public.mefrion_reference_assets a join public.mefrion_reference_resemblance r using(id) where a.active and a.withdrawn_at is null and a.species=p_species and r.species=a.species),
 'assets',public.mefrion_reference_lookup(array(select a.id from public.mefrion_reference_assets a join public.mefrion_reference_resemblance r using(id) where a.active and a.withdrawn_at is null and a.species=p_species and r.species=a.species order by a.id limit 1)));
$$;
create or replace function public.mefrion_reference_search_v2(p_species text,p_query text,p_color text,p_legacy text,p_fingerprint text,p_mean real,p_algorithm text,p_consent boolean,p_guest uuid,p_request uuid)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='10s' set hnsw.ef_search='240' as $$
declare
 q extensions.vector(384); c extensions.vector(64); legacy extensions.vector(768); fp bit(144);
 actor_id text; today date; used integer; cap integer; chosen text[]='{}';
 prints bit(144)[]='{}'; means real[]='{}'; vectors extensions.vector[]='{}'; credits text[]='{}';
 row_data record; cached record; duplicate boolean; i integer;
begin
 if p_consent is distinct from true or p_species is null or p_species not in ('dog','cat') or p_algorithm is distinct from 'dinov2-small-subject-v1' or p_request is null or p_fingerprint is null or p_fingerprint !~ '^[01]{144}$' or p_mean is null or not(p_mean between 0 and 255) then raise exception 'invalid_reference_query';end if;
 if p_query is null or length(p_query)>16000 or p_color is null or length(p_color)>4096 or p_legacy is null or length(p_legacy)>32000 then raise exception 'invalid_reference_query';end if;
 q=p_query::extensions.vector(384);c=p_color::extensions.vector(64);legacy=p_legacy::extensions.vector(768);fp=p_fingerprint::bit(144);
 if q is null or c is null or legacy is null or extensions.vector_norm(q) not between 0.98 and 1.02 or extensions.vector_norm(c) not between 0.98 and 1.02 then raise exception 'invalid_reference_query';end if;
 if auth.uid() is null then
  if p_guest is null then raise exception 'invalid_reference_guest';end if;
  actor_id='guest:'||p_guest::text;cap=10;
 else actor_id='user:'||auth.uid()::text;cap=50;end if;
 today=(now() at time zone 'Asia/Tokyo')::date;
 select * into cached from public.mefrion_resemblance_retries where id=p_request and actor=actor_id and species=p_species and expires>now();
 if found then return public.mefrion_reference_lookup(cached.candidates);end if;
 insert into public.mefrion_reference_usage(actor,day) values(actor_id,today) on conflict do nothing;
 select count into used from public.mefrion_reference_usage where actor=actor_id and day=today for update;
 select * into cached from public.mefrion_resemblance_retries where id=p_request and actor=actor_id and species=p_species and expires>now();
 if found then return public.mefrion_reference_lookup(cached.candidates);end if;
 if coalesce(auth.role(),'anon')<>'service_role' and used>=cap then raise exception 'reference_search_limit';end if;
 for row_data in
  with nearest as materialized (
   select r.id,r.embedding operator(extensions.<=>) q as semantic,r.color operator(extensions.<=>) c as color_distance
   from public.mefrion_reference_resemblance r join public.mefrion_reference_assets a using(id)
   where a.active and a.withdrawn_at is null and a.species=p_species and r.species=p_species
   order by r.embedding operator(extensions.<=>) q limit 240
  )
  select a.*,n.semantic from nearest n join public.mefrion_reference_assets a using(id)
  where n.semantic<=0.5
  order by n.semantic+0.12*n.color_distance,a.id
 loop
  if row_data.credit=any(credits) or (row_data.embedding operator(extensions.<->) legacy)<=0.08 then continue;end if;
  if abs(row_data.mean-p_mean)<=4 and bit_count(row_data.fingerprint # fp)<=12 then continue;end if;
  duplicate=false;
  for i in 1..coalesce(array_length(chosen,1),0) loop
   if (abs(means[i]-row_data.mean)<=4 and bit_count(prints[i] # row_data.fingerprint)<=12) or (vectors[i] operator(extensions.<->) row_data.embedding)<=0.08 then duplicate=true;exit;end if;
  end loop;
  if duplicate then continue;end if;
  credits=array_append(credits,row_data.credit);chosen=array_append(chosen,row_data.id);prints=array_append(prints,row_data.fingerprint);means=array_append(means,row_data.mean);vectors=array_append(vectors,row_data.embedding);
  if cardinality(chosen)=3 then exit;end if;
 end loop;
 update public.mefrion_reference_usage set count=count+1 where actor=actor_id and day=today;
 insert into public.mefrion_resemblance_retries values(p_request,actor_id,p_species,chosen,now()+interval '10 minutes');
 delete from public.mefrion_resemblance_retries where expires<=now();
 delete from public.mefrion_reference_usage where day<today-2;
 return public.mefrion_reference_lookup(chosen);
end;$$;
revoke all on function public.mefrion_reference_stats_v2(text),public.mefrion_reference_search_v2(text,text,text,text,text,real,text,boolean,uuid,uuid) from public;
grant execute on function public.mefrion_reference_stats_v2(text),public.mefrion_reference_search_v2(text,text,text,text,text,real,text,boolean,uuid,uuid) to anon,authenticated,service_role;
commit;
