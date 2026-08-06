-- ScoreMore read-only verification: Shift 1 V2 Q55 recovery + separate publish queue

-- 1. Confirm the new migration is recorded.
select version, name
from supabase_migrations.schema_migrations
where version = '20260806000000';

-- 2. Q55 must be ready/imported, not INVALID.
select
  b.package_id,
  i.item_index,
  i.proposed_question_id,
  i.validation_status,
  i.source_option_anomaly,
  i.source_option_anomaly_note,
  i.errors,
  i.warnings,
  i.created_draft_id,
  i.resolution_action
from public.import_batch_items i
join public.import_batches b on b.import_batch_id = i.import_batch_id
where b.package_id = 'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2'
  and i.proposed_question_id = 'GSSSB-CCE-2024-QUANT-0401S1-0055';

-- 3. Shift 1 V2 should reach 100 actual drafts after Import remaining drafts.
select
  b.package_id,
  count(d.draft_id) as actual_drafts,
  count(*) filter (where d.source_option_anomaly = 'DUPLICATE_OPTIONS_PRINTED') as printed_option_anomaly_drafts,
  count(*) filter (where d.review_status = 'PUBLISHED') as published_drafts
from public.import_batches b
left join public.draft_questions d on d.import_batch_id = b.import_batch_id
where b.package_id = 'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2'
group by b.package_id;

-- 4. Publish queue count and sample IDs.
select public.list_publish_queue(25, 0);

-- 5. No published question should have an untraced printed-option anomaly.
select question_id, source_option_anomaly, source_option_anomaly_note
from public.questions
where source_option_anomaly = 'DUPLICATE_OPTIONS_PRINTED'
  and nullif(btrim(source_option_anomaly_note), '') is null;

-- 6. Recent relevant audit rows.
select created_at, action, entity_type, entity_id, details
from public.admin_audit_logs
where action in (
  'REPAIR_PRINTED_DUPLICATE_OPTIONS',
  'CONFIRM_SOURCE_OPTION_ANOMALY',
  'PUBLISH_DRAFT',
  'PUBLISH_DRAFT_FAILED'
)
order by created_at desc
limit 30;
