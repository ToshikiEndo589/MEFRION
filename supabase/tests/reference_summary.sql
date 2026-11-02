begin;
create temporary table summary_test_results(name text,passed boolean);
create function pg_temp.summary_assert(label text,ok boolean) returns void language plpgsql security definer as $$
begin
 if ok is distinct from true then raise exception 'reference summary assertion failed: %',label;end if;
 insert into summary_test_results values(label,true);
end $$;
grant execute on function pg_temp.summary_assert(text,boolean) to anon,authenticated;
do $$
declare v_species text;result jsonb;expected bigint;sample jsonb;
begin
 for v_species in select unnest(array['dog','cat']) loop
  select count(*) into expected from public.mefrion_reference_assets a join public.mefrion_reference_resemblance r on r.id=a.id and r.species=a.species where a.active and a.withdrawn_at is null and a.species=v_species;
  execute 'set local role anon';
  result:=public.mefrion_reference_stats_v2(v_species);
  perform pg_temp.summary_assert(v_species||' summary only exposes count and preview',(select array_agg(k order by k) from jsonb_object_keys(result) k)=array['assets','count']);
  perform pg_temp.summary_assert(v_species||' count matches live eligible candidates',(result->>'count')::bigint=expected);
  if expected>0 then
   sample:=result->'assets'->0;
   perform pg_temp.summary_assert(v_species||' preview has matching species',sample->>'species'=v_species);
   perform pg_temp.summary_assert(v_species||' no descriptors exposed',not(sample ?| array['embedding','color','fingerprint','owner_id']));
  end if;
  execute 'reset role';
 end loop;
 execute 'set local role anon';
 perform pg_temp.summary_assert('unsupported species remains empty',public.mefrion_reference_stats_v2('bird')='{"count":0,"assets":[]}'::jsonb);
 perform pg_temp.summary_assert('null species remains empty',public.mefrion_reference_stats_v2(null)='{"count":0,"assets":[]}'::jsonb);
 execute 'reset role';
end $$;
select count(*) as checks,bool_and(passed) as passed from summary_test_results;
rollback;
