# ScoreMore Admin Console v1.4 — Unified Workspace + Smart Dynamic Filters

Target: **ScoreMore DEV only**.

This patch implements the UI plan approved in chat after reviewing the live mobile Admin and Dynamic Builder screenshots.

## Replace exactly these repository files

1. `admin.html`
2. `test-builder.html`
3. `assets/js/admin.js`
4. `assets/js/testBuilder4A.js`
5. `assets/js/adminShell.js` **(new)**
6. `assets/css/main.css`
7. `assets/css/testBuilder4A.css`

No Supabase migration is required. `assets/js/api.js` is intentionally unchanged.

## What changes

### Unified Admin Console
- One navigation model across Admin and Dynamic Builder.
- Desktop: persistent left sidebar.
- Mobile/tablet: off-canvas left drawer.
- Compact account menu prevents Student site / Sign out from wrapping into multiple header rows.
- Dynamic Builder keeps the same Admin shell and highlights `Dynamic Builder`.
- All old `#testManagerSection` back-links are removed in favor of `#admin-*` workspace routes.

### Admin Dashboard
- New Dashboard is the default Admin workspace.
- Queue/operations cards for Image & Content Repair, Final Review, Publish, and configured Tests.
- Quick actions for Import, Repair, Review, and Dynamic Builder.
- The locked quality gate is visibly preserved:
  `Import → Repair → Final Review → Publish → Test`.

Accuracy note: the Final Review card explicitly describes its number as the currently loaded draft page when more draft pages remain; it does not pretend to be an exact global count.

### Test Catalogue dynamic filters
The existing Test Catalogue gains client-side filters generated from actual configured tests:
- Status
- Test type
- Board
- Exam
- Subject
- Exam year
- Search

The options are populated from loaded test records; they are not hardcoded catalogue values.

### Dynamic Test Builder smart facets
The existing Phase 4A Supabase facet engine is preserved. No database rewrite is needed.

The UI now uses those authoritative facets as cascading smart filters:
- Exam context: Board → Exam → Year → Paper/Package
- Classification: Subject → Topic
- Advanced: Shift, Section, Language, Difficulty, Question type, Membership
- Each facet keeps database-provided counts.
- Large facet lists receive an in-menu search field.
- Facets recalculate after a short debounce when a selection changes.
- The question stack does **not** reload on every checkbox click; Admin presses `Apply filters` after choosing context.
- Pressing Enter in question search also applies the filters.

### Mode-aware safety
- `Original full PYQ`: only Paper/Package remains available; narrowing filters are cleared so an original paper cannot accidentally become partial.
- `Completed PYQ practice`: same full-paper package boundary, with supplements forced according to existing mode rules.
- `Sectional PYQ`: package + subject/topic and contextual filters remain available.
- `Custom selected`: complete smart filter set remains available.

The backend preview/save rules remain authoritative.

## DEV acceptance checklist

### Admin shell
- Sign in on ScoreMore DEV.
- Dashboard opens by default.
- Desktop sidebar stays visible and sticky.
- Mobile menu opens/closes the drawer correctly.
- Account menu opens without wrapping the topbar.
- Student site and Sign out work.
- Import / Repair / Final Review / Publish / Build Tests / Test Catalogue all open normally.

### Dynamic Builder
- Opening Dynamic Builder keeps the same Admin shell.
- Dynamic Builder is highlighted in the sidebar.
- Mobile header stays one compact row.
- Test modes switch without stale hidden filters.
- Original Full PYQ shows only package selection.
- Sectional shows package + subject/topic.
- Custom shows the complete filters.
- Changing a facet updates facet options/counts but does not reload the stack until Apply.
- Apply filters loads the matching question stack.
- Large Topic/Package lists can be searched inside the facet dropdown.
- Select visible / Select all filtered / Clear selection still work in Custom mode.
- Preview and Save/Publish still use the existing server-side Phase 4A RPCs.

### Test Catalogue
- Filter values are populated from configured tests.
- Status stat cards still work.
- Search + Type + Board + Exam + Subject + Year combine correctly.
- Clear filters restores all tests.
- Edit and status actions still work.

Do not promote to RankTiger PROD until this ScoreMore DEV acceptance passes.
