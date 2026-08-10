# Patch 4 Upload Instructions

1. Upload/replace the full `ScoreMore-main` contents in the existing **ScoreMore** GitHub repository.
2. Because mobile uploads may skip `.github`, verify this file exists afterward:
   - `.github/workflows/verify-ranktiger-prod.yml`
3. Confirm GitHub Actions shows:
   - **Verify RankTiger PROD Connection — READ ONLY**
4. Do not run the ScoreMore DEV database workflow.
5. Do not run any production database initialization workflow (none is added by Patch 4).
6. After the normal ScoreMore DEV Pages deployment is green, run the new verification workflow only when instructed, using exact confirmation:
   - `VERIFY_RANKTIGER_PROD`
