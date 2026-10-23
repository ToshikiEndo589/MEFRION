-- Keep keyset paging and per-post block checks index-backed as the feed grows.
-- The published state is checked inside post_allowed(), so this must be a
-- full index: a partial WHERE state='published' index would not be usable by
-- the outer social_page query.
begin;
create index if not exists mefrion_public_post_feed_order
    on mefrion_private.public_posts (published_at desc, id desc);
create index if not exists mefrion_social_block_reverse
    on mefrion_private.social_blocks (target_id, actor_id);
commit;
