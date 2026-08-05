-- ScoreMore visual fingerprint V2 verification (read-only)

select
  count(*) filter (where fingerprint_version = 2) as fingerprint_v2,
  count(*) filter (where fingerprint_version <> 2) as older_fingerprints
from public.draft_questions;

select
  count(*) filter (where fingerprint_version = 2) as fingerprint_v2,
  count(*) filter (where fingerprint_version <> 2) as older_fingerprints
from public.questions;

select
  ib.package_id,
  ib.draft_import_status,
  ib.total_raw,
  ib.total_draft,
  ib.total_error,
  ib.total_duplicate,
  count(*) filter (where i.fingerprint_version < 2 and i.created_draft_id is null) as needs_v2_recheck,
  count(*) filter (where i.validation_status = 'IMPORTED_TO_DRAFT') as imported_items,
  count(*) filter (where i.validation_status = 'LINKED_TO_EXISTING') as linked_items,
  count(*) filter (where i.resolution_action = 'BLOCKED') as blocked_items
from public.import_batches ib
join public.import_batch_items i on i.import_batch_id = ib.import_batch_id
where ib.package_id in (
  'GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2'
)
group by ib.import_batch_id, ib.package_id, ib.draft_import_status,
         ib.total_raw, ib.total_draft, ib.total_error, ib.total_duplicate
order by ib.package_id;

select
  i.item_index,
  i.proposed_question_id,
  i.validation_status,
  i.fingerprint_version,
  i.duplicate_kind,
  i.resolution_action,
  i.created_draft_id,
  i.matched_draft_id,
  i.matched_question_id,
  i.resolution_notes
from public.import_batch_items i
join public.import_batches b on b.import_batch_id = i.import_batch_id
where b.package_id = 'GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1'
  and i.item_index in (10, 37)
order by i.item_index;
