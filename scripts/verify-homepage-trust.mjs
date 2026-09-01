import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const sources = {
  index: read('index.html'),
  student: read('student.html'),
  admin: read('admin.html'),
  publicJs: read('assets/js/public.js'),
  studentJs: read('assets/js/student.js'),
  api: read('assets/js/api.js'),
  connection: read('assets/js/connectionState.js'),
  taxonomy: read('assets/js/testTypes.js'),
  homepageMigration: read('supabase/migrations/20260901173216_homepage_test_category_stats.sql'),
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
requireText('publicJs', [
  'bindConnectionBadge',
  'PUBLIC_TEST_CATEGORIES',
  'testTypes: category?.testTypes',
]);
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
requireText('api', [
  "async listTests({ testType = '', testTypes = []",
  "query.in('test_type', normalizedTestTypes)",
]);

requireText('homepageMigration', [
  'create or replace function public.get_public_stats()',
  'and public.test_is_student_ready(t.test_id)',
  "'mock_tests'",
  "'pyq_tests'",
  "'sectional_tests'",
  "'topic_tests'",
  'revoke all on function public.get_public_stats() from public, anon, authenticated;',
  'grant execute on function public.get_public_stats() to anon, authenticated;',
]);
forbidText('homepageMigration', [/student_attempts/i, /from public\.attempts/i]);

forbidText('admin', [/data-admin-view="analytics"/i, /Admin Analytics/i]);
forbidText('api', [/get_admin_analytics_v1/i, /list_admin_test_analytics_v1/i]);

for (const [name, html] of [
  ['index.html', sources.index],
  ['student.html', sources.student],
  ['admin.html', sources.admin],
]) {
  const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]);
  const duplicates = [...new Set(ids.filter((id, index) => ids.indexOf(id) !== index))];
  if (duplicates.length) failures.push(`${name} contains duplicate IDs: ${duplicates.join(', ')}`);
}

if (failures.length) {
  failures.forEach((failure) => console.error(`FAIL: ${failure}`));
  process.exit(1);
}

console.log('PASS: homepage trust, test taxonomy, truthful category counts, and resilient connection status are structurally wired.');
console.log('PASS: migration 27 exposes content-only public counts and Release 1 contains no Admin Analytics v1 surface.');
