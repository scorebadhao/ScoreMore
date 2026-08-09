# ScoreMore Database Schema v1.1

The authoritative schema is the ordered Supabase migration history:

```text
supabase/migrations/20260804000000_initial_scoremore_schema.sql
supabase/migrations/20260804010000_store_signup_mobile.sql
supabase/migrations/20260804020000_admin_fixed_test_manager.sql
supabase/migrations/20260804030000_phase3a_import_foundation.sql
```

## Configuration hierarchy

```text
boards
└── exams
    └── subjects
        └── topics
```

All catalogue selectors, import validators and test filters use these records. The frontend and import packages must not define a second catalogue.

## Question workflow

```text
source_files
     ↓
import_batches
     ├── import_batch_items
     ↓
draft_questions
     ↓ human review + publish_draft_question()
questions
     ├── question_content
     └── question_occurrences
```

### `source_files`

Stores private-upload metadata. `checksum_sha256` has a unique partial index, so the exact same file bytes cannot create another source record after a checksum is supplied.

### `import_batches`

Stores one package-level import run and reconciliation totals.

Phase 3 identity columns:

- `package_id`
- `package_checksum_sha256`
- `source_checksum_sha256`
- `schema_name`
- `schema_version`
- `package_manifest`
- `total_valid`
- `total_warning`
- `total_error`
- `total_duplicate`

`package_id` and canonical package checksum are independently unique when present.

### `import_batch_items`

Stores one immutable reconciliation row for every record found in an import package, including invalid and duplicate records.

Important fields:

- raw and normalized payload
- proposed Question ID
- strict and loose fingerprints
- occurrence key
- validation status
- errors and warnings
- duplicate classification
- matched master question/draft
- created draft

An invalid or duplicate item remains visible in import history even when no draft is created.

### `draft_questions`

Internal UUID workflow records. Phase 3A adds:

- `sort_order`
- `content_origin`
- `content_fingerprint`
- `loose_fingerprint`
- `import_item_id`

Active duplicate draft content and active duplicate proposed Question IDs are blocked by unique partial indexes.

### `questions`

`question_id` remains the inherited text primary key.

Phase 3A adds:

- `content_origin`
- `content_fingerprint`
- `loose_fingerprint`
- `import_item_id`

Student-image readiness fields:

- `student_image_refs`
- `student_image_review_status`
- `student_image_reviewed_by`
- `student_image_reviewed_at`
- `student_image_review_note`

Visual questions remain published master records but are not student-ready until an approved safe crop or a current audited `NO_STUDENT_IMAGE_REQUIRED` decision matches the source-image fingerprint.

`content_fingerprint` is globally unique in the master table. Changing a Question ID or source paper cannot create a second master row with identical strict content.

Options remain JSONB:

```json
{
  "A": "Option A",
  "B": "Option B",
  "C": "Option C",
  "D": "Option D"
}
```

### `question_occurrences`

Stores each authentic paper/shift appearance of a deduplicated master question.

A source occurrence is identified by a server-generated SHA-256 key built from source paper metadata and the original question locator. One occurrence key can reference only one master question.

This supports:

```text
one master question
→ many source occurrences
→ many dynamically configured tests
```

## Fingerprints

### Strict fingerprint

Generated server-side from:

```text
language
question_text
Option A
Option B
Option C
Option D
```

It uses Unicode NFC normalization, lower-casing and whitespace normalization while preserving meaningful punctuation and symbols.

The answer, explanation, Question ID and paper metadata are excluded, so answer disagreements become explicit conflicts instead of separate questions.

### Loose fingerprint

Removes punctuation/whitespace and sorts normalized option text. It raises only `POSSIBLE_DUPLICATE`; it never merges content automatically.

## Content origin

`content_origin` values:

- `SOURCE_EXTRACTED`
- `OCR_EXTRACTED`
- `AI_TRANSCRIBED`
- `MANUAL_ENTRY`
- `RECONSTRUCTED`
- `AI_GENERATED`

`RECONSTRUCTED` and `AI_GENERATED` content cannot be published as an original PYQ.

## Import validation statuses

- `PENDING`
- `VALID`
- `VALID_WITH_WARNINGS`
- `INVALID`
- `EXACT_DUPLICATE`
- `POSSIBLE_DUPLICATE`
- `ID_CONFLICT`
- `ANSWER_CONFLICT`
- `SOURCE_CONFLICT`
- `IMPORTED_TO_DRAFT`
- `LINKED_TO_EXISTING`
- `SKIPPED`

## Test model

`tests` stores test metadata and a JSONB `question_filter`.

Supported selection modes:

- `FIXED_PAPER`
- `FIXED_QUESTION_LIST`
- `FILTERED`
- `RULE_BASED`
- `RANDOMIZED`
- `PERSONALIZED`

For `FIXED_QUESTION_LIST`, use `test_question_links`.

For filtered tests, supported initial filter keys include:

```json
{
  "question_type": "PYQ",
  "board_id": "GSSSB",
  "exam_id": "CCE",
  "subject_id": "REASONING",
  "topic_id": null,
  "exam_year": 2024,
  "exam_date": "2024-04-01",
  "shift_no": 1,
  "paper_code": "0401S1",
  "section_code": "REASONING",
  "difficulty": "MEDIUM"
}
```

Omit unused keys rather than setting empty strings.

## Attempt model

```text
attempts
├── attempt_questions
└── attempt_answers
```

`attempt_questions` stores selected master-question references and their attempt positions. It does not duplicate master question content.

`attempt_answers` has a unique constraint on `(attempt_id, question_id)` so browser retries cannot create duplicate answer rows.

