-- Stock reference search only. Never reads family albums or enrols query photos.
begin;
create extension if not exists vector with schema extensions;
create table if not exists public.mefrion_reference_assets (
 id text primary key check(id ~ '^pexels-[0-9]+$'),
 species text not null check(species in ('dog','cat')),
 file text not null check(file=id||'.jpg'),
 credit text not null check(length(credit) between 1 and 500),
 source text not null check(source ~ '^https://www\.pexels\.com/photo/'),
 demo_only boolean not null default true check(demo_only),
 revision integer not null default 2 check(revision=2),
 embedding extensions.vector(768) not null,
 fingerprint bit(144) not null,
 mean real not null check(mean between 0 and 255),
 active boolean not null default false,
 withdrawn_at timestamptz,
 updated_at timestamptz not null default now()
);
alter table public.mefrion_reference_assets enable row level security;
revoke all on public.mefrion_reference_assets from anon,authenticated;
grant all on public.mefrion_reference_assets to service_role;
create index if not exists mefrion_reference_dog_vectors on public.mefrion_reference_assets using hnsw (embedding extensions.vector_l2_ops) where active and species='dog' and withdrawn_at is null;
create index if not exists mefrion_reference_cat_vectors on public.mefrion_reference_assets using hnsw (embedding extensions.vector_l2_ops) where active and species='cat' and withdrawn_at is null;
create table if not exists public.mefrion_reference_usage (
 actor text not null, day date not null, count integer not null default 0,
 primary key(actor,day)
);
create table if not exists public.mefrion_reference_retries (
 id uuid primary key, actor text not null, species text not null,
 candidates text[] not null, expires timestamptz not null
);
alter table public.mefrion_reference_usage enable row level security;
alter table public.mefrion_reference_retries enable row level security;
revoke all on public.mefrion_reference_usage,public.mefrion_reference_retries from anon,authenticated;
grant all on public.mefrion_reference_usage,public.mefrion_reference_retries to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('reference-thumbnails','reference-thumbnails',false,200000,array['image/jpeg'])
on conflict(id) do nothing;

create or replace function public.mefrion_reference_lookup(p_ids text[])
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'species',a.species,'file',a.file,'credit',a.credit,'source',a.source,'demoOnly',true) order by array_position(p_ids,a.id)),'[]'::jsonb)
 from public.mefrion_reference_assets a where cardinality(p_ids)<=60 and a.id=any(p_ids) and a.active and a.withdrawn_at is null;
$$;
create or replace function public.mefrion_reference_stats(p_species text)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('count',(select count(*) from public.mefrion_reference_assets where active and withdrawn_at is null and species=p_species),
 'assets',public.mefrion_reference_lookup(array(select id from public.mefrion_reference_assets where active and withdrawn_at is null and species=p_species order by id limit 1)));
$$;
create or replace function public.mefrion_reference_image_path(p_id text)
returns text language sql stable security definer set search_path='' as $$
 select file from public.mefrion_reference_assets where id=p_id and active and withdrawn_at is null;
$$;
create or replace function public.mefrion_reference_activate(p_ids text[])
returns integer language plpgsql security definer set search_path='' as $$
declare changed integer;
begin
 update public.mefrion_reference_assets a set active=true,updated_at=now()
 where a.id=any(p_ids) and a.withdrawn_at is null and exists(select 1 from storage.objects o where o.bucket_id='reference-thumbnails' and o.name=a.file);
 get diagnostics changed=row_count;return changed;
