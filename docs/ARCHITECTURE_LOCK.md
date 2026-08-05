# ScoreMore Architecture Lock v1.6

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

## Phase 3 import architecture lock

The user approved the Phase 3 design on 4 August 2026.

- HTML is a portable container; the JSON payload inside `#scoremore-import-data` is authoritative.
- Imported HTML is never executed or inserted into the admin DOM.
- Raw file bytes, canonical payload identity and original source identity use separate SHA-256 checksums.
- Every package question receives an item-level reconciliation row, including invalid and duplicate records.
- Strict content fingerprints block duplicate master questions even when Question IDs or source papers differ.
- Loose fingerprints produce human-review warnings only.
- One master question may have many rows in `question_occurrences`.
- Same Question ID with different content, same content with different answer, and same occurrence with different content are blocking conflicts.
- Missing answers may enter drafts but cannot be published.
- `RECONSTRUCTED` and `AI_GENERATED` content cannot be published as original PYQ content.
- No import route inserts directly into `questions`; `publish_draft_question()` remains mandatory.
- The versioned specification is `docs/HTML_IMPORT_SPEC_v1.md`.
- Phase 3B uses `assets/js/importEngine.js` for non-executing HTML parsing, UTF-8 decoding, canonical JSON and browser SHA-256 calculation.
- `stage_import_dry_run()` is the authoritative admin-only write boundary for dry-run batches and item reconciliation.
- Phase 3B creates `import_batches` and `import_batch_items` only; it must create no drafts and no published master questions.
- Exact package/file re-imports reuse the existing report instead of creating duplicate source, batch or item rows.

## Phase 3C controlled import lock

- Only `VALID` and `VALID_WITH_WARNINGS` reconciliation items may create drafts.
- Every selected item is revalidated by PostgreSQL immediately before draft insertion.
- `POSSIBLE_DUPLICATE`, conflict and invalid records remain blocked.
- Exact duplicates never create another draft or master question.
- Exact duplicate PYQ content may link a confirmed new source occurrence to the existing published master question.
- `import_valid_batch_items_to_drafts()` is the only Phase 3C batch-to-draft write boundary.
- `link_import_batch_occurrences()` is the only Phase 3C batch duplicate-occurrence write boundary.
- Both operations are admin-only, idempotent, audit logged and preserve the original source file, package, item and chronology references.
- Draft creation never bypasses `draft_questions`; human review and `publish_draft_question()` remain mandatory.
- Re-running the same import action must create zero additional drafts and zero duplicate master questions.

## Phase 3D controlled acceptance lock

- Phase 3D changes no production schema and adds no new frontend write path.
- The acceptance suite is stored under `examples/import/phase3d/`.
- Test packages are synthetic and must never be published as genuine PYQs.
- The main matrix must prove `VALID`, `VALID_WITH_WARNINGS`, `EXACT_DUPLICATE`, `POSSIBLE_DUPLICATE`, `ID_CONFLICT`, `ANSWER_CONFLICT` and `INVALID` handling.
- Separate packages must prove `SOURCE_CONFLICT`, local malformed-option rejection and `PACKAGE_ID_CONFLICT`.
- Exact file re-import must reuse source, batch, item and draft identities and create zero additional records.
- Controlled draft import must create exactly two drafts once and no published question.
- Invalid, conflict and possible-duplicate items remain blocked.
- Acceptance evidence is permanent; cleanup uses draft rejection, never destructive SQL deletion.
- Phase 4 cannot begin until `docs/PHASE3D_ACCEPTANCE_TESTS.md` passes completely.

## Locked near-term phase sequence

1. Separate the public and authenticated student applications — COMPLETED.
2. ScoreBadhao-inspired ScoreMore UI redesign — COMPLETED for the public landing, student dashboard, catalogue and test-engine foundation.
3. Build the validated HTML import engine:
   - Phase 3A database identity, duplicate constraints, validation RPCs and specification — COMPLETED and deployed.
   - Phase 3B admin safe parser, checksum identity, persistent dry-run staging and reconciliation UI — COMPLETED AND DEPLOYED.
   - Phase 3C controlled draft import and occurrence linking — COMPLETED AND DEPLOYED.
   - Phase 3D duplicate/conflict acceptance testing — CONTROLLED TEST SUITE PREPARED; execution pending.
4. Reuse imported master questions across original papers, sectional tests and topic practice without duplication.
5. Build Results history, detailed review and Mistake Revision.

This sequence may change only with explicit user approval.

## Architecture changes

Any change to this document requires explicit user approval before implementation.


## Phase 3E compatibility

AI-proposed answers, canonical topic mapping, dynamic paper completeness, confidence/source-quality metadata and safely labelled supplemental NORMAL questions are supported. AI-proposed answers and unresolved PYQ topics remain blocked from publication until human review.
