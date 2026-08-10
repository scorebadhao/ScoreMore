# ScoreMore DEV / RankTiger PROD Environment Foundation

Status: Patch 1 foundation

## Locked behavior

- `npm run dev` starts the ScoreMore development identity.
- `npm run build` remains backward-compatible and builds ScoreMore DEV.
- `npm run build:scoremore` builds ScoreMore DEV with base path `/ScoreMore/`.
- `npm run build:ranktiger` builds the future RankTiger production identity with base path `/`.
- Supabase URL and browser-safe publishable/anon key are still injected through `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
- No production Supabase project is created or referenced by Patch 1.
- The ScoreMore database deployment workflow is explicitly DEV-only.
- Product identity comes from `build-targets.js`, not from the database `app_name` setting.

## Build target source of truth

`build-targets.js`

This file contains only non-secret build identity settings:

- product name
- tagline fallback
- environment label
- Vite base path
- browser cache namespace

Never add Supabase passwords, service-role keys, access tokens, or other secrets to this file.

## Current targets

### ScoreMore DEV

- mode: `scoremore`
- name: `ScoreMore`
- base: `/ScoreMore/`
- environment: `development`

### RankTiger PROD foundation

- mode: `ranktiger`
- name: `RankTiger`
- base: `/`
- environment: `production`

The RankTiger mode is only a build capability at this stage. RankTiger GitHub, production Supabase, Cloudflare, domain, and release automation are intentionally not created by Patch 1.

## Verification without installing dependencies

Run:

```bash
npm run verify:targets
```

This verifier does not require Vite or Supabase packages. It checks the locked ScoreMore and RankTiger identities, HTML build placeholders, the DEV-only Pages build command, and the DEV-only database confirmation guard.

## Temporary text mark

Patch 1 uses a build-time text mark only:

- ScoreMore DEV: `S+`
- RankTiger PROD foundation: `RT`

This is not the final RankTiger logo or mascot. It prevents a future RankTiger build from accidentally displaying the ScoreMore `S+` mark before the dedicated RankTiger branding patch is completed.
