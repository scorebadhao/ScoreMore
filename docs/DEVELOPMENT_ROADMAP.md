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

- Define a versioned HTML package containing validated structured JSON.
- Add dry-run preview, schema validation, duplicate detection and metadata warnings.
- Import only into `draft_questions` and import-batch records.
- Preserve mandatory human review before publication.

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
