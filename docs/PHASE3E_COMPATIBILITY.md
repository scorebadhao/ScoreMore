# ScoreMore Phase 3E Compatibility Lock

## Purpose

Phase 3E extends the versioned HTML import contract without changing the locked master-question identity or draft-review-publish workflow.

## AI-proposed answers

When no official answer key is supplied, a generated package may include a solved answer with:

- `correct_answer`
- `answer_source: AI_PROPOSED`
- `answer_confidence: HIGH | MEDIUM | LOW`
- a reviewable explanation
- `verification_status: NEEDS_CHECK`

`AI_PROPOSED` is never publication-ready. An administrator must review the question, choose or correct the answer, record a human-verifiable answer source and save the review before publication.

## Topic mapping

Imports may provide either an approved `topic_id` or a suggestion:

- `suggested_topic_code`
- `suggested_topic_name`
- `topic_confidence`

ScoreMore first resolves exact Topic ID, Topic Code, Topic Name and approved aliases. Unresolved suggestions remain visible in the draft review interface. PYQs cannot be published without an approved primary topic.

## Dynamic paper completeness

The optional top-level `paper` object records:

- declared paper size
- extracted source questions
- missing question numbers
- generated supplemental count
- completeness status
- dynamic section boundaries and counts

The importer supports 100, 150 and other paper sizes up to the existing 2,000-record package limit.

## Missing-question safety

- `0` missing: `COMPLETE`
- `1–10` missing: `PARTIAL` or `PARTIAL_WITH_SUPPLEMENTS`
- more than `10` missing: `REJECTED`

A generated replacement is always:

- `question_type: NORMAL`
- `content_origin: AI_GENERATED`
- `is_supplemental: true`
- clearly labelled with `supplement_reason`

It cannot carry original PYQ question identity or be published as an original PYQ.

## Confidence and source quality

The compatibility fields are:

- `transcription_confidence`
- `answer_confidence`
- `topic_confidence`
- `source_quality`
- `answer_review_note`

Source quality values: `CLEAR`, `LOW_RESOLUTION`, `CROPPED`, `DIAGRAM_REVIEW`, `UNREADABLE`.

`UNREADABLE` content is blocked from publication until corrected.
