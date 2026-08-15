# ScoreMore Admin Safety & Efficiency v1.5 — VERIFIED

Target: **ScoreMore DEV only**

This patch is based on the currently accepted:
- Admin Console v1.4
- Admin Session Persistence Fix v1.0

It intentionally does **not** alter the accepted session/auth lifecycle.

## What v1.5 changes

### 1. Safer multi-package sectional identity
For a sectional test using more than one import package:
- the UI generates a neutral ID such as `SECTIONAL-MULTI-...`;
- the generated ID no longer looks like the test belongs to the first selected paper;
- every selected source package remains stored in `tests.question_filter` provenance;
- the server rejects a multi-package sectional Test ID that begins with one selected package ID.

### 2. Mode-aware diagnostics
Preview issues are now separated into:
- `INFO`
- `WARNING`
- `BLOCKER`

Examples:
- `MULTIPLE_PACKAGES` in Sectional mode → INFO
- `PARTIAL_PACKAGE` in Sectional / Completed PYQ → INFO
- `SUPPLEMENTAL_INCLUDED` in Completed PYQ → INFO
- `SUPPLEMENTAL_INCLUDED` in Sectional / Custom → WARNING
- incomplete Original Full PYQ → BLOCKER
- unique-master collapse in Original Full PYQ → BLOCKER
- Original Full question-count mismatch → BLOCKER

### 3. Protected test publication
- `Publish test` is disabled until the **current** configuration has an authoritative preview.
- A blocker changes the action to `Resolve blockers first`.
- Non-blocking warnings change it to `Publish with warnings`.
- Informational notices do not falsely look like warnings.
- Server-side publication independently rechecks blockers.

Saving a draft remains allowed so an admin can preserve work that is not yet publication-ready.

### 4. Better mobile filter action
The existing sticky Apply Filters bar is retained and refined:
- shows the current available question count in the button;
- safer mobile bottom spacing;
- compact touch-friendly layout.

### 5. Clearer Final Review wording
- `Verify final view & next` → `Approve & Next`
- `Save final review` → `Save Draft Review`

No review gate is weakened.

### 6. Bulk Publish confirmation summary
Before publishing selected reviewed questions, Admin now sees:
- selected count
- image readiness
- repaired-content count
- approved safe-image crop count
- no-student-image count
- supplemental count
- printed-option-anomaly count

The database still rechecks every question individually.

## Exact apply order

### Stage A — database first
Upload only:
`supabase/migrations/20260816010000_phase4a_safety_efficiency_v1.sql`

Optional documentation update:
`supabase/migrations/README.md`

Then run the normal:
**Deploy ScoreMore DEV Database**

Use the existing normal DEV workflow. Do **not** use `--include-all`.

Expected pending migration:
`20260816010000_phase4a_safety_efficiency_v1.sql`

Stop if the dry-run shows an unexpected migration.

### Stage B — frontend second
Only after the DEV database workflow is green, replace:
- `test-builder.html`
- `assets/js/api.js`
- `assets/js/admin.js`
- `assets/js/testBuilder4A.js`
- `assets/css/main.css`
- `assets/css/testBuilder4A.css`

Wait for **Deploy ScoreMore DEV to GitHub Pages** to turn green.

## DEV acceptance checklist

1. Session regression:
   - Admin → Dynamic Builder → Admin, no login request.
   - Android background/return, no forced logout.

2. Multi-package Sectional:
   - select 2+ packages + subject;
   - neutral `SECTIONAL-MULTI-...` Test ID appears;
   - preview shows Multiple Packages as INFO;
   - all source package IDs appear in provenance/preview;
   - manually entering a Test ID that starts with one selected package ID is rejected.

3. Partial package in Sectional:
   - `PARTIAL_PACKAGE` shows as INFO, not a blocker.

4. Incomplete Original Full PYQ:
   - preview shows publication blocker;
   - Publish button remains disabled;
   - Save as draft remains possible.

5. Complete Original Full PYQ:
   - no blockers;
   - Publish becomes available after preview.

6. Sectional with supplemental NORMAL questions:
   - supplemental notice remains a non-blocking WARNING;
   - action reads `Publish with warnings`;
   - confirmation repeats the warning.

7. Final Review:
   - buttons read `Approve & Next` and `Save Draft Review`.

8. Publish Centre:
   - selecting questions and pressing Publish shows the new safety summary;
   - Confirm Publish still calls the existing protected server publication path.

Do not promote v1.5 to RankTiger PROD until all tests pass in ScoreMore DEV.
