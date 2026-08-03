# ScoreMore

ScoreMore is a separate Supabase-based examination platform starter for the initial **GSSSB CCE** public scope.

It does not modify or connect to the current ScoreBadhao Google Sheets + Apps Script project.

## Included vertical slice

- Supabase email/password authentication
- Dynamic public settings and GSSSB CCE catalogue metadata
- Mobile-first student landing page and dashboard
- Published test catalogue
- Create/resume test attempt through PostgreSQL RPC
- Batched protected question loading
- Local answer persistence and queued Supabase synchronization
- Server-side scoring and mistake-book population
- Admin authorization through `profiles.role`
- Private source PDF/image upload
- Manual draft creation
- Mandatory human draft review
- Protected draft publication RPC
- Row Level Security policies
- Supabase migrations and seed data
- GitHub Pages deployment workflow

## Architecture rules

- Questions are stored once in `questions`.
- Imported/manual/PDF/OCR/AI questions first enter `draft_questions`.
- Only `publish_draft_question` moves a reviewed draft into `questions`.
- Existing ScoreBadhao Question ID formats are preserved as text primary keys.
- Boards, exams, subjects, topics, tests and packages are database-driven.
- The frontend uses `assets/js/api.js` as its central data layer.
- The Supabase service-role key must never be used in the browser.
- Never use `alert()`; use the global toast manager.

## Start locally

Requirements:

- Node.js 22.12 or later
- npm
- A Supabase project
- Supabase CLI for migration-based development

```bash
npm install
cp .env.example .env
npm run dev
```

Fill `.env` with the project URL and browser-safe publishable/anon key.

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_BROWSER_SAFE_KEY
```

Apply the database migration and seed by following [`docs/SETUP.md`](docs/SETUP.md).

## Build

```bash
npm run build
npm run preview
```

The production output is generated in `dist/`.

## Deploy to GitHub Pages

1. Create the GitHub repository exactly as `ScoreMore`.
2. Upload this repository content to the repository root.
3. Add repository secrets:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_PUBLISHABLE_KEY`
4. In **Settings → Pages**, select **GitHub Actions** as the source.
5. Push to `main` or run the workflow manually.

The Vite base path is `/ScoreMore/`. Change `vite.config.js` only if the repository name changes.

## Important documents

- [`docs/ARCHITECTURE_LOCK.md`](docs/ARCHITECTURE_LOCK.md)
- [`docs/DATABASE_SCHEMA.md`](docs/DATABASE_SCHEMA.md)
- [`docs/DEVELOPMENT_ROADMAP.md`](docs/DEVELOPMENT_ROADMAP.md)
- [`docs/MIGRATION_MAPPING_SCOREBADHAO.md`](docs/MIGRATION_MAPPING_SCOREBADHAO.md)
- [`docs/SETUP.md`](docs/SETUP.md)

## Official platform references

- Supabase JavaScript client: https://supabase.com/docs/reference/javascript/initializing
- Supabase Row Level Security: https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase migrations: https://supabase.com/docs/guides/deployment/database-migrations
- Supabase Storage access control: https://supabase.com/docs/guides/storage/security/access-control
- GitHub Pages custom workflows: https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages
