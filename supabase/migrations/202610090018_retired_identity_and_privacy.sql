begin;
create or replace function public.mefrion_list_pets() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'species',p.species,'breed',p.breed,'introduction',p.introduction,'role',case when p.owner_id=auth.uid() then 'owner' else 'family' end) order by p.created_at),'[]'::jsonb) from mefrion_private.pets p where public.mefrion_family_access(p.id));
end $$;
-- Remove the retiring author's free text from private support records, while
-- retaining only the minimum relationship/state needed for safety audit.
create function mefrion_private.retirement_scrub_support() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 update mefrion_private.reports set note='',snapshot='{}'::jsonb where actor_id=new.user_id or target_id=new.user_id;
 delete from mefrion_private.appeals where actor_id=new.user_id;
 delete from mefrion_private.social_blocks where actor_id=new.user_id or target_id=new.user_id;
 return new;
end $$;
revoke all on function mefrion_private.retirement_scrub_support() from public,anon,authenticated;
create trigger mefrion_retirement_support after insert on mefrion_private.account_retirements for each row execute function mefrion_private.retirement_scrub_support();
commit;
