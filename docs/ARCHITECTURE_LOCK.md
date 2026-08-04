# ScoreMore Architecture Lock v1.2

**Status:** APPROVED AND LOCKED  
**Approved:** 4 August 2026

## Identity

ScoreMore is a separate Supabase project and repository. It must not share a live database, environment file, backend code or source of truth with ScoreBadhao, WAGH Tuition Classes or WTC Learn.

## Locked platform shape

- One public website entry page: `index.html`
- One authenticated student application: `student.html`
- One protected admin page: `admin.html`
- One Supabase project
- One PostgreSQL database
- One repository
- One central frontend data module: `assets/js/api.js`
- PostgreSQL RPC for trusted multi-step workflows
- Supabase CLI migrations for schema history
- GitHub Pages deployment from GitHub Actions

## Locked page boundaries

### `index.html` — public application

- Public landing page
- Dynamic public statistics
- Public published-test catalogue
- Student sign-in and registration
- Authenticated-session redirect to `student.html`

### `student.html` — authenticated student application

- Student dashboard
- Dynamic test catalogue
- Active attempt and resume flow
- Test engine
- Future Results, Mistake Revision, Bookmarks, Practice and Profile modules
- Unauthenticated users are redirected to `index.html`

### `admin.html` — protected administration

- Admin role verification
- Draft-review-publish workflow
- Source upload
- Test configuration
- Future import and catalogue administration

Public, student and admin pages may share CSS, authentication helpers, the Supabase client and `assets/js/api.js`, but each page keeps a separate entry module.

## Approved frontend entry modules

- `assets/js/public.js` → `index.html`
- `assets/js/student.js` → `student.html`
- `assets/js/admin.js` → `admin.html`

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
- `student.html` must enforce authentication before showing student content.

## UI lock

- Mobile first
- Gujarati friendly
- Loading, empty and error states
- Global toast notifications
- No `alert()`
- No overlapping mobile controls
- Refresh-safe auth and attempt state
- Browser-back navigation must not sign the student out

## Phase 2 UI adoption lock

The ScoreBadhao repository supplied by the user may be used only as a UX reference. ScoreMore has adopted improved patterns for the public hero, dashboard hierarchy, test catalogue, bottom navigation, question workspace and question navigator.

The following remain prohibited:

- ScoreBadhao Google Sheets or Apps Script architecture
- ScoreBadhao authentication, payment, rank or data-access code
- ScoreBadhao branding or secrets
- Hardcoded ScoreBadhao catalogue data

The Phase 2 implementation is documented in `docs/UI_PARITY_SCOREBADHAO.md`.

## Locked near-term phase sequence

1. Separate the public and authenticated student applications.
2. ScoreBadhao-inspired ScoreMore UI redesign — COMPLETED for the public landing, student dashboard, catalogue and test-engine foundation.
3. Build the validated HTML import package and dry-run import engine.
4. Reuse imported master questions across original papers, sectional tests and topic practice without duplication.
5. Build Results history, detailed review and Mistake Revision.

This sequence may change only with explicit user approval.

## Architecture changes

Any change to this document requires explicit user approval before implementation.
