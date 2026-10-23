begin;
-- A former family member retains control over their own provided originals.
-- This does not restore access to family images, metadata or other providers.
create or replace function public.mefrion_delete_photo(p_photo uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_photo mefrion_private.photos;
begin
 perform mefrion_private.require_registered();
 select * into v_photo from mefrion_private.photos where id=p_photo for update;
 if not found or not (v_photo.provider_id=auth.uid() or (public.mefrion_family_access(v_photo.pet_id) and exists(select 1 from mefrion_private.pets where id=v_photo.pet_id and owner_id=auth.uid()))) then raise exception 'permission_required' using errcode='42501';end if;
 if v_photo.state='deleted' then return true;end if;
 update mefrion_private.photos set state='deleted' where id=p_photo;
 update mefrion_private.consents set allowed=false,version=version+1 where photo_id=p_photo;
 delete from mefrion_private.cards where first_id=p_photo or second_id=p_photo;
 insert into mefrion_private.deletion_outbox(object_path) values(v_photo.object_path);
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),v_photo.pet_id,'photo.delete');
 return true;
end $$;
-- Staff annotations stay private; affected users receive a fixed public notice.
create or replace function public.mefrion_my_moderation() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'decision',v.decision,'note',
 case v.decision when 'hide_post' then '運営確認により投稿を非表示にしました。' when 'suspend_account' then '運営確認により公開活動を停止しています。私的写真の管理と同意撤回は引き続き利用できます。' when 'restore_account' then '公開活動の停止を解除しました。以前の投稿は自動で再公開しません。' else '運営による確認を終了しました。' end,
 'created_at',v.created_at)),'[]'::jsonb) from mefrion_private.reports r
 join lateral(select * from mefrion_private.report_reviews where report_id=r.id order by created_at desc,id limit 1) v on true where r.target_id=auth.uid());
end $$;
commit;
