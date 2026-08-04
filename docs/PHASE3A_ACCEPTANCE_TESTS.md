# ScoreMore Phase 3A Acceptance Tests

Run these checks only after `20260804030000_phase3a_import_foundation.sql` deploys successfully.

## 1. Migration history

In Supabase SQL Editor:

```sql
select version, name
from supabase_migrations.schema_migrations
order by version;
```

Expected latest migration:

```text
20260804030000  phase3a_import_foundation
```

## 2. New tables

```sql
select to_regclass('public.import_batch_items') as import_batch_items,
       to_regclass('public.question_occurrences') as question_occurrences;
```

Both values must be non-null.

## 3. Fingerprint backfill

```sql
select
  question_id,
  length(content_fingerprint) as strict_length,
  length(loose_fingerprint) as loose_length,
  content_origin
from public.questions
order by question_id;
```

Every existing question must show both fingerprint lengths as `64`.

```sql
select
  draft_id,
  proposed_question_id,
  length(content_fingerprint) as strict_length,
  length(loose_fingerprint) as loose_length,
  content_origin,
  sort_order
from public.draft_questions
order by created_at;
```

Every existing draft must show both fingerprint lengths as `64`. Existing manual records may have `sort_order` as null; Phase 3 imports will supply it.

## 4. Duplicate constraints

```sql
select indexname
from pg_indexes
where schemaname = 'public'
  and indexname in (
    'source_files_checksum_sha256_uidx',
    'import_batches_package_id_uidx',
    'import_batches_package_checksum_uidx',
    'questions_content_fingerprint_uidx',
    'draft_questions_active_content_fingerprint_uidx',
    'draft_questions_active_proposed_id_uidx'
  )
order by indexname;
```

Expected: six rows.

## 5. RLS and policies

```sql
select relname, relrowsecurity
from pg_class
where oid in (
  'public.import_batch_items'::regclass,
  'public.question_occurrences'::regclass
)
order by relname;
```

Both rows must show `relrowsecurity = true`.

```sql
select tablename, policyname
from pg_policies
where schemaname = 'public'
  and tablename in ('import_batch_items', 'question_occurrences')
order by tablename, policyname;
```

Expected policies:

```text
import_batch_items_admin_all
question_occurrences_admin_all
```

## 6. RPC presence

```sql
select proname
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'validate_import_package',
    'validate_import_question',
    'link_question_occurrence',
    'build_question_fingerprints',
    'build_question_occurrence_key'
  )
order by proname;
```

Expected: five rows.

## 7. Existing workflow regression

On the deployed website verify:

1. Public statistics load.
2. Student sign-in still redirects to `student.html`.
3. The published Reasoning test appears.
4. Start/resume/submit still works.
5. Admin draft review still opens.
6. Existing published question remains visible.
7. Test Manager still lists the published test.

## 8. Phase 3B boundary

Phase 3A adds no HTML import interface. Do not expect a new admin upload section yet. The dry-run parser and reconciliation UI begin in Phase 3B.
