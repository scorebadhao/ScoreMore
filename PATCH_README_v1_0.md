# ScoreMore Admin Session Persistence Fix v1.0 — VERIFIED

## Target
ScoreMore DEV only.

## Problem fixed
The Admin page and Dynamic Test Builder could unexpectedly show the sign-in screen during
navigation, token refresh, page restoration, or a transient profile/session read.

The previous flow performed:
1. `api.getUser()`
2. `api.getProfile()`
3. `getProfile()` performed another `getUser()` internally

If the second auth read temporarily failed, the page could interpret that as a non-admin account
and automatically call `signOut()`.

## Fix
- Resolve the secure admin context in one controlled sequence:
  `getSession -> getUser once -> profile by verified user_id`.
- Retry transient session/profile verification once before declaring a temporary error.
- Never sign out because of a network/profile/data-loading error.
- Automatic sign-out is now limited to a successfully verified account whose profile is confirmed
  not to have role `ADMIN`.
- Explicit Sign out remains unchanged.
- Added a "Restoring admin session…" state so the login form does not flash during normal restoration.
- Added Retry session for temporary connection/session verification failures.
- Added safe handling for Supabase:
  - `INITIAL_SESSION`
  - `SIGNED_IN`
  - `TOKEN_REFRESHED`
  - `USER_UPDATED`
  - `SIGNED_OUT`
- Auth-state API work is deferred outside the Supabase callback.
- Added safe revalidation when Android/Chrome restores a page or returns from the background.
- A transient admin data-loading failure keeps the authenticated admin workspace open.

## Replace exactly these files
1. `admin.html`
2. `test-builder.html`
3. `assets/js/api.js`
4. `assets/js/admin.js`
5. `assets/js/testBuilder4A.js`

No SQL migration is required.
No `supabaseClient.js` change is required; the existing client already has:
`persistSession: true`, `autoRefreshToken: true`, and `detectSessionInUrl: true`.

## ScoreMore DEV acceptance test
After GitHub Pages deployment turns green:

### Test A — Admin → Dynamic Builder → Admin
1. Sign in once to ScoreMore Admin.
2. Open Dynamic Builder.
3. Return to Admin Dashboard.
4. Repeat 3–5 times.
Expected: no sign-in screen and no session loss.

### Test B — Android background/return
1. Stay on Admin Dashboard or Dynamic Builder.
2. Put Chrome in the background for 2–5 minutes.
3. Return to Chrome.
Expected: workspace remains open. A silent session recheck may occur; no forced logout.

### Test C — page refresh/navigation restoration
1. Refresh Admin.
2. Refresh Dynamic Builder.
3. Use Android Back/Forward between the two pages.
Expected: brief "Restoring admin session…" is allowed; the login form should appear only when
there is genuinely no session.

### Test D — explicit sign out
1. Use the account menu → Sign out.
Expected: sign-in form appears and the Supabase session is cleared.

Do not promote this patch to RankTiger PROD until all four tests pass in ScoreMore DEV.
