# ScoreMore mobile test runner and section navigation

## Scope

This patch stabilizes the authenticated ScoreMore student test runner without changing the draft-review-publish workflow, master Question IDs, test selection rules or RLS model.

## Frontend changes

- `assets/js/testEngine.js`
  - Loads one protected all-question navigation snapshot before loading question batches.
  - Restores answered, review and visited states after refresh or cross-device resume.
  - Builds section tabs dynamically from attempt question metadata.
  - Shows section-level answered counts and a section-scoped navigator.
  - Keeps global question numbering and preserves answers while switching sections.
  - Shows answered progress separately from the current question position.
  - Displays an authoritative countdown and locks the interface at expiry.
  - Uses explicit Saving, Saved, Retrying and Saved on device states.
  - Uses `Next` because option selection already saves immediately.
  - Renders only reviewed `student_image_refs`; raw source captures are not received by the browser.

- `assets/js/api.js`
  - Adds the central `getAttemptNavigation()` and `visitAttemptQuestion()` calls.

- `assets/js/student.js`
  - Adds active-attempt mode and reliably disposes timer/network listeners when leaving the runner.

- `assets/css/main.css`
  - Removes the large application header during an active attempt.
  - Adds sticky horizontal section tabs and a compact timer.
  - Reserves safe-area space for a fixed action bar so it cannot cover options or controls.
  - Constrains reviewed diagram crops without clipping them.

## Database changes

Migration: `supabase/migrations/20260807020000_mobile_test_runner_sections.sql`

- Adds `attempt_questions.visited_at` and refreshes it on each protected visit so cross-device resume can restore the latest position.
- Adds `questions.student_image_refs` as a separate, reviewed student-display boundary.
- Adds protected `get_attempt_navigation(uuid)`.
- Adds protected `visit_attempt_question(uuid, text)`.
- Enforces the test deadline in question loading, visit, answer-save and submission RPCs.
- Uses the same internal scoring path for manual and automatic submission.
- Keeps the internal scoring helper unavailable to browser roles.
- Does not expose answer keys, explanations or raw `image_refs` during an attempt.

## Image remediation rule

Existing `questions.image_refs` remain unchanged for audit/source review. They are deliberately not copied automatically because the current source captures may include duplicated question text, answer-state metadata or full-page whitespace.

Only diagram-only crops that an administrator has reviewed should be added to `questions.student_image_refs`. Until then, the runner shows a neutral “Diagram temporarily hidden” notice instead of exposing the raw capture.

## Acceptance checklist

1. Start a multi-section 100-question test on a narrow mobile viewport.
2. Confirm the ScoreMore application header and bottom navigation are hidden only during the attempt.
3. Confirm section tabs are generated from attempt data and are horizontally scrollable.
4. Select an answer, mark another for review, switch sections and return; confirm both states remain.
5. Refresh and resume; confirm all 100 navigation states—not only the current batch—are correct.
6. Open an unanswered question, refresh and confirm it remains Unanswered rather than Not visited.
7. Confirm the progress bar uses answered count while the header still shows question position.
8. Confirm the fixed Previous/Next bar never covers an option, image, review control or navigator.
9. Confirm option selection saves immediately and the action button reads Next.
10. Test Saving, Saved, Retrying and offline device states.
11. Confirm a timed test counts down, becomes urgent in the final minute and auto-submits at zero.
12. Attempt direct answer/question RPC calls after expiry; confirm the attempt is auto-submitted and no later answer is accepted.
13. Confirm duration `0` remains untimed.
14. Confirm single-section tests hide the section tab row.
15. Confirm raw `image_refs` never appear in browser attempt responses.
16. Add one reviewed diagram to `student_image_refs` and confirm it renders contained and unclipped.
17. Confirm submitted review/result access still works and answer keys are unavailable before submission.

## Deployment order

1. Run the controlled **Deploy ScoreMore Database** workflow with confirmation `DEPLOY_SCOREMORE`.
2. Deploy the updated frontend after the migration succeeds.
3. Populate reviewed diagram-only crops in `student_image_refs` through an audited admin data workflow.

The migration is additive and forward-only. It does not delete or rewrite existing questions, attempts, answers, tests or raw source images.
