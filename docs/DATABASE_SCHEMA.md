# ScoreMore Database Schema v1.0

The authoritative schema is the migration:

```text
supabase/migrations/20260804000000_initial_scoremore_schema.sql
```

## Configuration hierarchy

```text
boards
└── exams
    └── subjects
        └── topics
```

All catalogue selectors and test filters use these records. The frontend must not define its own duplicate catalogue.

## Question workflow

```text
source_files
     ↓
import_batches
     ↓
draft_questions
     ↓ human review + publish_draft_question()
questions
     └── question_content
```

`questions.question_id` is a text primary key because the inherited Question ID system must be preserved.

`draft_questions.draft_id` is a UUID because it is an internal workflow record.

Options are stored as JSONB:

```json
{
  "A": "Option A",
  "B": "Option B",
  "C": "Option C",
  "D": "Option D"
}
```

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

For filtered tests, supported initial filter keys are:

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

`attempt_questions` stores the selected question references and their positions for one attempt. It does not duplicate the master question content.

`attempt_answers` has a unique constraint on `(attempt_id, question_id)` so browser retries cannot create duplicate answer records.

## Protected RPC functions

- `get_public_stats()`
- `create_test_attempt(test_id)`
- `get_attempt_questions(attempt_id, offset, limit)`
- `save_attempt_answer(attempt_id, question_id, selected_answer, marked_review, time_taken_seconds)`
- `submit_test_attempt(attempt_id)`
- `get_attempt_review(attempt_id, offset, limit)`
- `publish_draft_question(draft_id)`
- `reject_draft_question(draft_id, notes)`

## Answer protection

Normal students have no direct SELECT policy on `questions`.

During an active attempt, `get_attempt_questions` returns question text and options but excludes:

- correct answer
- explanation
- protected content

After submission, `get_attempt_review` may return the answer and explanation for the owning student.

## Storage

Private bucket:

```text
source-documents
```

Allowed initial MIME types:

- PDF
- PNG
- JPEG
- WebP

Maximum initial object size: 50 MiB.
