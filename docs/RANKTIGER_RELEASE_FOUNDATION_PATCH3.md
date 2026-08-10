# RankTiger Release Foundation — Patch 3

## Purpose

Patch 3 prepares the ScoreMore repository for controlled RankTiger releases without creating or modifying any production system.

## Safety state after Patch 3

- ScoreMore remains the only editable source repository.
- ScoreMore DEV deployment continues unchanged.
- RankTiger production repository is not required yet.
- RankTiger PROD Supabase is not required yet.
- Cloudflare is not required yet.
- Production database migration is disabled in the Patch 3 workflow.
- Cross-repository push is disabled in the Patch 3 workflow.

## New manual workflow

`.github/workflows/prepare-ranktiger-release.yml`

Visible name:

`Prepare RankTiger Release Candidate — SAFE NO DEPLOY`

It runs only through `workflow_dispatch` and requires the exact confirmation:

`PREPARE_RANKTIGER_RC`

The workflow is intentionally blocked until both of these later prerequisites exist:

1. `package-lock.json`
2. GitHub secrets `RANKTIGER_SUPABASE_URL` and `RANKTIGER_SUPABASE_PUBLISHABLE_KEY`

Until then, pressing the workflow cannot deploy production; it stops safely.

## Candidate package

When later enabled, the workflow builds using:

`npm run build:ranktiger`

and creates:

```text
release/ranktiger/
├── dist/
└── RELEASE.json
```

`RELEASE.json` records:

- RankTiger version
- ScoreMore source commit
- source ref
- build target
- production base path
- UTC build time
- SHA-256 of the exact `dist/` tree
- migration count/latest migration present in source
- explicit flags showing that Patch 3 did not migrate PROD or publish RankTiger

## Dependency-lock gate

The current source does not yet contain `package-lock.json`. Patch 3 does not invent one because a valid npm lockfile must come from the real npm registry resolution. The release-candidate workflow therefore refuses to continue until a genuine lockfile exists.

ScoreMore DEV keeps its already-working `npm install` Pages workflow for now. This avoids disturbing the verified DEV deployment.

## Historical migration protection

`docs/LOCKED_MIGRATION_CHECKSUMS_PATCH3.json` records SHA-256 checksums for every SQL migration that existed when Patch 3 was created.

`npm run verify:release-foundation` confirms those historical migration files remain byte-for-byte unchanged. Future schema work must add a new migration file rather than editing an old one.

## Commands

Dependency-free structural safety check:

```bash
npm run verify:patch3
```

Future packaging command after a real RankTiger build exists:

```bash
RANKTIGER_RELEASE_VERSION=1.0.0-rc.1 npm run package:ranktiger
```

## What Patch 3 does NOT do

It does not:

- create the RankTiger GitHub repository
- create RankTiger PROD Supabase
- migrate RankTiger PROD
- store a database password
- store a service-role key
- request a RankTiger repository write token
- push to another repository
- connect Cloudflare
- publish `ranktiger.in`

Those remain later, separately verified phases.
