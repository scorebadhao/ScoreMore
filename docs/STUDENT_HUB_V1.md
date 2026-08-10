# ScoreMore Student Hub v1

## Status

Approved and implemented on 10 August 2026.

Student navigation is now:

```text
Home | Tests | Saved | Results | Profile
```

ScoreBadhao was reviewed only as a UX/functionality reference. ScoreMore remains an independent Vite + Supabase application and does not use ScoreBadhao sessions, Apps Script, Google Sheets, credentials, branding or source-of-truth data.

## Finding and impact

The existing ScoreMore student shell already supported Home, Tests and the mobile test runner, but Bookmarks, Mistakes, Results and Profile routes returned a reserved-feature message. The database contained the core learning tables but still allowed browser writes to some student-owned records.

Student Hub v1 completes those routes and moves all trusted student-hub workflows behind PostgreSQL RPCs. Direct browser writes to profile fields, bookmarks and mistake records are revoked.

## Home

- Most recent active attempt with answered progress
- Completed attempts, average accuracy, saved count and questions solved
- Dynamic test-type counts
- Weak-subject insight from submitted attempts
- Recommended student-ready test
- Package-access summary
- Recent results with detailed-result navigation

All metrics are calculated by `get_student_home()` for `auth.uid()`.

## Tests

- Server-side search and pagination
- Test type, subject, topic, year, date, shift, access and progress filters
- Recommended, newest, oldest, performance and name sorting
- Free, Unlocked and Premium state
- Start, Resume and Reattempt state
- Last score, best score and attempt count
- Compulsory student-image readiness remains enforced

`list_student_tests()` returns only published student-ready tests. Package access is checked by the database and remains rechecked by `create_test_attempt()`.

## Saved

One route contains two tabs:

```text
Bookmarks | Mistake Book
```

- Save/remove bookmark from the mobile test runner
- Save/remove bookmark from submitted-result review
- Search and filter saved questions
- Resolve or reopen a mistake record
- Show only approved `student_image_refs`
- Offer an existing configured Bookmark/Mistake revision test

Correct answers and explanations are returned only when the student has a submitted occurrence of the question and no active attempt currently contains it. Raw `image_refs` are never returned.

## Results

- Submitted-attempt history with search, sorting and pagination
- Score, maximum score, accuracy, correct, wrong, skipped and negative-mark loss
- Subject and difficulty performance
- Topic-performance contract
- Timing analysis and repeated-mistake count
- Personalized weak-subject next action
- Review filters: All, Correct, Wrong, Skipped and Marked
- Approved student-safe diagrams and bookmark action
- Reattempt action

Scores and analytics are calculated from server-owned attempt records. Detailed review is denied unless the attempt belongs to `auth.uid()` and is `SUBMITTED` or `AUTO_SUBMITTED`.

## Profile

Editable:

- Full name
- Preferred language
- Target board
- Target exam

Protected/read-only:

- Verified email
- Registered mobile
- Role
- Status and authorization data

`update_student_profile()` validates the board/exam relationship and updates only approved learning-preference fields.

## Files

```text
supabase/migrations/20260810010000_student_hub_v1.sql
student.html
assets/js/student.js
assets/js/api.js
assets/js/testEngine.js
assets/css/main.css
supabase/migrations/README.md
docs/STUDENT_HUB_V1.md
docs/DEVELOPMENT_ROADMAP.md
docs/README.md
```

No admin file is changed.

## Deployment order

1. Upload the new migration.
2. Run the controlled ScoreMore database deployment workflow.
3. Upload the five frontend files and documentation.
4. Wait for GitHub Pages deployment to succeed.
5. Open the student site in a fresh/incognito session and complete the acceptance checklist.

Deploy the migration before the frontend because the mobile runner now requests bookmark state from a new protected RPC.

## Acceptance checklist

- Home metrics and active-attempt resume reflect only the signed-in student.
- Test filters and pagination work on mobile and desktop.
- Premium tests cannot be started without valid package access.
- A question can be saved and removed inside an active test.
- Saved answer/explanation remains locked while the question is in an active attempt.
- Submitted attempt unlocks eligible Saved review.
- Wrong answers enter Mistake Book and resolve/reopen correctly.
- Result history and detailed review are submitted-attempt only.
- Result review never exposes raw source captures.
- Profile cannot change mobile, email or role.
- Another user cannot read the first user's Home, Saved, Results or Profile data.
- Mobile back navigation moves between the five routes without signing out.
- Existing answer save, offline queue, section tabs, timer and submit flows still pass regression.

## Architecture confirmation

- Central frontend data access remains in `assets/js/api.js`.
- Trusted multi-step operations use PostgreSQL RPCs.
- RLS remains enabled.
- Master questions remain single-copy.
- Draft-review-publish is unchanged.
- Image Repair Centre and compulsory image readiness remain unchanged.
- No service-role credential or secret is added to frontend code.

