# ScoreMore Architecture Lock v1.0

## Identity

ScoreMore is a separate Supabase project and repository. It must not share a live database, environment file, backend code or source of truth with ScoreBadhao, WAGH Tuition Classes or WTC Learn.

## Locked platform shape

- One student website
- One admin page
- One Supabase project
- One PostgreSQL database
- One repository
- One central frontend data module: `assets/js/api.js`
- PostgreSQL RPC for trusted multi-step workflows
- Supabase CLI migrations for schema history
- GitHub Pages deployment from GitHub Actions

## Initial public scope

- Board: GSSSB
- Exam: CCE

The UI may emphasize GSSSB CCE, but IDs and catalogue records come from PostgreSQL.

## Content lock

- Preserve inherited normal and PYQ Question ID formats.
- Store every published master question once.
- Use test filters or fixed links to reuse questions.
- All imported/manual/PDF/OCR/AI content enters `draft_questions` first.
- Human review is mandatory.
- Publication occurs only through `publish_draft_question`.

## Security lock

- RLS remains enabled on exposed tables.
- Students can access only their own personal data.
- Students cannot directly query master answers during an attempt.
- The service-role key never enters frontend code or GitHub.
- Admin status is checked from database-owned `profiles.role`.
- The private `source-documents` bucket is admin-only.

## UI lock

- Mobile first
- Gujarati friendly
- Loading, empty and error states
- Global toast notifications
- No `alert()`
- No overlapping mobile controls
- Refresh-safe auth and attempt state

## Architecture changes

Any change to this document requires explicit user approval before implementation.
