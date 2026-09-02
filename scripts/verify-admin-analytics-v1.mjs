import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const sources = {
  index: read('index.html'),
  student: read('student.html'),
  publicJs: read('assets/js/public.js'),
  studentJs: read('assets/js/student.js'),
  api: read('assets/js/api.js'),
  adminHtml: read('admin.html'),
  adminJs: read('assets/js/admin.js'),
  connection: read('assets/js/connectionState.js'),
  taxonomy: read('assets/js/testTypes.js'),
  homepageMigration: read('supabase/migrations/20260901173216_homepage_test_category_stats.sql'),
  analyticsMigration: read('supabase/migrations/20260901173351_admin_analytics_v1.sql'),
};

const failures = [];
function requireText(sourceName, fragments) {
  for (const fragment of fragments) {
    if (!sources[sourceName].includes(fragment)) failures.push(`${sourceName} is missing: ${fragment}`);
  }
}
function forbidText(sourceName, patterns) {
  for (const pattern of patterns) {
    if (pattern.test(sources[sourceName])) failures.push(`${sourceName} contains forbidden text: ${pattern}`);
  }
}

requireText('index', [
  'Mock Tests',
  'PYQ Tests',
  'Sectional Tests',
  'Topic Tests',
  'Explore verified PYQ, mock, sectional and topic-wise tests for your target exam.',
  'Sign in to start free tests, save your progress and review your results.',
]);
forbidText('index', [
  /Catalogue information is loaded live/i,
  /Premium access remains reserved/i,
  /Published questions/i,
  /Student attempts/i,
]);

requireText('connection', [
  "full: 'Good Luck, Student!'",
  "full: 'Offline'",
  'navigator.onLine',
  "window.addEventListener('online'",
  "window.addEventListener('offline'",
  "method: 'HEAD'",
  "cache: 'no-store'",
  'AbortController',
]);
requireText('publicJs', ['bindConnectionBadge', 'PUBLIC_TEST_CATEGORIES', 'testTypes: category?.testTypes']);
requireText('studentJs', [
  'bindConnectionBadge',
  'responses are saved on this device',
  'Saved answers will synchronize automatically',
]);
requireText('taxonomy', [
  "PYQ_FULL: Object.freeze({ label: 'PYQ Test'",
  "FULL_MOCK: Object.freeze({ label: 'Mock Test'",
  "SECTIONAL_MOCK: Object.freeze({ label: 'Sectional Test'",
  "TOPIC_PRACTICE: Object.freeze({ label: 'Topic Test'",
]);

requireText('homepageMigration', [
  'create or replace function public.get_public_stats()',
  "and public.test_is_student_ready(t.test_id)",
  "'mock_tests'",
  "'pyq_tests'",
  "'sectional_tests'",
  "'topic_tests'",
  'revoke all on function public.get_public_stats() from public, anon, authenticated;',
  'grant execute on function public.get_public_stats() to anon, authenticated;',
]);
forbidText('homepageMigration', [/student_attempts/i, /from public\.attempts/i]);

requireText('adminHtml', [
  'data-admin-view="analytics"',
  'data-analytics-tab="overview"',
  'data-analytics-tab="students"',
  'data-analytics-tab="tests"',
  'data-analytics-tab="content"',
  'Asia/Kolkata',
  'No student contact details or raw answers are included.',
  'data-content-health="taxonomy_review"',
]);
requireText('adminJs', [
  'loadAdminAnalytics',
  'getAdminAnalyticsV1',
  'listAdminTestAnalyticsV1',
  'ADMIN_ANALYTICS_PAGE_SIZE',
]);
requireText('api', [
  "client.rpc('get_admin_analytics_v1'",
  "client.rpc('list_admin_test_analytics_v1'",
]);
requireText('analyticsMigration', [
  'create or replace function public.get_admin_analytics_v1(',
  'create or replace function public.list_admin_test_analytics_v1(',
  'security invoker',
  'not public.is_admin()',
  'Analytics ranges cannot exceed 366 days.',
  'attempts_analytics_started_idx',
  'attempts_analytics_repeat_idx',
  'profiles_active_student_created_idx',
  'end as score_percentage',
  "round(avg(score_percentage), 2)",
  'a.total_questions * t.marks_per_question',
  "'taxonomy_review'",
  'revoke all on function public.get_admin_analytics_v1',
  'grant execute on function public.get_admin_analytics_v1',
]);
forbidText('analyticsMigration', [
  /security\s+definer/i,
  /public\.attempt_answers/i,
  /correct_answer/i,
  /selected_answer/i,
  /['"](?:email|mobile|user_id)['"]/i,
  /auth\.users/i,
  /service_role/i,
]);

for (const [name, html] of [['index.html', sources.index], ['student.html', sources.student], ['admin.html', sources.adminHtml]]) {
  const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]);
  const duplicates = [...new Set(ids.filter((id, index) => ids.indexOf(id) !== index))];
  if (duplicates.length) failures.push(`${name} contains duplicate IDs: ${duplicates.join(', ')}`);
}

if (failures.length) {
  failures.forEach((failure) => console.error(`FAIL: ${failure}`));
  process.exit(1);
}

console.log('PASS: homepage trust/taxonomy, resilient connection status, and admin-only aggregate Analytics v1 are structurally wired.');
console.log('PASS: public stats exclude student activity; analytics RPCs preserve RLS with SECURITY INVOKER and return no PII/answer data.');
