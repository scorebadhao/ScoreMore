# RankTiger PROD Database Initialization — Patch 5

Status: guarded production-write foundation.

## Purpose

Patch 5 introduces the first workflow that is allowed to write to the separate `RANKTIGER_PROD` Supabase project.

The workflow is intentionally limited to:

1. re-verifying the RankTiger target and credentials,
2. validating immutable migration checksums,
3. validating the narrow shared production-safe seed,
4. previewing pending migrations,
5. applying migrations in Supabase migration order,
6. applying the shared catalogue/settings seed,
7. verifying remote migration history,
8. verifying seeded public catalogue/settings data through the RankTiger Data API.

It does **not** deploy frontend code, push to the RankTiger GitHub repository, or trigger Cloudflare.

## Manual workflow

`.github/workflows/initialize-ranktiger-prod-db.yml`

Workflow name:

`Initialize / Update RankTiger PROD Database — GUARDED`

Required confirmation:

`INITIALIZE_RANKTIGER_PROD`

## Production credentials

The workflow consumes these GitHub repository secrets from the ScoreMore repository:

- `SUPABASE_ACCESS_TOKEN` — account-level CLI token already used by ScoreMore.
- `RANKTIGER_SUPABASE_PROJECT_ID`
- `RANKTIGER_SUPABASE_DB_PASSWORD`
- `RANKTIGER_SUPABASE_URL`
- `RANKTIGER_SUPABASE_PUBLISHABLE_KEY`

It must not use ScoreMore DEV database/project/browser secrets.

## Migration immutability

All 18 migrations locked in `docs/LOCKED_MIGRATION_CHECKSUMS_PATCH3.json` remain immutable. Patch 5 verifies each SHA-256 before allowing the production database push.

Future database changes must be new migration files; historical migrations must not be edited.

## Production-safe seed

The shared `supabase/seed.sql` is permitted to write only to:

- `boards`
- `exams`
- `subjects`
- `topics`
- `app_settings`

It must not seed students/users, questions, drafts, tests, attempts, payments, or admin data. Product identity remains build-controlled and `app_name`, `app_mark`, and `app_environment` are forbidden in the shared seed.

## Post-deploy checks

After a successful push, the workflow checks all locked migration versions are present remotely and verifies the expected seeded `GSSSB` board, `CCE` exam, and `hero_title` setting through the public RankTiger Data API using the RankTiger publishable key.

## Important

This workflow writes to production. Run it only after the read-only `Verify RankTiger PROD Connection — READ ONLY` workflow passes and only when the intended ScoreMore source revision is approved for database deployment.
