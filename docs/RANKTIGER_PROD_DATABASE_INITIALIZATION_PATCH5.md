# RankTiger PROD Database Initialization — Patch 5.1

Patch 5.1 is the production-safe correction to Patch 5.

## Production rule
RankTiger PROD is initialized and updated with **versioned migrations only**.
The production workflow must never run `supabase db push --include-seed`.

The shared `supabase/seed.sql` remains for ScoreMore DEV/local reset workflows. Approved baseline reference content for production is captured as an idempotent migration:

`supabase/migrations/20260811020000_public_catalogue_baseline.sql`

The catalogue migration is restricted to:
- boards
- exams
- subjects
- topics
- app_settings

It contains no users, questions, tests, attempts, payments, access grants, admin data, or product-identity keys (`app_name`, `app_mark`, `app_environment`).

## Guarded production workflow
`.github/workflows/initialize-ranktiger-prod-db.yml`

Required confirmation:
`INITIALIZE_RANKTIGER_PROD`

Sequence:
1. Confirmation gate
2. Verify workflow and migration locks
3. Require RankTiger PROD credentials
4. Block ScoreMore DEV target
5. Cross-check RankTiger URL/project ID
6. Verify account token and publishable key
7. Link RankTiger PROD
8. Read current migration status
9. `supabase db push --dry-run`
10. `supabase db push --yes`
11. Verify all 19 approved migrations remotely
12. Verify baseline public catalogue through the RankTiger Data API

The workflow does not deploy the frontend, update the RankTiger repository, or trigger Cloudflare.
