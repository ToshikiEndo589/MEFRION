-- Archived managed inventory may be cleaned by an MFA-verified editor.
-- This does not grant access to ordinary family photos or revive publication.
begin;
create or replace function public.mefrion_seed_delete_photo(p_photo uuid,p_explicit boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare p mefrion_private.photos;
begin
 perform mefrion_private.require_seed('edit');
 select * into p from mefrion_private.photos where id=p_photo for update;
 if p_explicit is distinct from true or not found or not exists(select 1 from mefrion_private.managed_pets where pet_id=p.pet_id) then raise exception 'managed_photo_required' using errcode='42501';end if;
 if p.state='deleted' then return true;end if;
 update mefrion_private.photos set state='deleted' where id=p_photo;
 update mefrion_private.consents set allowed=false,version=version+1 where photo_id=p_photo;
 delete from mefrion_private.cards where first_id=p_photo or second_id=p_photo;
 insert into mefrion_private.deletion_outbox(object_path) values(p.object_path);
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p.pet_id,'seed.photo.delete');
 return true;
end $$;
revoke execute on function public.mefrion_seed_delete_photo(uuid,boolean) from public,anon;
grant execute on function public.mefrion_seed_delete_photo(uuid,boolean) to authenticated;
commit;
