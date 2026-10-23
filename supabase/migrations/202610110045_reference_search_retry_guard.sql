-- Serialize replay checks and bound incoming feature payloads. Stock tables only.
begin;
create or replace function public.mefrion_reference_search(p_species text,p_query text,p_fingerprint text,p_mean real,p_revision integer,p_consent boolean,p_guest uuid,p_request uuid)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='10s' as $$
declare
 q extensions.vector(768); fp bit(144); actor_id text; today date; used integer; cap integer;
 chosen text[]='{}'; prints bit(144)[]='{}'; means real[]='{}'; vectors extensions.vector[]='{}';
 row_data record; cached record; duplicate boolean; i integer;
begin
 if p_consent is distinct from true or p_species not in ('dog','cat') or p_species is null or p_revision is distinct from 2 or p_request is null or p_fingerprint is null or p_fingerprint !~ '^[01]{144}$' or p_mean is null or p_mean not between 0 and 255 then raise exception 'invalid_reference_query';end if;
 if p_query is null or length(p_query)>32000 then raise exception 'invalid_reference_query';end if;
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
 select * into cached from public.mefrion_reference_retries where id=p_request and actor=actor_id and species=p_species and expires>now();
 if found then return public.mefrion_reference_lookup(cached.candidates);end if;
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
 delete from public.mefrion_reference_usage where day<today-2;
 return public.mefrion_reference_lookup(chosen);
end;$$;
commit;
