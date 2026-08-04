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

#### Phase 3A — Import database foundation — COMPLETED IN REPOSITORY

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

#### Phase 3B — Dry-run parser and reconciliation UI

- Safely parse only `#scoremore-import-data`.
- Calculate raw-file and canonical-payload checksums.
- Validate JSON Schema and package identity.
- Merge source/default/item metadata.
- Call PostgreSQL validation for every record.
- Persist and display dry-run status, errors, warnings, duplicates and conflicts.
- Do not create drafts yet.

#### Phase 3C — Controlled draft import

- Import selected valid new records into `draft_questions`.
- Link human-confirmed exact duplicates as source occurrences.
- Preserve raw payload, normalized payload and complete audit history.
- Provide downloadable reconciliation output.

#### Phase 3D — Duplicate/conflict acceptance testing

Test a package containing valid, exact duplicate, alternate-ID duplicate, ID conflict, answer conflict, source conflict, missing answer and unknown catalogue records. Re-import the same file and verify zero extra source files, batches, drafts and master questions.

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
