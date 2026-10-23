begin;
-- require_seed holds the operator row while authorizing. These POST RPCs must
-- use a writable transaction even though their returned payload is read-only.
alter function public.mefrion_seed_list() volatile;
alter function public.mefrion_seed_audit() volatile;
alter function public.mefrion_seed_metrics() volatile;
commit;
