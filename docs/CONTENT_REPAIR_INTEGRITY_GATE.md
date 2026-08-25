# ScoreMore Content Repair Integrity Gate v1.0

## Outcome

This patch closes the workflow gap demonstrated in `1000302307.mp4`: content completeness is now independent from image readiness. A visual or non-visual draft can be returned from Final Review to the Repair Centre, the exact draft is opened with clean filters, and publication is blocked until the repaired revision is explicitly confirmed against its source evidence.

## What changed

- Added `content_repair_status` and an audited repair reason/lifecycle to `draft_questions`.
- Added an optimistic `repair_revision` check to return, save/reset repair, and Final Review writes.
- Broadened the existing repair queue to include non-visual content problems.
- Added an audited `Final Review -> Content Repair` transition instead of navigation-only behavior.
- Made paper/date/shift/section/original-question/source-page identity prominent in Repair, Final Review, and Publish preview.
- Removed the unsafe visual default from missing/AI answer source to `MANUALLY_VERIFIED`.
- Added a mandatory revision-bound source/presentation confirmation and conditional content-verification note.
- Added client-side approval blockers and equivalent server checks.
- Added a separate before-publish database trigger so a stale client or direct RPC cannot bypass the gate.
- Protected workflow columns from direct browser updates; changes must pass through audited admin RPCs.
- Removed the mobile sticky Final Review overlay.

## Controlled deployment

1. Commit the patch to the **ScoreMore** repository only.
2. Run `npm ci --no-audit --no-fund` and `npm run verify:content-repair-integrity`.
3. Build ScoreMore with `npm run build:scoremore`.
4. From the controlled `Deploy ScoreMore DEV Database` workflow, enter `DEPLOY_SCOREMORE_DEV`.
5. Confirm the dry-run contains only the new forward migration `20260825010000_content_repair_integrity_gate.sql`, then apply it to the locked ScoreMore DEV project.
6. Deploy the matching frontend bundle. The migration intentionally revokes the stale repair/review RPC contracts, so database and frontend should be released together.

Do not apply this migration to RankTiger PROD during DEV acceptance. Existing already-applied migrations were not edited.

## Mandatory DEV acceptance cases

| Case | Action | Expected result |
|---|---|---|
| Video Q0066 incomplete stem | Open Final Review and choose **Return for content repair** with `INCOMPLETE_QUESTION` | Audit row is written, revision increments, content status becomes `NEEDS_REPAIR`, exact Q0066 opens in Repair |
| Non-visual repair routing | Repeat with a draft whose `image_refs` is empty | Repair queue contains it; image area says not applicable; text/options editor remains active |
| Stale filter regression | Start with unrelated paper/shift/section/Q filters, then return Q0066 | Old filters are reset; search/status point to Q0066 and `CONTENT_REPAIR` |
| Repair resolution | Correct the complete stem/options and save with an audit note | Content becomes `READY`, revision increments again, prior review/source confirmation is cleared |
| Final Review data | Reopen Q0066 | Final student presentation, paper/source identity, imported evidence, answer/topic/explanation fields are all visible |
| Missing answer/source/topic | Leave any mandatory field unset | Both approval buttons remain disabled and the blocker list names the missing data |
| Source confirmation | Complete fields but leave confirmation unchecked | Approval remains disabled; server also rejects a forged request |
| Repaired/flagged content note | Confirm repaired content without a five-character note | Client and server both reject approval |
| Successful approval | Confirm the current revision and all required academic fields | `reviewed_repair_revision` and `content_source_confirmed_revision` equal `repair_revision`; draft appears in Publish Centre |
| Stale concurrency | Load the same draft in two sessions; repair in one, approve in the other | Second write is rejected and must reload the latest revision |
| Direct publish bypass | Try to publish a draft with `NEEDS_REPAIR` or mismatched confirmation revision | Before-insert content guard rejects publication |
| Mobile layout | Review on a narrow viewport and scroll through source/question/options | Actions are in normal flow and do not cover question data |

## Promotion gate

RankTiger promotion remains blocked until all acceptance cases above pass in ScoreMore DEV, the standard ScoreMore/RankTiger static verifier chain remains green, and a fresh backup/rollback point is recorded under the existing production operations lock.
