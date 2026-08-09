# ScoreMore compulsory Student-safe Image Repair Centre

## Publication and readiness rule

A reviewed draft may still be published into the master `questions` table so its identity, source and audit trail are preserved. Publication does not make a visual question student-ready.

Every published question with at least one raw `image_refs` item must receive exactly one current audited decision:

| Current state | Student-ready | Meaning |
| --- | --- | --- |
| `NOT_APPLICABLE` | Yes | The question has no source image. |
| `NEEDS_REVIEW` | No | A source image exists but no current audited decision exists. |
| `SAFE_CROP_APPROVED` | Yes | A clean private diagram-only crop is approved. |
| `NO_STUDENT_IMAGE_REQUIRED` | Yes | The source capture is audit evidence; verified text/options are sufficient. |

The authoritative predicate is `question_is_student_ready(question_id)`. UI state cannot bypass it.

## Compulsory enforcement

Unresolved visual questions are:

- excluded from the simple Test Builder;
- excluded from Phase 4A facets, question results and server-side select-all;
- rejected when a question link is inserted into a test;
- rejected by the deferred test-publication guard;
- hidden from the student catalogue when an existing fixed test becomes unresolved;
- rejected during every new attempt materialization;
- never silently skipped to produce a shorter test.

Existing in-progress attempts remain resumable. If an approved crop is removed or the raw source changes, the protected runner returns the safe fallback for that already-materialized question. New attempts remain blocked until review is completed again.

## Approved crop path

```text
admin-only source preview
→ upload diagram-only crop
→ pending candidate
→ student-view preview
→ explicit approval
→ SAFE_CROP_APPROVED
→ protected attempt delivery
```

Raw source captures stay in `questions.image_refs` and the private `source-documents` bucket. Approved crops stay in the private `student-question-images` bucket and are mirrored to `questions.student_image_refs` only through the audited approval RPC.

## No-image-required path

Use this only when the raw capture is evidence for admin verification and the complete question is answerable from the verified text and options.

```text
inspect raw source
→ verify text and all four options are complete
→ write a reason (minimum 10 characters)
→ confirm No student image required
→ NO_STUDENT_IMAGE_REQUIRED
```

The decision is fingerprinted to the current `image_refs`. Changing any raw source reference automatically revokes the decision and returns the question to `NEEDS_REVIEW`.

## Database model

Migrations:

- `20260808010000_student_safe_image_repair_centre.sql`
- `20260808020000_compulsory_student_image_readiness.sql`

`question_image_repairs` stores crop candidates and their `PENDING`, `APPROVED`, `SUPERSEDED` or `REMOVED` lifecycle.

`question_image_review_decisions` stores current and historical audited decisions. Direct browser table access is denied. A current decision includes:

- decision type;
- source-image SHA-256 fingerprint;
- approved repair reference when applicable;
- admin note;
- deciding admin and timestamp;
- current, superseded or revoked status.

Projection fields on `questions` support efficient admin filtering:

- `student_image_review_status`
- `student_image_reviewed_by`
- `student_image_reviewed_at`
- `student_image_review_note`

The readiness function still validates the protected decision/repair records and source fingerprint; projection fields alone cannot authorize student use.

## Protected RPCs

- `list_student_image_repair_queue(...)`
- `get_student_image_repair_detail(text)`
- `register_student_image_upload(...)`
- `approve_student_image_repair(...)`
- `discard_student_image_upload(...)`
- `remove_approved_student_image(...)`
- `mark_student_image_not_required(...)`
- `reopen_student_image_review(...)`

Trusted enforcement helpers:

- `question_student_image_readiness(text)`
- `question_is_student_ready(text)`
- `test_is_student_ready(text)`

## Admin checklist

1. Open **Admin → Image repair**.
2. Resolve every item under **Needs repair**.
3. If students require the figure/table/diagram, upload a clean crop and approve it.
4. If the source capture is audit-only, record a precise no-image-required reason.
5. Confirm the queue moves the question to **Approved** or **No student image required**.
6. Confirm the question now appears in Test Builder results.
7. Reopen review or remove an approved crop only with a reason; both actions immediately block new student use.

## Acceptance checklist

1. Publish a draft with `image_refs`; confirm it enters `NEEDS_REVIEW`.
2. Confirm it is absent from both Test Builders.
3. Confirm direct test-link insertion and test publication are rejected.
4. Confirm a new attempt containing it cannot start and no partial attempt persists.
5. Approve a safe crop; confirm builder, publication and attempt eligibility restore immediately.
6. Confirm students receive only the approved signed crop, never raw `image_refs` or an answer key.
7. Record `NO_STUDENT_IMAGE_REQUIRED`; confirm the runner displays text/options without a hidden-diagram warning.
8. Reopen that decision; confirm the question becomes unresolved again.
9. Change the raw source reference after approval; confirm the previous decision is revoked automatically.
10. Confirm an existing in-progress attempt remains safe while every new attempt is blocked.
11. Confirm audit logs include crop approval/removal and no-image confirmation/reopening.

## Deployment order

1. Upload `20260808020000_compulsory_student_image_readiness.sql`.
2. Run **Deploy ScoreMore Database** with `DEPLOY_SCOREMORE`.
3. Confirm migration `20260808020000` is applied.
4. Upload the frontend and documentation files from the same checked patch.
5. Wait for the latest GitHub Pages deployment to become green.
6. Resolve the compulsory Image Repair queue before publishing or starting affected tests.

This extension is additive and forward-only. It preserves the master-question workflow, RLS, private source boundary, approved-crop storage, test-engine answer protection and ScoreMore-only architecture.
