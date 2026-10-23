begin;
create or replace function mefrion_private.withdraw_comment_alias() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' or not new.enabled then
  update mefrion_private.social_comments set state='hidden' where alias_pet=old.pet_id;
  delete from mefrion_private.social_notifications n using mefrion_private.social_comments c where c.alias_pet=old.pet_id and n.kind in ('comment','reply') and n.event_key=c.id::text;
  update mefrion_private.social_identities set last_pet=null where last_pet=old.pet_id;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
revoke all on function mefrion_private.withdraw_comment_alias() from public,anon,authenticated;
create trigger mefrion_withdraw_comment_alias after update of enabled or delete on mefrion_private.public_profiles for each row execute function mefrion_private.withdraw_comment_alias();
commit;
