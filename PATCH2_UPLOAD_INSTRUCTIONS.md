# Patch 2 Upload Instructions

1. Upload/replace the files from this repository in the existing **ScoreMore** GitHub repository.
2. Keep the existing `.github/workflows/` files exactly as they are; Patch 2 does not change them.
3. Wait for **Deploy ScoreMore DEV to GitHub Pages** to finish successfully.
4. Do **not** run **Deploy ScoreMore DEV Database**. Patch 2 contains no migration.
5. Verify the existing ScoreMore DEV site still shows ScoreMore and the normal student flow works.
6. Do not create RankTiger GitHub, RankTiger Supabase, or Cloudflare yet.

Primary modified runtime files:

- `build-targets.js`
- `assets/js/config.js`
- `assets/js/public.js`
- `assets/js/student.js`
- `assets/js/api.js`
- `supabase/seed.sql`
- `package.json`
- `.env.example`

New verification/documentation files are included in the repository.
