# RankTiger First Release Candidate — Patch 6

Status: CANDIDATE-ONLY / NO PRODUCTION FRONTEND DEPLOYMENT

Patch 6 operationalizes the existing RankTiger release-candidate foundation after RankTiger PROD database initialization succeeded.

## Locked purpose

Patch 6 may:

1. bootstrap a reproducible `package-lock.json` as a GitHub Actions artifact,
2. require that lock to be committed back into ScoreMore before a candidate build,
3. verify the complete ScoreMore → RankTiger safety chain,
4. verify the RankTiger PROD project identity and public API baseline using browser-safe values only,
5. build the `ranktiger` Vite target with base `/`,
6. package `release/ranktiger/dist/` plus `RELEASE.json`,
7. upload the candidate as a GitHub Actions artifact.

Patch 6 must NOT:

- migrate RankTiger PROD,
- use a database password or Supabase account access token in the RC workflow,
- push to the RankTiger repository,
- deploy to Cloudflare,
- attach `ranktiger.in`,
- expose service-role/secret keys,
- run automatically on normal ScoreMore commits.

## One-time dependency lock bootstrap

Workflow:

`.github/workflows/bootstrap-package-lock.yml`

Manual confirmation:

`BOOTSTRAP_SCOREMORE_LOCK`

The workflow runs `npm install --package-lock-only` and uploads `package-lock.json` as an artifact. It has `contents: read`, uses no repository secrets, and performs no deployment.

The generated `package-lock.json` must then be uploaded to the ScoreMore repository root. After that, RankTiger release candidates use `npm ci` and refuse to build without the committed lock.

## Release-candidate workflow

Workflow:

`.github/workflows/prepare-ranktiger-release.yml`

Manual confirmation:

`PREPARE_RANKTIGER_RC`

First candidate version:

`1.0.0-rc.1`

The workflow requires:

- `RANKTIGER_SUPABASE_PROJECT_ID`
- `RANKTIGER_SUPABASE_URL`
- `RANKTIGER_SUPABASE_PUBLISHABLE_KEY`

It explicitly rejects the locked ScoreMore DEV project ID and cross-checks the RankTiger URL against the RankTiger project ID before using the production browser-safe configuration.

## Candidate artifact

The artifact contains:

```text
release/ranktiger/
├── dist/
│   ├── index.html
│   ├── student.html
│   ├── admin.html
│   ├── test-builder.html
│   └── assets/...
└── RELEASE.json
```

`RELEASE.json` records:

- candidate version,
- exact ScoreMore source commit/ref,
- RankTiger build target and `/` base path,
- `dist/` SHA-256 tree fingerprint,
- dependency-lock SHA-256,
- package manifest SHA-256,
- RankTiger PROD project ID used for the build,
- 20-migration Patch 5.2 source baseline,
- latest source migration,
- confirmation that the public PROD baseline was verified before build,
- confirmation that this workflow did not migrate PROD, update RankTiger GitHub, deploy Cloudflare, or deploy the student domain.

## Promotion boundary

A successful Patch 6 candidate is still NOT a stable release.

The next phase must inspect/download the artifact and then add a separate controlled promotion path that copies only the approved built `dist/` plus minimal release metadata into the RankTiger production repository.
