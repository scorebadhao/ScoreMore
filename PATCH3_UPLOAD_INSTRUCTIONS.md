# Patch 3 Upload Instructions

1. Upload/replace the full repository contents in the existing `ScoreMore` GitHub repository.
2. Keep the already-correct Patch 1 DEV workflows.
3. This patch adds one new hidden workflow file:
   `.github/workflows/prepare-ranktiger-release.yml`
4. If mobile upload skips `.github`, upload that workflow file separately afterward.
5. Wait for `Deploy ScoreMore DEV to GitHub Pages` to finish green.
6. Test ScoreMore DEV normally.
7. Do NOT run `Deploy ScoreMore DEV Database` — Patch 3 has no database migration.
8. Do NOT run `Prepare RankTiger Release Candidate — SAFE NO DEPLOY` yet. It is intentionally blocked until later prerequisites exist.
