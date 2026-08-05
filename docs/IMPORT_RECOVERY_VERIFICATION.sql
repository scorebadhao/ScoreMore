-- ScoreMore import recovery verification (read-only)
-- Run in Supabase SQL Editor after deploying the recovery migration and testing the UI.

-- 1. Batch counters and current draft-import state.
select
  ib.package_id,
  ib.import_batch_id,
  ib.status as dry_run_status,
  ib.draft_import_status,
  ib.total_raw,
  ib.total_valid,
  ib.total_warning,
  ib.total_error,
  ib.total_duplicate,
  ib.total_draft,
  ib.total_linked,
  ib.total_skipped,
  ib.created_at,
  ib.completed_at,
  ib.draft_import_completed_at
from public.import_batches ib
where ib.package_id in (
  'GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2'
)
order by ib.created_at desc;

-- 2. Authoritative item-status distribution.
select
  ib.package_id,
  ibi.validation_status,
  ibi.resolution_action,
  count(*) as item_count
from public.import_batches ib
join public.import_batch_items ibi on ibi.import_batch_id = ib.import_batch_id
where ib.package_id in (
  'GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2'
)
group by ib.package_id, ibi.validation_status, ibi.resolution_action
order by ib.package_id, ibi.validation_status, ibi.resolution_action;

-- 3. Actual drafts versus ledger counters. Zero rows means no mismatch.
select
  ib.package_id,
  ib.total_draft as ledger_drafts,
  count(d.draft_id) as actual_drafts
from public.import_batches ib
left join public.draft_questions d on d.import_batch_id = ib.import_batch_id
where ib.package_id in (
  'GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2'
)
group by ib.package_id, ib.total_draft
having ib.total_draft <> count(d.draft_id);

-- 4. Duplicate draft protection. Zero rows is required.
select import_item_id, count(*) as draft_count
from public.draft_questions
where import_item_id is not null
group by import_item_id
having count(*) > 1;

-- 5. Confirm that this recovery workflow has published nothing automatically.
select
  ib.package_id,
  count(q.question_id) as published_master_questions_from_batch
from public.import_batches ib
left join public.questions q on q.import_batch_id = ib.import_batch_id
where ib.package_id in (
  'GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2'
)
group by ib.package_id
order by ib.package_id;
