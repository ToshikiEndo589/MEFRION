begin;
-- Summary/count reads need only species and IDs, never the large vectors.
create index if not exists mefrion_reference_active_species_ids on public.mefrion_reference_assets(species,id) where active and withdrawn_at is null;
create index if not exists mefrion_resemblance_species_ids on public.mefrion_reference_resemblance(species,id);
-- Separate the count and first-item plans, and avoid per-backend JIT startup
-- on a tiny interactive metadata request. Keep live withdrawal filtering.
create or replace function public.mefrion_reference_stats_v2(p_species text)
returns jsonb language plpgsql stable security definer set search_path='' set jit=off as $$
declare total bigint;sample text;
begin
 if p_species is null or p_species not in ('dog','cat') then return jsonb_build_object('count',0,'assets','[]'::jsonb);end if;
 select count(*) into total from public.mefrion_reference_assets a
 join public.mefrion_reference_resemblance r on r.id=a.id and r.species=a.species
 where a.active and a.withdrawn_at is null and a.species=p_species;
 select a.id into sample from public.mefrion_reference_assets a
 join public.mefrion_reference_resemblance r on r.id=a.id and r.species=a.species
 where a.active and a.withdrawn_at is null and a.species=p_species order by a.id limit 1;
 return jsonb_build_object('count',total,'assets',case when sample is null then '[]'::jsonb else public.mefrion_reference_lookup(array[sample]) end);
end $$;
revoke all on function public.mefrion_reference_stats_v2(text) from public;
grant execute on function public.mefrion_reference_stats_v2(text) to anon,authenticated,service_role;
analyze public.mefrion_reference_assets;
analyze public.mefrion_reference_resemblance;
notify pgrst,'reload schema';
commit;
