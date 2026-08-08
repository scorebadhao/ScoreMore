# ScoreMore Student-safe Image Repair Centre

## Purpose

The mobile test runner never receives raw `questions.image_refs`. Those source captures may contain question text, options, answer-state labels, internal IDs or full-page whitespace.

The Image Repair Centre provides the audited remediation path:

```text
admin-only source preview
→ upload diagram-only crop
→ pending candidate
→ admin student-view preview
→ explicit approval
→ questions.student_image_refs
→ protected attempt delivery
```

No question is republished and no test is recreated.

## Database and storage

Migration: `supabase/migrations/20260808010000_student_safe_image_repair_centre.sql`

- Adds `question_image_repairs` with `PENDING`, `APPROVED`, `SUPERSEDED` and `REMOVED` states.
- Keeps direct browser access to the table denied; all state changes use admin-only RPC functions.
- Adds the private `student-question-images` bucket for PNG, JPEG and WebP files up to 5 MB.
- Allows admins to manage objects.
- Allows an authenticated student to sign an approved object only when that question belongs to one of the student's attempts.
- Preserves raw source images and published question identity.
- Records register, approve, replace, discard and remove actions in `admin_audit_logs`.

## Admin workflow

1. Open **Admin → Image repair**.
2. Filter by repair state, Question ID/text, paper code, shift, section or original question number.
3. Open a question and inspect its admin-only source preview.
4. Create a clean crop outside ScoreMore containing only the required diagram, figure or table.
5. Upload the PNG, JPEG or WebP crop with accessible alt text.
6. Inspect the student preview. The pending crop is not yet student-visible.
7. Select **Approve student image** only after verifying that the crop contains no answer state, source IDs, duplicated question/options or unnecessary page area.
8. Refresh or reopen the student attempt. The approved crop replaces the temporary hidden-diagram notice.

An approved crop may be replaced by approving a new pending candidate. Removing the approved crop immediately clears `student_image_refs` and restores the safe fallback.

## Protected RPCs

- `list_student_image_repair_queue(...)`
- `get_student_image_repair_detail(text)`
- `register_student_image_upload(...)`
- `approve_student_image_repair(...)`
- `discard_student_image_upload(...)`
- `remove_approved_student_image(...)`

The existing protected `get_attempt_questions(...)` continues to return only `student_image_refs`. `assets/js/api.js` exchanges private storage paths for one-hour signed URLs before the test runner renders them.

## Acceptance checklist

1. Confirm the default queue lists published visual questions with no approved crop.
2. Search by Question ID and filter by paper, shift, section and original question number.
3. Confirm queue results never include raw source bytes.
4. Open one record and confirm raw source preview is admin-only.
5. Reject non-image files and images above 5 MB.
6. Upload a clean crop and confirm the queue state becomes `PENDING` while `student_image_refs` remains empty.
7. Confirm the student preview shows the pending candidate but an active student attempt still shows the hidden-diagram notice.
8. Approve the candidate and confirm the audit record, private storage reference and `student_image_refs` update.
9. Resume a student attempt containing the question and confirm the signed crop renders without exposing raw `image_refs` or the correct answer.
10. Confirm a different student with no attempt containing the question cannot sign the object.
11. Approve a replacement and confirm the prior repair becomes `SUPERSEDED`.
12. Discard a pending candidate and confirm it never becomes student-visible.
13. Remove an approved crop and confirm the safe hidden-diagram notice returns.

## Deployment order

1. Upload all patch files with their repository paths preserved.
2. Run **Deploy ScoreMore Database** with `DEPLOY_SCOREMORE`.
3. Confirm migration `20260808010000` is applied.
4. Wait for the latest GitHub Pages deployment to become green.
5. Repair and approve each hidden visual question through the Admin Dashboard.

This change is additive and forward-only. It does not edit older migrations or weaken the mobile test-runner safety boundary.
