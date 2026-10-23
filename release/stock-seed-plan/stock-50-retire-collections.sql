-- Run only after stock-50-individual-pets.sql succeeds. Do not delete rights history.
begin;
do $$
declare old_ids uuid[]:=array[
 '0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,
 'eaccee71-67b0-4222-ae16-ca404a568787'::uuid];
begin
 if (select count(*) from mefrion_private.public_posts post
     join mefrion_private.managed_pets managed on managed.pet_id=post.pet_id
     where managed.external_key like 'stock-individual-%'
       and post.state='published')<>50 then
   raise exception 'individual posts are not all published';
 end if;
 if exists(select 1 from mefrion_private.public_posts where pet_id=any(old_ids) and state='published')
 or exists(select 1 from mefrion_private.photos where pet_id=any(old_ids) and state<>'deleted')
 or exists(select 1 from mefrion_private.seed_jobs where pet_id=any(old_ids) and state<>'published')
 or exists(select 1 from mefrion_private.follows where pet_id=any(old_ids)) then
   raise exception 'collection profiles are still in use';
 end if;
end $$;
-- SQL Editor has no end-user JWT. Restore the gate before this transaction commits.
alter table mefrion_private.public_profiles disable trigger mefrion_public_profile_write;
update mefrion_private.public_profiles set enabled=false
where pet_id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,
                 'eaccee71-67b0-4222-ae16-ca404a568787'::uuid);
alter table mefrion_private.public_profiles enable trigger mefrion_public_profile_write;
update mefrion_private.managed_pets set active=false
where pet_id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,
                 'eaccee71-67b0-4222-ae16-ca404a568787'::uuid);
commit;
select count(*) filter(where profile.enabled) as visible_collections,
       count(*) filter(where managed.active) as active_collections
from mefrion_private.managed_pets managed
join mefrion_private.public_profiles profile on profile.pet_id=managed.pet_id
where managed.pet_id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,
                         'eaccee71-67b0-4222-ae16-ca404a568787'::uuid);
