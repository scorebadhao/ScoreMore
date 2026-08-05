# Phase 3E Compatibility Acceptance Tests

## Deployment order

1. Apply `20260805000000_add_ai_proposed_answer_source.sql`.
2. Apply `20260805000100_phase3e_compatibility.sql`.
3. Deploy the frontend/documentation patch.

## Test A — AI answer and topic mapping

Run `ScoreMore_Phase3E_AI_Answer_Topic.html`.

Expected:

- package accepted with warnings
- one record ready for draft
- answer source shown as `AI_PROPOSED`
- answer confidence shown as `HIGH`
- suggested `NUMBER_SERIES` maps to `REASONING-NUMBER-SERIES`
- direct publication is blocked
- review dialog allows answer/source/explanation/topic confirmation
- after saving review, `verification_status = VERIFIED`, `answer_source = MANUALLY_VERIFIED` (or an official source), and publication becomes available

Reject the synthetic draft after testing.

## Test B — one missing question with supplement

Run `ScoreMore_Phase3E_One_Missing_Supplement.html`.

Expected:

- declared total 2
- extracted source 1
- missing 1
- supplements 1
- status `PARTIAL_WITH_SUPPLEMENTS`
- source record remains PYQ
- supplemental record is `NORMAL`, `AI_GENERATED`, clearly labelled, and has no original PYQ occurrence identity

Reject both synthetic drafts after testing.

## Test C — more than ten missing

Run `ScoreMore_Phase3E_Reject_11_Missing.html`.

Expected:

- local schema/package validation stops
- `MISSING_QUESTION_LIMIT_EXCEEDED`
- no source upload
- no persistent import batch
- no drafts

## Regression

- Existing Phase 3B/3C/3D packages remain compatible.
- Exact reimport still reuses source, batch, items and drafts.
- Existing published questions/tests/attempts remain unchanged.
