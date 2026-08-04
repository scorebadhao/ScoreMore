# ScoreMore Phase 3B Acceptance Tests

**Scope:** Safe HTML package parsing, SHA-256 identity, persistent dry-run reconciliation and duplicate reporting.  
**Important:** Phase 3B must create no `draft_questions` and no published `questions`.

## 1. Deployment order

1. Commit `supabase/migrations/20260804040000_phase3b_import_dry_run.sql`.
2. Run **Deploy ScoreMore Database** with `DEPLOY_SCOREMORE`.
3. After the database workflow is green, upload the Phase 3B frontend/docs files.
4. Wait for **Deploy ScoreMore to GitHub Pages** to become green.

## 2. Database objects

Run in Supabase SQL Editor:

```sql
select proname
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'normalize_import_question_payload',
    'get_import_batch_report',
    'stage_import_dry_run'
  )
order by proname;
```

Expected: 3 rows.

## 3. Admin UI smoke test

Open:

```text
https://scorebadhao.github.io/ScoreMore/admin.html?v=phase3b
```

Confirm:

- **HTML Question Import** appears.
- The page states that imported HTML is never executed.
- **Import valid records to drafts** is disabled.
- Recent dry runs can be opened.

## 4. Safe parser test

Choose:

```text
examples/import/ScoreMore_Phase3B_DryRun_Sample.html
```

Expected local inspection:

- Schema: `1.0.0`
- Records: `2`
- Raw HTML SHA-256 displayed
- Canonical package SHA-256 displayed
- No imported HTML is visually embedded in the admin page

## 5. Authoritative dry run

Tap **Run dry validation**.

Expected:

- A persistent import batch is created.
- No draft question is created.
- No published question is created.
- `Q001` should normally match the previously published sample question and report an exact duplicate.
- `Q002` should normally report `VALID` and `Ready for draft`, unless the same content was already added separately.

Read-only verification:

```sql
select
  package_id,
  status,
  total_raw,
  total_valid,
  total_warning,
  total_error,
  total_duplicate,
  total_draft,
  total_published
from public.import_batches
where package_id = 'GSSSB-CCE-PHASE3B-DRYRUN-V1';
```

Expected:

- `total_raw = 2`
- `total_draft = 0`
- `total_published = 0`

```sql
select
  item_index,
  source_record_id,
  proposed_question_id,
  validation_status,
  duplicate_kind,
  matched_question_id,
  jsonb_array_length(errors) as error_count,
  jsonb_array_length(warnings) as warning_count
from public.import_batch_items
where import_batch_id = (
  select import_batch_id
  from public.import_batches
  where package_id = 'GSSSB-CCE-PHASE3B-DRYRUN-V1'
)
order by item_index;
```

Expected: 2 persistent item rows.

## 6. Exact same file re-import

Run the exact same HTML file again.

Expected:

- Existing report is reused.
- No second `source_files` row.
- No second `import_batches` row.
- No additional `import_batch_items` rows.

```sql
select count(*)
from public.import_batches
where package_id = 'GSSSB-CCE-PHASE3B-DRYRUN-V1';
```

Expected: `1`.

## 7. Same package ID with changed content

Make a local test copy, change one option, but keep the same `package_id`.

Expected:

- `PACKAGE_ID_CONFLICT`
- No new import batch
- No new item rows

## 8. Unsafe/malformed HTML

Test these separately:

- HTML without `#scoremore-import-data`
- HTML with two matching payload scripts
- invalid JSON
- unsupported `schema_version`
- unknown top-level field
- missing option D

Expected:

- Client validation blocks upload when structurally unsafe/invalid.
- Server validation remains authoritative for package identity and live catalogue checks.

## 9. Download reconciliation

Tap **Download report**.

Expected JSON contains:

- file name and file size
- raw and canonical checksums
- client schema validation
- persistent batch summary
- every item status, errors, warnings and duplicate match

## 10. Regression checks

Confirm all still work:

- manual draft creation
- human review and publication
- fixed-question Test Manager
- public catalogue
- student start/resume/submit
- admin role protection

## 11. Phase 3B completion gate

Phase 3C may begin only after:

- exact same file produces zero duplicate source/batch/item rows;
- package ID conflicts are blocked;
- dry run creates no drafts or master questions;
- item statuses are readable on Android;
- reconciliation download works;
- existing question/test/student flows pass regression.
