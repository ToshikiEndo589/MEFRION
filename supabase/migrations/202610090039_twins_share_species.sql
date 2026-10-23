begin;
create or replace function public.mefrion_share_twins(p_search uuid,p_query uuid,p_candidate uuid,p_key uuid,p_explicit boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare search mefrion_private.twins_searches;candidate mefrion_private.twins_candidates;query mefrion_private.photos;old mefrion_private.twins_shares;v_query integer;v_other integer;id uuid:=gen_random_uuid();media uuid;
begin
 perform mefrion_private.require_registered();
 if p_explicit is distinct from true or p_key is null then raise exception 'explicit_share_required';end if;
 select * into search from mefrion_private.twins_searches where twins_searches.id=p_search and actor_id=auth.uid() and state='results' and p_candidate=any(candidates) for share;
 if not found then raise exception 'own_result_required' using errcode='42501';end if;
 select photo.* into query from mefrion_private.photos photo join mefrion_private.pets p on p.id=photo.pet_id and p.owner_id=auth.uid() and p.species=search.species join mefrion_private.public_profiles f on f.pet_id=p.id and f.enabled where photo.id=p_query and photo.state='ready' for share of photo,p;
 if not found then raise exception 'owned_public_query_photo_required' using errcode='42501';end if;
 select * into candidate from mefrion_private.twins_candidates where twins_candidates.id=p_candidate and owner_id<>auth.uid() and pet_id in(select p.id from mefrion_private.pets p where p.species=search.species) and mefrion_private.twins_visible(twins_candidates.id,auth.uid()) for share;
 if not found then raise exception 'current_candidate_required' using errcode='42501';end if;
 select version into v_query from mefrion_private.consents where photo_id=p_query and purpose='external_share' and allowed for share;
 select version into v_other from mefrion_private.consents where photo_id=candidate.source_id and purpose='external_share' and allowed for share;
 if v_query is null or v_other is null then raise exception 'both_external_consents_required' using errcode='42501';end if;
 select * into old from mefrion_private.twins_shares where actor_id=auth.uid() and request_key=p_key;
 if found then if old.search_id<>p_search or old.query_source<>p_query or old.candidate_id<>p_candidate or old.query_version<>v_query or old.candidate_version<>v_other then raise exception 'idempotency_conflict';end if;return jsonb_build_object('id',old.id,'state',old.state);end if;
 insert into mefrion_private.twins_shares(id,actor_id,search_id,query_pet,query_source,candidate_id,query_version,candidate_version,request_key) values(id,auth.uid(),p_search,query.pet_id,p_query,p_candidate,v_query,v_other,p_key);
 media:=gen_random_uuid();insert into mefrion_private.twins_share_media values(media,id,p_query,0,'twins-share-'||media::text||'.jpg');media:=gen_random_uuid();insert into mefrion_private.twins_share_media values(media,id,candidate.source_id,1,'twins-share-'||media::text||'.jpg');
 return jsonb_build_object('id',id,'state','pending');
end $$;
commit;
