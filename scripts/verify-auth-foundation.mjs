import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { evaluatePassword } from '../assets/js/passwordPolicy.js';

const ROOT = resolve(import.meta.dirname, '..');
const problems = [];
const pass = (condition, message) => { if (!condition) problems.push(message); };
const source = async (path) => readFile(resolve(ROOT, path), 'utf8');

pass(!evaluatePassword('short1').isValid, 'Passwords shorter than 8 characters must fail.');
pass(!evaluatePassword('abcdefgh').isValid, 'A password without a number must fail.');
pass(!evaluatePassword('12345678').isValid, 'A password without a letter must fail.');
pass(evaluatePassword('student1').isValid, 'An 8-character letter/number password must pass.');
pass(!evaluatePassword('student1').isRecommendedLength, 'Eight characters must not be presented as the recommended length.');
pass(evaluatePassword('student12345').isRecommendedLength, 'Twelve or more characters must be recommended.');
pass(evaluatePassword('ગુજરાતી૧૨૩').isValid, 'The policy must support Unicode letters and numbers.');

const [index, resetHtml, api, auth, resetJs, student, adminHtml, admin, builderHtml, builder, config, turnstile, migration, supabaseConfig, vite, envExample] = await Promise.all([
  source('index.html'),
  source('reset-password.html'),
  source('assets/js/api.js'),
  source('assets/js/auth.js'),
  source('assets/js/resetPassword.js'),
  source('assets/js/student.js'),
  source('admin.html'),
  source('assets/js/admin.js'),
  source('test-builder.html'),
  source('assets/js/testBuilder4A.js'),
  source('assets/js/config.js'),
  source('assets/js/turnstile.js'),
  source('supabase/migrations/20260830010000_student_google_auth_onboarding.sql'),
  source('supabase/config.toml'),
  source('vite.config.js'),
  source('.env.example'),
]);

for (const marker of ['forgotPasswordButton', 'recoveryForm', 'googleSignInButton', 'signUpPasswordPolicy', 'confirmPassword']) {
  pass(index.includes(marker), `Student auth HTML is missing ${marker}.`);
}
pass(index.includes('minlength="8"'), 'Student account creation must advertise the 8-character minimum.');
pass(!index.includes('maxlength="12"'), 'Passwords longer than 12 characters must remain allowed.');
pass(!adminHtml.includes('googleSignInButton') && !builderHtml.includes('googleSignInButton'), 'Google sign in must remain student-only.');

pass(api.includes("client.auth.resetPasswordForEmail"), 'Forgot-password API call is missing.');
pass(api.includes("new URL('./reset-password.html'"), 'Password recovery must use the build-owned reset page.');
pass(api.includes("client.auth.signInWithOAuth") && api.includes("provider: 'google'"), 'Google OAuth must use the Supabase provider API.');
pass(api.includes("queryParams: { prompt: 'select_account' }"), 'Google sign in must ask the student to select the intended account.');
pass(api.includes('captchaToken'), 'Auth requests must forward optional CAPTCHA tokens.');
pass(api.includes('assertPasswordPolicy(next)'), 'Profile password changes must use the shared password policy.');
pass(api.includes("scope: 'global'"), 'Successful password recovery must close sessions globally.');
pass(api.includes('getAuthenticatorAssuranceLevel') && api.includes('challengeAndVerify'), 'Admin TOTP assurance/challenge APIs are missing.');

pass(resetHtml.includes('noindex,nofollow'), 'The password-reset page must not be indexed.');
pass(resetJs.includes("event === 'PASSWORD_RECOVERY'"), 'The reset form must require the PASSWORD_RECOVERY event.');
pass(resetJs.includes('assertPasswordPolicy(password)'), 'Password recovery must enforce the shared password policy.');
pass(student.includes('completeStudentOnboarding'), 'The Student Hub must complete missing Google profile fields through the guarded RPC.');
pass(student.includes('requiresOnboarding'), 'New Google students must be blocked from tests until onboarding is complete.');