end;$$;
create or replace function public.mefrion_reference_withdraw(p_id text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 update public.mefrion_reference_assets set active=false,withdrawn_at=now(),updated_at=now() where id=p_id;
 return found;
end;$$;
create or replace function public.mefrion_reference_search(p_species text,p_query text,p_fingerprint text,p_mean real,p_revision integer,p_consent boolean,p_guest uuid,p_request uuid)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='10s' as $$
declare
 q extensions.vector(768); fp bit(144); actor_id text; today date; used integer; cap integer;
 chosen text[]='{}'; prints bit(144)[]='{}'; means real[]='{}'; vectors extensions.vector[]='{}';
 row_data record; cached record; duplicate boolean; i integer;
begin
 if p_consent is distinct from true or p_species not in ('dog','cat') or p_species is null or p_revision is distinct from 2 or p_request is null or p_fingerprint is null or p_fingerprint !~ '^[01]{144}$' or p_mean is null or p_mean not between 0 and 255 then raise exception 'invalid_reference_query';end if;
 q=p_query::extensions.vector(768);fp=p_fingerprint::bit(144);
 if q is null then raise exception 'invalid_reference_query';end if;
 if auth.uid() is null then
   if p_guest is null then raise exception 'invalid_reference_guest';end if;
   actor_id='guest:'||p_guest::text;today=(now() at time zone 'Asia/Tokyo')::date;cap=10;
 else actor_id='user:'||auth.uid()::text;today=(now() at time zone 'Asia/Tokyo')::date;cap=50;end if;
 -- Same request is replayable for 10 minutes without charging another search.
 select * into cached from public.mefrion_reference_retries where id=p_request and actor=actor_id and species=p_species and expires>now();
 if found then return public.mefrion_reference_lookup(cached.candidates);end if;
 -- Rate counter row is locked to avoid concurrent requests exceeding the cap.
 insert into public.mefrion_reference_usage(actor,day) values(actor_id,today) on conflict do nothing;
 select count into used from public.mefrion_reference_usage where actor=actor_id and day=today for update;
 if coalesce(auth.role(),'anon')<>'service_role' and used>=cap then raise exception 'reference_search_limit';end if;
 for row_data in
   select a.* from public.mefrion_reference_assets a
   where a.active and a.withdrawn_at is null and a.species=p_species
   order by a.embedding operator(extensions.<->) q limit 100
 loop
   if (row_data.embedding operator(extensions.<->) q)>1.1 or (row_data.embedding operator(extensions.<->) q)<=0.08 then continue;end if;
   if abs(row_data.mean-p_mean)<=4 and bit_count(row_data.fingerprint # fp)<=12 then continue;end if;
   duplicate=false;
   for i in 1..coalesce(array_length(chosen,1),0) loop
     if (abs(means[i]-row_data.mean)<=4 and bit_count(prints[i] # row_data.fingerprint)<=12) or (vectors[i] operator(extensions.<->) row_data.embedding)<=0.08 then duplicate=true;exit;end if;
   end loop;
   if duplicate then continue;end if;
   chosen=array_append(chosen,row_data.id);prints=array_append(prints,row_data.fingerprint);means=array_append(means,row_data.mean);vectors=array_append(vectors,row_data.embedding);
   if cardinality(chosen)=3 then exit;end if;
 end loop;
 update public.mefrion_reference_usage set count=count+1 where actor=actor_id and day=today;
 insert into public.mefrion_reference_retries values(p_request,actor_id,p_species,chosen,now()+interval '10 minutes');
 delete from public.mefrion_reference_retries where expires<=now();
 return public.mefrion_reference_lookup(chosen);
end;$$;
revoke all on function public.mefrion_reference_lookup(text[]),public.mefrion_reference_stats(text),public.mefrion_reference_search(text,text,text,real,integer,boolean,uuid,uuid) from public;
grant execute on function public.mefrion_reference_lookup(text[]),public.mefrion_reference_stats(text),public.mefrion_reference_search(text,text,text,real,integer,boolean,uuid,uuid) to anon,authenticated,service_role;
revoke all on function public.mefrion_reference_image_path(text),public.mefrion_reference_activate(text[]),public.mefrion_reference_withdraw(text) from public,anon,authenticated;
grant execute on function public.mefrion_reference_image_path(text),public.mefrion_reference_activate(text[]),public.mefrion_reference_withdraw(text) to service_role;
commit;
