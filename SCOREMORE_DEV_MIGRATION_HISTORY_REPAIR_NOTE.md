# ScoreMore DEV migration-history repair — one time

## Why this file exists
ScoreMore DEV already contains the catalogue parent records required by `20260805000050_catalogue_parent_prerequisites.sql`, but that migration timestamp is missing from the remote `supabase_migrations.schema_migrations` history. Because later migrations are already recorded remotely, normal `supabase db push` refuses to insert this older local timestamp.

## Safer recovery choice
Do **not** enable `--include-all` in the normal ScoreMore DEV deploy workflow.

Run the separate guarded workflow:

`.github/workflows/repair-scoremore-dev-migration-history.yml`

It changes migration **history only** for the exact timestamp `20260805000050`; it does not execute that migration SQL and it does not apply the new Draft-First Image & Content Repair migration.

Confirmation text:

`REPAIR_SCOREMORE_DEV_20260805000050`

After the history repair, the workflow runs the normal `db push --dry-run --include-seed` command only. Inspect that preview before running the ordinary `Deploy ScoreMore DEV Database` workflow.

## Expected dry-run after repair
The normal preview should no longer complain about an older migration before the remote head. It should show only genuinely pending later migrations, expected from the inspected repository to include:

- `20260811020000_public_catalogue_baseline.sql`
- `20260814010000_draft_first_image_content_repair_workflow.sql`

If anything else appears, stop and inspect before applying.

## Cleanup
After DEV migration history and the normal database deployment both succeed, delete this one-time workflow in a later housekeeping commit. Keep `.github/workflows/deploy-supabase.yml` as the normal guarded DEV deployment path.
