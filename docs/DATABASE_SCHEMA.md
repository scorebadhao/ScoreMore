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

Phase 3 import validation:

- `validate_import_package(manifest, package_checksum, source_checksum)`
- `validate_import_question(question)`
- `link_question_occurrence(question_id, occurrence, import_batch_id, source_file_id, import_item_id)`

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

Current upload types include PDF, PNG, JPEG and WebP. Phase 3B will add controlled HTML package handling without making imported files public.
