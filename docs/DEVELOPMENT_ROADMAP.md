# ScoreMore Development Roadmap

## Phase SM-0 — Repository and Supabase foundation

- Create repository and Supabase project
- Apply migrations and seed
- Configure local environment
- Bootstrap owner admin
- Verify GitHub Pages deployment
- Test all RLS policies

Acceptance: no secret in GitHub; public catalogue loads; non-admin cannot open admin data.

## Phase SM-1 — Draft-review-publish vertical slice

- Dynamic board/exam/subject/topic selectors
- Private source upload
- CSV/static-page import adapter
- PDF/OCR import records
- Draft validation and preview
- Review correction form
- Publish and reject audit trail

Acceptance: no import path can insert directly into `questions`.

## Phase SM-2 — Dynamic landing and dashboard

- Dynamic statistics
- Authentication lifecycle
- Student profile
- Continue attempt card
- Recent attempts
- Recommended test placeholder based on data
- Refresh and mobile-back stability

## Phase SM-3 — Test catalogue

- Dynamic test tabs
- Year/date/shift/subject filters
- Package locks
- Start/resume/reattempt state
- Pagination/lazy loading

## Phase SM-4 — Test engine stabilization

- Exam, Practice and Review modes
- Timer and auto-submit
- Question palette
- Section switching
- Mark for review
- Bookmark
- IndexedDB/local queue
- Retry and conflict handling
- Duplicate submission protection

## Phase SM-5 — Real GSSSB CCE PYQ import

- Import one complete shift through drafts
- Verify official answer source
- Publish after human review
- Build original full paper
- Build sectional tests from the same question rows
- Build topic practice from the same question rows

## Phase SM-6 — Results and analytics

- Score summary
- Subject/topic/difficulty analysis
- Time analysis
- Mistake patterns
- Recommendation engine

## Phase SM-7 — Revision loops

- Bookmarks
- Mistake book
- Repeated mistake count
- Revision test generation

## Phase SM-8 — Rank and leaderboard

- Test rank
- Percentile
- Readiness score
- Improvement trend
- Privacy-safe leaderboard names

## Phase SM-9 — Packages and payment readiness

- Package catalogue
- Access expiry
- Admin grants
- Razorpay/UPI readiness
- Payment verification through trusted backend logic

## Phase SM-10 — Production quality

- Mobile device QA
- Slow network QA
- Offline answer QA
- RLS/security review
- Accessibility review
- Lighthouse review
- Error logging
- Backup and restore drill
- Launch checklist
