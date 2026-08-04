# ScoreMore

ScoreMore is a separate Supabase-based examination platform for the initial **GSSSB CCE** public scope.

It does not modify or connect to the ScoreBadhao Google Sheets + Apps Script project.

## Application pages

- `index.html` — public landing page, statistics, public test catalogue and authentication
- `student.html` — authenticated student dashboard, test catalogue and test engine
- `admin.html` — protected question and test administration

## Phase 2 UI foundation

ScoreMore now uses a separate public page and authenticated student application with a ScoreBadhao-inspired, ScoreMore-specific mobile UI. The UX reference is documented in `docs/UI_PARITY_SCOREBADHAO.md`; no ScoreBadhao backend architecture is used.


## Phase 3A import foundation

The approved HTML import architecture now has its database and specification foundation:

- versioned `scoremore.question-import` JSON payload embedded in HTML;
- raw file, canonical package and original source checksum identities;
- persistent item-level reconciliation in `import_batch_items`;
- strict duplicate prevention through server-generated content fingerprints;
- warning-only loose fingerprints for possible OCR/option-order matches;
- one master question with many authentic `question_occurrences`;
- content-origin and answer-source tracking;
- admin-only package/question validation RPCs;
- mandatory draft-review-publish remains unchanged.

Specification files:

- `docs/HTML_IMPORT_SPEC_v1.md`
- `docs/scoremore-question-import.schema.v1.json`

Phase 3A provides the database identity and duplicate foundation. Phase 3B now adds the safe dry-run interface:

- non-executing HTML parsing through `assets/js/importEngine.js`;
- raw-file and canonical-package SHA-256 checksums;
- client structural validation plus authoritative PostgreSQL validation;
- private HTML source storage;
- persistent `import_batches` and `import_batch_items` reconciliation;
- exact package/file report reuse;
- mobile filters, recent batch history and downloadable reconciliation JSON.

Phase 3B creates no drafts and publishes no questions. Controlled draft creation remains Phase 3C.

## Included vertical slice

- Supabase email/password authentication
- Mobile number stored in the student profile
- Dynamic public settings and GSSSB CCE catalogue metadata
- Separate public and authenticated student applications
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
- Fixed-question test manager
- Phase 3B HTML import dry-run and reconciliation engine
- Row Level Security policies
- Supabase migrations and seed data
- GitHub Pages deployment workflow

## Architecture rules

- Questions are stored once in `questions`.
- Imported/manual/PDF/OCR/AI questions first enter `draft_questions`.
- Only `publish_draft_question` moves a reviewed draft into `questions`.
- Existing Question ID formats are preserved as text primary keys.
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

Fill `.env` with the project URL and browser-safe publishable key.

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_BROWSER_SAFE_KEY
```

Local pages:

```text
http://localhost:5173/              public landing
http://localhost:5173/student.html  student application
http://localhost:5173/admin.html    admin application
```

Apply database migrations by following [`docs/SETUP.md`](docs/SETUP.md).

## Build

```bash
npm run build
npm run preview
```

The production output is generated in `dist/` and includes all three HTML entry points.

## Deploy to GitHub Pages

1. Use the GitHub repository named `ScoreMore`.
2. Add repository secrets:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_PUBLISHABLE_KEY`
3. In **Settings → Pages**, select **GitHub Actions** as the source.
4. Push to `main` or run the workflow manually.

Production pages:

```text
https://scorebadhao.github.io/ScoreMore/
https://scorebadhao.github.io/ScoreMore/student.html
https://scorebadhao.github.io/ScoreMore/admin.html
```

The Vite base path is `/ScoreMore/`. Change `vite.config.js` only if the repository name changes.

## Important documents

- [`docs/ARCHITECTURE_LOCK.md`](docs/ARCHITECTURE_LOCK.md)
- [`docs/DATABASE_SCHEMA.md`](docs/DATABASE_SCHEMA.md)
- [`docs/DEVELOPMENT_ROADMAP.md`](docs/DEVELOPMENT_ROADMAP.md)
- [`docs/MIGRATION_MAPPING_SCOREBADHAO.md`](docs/MIGRATION_MAPPING_SCOREBADHAO.md)
- [`docs/SETUP.md`](docs/SETUP.md)
