# ScoreMore Admin UI Sidebar v1.3 — VERIFIED

Target: ScoreMore DEV only.

This is a UI/navigation patch only. It does not change Supabase schema, RPCs, import rules,
image-repair rules, review rules, publication guards, test data structures, or RankTiger PROD.

## Replace exactly these repository files

1. `admin.html`
2. `assets/js/admin.js`
3. `assets/css/main.css`

No `api.js` replacement is required for this UI patch.

## New admin navigation

Desktop:
- Persistent professional left sidebar.
- Only the selected admin function is shown in the main workspace.
- Sidebar groups question workflow and test operations.

Mobile/tablet:
- Compact menu button in the admin top bar.
- Off-canvas left drawer with backdrop and close control.
- Selecting a function closes the drawer automatically.

Question workflow remains exactly:
Import → Image & Content Repair → Final Review → Publish

Test functions:
- Build Tests
- Dynamic Builder
- Test Catalogue

## Functional safety preserved

- All previous functional HTML IDs are preserved.
- Existing import, repair, review, publish and test handlers remain wired to the same controls.
- `refreshDrafts` was moved into Final Review as a contextual action; its ID is unchanged.
- Editing an existing configured test automatically opens the Build Tests workspace.
- “Back to repair” navigation now opens the Repair workspace when needed.
- Active workspace is remembered for the current browser session.
- URL hash deep-links use `#admin-import`, `#admin-repair`, `#admin-review`,
  `#admin-publish`, `#admin-tests`, and `#admin-catalogue`.

## Upload sequence

Upload all 3 files to the matching paths in the ScoreMore repository in one commit if convenient.
Wait for `Deploy ScoreMore DEV to GitHub Pages` to become green.

Then test on ScoreMore DEV only:
1. Sign in as admin.
2. Desktop: sidebar is visible and sticky.
3. Mobile: menu button opens/closes the left drawer.
4. Open each function and confirm only that workspace is visible.
5. Import screen still validates packages.
6. Repair queue still opens repair details.
7. Final Review still opens ready drafts.
8. Publish queue still loads.
9. Build Tests still loads questions.
10. Test Catalogue still loads configured tests.
11. Dynamic Builder link still opens the separate dynamic builder page.
12. Sign out and sign back in.

Do not promote this UI to RankTiger PROD until ScoreMore DEV acceptance passes.
