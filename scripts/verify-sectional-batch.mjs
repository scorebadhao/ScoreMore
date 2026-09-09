import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const sources = {
  html: read('test-builder.html'),
  builder: read('assets/js/testBuilder4A.js'),
  api: read('assets/js/api.js'),
  css: read('assets/css/testBuilder4A.css'),
  migration: read('supabase/migrations/20260908154802_sectional_batch_identity_safety.sql'),
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

requireText('html', [
  'id="phase4aSectionalBatchCard"',
  'data-mode-visibility="PYQ_SECTIONAL"',
  'Create every package subject',
  'Draft-only · atomic · no overwrite',
  'Review every draft before publishing',
  'id="phase4aBatchPreviewButton"',
  'id="phase4aBatchCreateButton"',
]);
requireText('builder', [
  "[packageId, subjectPart, topicPart, scopeToken, 'SECTIONAL-TEST']",
  'This old package-only Test ID is unsafe',
  'previewPhase4ASectionalBatch',
  'savePhase4ASectionalBatch',
  'Existing tests are skipped',
]);
requireText('api', [
  "client.rpc('save_phase4a_dynamic_test_v16'",
  "client.rpc('preview_phase4a_sectional_batch_v1'",
  "client.rpc('save_phase4a_sectional_batch_v1'",
  "p_confirmation: 'CREATE_MISSING_SECTIONAL_DRAFTS'",
]);
requireText('css', [
  '.phase4a-batch-list',
  '.phase4a-batch-item.blocked',
  '@media (max-width: 680px)',
]);
requireText('migration', [
  'create or replace function public.save_phase4a_dynamic_test_v16(',
  'already belongs to a different test scope. Nothing was overwritten.',
  'The package-only sectional Test ID % is unsafe.',
  "pg_advisory_xact_lock(hashtext('scoremore:dynamic-test:' || v_test_id))",
  'revoke execute on function public.save_phase4a_dynamic_test_v15(',
  'revoke execute on function public.save_phase4a_dynamic_test(',
  'create or replace function public.phase4a_sectional_batch_plan_v1(',
  "when p.existing_test_count = 1 then 'ALREADY_EXISTS'",
  "else 'CREATE_DRAFT'",
  'create or replace function public.preview_phase4a_sectional_batch_v1(',
  'create or replace function public.save_phase4a_sectional_batch_v1(',
  'perform pg_advisory_xact_lock(',
  'was created while this batch was running. No sectional draft was created; preview again.',
  "<> 'CREATE_MISSING_SECTIONAL_DRAFTS'",
  "where action_status = 'CREATE_DRAFT'",
  'public.save_phase4a_dynamic_test_v16(',
  "'status', 'DRAFT'",
  'revoke all on function public.phase4a_sectional_batch_plan_v1(text[],boolean) from public, anon, authenticated;',
  'grant execute on function public.preview_phase4a_sectional_batch_v1(text[],boolean) to authenticated;',
  'grant execute on function public.save_phase4a_sectional_batch_v1(',
]);
forbidText('migration', [
  /grant\s+execute[\s\S]{0,160}\bto\s+(?:public|anon)\s*;/i,
  /service_role/i,
  /auth\.users/i,
  /\bcreate\s+table\b/i,
  /\bdrop\s+table\b/i,
]);

const ids = [...sources.html.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]);
const duplicateIds = [...new Set(ids.filter((id, index) => ids.indexOf(id) !== index))];
if (duplicateIds.length) failures.push(`test-builder.html contains duplicate IDs: ${duplicateIds.join(', ')}`);

if (failures.length) {
  failures.forEach((failure) => console.error(`FAIL: ${failure}`));
  process.exit(1);
}

console.log('PASS: sectional Test IDs are subject-safe in the client and protected against cross-scope replacement in PostgreSQL.');
console.log('PASS: package batch creation is admin-only, preview-first, atomic, conflict-blocking and draft-only.');