## Protected RPC functions

Student/test workflow:

- `get_public_stats()`
- `create_test_attempt(test_id)`
- `get_attempt_questions(attempt_id, offset, limit)`
- `save_attempt_answer(attempt_id, question_id, selected_answer, marked_review, time_taken_seconds)`
- `submit_test_attempt(attempt_id)`
- `get_attempt_review(attempt_id, offset, limit)`

Admin content/test workflow:

- `publish_draft_question(draft_id)`
- `reject_draft_question(draft_id, notes)`
- `save_fixed_question_test(...)`
- `list_student_image_repair_queue(...)`
- `get_student_image_repair_detail(question_id)`
- `approve_student_image_repair(...)`
- `mark_student_image_not_required(...)`
- `reopen_student_image_review(...)`
- `remove_approved_student_image(...)`

Phase 3 import validation:

- `validate_import_package(manifest, package_checksum, source_checksum)`
- `validate_import_question(question)`
- `link_question_occurrence(question_id, occurrence, import_batch_id, source_file_id, import_item_id)`
- `stage_import_dry_run(manifest, raw_file_checksum, package_checksum, source_file_id)`
- `get_import_batch_report(import_batch_id)`

All import RPCs require an active database-owned ADMIN profile.

## Answer protection

Normal students have no direct SELECT policy on `questions`.

During an active attempt, `get_attempt_questions` excludes answer keys and explanations. After submission, `get_attempt_review` may return them only to the owning student.

## Row Level Security

`import_batch_items` and `question_occurrences` have RLS enabled and admin-only policies. No student or anonymous read policy is added.

## Storage

Private bucket:

```text
source-documents
```

Current private upload types include PDF, PNG, JPEG, WebP and versioned ScoreMore HTML import packages. HTML files remain admin-only and are never rendered or executed.

Private student-safe image bucket:

```text
student-question-images
```

Only admins may upload, update or delete diagram-only crops. An authenticated student may sign an approved object only when its question belongs to one of that student's attempts. Repair metadata and lifecycle state are stored in `question_image_repairs`; audited crop/no-image decisions are stored in `question_image_review_decisions`; the active approved reference is mirrored to `questions.student_image_refs` through admin-only RPCs.

The database readiness predicate is enforced by Test Builder filters, test-link guards, a deferred test-publication guard, the student catalogue policy and new-attempt materialization. Unresolved image questions are never silently skipped to shorten a test.


## Phase 3B dry-run operations

### `stage_import_dry_run()`

Admin-only security-definer RPC. It accepts one validated manifest, raw HTML checksum, canonical package checksum and private `source_file_id`. It:

- reuses an existing exact package report;
- blocks package ID conflicts;
- creates one `import_batches` dry-run row;
- merges source → defaults → item metadata;
- normalizes each record to database-shaped JSON;
- calls `validate_import_question()` for live catalogue and master duplicate checks;
- detects duplicate IDs/content/answers/occurrences inside the same package;
- detects inconsistent passage/group metadata;
- persists every item in `import_batch_items`;
- writes an admin audit event;
- creates no `draft_questions` and no `questions`.

### `get_import_batch_report()`

Returns an admin-only JSON report containing batch/source identity, summary counters and ordered item reconciliation rows.

### Dry-run status values

`import_batches.status` uses:

- `DRY_RUN_PROCESSING`
- `DRY_RUN_COMPLETE`
- `DRY_RUN_COMPLETE_WITH_WARNINGS`
- `DRY_RUN_COMPLETE_WITH_ERRORS`


## Phase 3C controlled draft import

### New import action fields

`import_batches` adds:

- `draft_import_status` (`NOT_STARTED`, `PARTIAL`, `COMPLETE`)
- `total_linked`
- `total_skipped`
- `draft_import_started_at`
- `draft_import_completed_at`

`import_batch_items` adds:

- `resolution_action` (`NONE`, `CREATE_DRAFT`, `LINK_OCCURRENCE`, `SKIP_DUPLICATE`, `BLOCKED`)
- `resolution_notes`
- `resolved_by`
- `resolved_at`

### `import_valid_batch_items_to_drafts()`

Admin-only security-definer RPC. It:

1. locks the selected import batch;
2. accepts only item IDs belonging to that batch;
3. accepts only `VALID` and `VALID_WITH_WARNINGS` records;
4. calls `validate_import_question()` again against current database state;
5. skips records that became duplicates or conflicts;
6. inserts eligible records into `draft_questions`;
7. copies original catalogue, source, chronology, grouping, answer, content-origin and import traceability fields;
8. marks the item `IMPORTED_TO_DRAFT`;
9. records the action in `admin_audit_logs`;
10. returns the refreshed reconciliation report.

It never inserts into `questions`.

### `link_import_batch_occurrences()`

Admin-only security-definer RPC. It accepts only selected `EXACT_DUPLICATE` items that have:

- an exact matched published master question; and
- a valid source occurrence key.

It delegates to `link_question_occurrence()` and therefore stores one master question with another authentic paper occurrence. Possible duplicates cannot use this function.

### Idempotency

- `created_draft_id` is unique.
- Active draft Question IDs and strict content fingerprints remain unique.
- The RPC revalidates immediately before insert.
- Repeated calls return already-imported records instead of creating new drafts.
- Occurrence keys remain unique and cannot point to different master content.


## Phase 3E compatibility

AI-proposed answers, canonical topic mapping, dynamic paper completeness, confidence/source-quality metadata and safely labelled supplemental NORMAL questions are supported. AI-proposed answers and unresolved PYQ topics remain blocked from publication until human review.
