# RankTiger PROD Connection Verification — Patch 4

## Purpose

Patch 4 verifies that the ScoreMore GitHub repository can safely identify and connect to the separate `RANKTIGER_PROD` Supabase project before any production migration is allowed.

## Workflow

`.github/workflows/verify-ranktiger-prod.yml`

Visible GitHub Actions name:

**Verify RankTiger PROD Connection — READ ONLY**

The workflow is manual-only and requires this exact confirmation:

`VERIFY_RANKTIGER_PROD`

## Credentials used

- `SUPABASE_ACCESS_TOKEN` — existing account-level Supabase access token
- `RANKTIGER_SUPABASE_PROJECT_ID`
- `RANKTIGER_SUPABASE_URL`
- `RANKTIGER_SUPABASE_PUBLISHABLE_KEY`
- `RANKTIGER_SUPABASE_DB_PASSWORD`

No secret API key/service-role key is required.

## Verification performed

1. Blocks unless the exact manual confirmation is supplied.
2. Requires all configured RankTiger PROD credentials.
3. Refuses to continue if the RankTiger project ID equals the locked ScoreMore DEV project ID.
4. Cross-checks that the project URL is exactly `https://<project-id>.supabase.co`.
5. Confirms the existing Supabase access token can see the RankTiger project.
6. Checks the RankTiger Data API endpoint using the publishable key.
7. Links the CLI to RankTiger PROD using the production DB password.
8. Reads remote migration status using `supabase migration list --linked`.

## Explicitly forbidden in Patch 4

Patch 4 does not run:

- `supabase db push`
- seeds
- migration up/down/repair
- database reset
- configuration push
- Supabase secret changes
- function deployment
- RankTiger repository writes
- Cloudflare deployment

## Production state after Patch 4

The production database should remain uninitialized. Patch 4 only proves the credentials and target are correct enough to proceed to a separately approved initialization step later.
