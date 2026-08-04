# ScoreMore Phase 3C Acceptance Tests

## Purpose

Verify that reconciled HTML records enter `draft_questions` accurately and idempotently without creating duplicate drafts or published questions.

## Preconditions

- Phase 3A, Phase 3B and the HTML MIME hotfix are deployed.
- The Phase 3B sample package has one exact duplicate and one valid record.
- The current admin account has `profiles.role = 'ADMIN'` and `status = 'ACTIVE'`.

## A. Deployment

1. Deploy `20260804060000_phase3c_controlled_draft_import.sql` through **Deploy ScoreMore Database**.
2. Confirm the migration workflow is green.
3. Deploy the Phase 3C frontend files through GitHub Pages.
4. Open `admin.html?v=phase3c`.

## B. Open the existing reconciliation

1. Open **Recent dry runs**.
2. Open package `GSSSB-CCE-PHASE3B-DRYRUN-V1`.
3. Confirm:
   - total records: 2;
   - one `EXACT_DUPLICATE`;
   - one `VALID`;
   - ready for draft: 1;
   - drafts created: 0 before the first import.

## C. Controlled draft creation

1. Confirm only the `VALID` record has **Create draft** selected.
2. Tap **Import selected valid records to drafts**.
3. Confirm the modal states that only drafts will be created.
4. Approve the action.
5. Confirm:
   - exactly one item changes to `IMPORTED_TO_DRAFT`;
   - **Drafts created** becomes 1;
   - a persistent `created_draft_id` is shown;
   - the exact duplicate creates no draft;
   - the Question drafts section contains the new question in `PENDING` state.

## D. Idempotency

1. Open the same batch again.
2. Confirm the imported item is not selectable for draft creation.
3. Run the same HTML package again and open the reused report.
4. Confirm the same batch ID and same created draft ID are displayed.
5. Confirm the import button is disabled when no valid records remain.
6. Query or inspect `draft_questions` and confirm exactly one active draft exists for the imported Question ID/content.

Expected:

```text
0 additional source files
0 additional import batches
0 additional import items
0 additional drafts
0 published questions created by the import action
```

## E. Human review lock

1. Open the created draft.
2. Confirm source metadata, chronology, options, answer, explanation, content origin and import traceability are present.
3. Do not publish until human review is complete.
4. Confirm the controlled import itself did not insert into `questions`.

## F. Duplicate and conflict lock

- `EXACT_DUPLICATE` creates no draft.
- `POSSIBLE_DUPLICATE` remains blocked and requires later human resolution.
- `ID_CONFLICT`, `ANSWER_CONFLICT`, `SOURCE_CONFLICT` and `INVALID` cannot be selected.
- A record that becomes a duplicate after dry run is blocked by current-state revalidation.

## G. Exact duplicate PYQ occurrence linking

Use a test package containing exact published PYQ content with a new valid paper occurrence.

1. Select **Link this PYQ occurrence**.
2. Tap **Link selected PYQ occurrences**.
3. Confirm:
   - item changes to `LINKED_TO_EXISTING`;
   - no draft is created;
   - no master question is created;
   - one `question_occurrences` row is created or reused;
   - linking again creates zero additional occurrence rows.

## H. Regression

Verify:

- manual draft creation;
- draft review and publication;
- Admin Test Manager;
- public catalogue;
- student sign-in;
- test start/resume/submit;
- scoring.

## Pass condition

Phase 3C passes only when draft creation, duplicate skipping, occurrence linking, audit persistence and retries are all correct on mobile and no import operation bypasses human publication.