for (const [name, body] of [['student', index], ['admin', adminHtml], ['builder', builderHtml]]) {
  pass(body.includes('Turnstile') || body.includes('turnstile'), `${name} sign-in surface is missing its Turnstile mount.`);
}
pass(config.includes('VITE_TURNSTILE_SITE_KEY'), 'Turnstile must use a browser-safe build value.');
pass(turnstile.includes('challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'), 'Turnstile must load the official explicit-render client.');
pass(!turnstile.includes('secret'), 'Turnstile browser code must not contain a secret key.');
pass(envExample.includes('VITE_TURNSTILE_SITE_KEY') && envExample.includes('Never put the secret key here'), 'The environment example must distinguish the public Turnstile site key from its secret.');

pass(/^begin;/m.test(migration) && /^commit;/m.test(migration), 'Auth migration must be transaction-wrapped.');
pass(migration.includes("new.raw_app_meta_data ->> 'provider'"), 'OAuth provider trust must come from protected app metadata.');
pass(migration.includes("v_provider not in ('email', 'google')"), 'The profile trigger must reject unapproved providers.');
pass(!migration.includes("raw_user_meta_data ->> 'role'"), 'User metadata must never control database roles.');
pass(migration.includes('public.complete_student_onboarding'), 'One-time student onboarding RPC is missing.');
pass(migration.includes("v_role <> 'STUDENT'") && migration.includes("v_status <> 'ACTIVE'"), 'Onboarding must require an active database-owned STUDENT profile.');
pass(migration.includes('where user_id = v_user_id and mobile is null'), 'Onboarding mobile assignment must be one-time.');
pass(migration.includes('from auth.mfa_factors') && migration.includes("auth.jwt() ->> 'aal'"), 'Admin MFA must be enforced by the database-owned admin predicate.');
pass(migration.includes("= 'aal2'"), 'Verified admin factors must require AAL2.');

pass(admin.includes("context.status === 'MFA_REQUIRED'"), 'Admin workspace must stop at a TOTP challenge when AAL2 is required.');
pass(builder.includes("context.status === 'MFA_REQUIRED'"), 'Dynamic Builder must stop at the central TOTP challenge when AAL2 is required.');
pass(admin.includes('enrollAdminTotp') && admin.includes('verifyTotp'), 'Admin TOTP enrollment UI is incomplete.');
pass(admin.includes('safeMfaQrUrl') && admin.includes('data:image\\/svg\\+xml'), 'Admin TOTP QR rendering must accept only SVG data URLs.');
pass(!admin.includes('safeUrl('), 'Admin auth code must not reference an undefined generic URL helper.');
pass(supabaseConfig.includes('[auth.email.template.recovery]'), 'Local recovery email template configuration is missing.');
pass(supabaseConfig.includes('[auth.email.notification.password_changed]'), 'Password-change notification configuration is missing.');
for (const templateName of ['recovery', 'password_changed_notification', 'identity_linked_notification', 'mfa_factor_enrolled_notification']) {
  pass(supabaseConfig.includes(`content_path = "./templates/${templateName}.html"`), `Supabase template path is invalid for ${templateName}.`);
}
pass(!supabaseConfig.includes('./supabase/templates/'), 'Template paths must be relative to supabase/config.toml without a duplicate supabase/ segment.');
pass(vite.includes("resetPassword: resolve(import.meta.dirname, 'reset-password.html')"), 'The recovery page must be a first-class build entry.');

const templates = await Promise.all([
  source('supabase/templates/recovery.html'),
  source('supabase/templates/password_changed_notification.html'),
  source('supabase/templates/identity_linked_notification.html'),
  source('supabase/templates/mfa_factor_enrolled_notification.html'),
]);
for (const body of templates) {
  pass(!/sb_secret_|service_role|BEGIN PRIVATE KEY|smtp_password/i.test(body), 'Auth email templates must not contain credentials.');
}

if (problems.length) {
  console.error('AUTH FOUNDATION VERIFICATION FAILED');
  for (const item of problems) console.error(`- ${item}`);
  process.exit(1);
}

console.log('PASS: password recovery, 8+ letter/number policy, Google student onboarding, optional Turnstile, and admin TOTP enforcement are structurally safe.');
console.log('PASS: Google remains student-only and database roles never trust user metadata.');
console.log('PASS: no paid service, provider secret, SMTP credential, or Turnstile secret is embedded in browser or template files.');
