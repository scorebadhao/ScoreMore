import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const root = process.cwd();
const migrationsRoot = path.join(root, 'supabase', 'migrations');
const workflowPath = path.join(root, '.github', 'workflows', 'initialize-ranktiger-prod-db.yml');
const releasePolicyPath = path.join(root, 'ranktiger-release.config.json');
const patch3LockPath = path.join(root, 'docs', 'LOCKED_MIGRATION_CHECKSUMS_PATCH3.json');
const patch52LockPath = path.join(root, 'docs', 'LOCKED_MIGRATION_CHECKSUMS_PATCH5_2.json');
const productionBaselineLockPath = path.join(root, 'docs', 'LOCKED_MIGRATION_CHECKSUMS_RANKTIGER_25.json');
const previousCandidateLockPath = path.join(root, 'docs', 'LOCKED_MIGRATION_CHECKSUMS_RANKTIGER_27.json');
const previousStableLockPath = path.join(root, 'docs', 'LOCKED_MIGRATION_CHECKSUMS_RANKTIGER_30.json');
const previousSectionalLockPath = path.join(root, 'docs', 'LOCKED_MIGRATION_CHECKSUMS_RANKTIGER_31.json');
const expectedActiveLockFile = 'docs/LOCKED_MIGRATION_CHECKSUMS_RANKTIGER_32.json';
const expectedActiveMigrationCount = 32;

const authMigrationName = '20260830010000_student_google_auth_onboarding.sql';
const homepageMigrationName = '20260901173216_homepage_test_category_stats.sql';
const analyticsMigrationName = '20260901173351_admin_analytics_v1.sql';
const analyticsFixMigrationName = '20260902085235_admin_analytics_score_normalization_fix.sql';
const taxonomyMigrationName = '20260907202905_ranktiger_completed_practice_taxonomy_names.sql';
const sectionalBatchMigrationName = '20260908154802_sectional_batch_identity_safety.sql';
const analyticsPerformanceMigrationName = '20260909165335_admin_analytics_statement_timeout_fix.sql';
const prerequisiteName = '20260805000050_catalogue_parent_prerequisites.sql';
const phase3eName = '20260805000100_phase3e_compatibility.sql';
const catalogueMigrationName = '20260811020000_public_catalogue_baseline.sql';

