# Patch 6 upload instructions

Upload/replace the Patch 6 files in the existing **ScoreMore** repository. Do not upload them to RankTiger.

Critical workflow paths:

- `.github/workflows/bootstrap-package-lock.yml` (new)
- `.github/workflows/prepare-ranktiger-release.yml` (replace)

Critical script/config paths:

- `scripts/verify-dependency-lock.mjs` (new)
- `scripts/verify-ranktiger-release-candidate.mjs` (new)
- `scripts/package-ranktiger-release.mjs` (replace)
- `package.json` (replace)
- `ranktiger-release.config.json` (replace)

After the normal ScoreMore DEV Pages deployment is green:

1. Do **not** run the RankTiger candidate workflow yet.
2. Run **Bootstrap ScoreMore Dependency Lock — SAFE NO DEPLOY**.
3. Enter `BOOTSTRAP_SCOREMORE_LOCK`.
4. Download the generated workflow artifact.
5. Extract `package-lock.json` and upload it to the **root of ScoreMore** as `package-lock.json`.
6. Wait for ScoreMore DEV Pages to be green again.
7. Then run **Prepare RankTiger Release Candidate — SAFE NO DEPLOY** with version `1.0.0-rc.1` and confirmation `PREPARE_RANKTIGER_RC`.

The candidate workflow does not deploy to RankTiger GitHub, Cloudflare, or the student domain.
