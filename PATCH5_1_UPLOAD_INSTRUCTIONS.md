# Patch 5.1 Upload Instructions

1. Replace the existing ScoreMore repository contents with the full Patch 5.1 repository, or upload the changed files preserving paths.
2. Confirm `.github/workflows/initialize-ranktiger-prod-db.yml` is the Patch 5.1 version.
3. Confirm `supabase/migrations/20260811020000_public_catalogue_baseline.sql` exists.
4. Wait for the normal ScoreMore DEV Pages deployment to complete.
5. Do **not** run the RankTiger PROD database workflow until ChatGPT verifies the installation screenshot.
6. The production workflow must not contain `--include-seed`.
