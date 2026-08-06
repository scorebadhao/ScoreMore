# ScoreMore Development Roadmap

## Locked near-term sequence — approved 4 August 2026

### Phase 1 — Public/student application separation

- Keep `index.html` public-only.
- Add authenticated `student.html`.
- Use `assets/js/public.js` for the public entry point.
- Keep `assets/js/student.js` for the authenticated application.
- Preserve authentication, catalogue, attempt, refresh and mobile-back behaviour.

Acceptance:

- Logged-out visitors can use the public landing, catalogue and authentication forms.
- Logged-in users are redirected from `index.html` to `student.html`.
- Opening `student.html` while signed out redirects to `index.html`.
- Test start/resume/submit survives the page separation.
- GitHub Pages builds `index.html`, `student.html` and `admin.html`.

### Phase 2 — ScoreBadhao-inspired ScoreMore UI redesign — COMPLETED

- Reviewed the user-supplied ScoreBadhao repository ZIP.
- Rebuilt the useful public, dashboard, catalogue, navigation and test-engine UX patterns for ScoreMore.
- Added improved mobile hierarchy, accessibility, search, test-type tabs, question navigator and result summary.
- Preserved Supabase, RLS, RPC, separate-page and central API architecture.
- Did not copy ScoreBadhao backend architecture, Apps Script logic, secrets or branding.

Acceptance:

- Public landing, discovery, catalogue and authentication remain database driven.
- Student dashboard and catalogue remain fully authenticated and refresh safe.
- Existing test start/resume/save/submit behaviour remains connected to Supabase.
- Admin question and test workflows remain unaffected.
- Results history and Mistake Revision stay deferred to Phase 5.

### Phase 3 — Accurate validated HTML import engine

#### Phase 3A — Import database foundation — COMPLETED AND DEPLOYED

- Added versioned HTML/JSON package specification and machine-readable JSON Schema.
- Added raw-file, canonical-package and source checksum identities.
- Added `import_batch_items` for permanent item-level reconciliation.
- Added `question_occurrences` so one master question can represent multiple authentic source appearances.
- Added server-generated strict and loose fingerprints.
- Added content-origin tracking and PYQ origin restrictions.
- Added draft chronology and import-item traceability.
- Added package/question validation RPCs and secure occurrence-link RPC.
- Strengthened `publish_draft_question()` against duplicate content and source conflicts.

Acceptance before Phase 3B:

- Database migration workflow succeeds.
- Existing question, draft, test and attempt flows remain operational.
- Existing records receive fingerprints.
- Duplicate master content is protected by a unique index.
- New import tables remain admin-only under RLS.
- Validation RPCs return structured errors/warnings without writing data.

#### Phase 3B — Dry-run parser and reconciliation UI — COMPLETED AND DEPLOYED

- Safely parses only `#scoremore-import-data`; imported HTML and scripts are never rendered or executed.
- Calculates raw-file and canonical-payload SHA-256 checksums in the browser.
- Performs versioned structural validation aligned to the locked JSON Schema.
- Reuses exact source/package reports and blocks package ID conflicts.
- Uploads new HTML packages to the private admin-only source bucket.
- Calls PostgreSQL validation for every merged source/default/item record.
- Persists item-level status, errors, warnings, fingerprints, duplicates and conflicts.
- Provides Android-friendly filters, batch history and downloadable reconciliation JSON.
- Creates no drafts and no published questions.

Acceptance before Phase 3C:

- database and frontend workflows deploy successfully;
- the same file reuses one source, one batch and the same item rows;
- changed content with the same package ID is blocked;
- dry-run summary and item details are readable on mobile;
- manual draft, Test Manager and student attempt flows pass regression.

#### Phase 3C — Controlled draft import — COMPLETED AND DEPLOYED

