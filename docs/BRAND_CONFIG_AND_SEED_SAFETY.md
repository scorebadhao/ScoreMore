# ScoreMore DEV / RankTiger PROD — Brand Configuration and Seed Safety

Status: Patch 2

## Purpose

Patch 2 makes the shared source safe to render either ScoreMore DEV or RankTiger PROD without allowing a database seed, legacy backend message, or browser-storage key to leak the wrong product identity.

## Build-controlled identity

`build-targets.js` is the only source of truth for:

- product name;
- product mark;
- environment identity;
- Vite base path;
- browser cache namespace;
- default public copy used when database content is absent.

The database is not allowed to decide which product is running.

## Database public settings

The database may continue to control public content such as:

- `app_tagline`;
- `scope_badge`;
- `hero_title`;
- `hero_subtitle`.

The runtime resolver ignores database values for product identity (`app_name`, `app_mark`, `app_environment`). Existing DEV rows such as `app_name = ScoreMore` may remain in the current database because the application no longer treats them as authoritative.

## Shared seed rule

`supabase/seed.sql` is now a shared environment-neutral content seed.

It MUST NOT seed:

- `app_name`;
- `app_mark`;
- `app_environment`;
- production credentials;
- environment-specific URLs.

This prevents a future RankTiger database deployment from being branded back to ScoreMore by `--include-seed`.

## Historical migration rule

Already-applied migrations are immutable history and are not renamed merely because the public product is now RankTiger.

Some historical PostgreSQL exception/comment text still contains the display word `ScoreMore`. Patch 2 normalizes human-readable backend errors through `brandRuntimeText()` so a RankTiger build displays `RankTiger` without rewriting migration history.

Internal compatibility identifiers deliberately remain unchanged, including:

- `scoremore.question-import`;
- `#scoremore-import-data`;
- existing migration filenames;
- internal dataset/property names where renaming would break compatibility.

These are protocol/implementation identifiers, not public branding.

## Browser state separation

Pending-test browser state now uses the build cache namespace instead of a hardcoded `scoremore:` key. ScoreMore DEV and RankTiger PROD therefore have independently named browser-state keys even before domain isolation is considered.

## Verification

Run:

```bash
npm run verify:patch2
```

This is dependency-free and checks both Patch 1 target safety and Patch 2 brand/seed safety.
