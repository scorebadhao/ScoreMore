# Authentication security gate

This gate adds student password recovery, an 8-character minimum password policy with letters and numbers (12+ recommended), student-only Google OAuth, optional Cloudflare Turnstile, password-change notifications, and opt-in admin TOTP.

## Source behavior

- Email/password remains available for students and admins.
- Google is offered only on the student landing page and only when the active Supabase project reports Google as enabled.
- A verified Google email can link to the existing Supabase user, preserving `auth.uid()` and all owned progress.
- A first-time Google student receives the database default `STUDENT` role and must complete mobile, language, board, and exam setup before using the Student Hub.
- User-editable metadata is never used for the admin role.
- An admin without TOTP behaves as before. Once a verified TOTP factor exists, `public.is_admin()` requires an AAL2 session across existing admin RLS policies and RPCs.
- Password-reset responses are account-neutral, reset links land on the build-owned recovery page, and a successful reset signs out globally.

## Hosted DEV configuration (no secrets in Git)

1. In the ScoreMore DEV Supabase Auth URL settings, retain the ScoreMore DEV Site URL and allow its `student.html` and `reset-password.html` routes. Keep RankTiger production URLs out of this project.
2. In the Email provider settings, set minimum password length to **8** and require **letters and digits**. Do not enable paid leaked-password protection without separate approval.
3. Create a dedicated Google OAuth web client for ScoreMore DEV. Its authorized redirect URI is `https://stejewkuikvqpqotjnnt.supabase.co/auth/v1/callback`. Store the Google client secret only in Supabase Auth provider settings.
4. For Turnstile, put the browser-safe site key in the GitHub secret `VITE_TURNSTILE_SITE_KEY`; put the Turnstile secret only in Supabase CAPTCHA settings. Enable CAPTCHA only after every auth form has deployed with the site key.
5. For Resend SMTP, verify the chosen sending domain, then store the SMTP credential only in Supabase SMTP settings. Copy the reviewed recovery and security-notification templates into the hosted Auth template settings.
6. Enable TOTP challenge/verification in Supabase Auth before enrolling the admin. Keep access to the authenticator app; lost-device recovery requires a Supabase project administrator.

## Production separation

RankTiger PROD needs its own Google OAuth client, Turnstile widget/secret, SMTP configuration, redirect allowlist, and hosted email templates. Configure those only after ScoreMore DEV smoke tests pass and a separate production approval is given.

The implementation itself uses free-capable services. Usage beyond provider free quotas or any Supabase plan upgrade remains a separate, explicit purchase decision.
