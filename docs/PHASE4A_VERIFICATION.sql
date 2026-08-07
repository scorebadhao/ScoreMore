-- ScoreMore Phase 4A verification
-- Run after 20260807010000_phase4a_dynamic_multifilter_test_builder.sql is green.
-- These queries are read-only.

-- 1. Migration history
select version
from supabase_migrations.schema_migrations
where version = '20260807010000';

-- 2. Required view and functions
select
  to_regclass('public.phase4a_question_package_catalogue') as catalogue_view,
  to_regprocedure('public.get_phase4a_test_builder_facets(jsonb)') as facets_rpc,
  to_regprocedure('public.search_phase4a_test_builder_questions(jsonb,text,text,integer,integer)') as search_rpc,
  to_regprocedure('public.select_all_phase4a_test_builder_question_ids(jsonb,text,text)') as select_all_rpc,
  to_regprocedure('public.preview_phase4a_dynamic_test(text,jsonb,text[],text,public.test_type)') as preview_rpc,
  to_regprocedure('public.save_phase4a_dynamic_test(text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean)') as save_rpc;

-- 3. Supporting indexes
select indexname
from pg_indexes
where schemaname = 'public'
  and indexname in (
    'import_batches_phase4a_supersedes_idx',
    'questions_phase4a_import_batch_idx',
    'question_occurrences_phase4a_batch_idx'
  )
order by indexname;

-- 4. Browser roles must not have direct SELECT on the package catalogue view
select
  has_table_privilege('anon', 'public.phase4a_question_package_catalogue', 'select') as anon_can_select,
  has_table_privilege('authenticated', 'public.phase4a_question_package_catalogue', 'select') as authenticated_can_select;
-- Expected: false / false. Access is only through admin-checked security-definer RPCs.

-- 5. Import package version status
select
  b.package_id,
  b.package_version,
  b.supersedes_package_id,
  b.paper_completeness_status,
  not exists (
    select 1
    from public.import_batches newer
    where newer.supersedes_package_id = b.package_id
  ) as is_active_version
from public.import_batches b
where b.package_id in (
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V1',
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2',
  'GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1'
)
order by b.package_id;
-- Expected: Shift 1 V1 inactive; Shift 1 V2 and Shift 3 V1 active.

-- 6. Published memberships by package
select
  package_id,
  bool_or(is_active_version) as is_active_version,
  max(paper_completeness_status) as completeness_status,
  count(*) as membership_rows,
  count(distinct question_id) as unique_published_questions,
  count(distinct question_id) filter (where membership_type = 'SOURCE_PYQ') as source_pyq,
  count(distinct question_id) filter (where membership_type = 'SUPPLEMENTAL_NORMAL') as supplemental_normal,
  count(distinct question_id) filter (where membership_type = 'PACKAGE_NORMAL') as package_normal,
  count(*) - count(distinct question_id) as repeated_memberships
from public.phase4a_question_package_catalogue
where package_id in (
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2',
  'GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1'
)
group by package_id
order by package_id;
-- When fully published:
-- Shift 1 V2 => 100 source, 0 supplement.
-- Shift 3 V1 => 99 source, 1 supplemental NORMAL.

-- 7. Dynamic subject distribution across the two real packages
select
  subject_id,
  max(subject_name) as subject_name,
  count(distinct question_id) as unique_questions,
  count(distinct package_id) as package_count
from public.phase4a_question_package_catalogue
where package_id in (
  'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2',
  'GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1'
)
  and is_active_version
group by subject_id
order by subject_id;

-- 8. Verify every published import question has exactly one master row
select content_fingerprint, count(*) as master_rows
from public.questions
where question_status = 'PUBLISHED'
group by content_fingerprint
having count(*) > 1;
-- Expected: zero rows.

-- 9. Phase 4A tests and provenance after creating a test
select
  test_id,
  test_name,
  test_type,
  selection_mode,
  question_count,
  status,
  question_filter ->> 'builder_mode' as builder_mode,
  question_filter -> 'import_package_ids' as import_package_ids,
  question_filter ->> 'duplicate_handling' as duplicate_handling,
  question_filter ->> 'supplemental_count' as supplemental_count
from public.tests
where question_filter ->> 'schema' = 'scoremore.phase4a-test-builder'
order by updated_at desc;

-- 10. Link count and position integrity
select
  t.test_id,
  t.question_count,
  count(l.question_id) as linked_questions,
  count(distinct l.question_id) as distinct_questions,
  min(l.position) as first_position,
  max(l.position) as last_position
from public.tests t
join public.test_question_links l on l.test_id = t.test_id
where t.question_filter ->> 'schema' = 'scoremore.phase4a-test-builder'
group by t.test_id, t.question_count
order by t.test_id;
-- Expected per test: question_count = linked_questions = distinct_questions,
-- first_position = 1 and last_position = question_count.

-- 11. Audit trail
select created_at, admin_user_id, entity_id as test_id, details
from public.admin_audit_logs
where action = 'SAVE_PHASE4A_DYNAMIC_TEST'
order by created_at desc
limit 25;