const migrationPath = (name) => path.join(migrationsRoot, name);
const prerequisitePath = migrationPath(prerequisiteName);
const catalogueMigrationPath = migrationPath(catalogueMigrationName);
const taxonomyMigrationPath = migrationPath(taxonomyMigrationName);
const sectionalBatchMigrationPath = migrationPath(sectionalBatchMigrationName);
const analyticsPerformanceMigrationPath = migrationPath(analyticsPerformanceMigrationName);

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function loadJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    fail(`${label} is missing or invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
    return {};
  }
}

function verifyLock(lock, { label, version, count, requireMetadata = true }) {
  const approved = lock?.migrations ?? {};
  if (version && lock.lock_version !== version) fail(`${label} lock version must be ${version}.`);
  if ((requireMetadata && lock.migration_count !== count) || Object.keys(approved).length !== count) {
    fail(`${label} must contain exactly ${count} migration checksums.`);
  }
  for (const [name, expected] of Object.entries(approved)) {
    const filePath = migrationPath(name);
    if (!fs.existsSync(filePath)) {
      fail(`${label} migration is missing: ${name}`);
      continue;
    }
    if (!/^[0-9a-f]{64}$/.test(expected) || sha256(filePath) !== expected) {
      fail(`${label} migration checksum mismatch: ${name}`);
    }
  }
  return approved;
}

for (const required of [
  workflowPath,
  releasePolicyPath,
  patch3LockPath,
  patch52LockPath,
  productionBaselineLockPath,
  previousCandidateLockPath,
  previousStableLockPath,
  previousSectionalLockPath,
  prerequisitePath,
  catalogueMigrationPath,
  taxonomyMigrationPath,
  sectionalBatchMigrationPath,
  analyticsPerformanceMigrationPath,
]) {
  if (!fs.existsSync(required)) fail(`Missing required RankTiger promotion-safety file: ${path.relative(root, required)}`);
}
if (process.exitCode) process.exit();

const releasePolicy = loadJson(releasePolicyPath, 'RankTiger release policy');
if (releasePolicy.requiredMigrationLockFile !== expectedActiveLockFile) {
  fail(`RankTiger release policy must use ${expectedActiveLockFile}.`);
}
if (releasePolicy.requiredMigrationCount !== expectedActiveMigrationCount) {
  fail(`RankTiger release policy must require exactly ${expectedActiveMigrationCount} migrations.`);
}
if (releasePolicy.firstCandidateVersion !== '1.2.1-rc.2') {
  fail('RankTiger release policy must resume the 1.2.1 candidate line at 1.2.1-rc.2.');
}

const activeLockPath = path.join(root, releasePolicy.requiredMigrationLockFile || '');
if (!fs.existsSync(activeLockPath)) fail(`Missing active RankTiger migration lock: ${releasePolicy.requiredMigrationLockFile}`);
if (process.exitCode) process.exit();

const workflow = fs.readFileSync(workflowPath, 'utf8');
const prerequisite = fs.readFileSync(prerequisitePath, 'utf8');
const catalogue = fs.readFileSync(catalogueMigrationPath, 'utf8');
const taxonomy = fs.readFileSync(taxonomyMigrationPath, 'utf8');
const sectionalBatch = fs.readFileSync(sectionalBatchMigrationPath, 'utf8');
const analyticsPerformance = fs.readFileSync(analyticsPerformanceMigrationPath, 'utf8');
const patch3Locked = loadJson(patch3LockPath, 'Patch 3 lock');
const patch52Locked = loadJson(patch52LockPath, 'Patch 5.2 lock');
const productionBaselineLocked = loadJson(productionBaselineLockPath, 'RankTiger 25 production lock');
const previousCandidateLocked = loadJson(previousCandidateLockPath, 'RankTiger 27 candidate lock');
const previousStableLocked = loadJson(previousStableLockPath, 'RankTiger 30 stable lock');
const previousSectionalLocked = loadJson(previousSectionalLockPath, 'RankTiger 31 sectional lock');
const activeLocked = loadJson(activeLockPath, 'RankTiger 32 active lock');

const requiredWorkflowFragments = [
  'INITIALIZE_RANKTIGER_PROD',
  'RANKTIGER_SUPABASE_PROJECT_ID',
  'RANKTIGER_SUPABASE_DB_PASSWORD',
  'RANKTIGER_SUPABASE_URL',
  'RANKTIGER_SUPABASE_PUBLISHABLE_KEY',
  'SUPABASE_ACCESS_TOKEN',
  'supabase db push --dry-run --include-all',
  'supabase db push --yes --include-all',
  'supabase migration list --linked | tee /tmp/ranktiger-migrations-before.txt',
  'supabase migration list --linked | tee /tmp/ranktiger-migrations-after.txt',
  'ranktiger-release.config.json',
  'requiredMigrationLockFile',
  "line.split(/[|│]/)[1]?.match(/\\d{14}/)?.[0]",
  'Unapproved remote migration versions detected before deploy',
  'Missing remote migration versions after deploy',
  'Unapproved remote migration versions detected after deploy',
  'verify-ranktiger-prod-database-init.mjs',
  'all 32 locked migrations',
  'Locked migrations verified: 32',
];
for (const fragment of requiredWorkflowFragments) {
  if (!workflow.includes(fragment)) fail(`RankTiger workflow is missing required safety/apply fragment: ${fragment}`);
}

const forbiddenWorkflowPatterns = [
  /--include-seed/i,
  /supabase\s+db\s+reset/i,
  /supabase\s+migration\s+(repair|down)/i,
  /git\s+push/i,
  /wrangler|cloudflare\/pages-action/i,
  /RANKTIGER_SUPABASE_SECRET/i,
  /SERVICE_ROLE/i,
  /sb_secret_/i,
];
for (const pattern of forbiddenWorkflowPatterns) {
  if (pattern.test(workflow)) fail(`RankTiger workflow contains forbidden operation/pattern: ${pattern}`);
}

for (const secret of [
  'secrets.SUPABASE_DB_PASSWORD',
  'secrets.SUPABASE_PROJECT_ID',
  'secrets.VITE_SUPABASE_URL',
  'secrets.VITE_SUPABASE_PUBLISHABLE_KEY',
]) {
  if (workflow.includes(secret)) fail(`RankTiger workflow must not reference ScoreMore DEV secret: ${secret}`);
}

const patch3Approved = verifyLock(patch3Locked, { label: 'Patch 3 historical lock', version: null, count: 18, requireMetadata: false });
const patch52Approved = verifyLock(patch52Locked, { label: 'Patch 5.2 historical lock', version: 'PATCH5_2', count: 20 });
const productionBaselineApproved = verifyLock(productionBaselineLocked, { label: 'RankTiger 1.1.0 production baseline', version: 'RANKTIGER_25', count: 25 });
const previousCandidateApproved = verifyLock(previousCandidateLocked, { label: 'RankTiger 27 candidate baseline', version: 'RANKTIGER_27', count: 27 });
const previousStableApproved = verifyLock(previousStableLocked, { label: 'RankTiger 1.2.0 stable baseline', version: 'RANKTIGER_30', count: 30 });
const previousSectionalApproved = verifyLock(previousSectionalLocked, { label: 'RankTiger 31 sectional baseline', version: 'RANKTIGER_31', count: 31 });
const approved = verifyLock(activeLocked, { label: 'RankTiger 1.2.1 active lock', version: 'RANKTIGER_32', count: expectedActiveMigrationCount });

for (const [name, expected] of Object.entries(patch3Approved)) {
  if (patch52Approved[name] !== expected) fail(`Patch 5.2 lock does not preserve Patch 3 checksum: ${name}`);
}
for (const [name, expected] of Object.entries(patch52Approved)) {
  if (productionBaselineApproved[name] !== expected) fail(`RankTiger 25 lock does not preserve Patch 5.2 checksum: ${name}`);
}
for (const [name, expected] of Object.entries(productionBaselineApproved)) {
  if (approved[name] !== expected) fail(`RankTiger 32 lock does not preserve production baseline checksum: ${name}`);
}
for (const [name, expected] of Object.entries(previousCandidateApproved)) {
  if (approved[name] !== expected) fail(`RankTiger 32 lock does not preserve candidate-27 checksum: ${name}`);
}
for (const [name, expected] of Object.entries(previousStableApproved)) {
  if (approved[name] !== expected) fail(`RankTiger 32 lock does not preserve the RankTiger 1.2.0 stable checksum: ${name}`);
}
for (const [name, expected] of Object.entries(previousSectionalApproved)) {
  if (approved[name] !== expected) fail(`RankTiger 32 lock does not preserve the RankTiger 31 sectional checksum: ${name}`);
}

const approvedNames = Object.keys(approved).sort();
const sourceMigrationNames = fs.readdirSync(migrationsRoot)
  .filter((name) => name.endsWith('.sql'))
  .sort();
if (JSON.stringify(approvedNames) !== JSON.stringify(sourceMigrationNames)) {
  fail('Source migration files do not exactly match the active RankTiger 32 migration lock.');
}

const expectedAfterPatch52 = [
  '20260814010000_draft_first_image_content_repair_workflow.sql',
  '20260816010000_phase4a_safety_efficiency_v1.sql',
  '20260817010000_phase4a_facet_performance_fix.sql',
  '20260825010000_content_repair_integrity_gate.sql',
  '20260826212517_admin_task_inbox_published_image_queue.sql',
  authMigrationName,
  homepageMigrationName,
  analyticsMigrationName,
  analyticsFixMigrationName,
  taxonomyMigrationName,
  sectionalBatchMigrationName,
  analyticsPerformanceMigrationName,
];
const additionsAfterPatch52 = approvedNames.filter((name) => !(name in patch52Approved));
if (JSON.stringify(additionsAfterPatch52) !== JSON.stringify(expectedAfterPatch52)) {
  fail(`RankTiger 32 lock must add exactly the twelve reviewed migrations after Patch 5.2; found: ${additionsAfterPatch52.join(', ')}`);
}

const expectedAfterProduction = [
  authMigrationName,
  homepageMigrationName,
  analyticsMigrationName,
  analyticsFixMigrationName,
  taxonomyMigrationName,
  sectionalBatchMigrationName,
  analyticsPerformanceMigrationName,
];
const additionsAfterProduction = approvedNames.filter((name) => !(name in productionBaselineApproved));
if (JSON.stringify(additionsAfterProduction) !== JSON.stringify(expectedAfterProduction)) {
  fail(`RankTiger 32 lock must add exactly migrations 26–32 after the immutable production baseline; found: ${additionsAfterProduction.join(', ')}`);
}

const expectedAfterCandidate27 = [analyticsMigrationName, analyticsFixMigrationName, taxonomyMigrationName, sectionalBatchMigrationName, analyticsPerformanceMigrationName];
const additionsAfterCandidate27 = approvedNames.filter((name) => !(name in previousCandidateApproved));
if (JSON.stringify(additionsAfterCandidate27) !== JSON.stringify(expectedAfterCandidate27)) {
  fail(`RankTiger 32 lock must add only Analytics v1, its two fixes, taxonomy correction and sectional identity safety after candidate 27; found: ${additionsAfterCandidate27.join(', ')}`);
}

const additionsAfterStable = approvedNames.filter((name) => !(name in previousStableApproved));
if (JSON.stringify(additionsAfterStable) !== JSON.stringify([sectionalBatchMigrationName, analyticsPerformanceMigrationName])) {
  fail(`RankTiger 32 lock must add only the sectional identity/batch and Analytics performance migrations after the immutable RankTiger 1.2.0 stable baseline; found: ${additionsAfterStable.join(', ')}`);
}

const additionsAfterSectional = approvedNames.filter((name) => !(name in previousSectionalApproved));
if (JSON.stringify(additionsAfterSectional) !== JSON.stringify([analyticsPerformanceMigrationName])) {
  fail(`RankTiger 32 lock must add only the Analytics performance migration after the immutable RankTiger 31 baseline; found: ${additionsAfterSectional.join(', ')}`);
}

const orderedNames = approvedNames;
const prereqIndex = orderedNames.indexOf(prerequisiteName);
const phase3eIndex = orderedNames.indexOf(phase3eName);
if (prereqIndex < 0 || phase3eIndex < 0 || prereqIndex + 1 !== phase3eIndex) {
  fail('Catalogue prerequisite migration must sort immediately before 20260805000100_phase3e_compatibility.sql.');
}

const prerequisiteAllowedTables = new Set(['boards', 'exams', 'subjects']);
const prereqTargets = [...prerequisite.matchAll(/insert\s+into\s+(?:public\.)?([a-zA-Z0-9_]+)/gi)].map((match) => match[1].toLowerCase());
if (!prereqTargets.length) fail('Catalogue prerequisite migration contains no INSERT targets.');
for (const target of new Set(prereqTargets)) {
  if (!prerequisiteAllowedTables.has(target)) fail(`Catalogue prerequisite writes to non-approved table: ${target}`);
}
for (const requiredSubject of ['REASONING', 'QUANTITATIVE_APTITUDE', 'ENGLISH', 'GUJARATI']) {
  if (!prerequisite.includes(`'${requiredSubject}'`)) fail(`Catalogue prerequisite is missing required subject: ${requiredSubject}`);
}
for (const pattern of [
  /insert\s+into\s+(?:public\.)?(topics|app_settings|profiles|questions|draft_questions|tests|attempts|attempt_answers|payments|package_access|admin_audit_logs)\b/i,
  /auth\.users/i,
  /service_role/i,
  /sb_secret_/i,
]) {
  if (pattern.test(prerequisite)) fail(`Catalogue prerequisite contains forbidden pattern: ${pattern}`);
}

const approvedCatalogueTables = new Set(['boards', 'exams', 'subjects', 'topics', 'app_settings']);
const insertTargets = [...catalogue.matchAll(/insert\s+into\s+(?:public\.)?([a-zA-Z0-9_]+)/gi)].map((match) => match[1].toLowerCase());
if (!insertTargets.length) fail('Public catalogue migration contains no INSERT targets.');
for (const target of new Set(insertTargets)) {
  if (!approvedCatalogueTables.has(target)) fail(`Public catalogue migration writes to non-approved table: ${target}`);
}
for (const pattern of [
  /['"]app_name['"]/i,
  /['"]app_mark['"]/i,
  /['"]app_environment['"]/i,
  /insert\s+into\s+(?:public\.)?(profiles|questions|draft_questions|tests|attempts|attempt_answers|payments|package_access|admin_audit_logs)\b/i,
  /auth\.users/i,
  /service_role/i,
  /sb_secret_/i,
]) {
  if (pattern.test(catalogue)) fail(`Public catalogue migration contains forbidden identity/test/user pattern: ${pattern}`);
}

const taxonomyIds = [
  'GSSSB-CCE-2024-1705-S3-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
  'GSSSB-CCE-2024-2005-S1-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
  'GSSSB-CCE-2024-2005-S2-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
  'GSSSB-CCE-2024-2005-S3-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
  'GSSSB-CCE-2024-2005-S4-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
];
const correctedNames = [
  'CCE 2024 Completed Practice Test - 17 May Shift 3',
  'CCE 2024 Completed Practice Test - 20 May Shift 1',
  'CCE 2024 Completed Practice Test - 20 May Shift 2',
  'CCE 2024 Completed Practice Test - 20 May Shift 3',
  'CCE 2024 Completed Practice Test - 20 May Shift 4',
];
for (const id of taxonomyIds) {
  const occurrences = taxonomy.split(id).length - 1;
  if (occurrences < 3) fail(`Taxonomy migration does not fully guard and verify exact test ID: ${id}`);
}
for (const correctedName of correctedNames) {
  if (!taxonomy.includes(`'${correctedName}'`)) fail(`Taxonomy migration is missing approved test name: ${correctedName}`);
}
for (const fragment of [
  "set local lock_timeout = '5s'",
  "set local statement_timeout = '30s'",
  "t.test_type <> 'FULL_MOCK'",
  "t.test_type = 'FULL_MOCK'",
  't.test_name is distinct from v.corrected_name',
  "upper(t.test_name) like '%PYQ%'",
  "using errcode = 'P0001'",
]) {
  if (!taxonomy.includes(fragment)) fail(`Taxonomy migration is missing required safety fragment: ${fragment}`);
}
const taxonomyUpdateTargets = [...taxonomy.matchAll(/\bupdate\s+(?:public\.)?([a-z_][a-z0-9_]*)/gi)].map((match) => match[1].toLowerCase());
if (!taxonomyUpdateTargets.length || taxonomyUpdateTargets.some((target) => target !== 'tests')) {
  fail(`Taxonomy migration may update only public.tests; found: ${taxonomyUpdateTargets.join(', ') || 'none'}`);
}
for (const pattern of [
  /\bdelete\s+from\b/i,
  /\btruncate\b/i,
  /\bdrop\s+(?:table|function|schema|type)\b/i,
  /\balter\s+table\b/i,
  /\binsert\s+into\b/i,
  /auth\.users/i,
  /service_role/i,
  /sb_secret_/i,
]) {
  if (pattern.test(taxonomy)) fail(`Taxonomy migration contains forbidden operation/pattern: ${pattern}`);
}

for (const fragment of [
  'create or replace function public.save_phase4a_dynamic_test_v16(',
  'already belongs to a different test scope. Nothing was overwritten.',
  'The package-only sectional Test ID % is unsafe.',
  "pg_advisory_xact_lock(hashtext('scoremore:dynamic-test:' || v_test_id))",
  'revoke execute on function public.save_phase4a_dynamic_test_v15(',
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
  'revoke all on function public.phase4a_sectional_batch_plan_v1(text[],boolean) from public, anon, authenticated;',
  'grant execute on function public.preview_phase4a_sectional_batch_v1(text[],boolean) to authenticated;',
]) {
  if (!sectionalBatch.includes(fragment)) fail(`Sectional identity/batch migration is missing required safety fragment: ${fragment}`);
}
if ((sectionalBatch.match(/if not public\.is_admin\(\)/g) || []).length < 4) {
  fail('Sectional identity/batch migration must enforce admin authorization in every client-callable or privileged planning function.');
}
for (const pattern of [
  /\bdelete\s+from\b/i,
  /\btruncate\b/i,
  /\bdrop\s+(?:table|function|schema|type)\b/i,
  /\balter\s+table\b/i,
  /\bcreate\s+table\b/i,
  /insert\s+into\s+(?:public\.)?(profiles|questions|draft_questions|attempts|attempt_answers|payments|package_access)\b/i,
  /auth\.users/i,
  /service_role/i,
  /sb_secret_/i,
]) {
  if (pattern.test(sectionalBatch)) fail(`Sectional identity/batch migration contains forbidden operation/pattern: ${pattern}`);
}

for (const fragment of [
  "set local lock_timeout = '5s'",
  "set local statement_timeout = '30s'",
  'create or replace function public.test_is_student_ready(p_test_id text)',
  "when jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) = 0 then true",
  'else public.question_is_student_ready(q.question_id)',
  'create or replace function public.get_admin_analytics_v1(',
  'create or replace function public.list_admin_test_analytics_v1(',
  'scoped_tests_base as materialized',
  'fixed_link_stats as materialized',
  'public.test_is_student_ready(t.test_id) as student_ready',
  'security invoker',
  'not public.is_admin()',
  'revoke all on function public.get_admin_analytics_v1',
  'grant execute on function public.get_admin_analytics_v1',
]) {
  if (!analyticsPerformance.includes(fragment)) fail(`Analytics performance migration is missing required safety fragment: ${fragment}`);
}
if ((analyticsPerformance.match(/security\s+invoker/gi) || []).length < 2) {
  fail('Analytics performance migration must keep both browser-facing analytics RPCs SECURITY INVOKER.');
}
for (const pattern of [
  /\bdelete\s+from\b/i,
  /\btruncate\b/i,
  /\bdrop\s+(?:table|function|schema|type)\b/i,
  /\balter\s+table\b/i,
  /\bcreate\s+table\b/i,
  /\binsert\s+into\b/i,
  /public\.attempt_answers/i,
  /correct_answer/i,
  /selected_answer/i,
  /auth\.users/i,
  /service_role/i,
  /sb_secret_/i,
]) {
  if (pattern.test(analyticsPerformance)) fail(`Analytics performance migration contains forbidden operation/pattern: ${pattern}`);
}

if (process.exitCode) process.exit();
console.log('PASS: RankTiger PROD database initialization is migration-only; production seed execution is forbidden.');
console.log('PASS: Remote migration history must be an approved subset before write and exactly match after write.');
console.log('PASS: 18-migration Patch 3 and 20-migration Patch 5.2 historical locks remain immutable.');
console.log('PASS: immutable 25-migration RankTiger 1.1.0 production baseline is preserved exactly.');
console.log('PASS: immutable 27-migration candidate baseline is preserved exactly.');
console.log('PASS: immutable 30-migration RankTiger 1.2.0 stable baseline is preserved exactly.');
console.log('PASS: immutable 31-migration sectional baseline is preserved exactly.');
console.log('PASS: 32 approved migrations exactly match the source set and are checksum-locked for RankTiger 1.2.1.');
console.log(`PASS: reviewed migrations after production baseline: ${additionsAfterProduction.join(', ')}`);
console.log(`PASS: reviewed additions after candidate 27: ${additionsAfterCandidate27.join(', ')}`);
console.log(`PASS: reviewed additions after stable 1.2.0: ${additionsAfterStable.join(', ')}`);
console.log(`PASS: reviewed additions after sectional baseline: ${additionsAfterSectional.join(', ')}`);
console.log('PASS: completed-practice taxonomy correction is exact-ID, FULL_MOCK-guarded, bounded, and self-verifying.');
console.log('PASS: sectional batch is admin-only, conflict-blocking, atomic, draft-only and preserves existing tests.');
console.log('PASS: Analytics performance fix preserves RLS, answer secrecy and the existing readiness result while removing repeated scans.');
console.log(`PASS: prerequisite targets only: ${[...new Set(prereqTargets)].sort().join(', ')}`);
console.log(`PASS: versioned catalogue baseline targets only: ${[...new Set(insertTargets)].sort().join(', ')}`);