- Imports only selected `VALID` and `VALID_WITH_WARNINGS` items into `draft_questions`.
- Revalidates every selected record against current database state before insertion.
- Skips exact duplicates without creating duplicate drafts or master questions.
- Keeps possible duplicates and conflicts blocked for human correction.
- Links explicitly selected exact duplicate PYQ occurrences to existing master questions.
- Preserves source file, import batch, import item, sort order, content origin and fingerprint traceability.
- Records per-item resolution action, admin identity and timestamp.
- Supports safe retries without creating additional drafts.
- Keeps human review and protected publication mandatory.

Acceptance before Phase 3D:

- database migration and frontend workflows deploy successfully;
- the sample package creates exactly one new pending draft;
- its exact duplicate creates no draft;
- running the import action again creates zero extra drafts;
- reopening the same batch displays the created draft ID and persistent action state;
- manual draft, test manager and student flows pass regression.

#### Phase 3D — Duplicate/conflict acceptance testing — TEST SUITE PREPARED

- Added a controlled eight-record matrix for valid, warning, exact duplicate, alternate-ID duplicate, possible duplicate, ID conflict, answer conflict and unknown catalogue handling.
- Added separate source-occurrence conflict, malformed-options and package-ID conflict packages.
- Added exact execution order, expected status matrix and read-only SQL verification.
- Requires exactly two controlled drafts once, zero published Phase 3D questions and zero extra records on exact re-import.
- Phase 4 remains blocked until the complete mobile acceptance checklist passes.

### Phase 4 — Dynamic question reuse

- Import one genuine GSSSB CCE shift.
- Reuse each published master question for the original paper, sectional tests and topic practice.
- Do not duplicate master question rows.

### Phase 5 — Results and Mistake Revision

- Results history
- Detailed attempt review
- Improved result summary
- Mistake Revision list
- Automatic resolved/unresolved status
- Secure student-only RPC functions

---

## Long-term roadmap

### Foundation and security

- Repository and separate Supabase project
- Migration-based database history
- Owner/admin bootstrap
- RLS verification
- Dynamic public configuration

### Content operations

- Draft validation and preview
- Human review and correction
- Protected publication
- Private source upload
- Import history and reconciliation

### Test platform

- Dynamic catalogue
- Fixed and filtered question selection
- Exam, Practice and Review modes
- Offline answer queue
- Server-side scoring
- Duplicate submission protection

### Learning and analytics

- Bookmarks
- Mistake practice generation
- Subject/topic/difficulty analysis
- Time analysis
- Rank, percentile and readiness score

### Commercial readiness

- Package catalogue
- Access expiry
- Admin grants
- Payment verification through trusted backend logic

### Production quality

- Mobile and desktop QA
- Slow-network and offline QA
- Security and RLS review
- Accessibility and Lighthouse review
- Backup and restore drill


## Phase 3E compatibility

AI-proposed answers, canonical topic mapping, dynamic paper completeness, confidence/source-quality metadata and safely labelled supplemental NORMAL questions are supported. AI-proposed answers and unresolved PYQ topics remain blocked from publication until human review.

## Import reliability patch

Completed: AI_PROPOSED status repair, timeout-state recovery, compact mobile reports, automatic safe preparation, chunked draft creation, mobile record pagination, and protected reset of untouched drafts.

## Import recovery refinement — completed patch

- Visual-aware fingerprint Version 2
- Old batch recheck without re-upload
- True duplicate reuse/linking instead of copy creation
- Deferred PYQ occurrence linking after canonical draft publication
- Lightweight draft list and one-draft-at-a-time review
- Verify-and-next mobile workflow

## Import and publication refinement — completed patch

- Genuine printed duplicate-option anomaly support with explicit source traceability
- In-place recovery of Shift 1 V2 Q55 without deleting the batch or 99 valid drafts
- Separate Review Centre and Publish Centre
- Compact verified publish queue
- Individual and chunked verified publication with per-item failure isolation

## Test administration refinement — completed patch

- Three-step mobile Test Builder
- Exact PYQ year/shift/paper filtering
- Original-question chronology in fixed lists
- Local search and visible-question selection
- Test ID/name suggestion
- Paper metadata stored on tests
- Searchable catalogue with status counts
- Edit, Publish, Archive and Restore Draft actions
