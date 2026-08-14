# ScoreMore — Repo-Inspected Patch v1.2

Target: **ScoreMore DEV only**

This patch was rebuilt from the user's uploaded `ScoreMore-main (2).zip`.

## Approved workflow

Import → Image & Content Repair → Final Human Review → Publish → Test

## Critical database-history finding

The current ScoreMore DEV remote migration history is missing:

`20260805000050_catalogue_parent_prerequisites`

even though later migrations are already recorded and the required GSSSB / CCE / subject catalogue rows already exist in DEV.

The normal `.github/workflows/deploy-supabase.yml` is therefore intentionally left unchanged.

This patch adds a separate, one-time guarded workflow:

`.github/workflows/repair-scoremore-dev-migration-history.yml`

It targets only ScoreMore DEV and only repairs the history entry for `20260805000050`, then runs the **normal dry-run only**. It does not use `--include-all` and it does not automatically apply pending migrations.

## Safe application sequence

### Stage A — migration-history repair only

Upload only:

`.github/workflows/repair-scoremore-dev-migration-history.yml`

Then run:

**Repair ScoreMore DEV Migration History — ONE TIME**

Confirmation:

`REPAIR_SCOREMORE_DEV_20260805000050`

The workflow will:
1. hard-check the ScoreMore DEV project ref;
2. verify the expected local migration files;
3. show migration history before;
4. mark only `20260805000050` as applied in migration history;
5. show migration history after;
6. run the normal ScoreMore DEV `db push --dry-run --include-seed`;
7. stop without applying later migrations.

Inspect the dry-run. Expected pending migrations from the inspected repo are:
- `20260811020000_public_catalogue_baseline.sql`
- `20260814010000_draft_first_image_content_repair_workflow.sql`

If the preview shows anything unexpected, stop.

### Stage B — normal ScoreMore DEV database deployment

Only after Stage A preview is correct, run the repository's existing:

**Deploy ScoreMore DEV Database**

with its normal confirmation.

Do not add `--include-all` to the normal workflow.

### Stage C — frontend patch

Only after the DEV database deployment succeeds, replace:
- `admin.html`
- `assets/js/admin.js`
- `assets/js/api.js`
- `assets/css/main.css`

The new admin workflow then becomes:
- Import
- Image & Content Repair
- Final Review
- Publish
- Test

### Stage D — DEV acceptance

Test:
- visual drafts are blocked from Final Review until image readiness is resolved;
- admin can edit question text and Option A–D in repair;
- imported text/options remain available as immutable audit content;
- content/image edits invalidate old review;
- Final Review shows the final student-safe presentation;
- Publish requires the current reviewed repair revision;
- mobile and desktop layouts are usable;
- existing published-question image maintenance remains intact.

### Stage E — cleanup

After DEV acceptance succeeds, delete the one-time repair workflow in a later housekeeping commit.

Do not deploy this feature to RankTiger PROD until ScoreMore DEV acceptance passes.
