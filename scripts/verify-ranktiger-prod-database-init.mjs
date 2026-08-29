import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const root = process.cwd();
const workflowPath = path.join(root, '.github', 'workflows', 'initialize-ranktiger-prod-db.yml');
const releasePolicyPath = path.join(root, 'ranktiger-release.config.json');
const patch3LockPath = path.join(root, 'docs', 'LOCKED_MIGRATION_CHECKSUMS_PATCH3.json');
const patch52LockPath = path.join(root, 'docs', 'LOCKED_MIGRATION_CHECKSUMS_PATCH5_2.json');
const expectedActiveLockFile = 'docs/LOCKED_MIGRATION_CHECKSUMS_RANKTIGER_25.json';
const expectedActiveMigrationCount = 25;
const prerequisiteName = '20260805000050_catalogue_parent_prerequisites.sql';
const prerequisitePath = path.join(root, 'supabase', 'migrations', prerequisiteName);
const phase3eName = '20260805000100_phase3e_compatibility.sql';
const catalogueMigrationName = '20260811020000_public_catalogue_baseline.sql';
const catalogueMigrationPath = path.join(root, 'supabase', 'migrations', catalogueMigrationName);

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

for (const required of [workflowPath, releasePolicyPath, patch3LockPath, patch52LockPath, prerequisitePath, catalogueMigrationPath]) {
  if (!fs.existsSync(required)) fail(`Missing required RankTiger promotion-safety file: ${path.relative(root, required)}`);
}
if (process.exitCode) process.exit();

const releasePolicy = JSON.parse(fs.readFileSync(releasePolicyPath, 'utf8'));
if (releasePolicy.requiredMigrationLockFile !== expectedActiveLockFile) {
  fail(`RankTiger release policy must use ${expectedActiveLockFile}.`);
}
if (releasePolicy.requiredMigrationCount !== expectedActiveMigrationCount) {
  fail(`RankTiger release policy must require exactly ${expectedActiveMigrationCount} migrations.`);
}
const activeLockPath = path.join(root, releasePolicy.requiredMigrationLockFile);
if (!fs.existsSync(activeLockPath)) fail(`Missing active RankTiger migration lock: ${releasePolicy.requiredMigrationLockFile}`);
if (process.exitCode) process.exit();

const workflow = fs.readFileSync(workflowPath, 'utf8');
const prerequisite = fs.readFileSync(prerequisitePath, 'utf8');
const catalogue = fs.readFileSync(catalogueMigrationPath, 'utf8');
const patch3Locked = JSON.parse(fs.readFileSync(patch3LockPath, 'utf8'));
const patch52Locked = JSON.parse(fs.readFileSync(patch52LockPath, 'utf8'));
const activeLocked = JSON.parse(fs.readFileSync(activeLockPath, 'utf8'));

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

const forbiddenDevSecrets = [
  'secrets.SUPABASE_DB_PASSWORD',
  'secrets.SUPABASE_PROJECT_ID',
  'secrets.VITE_SUPABASE_URL',
  'secrets.VITE_SUPABASE_PUBLISHABLE_KEY',
];
for (const secret of forbiddenDevSecrets) {
  if (workflow.includes(secret)) fail(`RankTiger workflow must not reference ScoreMore DEV secret: ${secret}`);
}

// Patch 3's original 18 migrations are immutable.
const original = patch3Locked?.migrations ?? {};
if (Object.keys(original).length !== 18) fail(`Expected 18 Patch 3 historical migrations, found ${Object.keys(original).length}.`);
for (const [name, expected] of Object.entries(original)) {
  const filePath = path.join(root, 'supabase', 'migrations', name);
  if (!fs.existsSync(filePath)) {
    fail(`Historical migration is missing: ${name}`);
    continue;
  }
  if (sha256(filePath) !== expected) fail(`Historical migration checksum mismatch: ${name}`);
}

// Patch 5.2 locks 18 historical migrations + prerequisite + catalogue baseline.
const patch52Approved = patch52Locked?.migrations ?? {};
if (Object.keys(patch52Approved).length !== 20) fail(`Expected 20 Patch 5.2 historical migrations, found ${Object.keys(patch52Approved).length}.`);
for (const [name, expected] of Object.entries(patch52Approved)) {
  const filePath = path.join(root, 'supabase', 'migrations', name);
  if (!fs.existsSync(filePath)) {
    fail(`Patch 5.2 historical migration is missing: ${name}`);
    continue;
  }
  if (sha256(filePath) !== expected) fail(`Patch 5.2 historical migration checksum mismatch: ${name}`);
}

// The active promotion lock must be an exact immutable snapshot of every source migration.
const approved = activeLocked?.migrations ?? {};
const approvedNames = Object.keys(approved).sort();
const sourceMigrationNames = fs.readdirSync(path.join(root, 'supabase', 'migrations'))
  .filter((name) => name.endsWith('.sql'))
  .sort();
if (activeLocked.lock_version !== 'RANKTIGER_25') fail('Active RankTiger migration lock version must be RANKTIGER_25.');
if (activeLocked.migration_count !== expectedActiveMigrationCount) fail('Active RankTiger migration lock metadata must declare 25 migrations.');
if (approvedNames.length !== expectedActiveMigrationCount) fail(`Expected 25 active RankTiger migration checksums, found ${approvedNames.length}.`);
if (JSON.stringify(approvedNames) !== JSON.stringify(sourceMigrationNames)) {
  fail('Source migration files do not exactly match the active RankTiger migration lock.');
}
for (const [name, expected] of Object.entries(approved)) {
  const filePath = path.join(root, 'supabase', 'migrations', name);
  if (!fs.existsSync(filePath)) {
    fail(`Active RankTiger migration is missing: ${name}`);
    continue;
  }
  if (!/^[0-9a-f]{64}$/.test(expected) || sha256(filePath) !== expected) {
    fail(`Active RankTiger migration checksum mismatch: ${name}`);
  }
}
for (const [name, expected] of Object.entries(patch52Approved)) {
  if (approved[name] !== expected) fail(`Active RankTiger lock does not preserve Patch 5.2 checksum: ${name}`);
}
const expectedNewMigrations = [
  '20260814010000_draft_first_image_content_repair_workflow.sql',
  '20260816010000_phase4a_safety_efficiency_v1.sql',
  '20260817010000_phase4a_facet_performance_fix.sql',
  '20260825010000_content_repair_integrity_gate.sql',
  '20260826212517_admin_task_inbox_published_image_queue.sql',
];
const addedMigrations = approvedNames.filter((name) => !(name in patch52Approved));
if (JSON.stringify(addedMigrations) !== JSON.stringify(expectedNewMigrations)) {
  fail(`Active RankTiger lock must add exactly the five reviewed migrations; found: ${addedMigrations.join(', ')}`);
}

// The prerequisite must run immediately before the locked Phase 3E topic migration.
const orderedNames = Object.keys(approved).sort();
const prereqIndex = orderedNames.indexOf(prerequisiteName);
const phase3eIndex = orderedNames.indexOf(phase3eName);
if (prereqIndex < 0 || phase3eIndex < 0 || prereqIndex + 1 !== phase3eIndex) {
  fail('Catalogue prerequisite migration must sort immediately before 20260805000100_phase3e_compatibility.sql.');
}

// It may write only the parent rows needed by Phase 3E: boards, exams, subjects.
const prerequisiteAllowedTables = new Set(['boards', 'exams', 'subjects']);
const prereqTargets = [...prerequisite.matchAll(/insert\s+into\s+(?:public\.)?([a-zA-Z0-9_]+)/gi)].map((m) => m[1].toLowerCase());
if (!prereqTargets.length) fail('Catalogue prerequisite migration contains no INSERT targets.');
for (const target of new Set(prereqTargets)) {
  if (!prerequisiteAllowedTables.has(target)) fail(`Catalogue prerequisite writes to non-approved table: ${target}`);
}
for (const requiredSubject of ['REASONING', 'QUANTITATIVE_APTITUDE', 'ENGLISH', 'GUJARATI']) {
  if (!prerequisite.includes(`'${requiredSubject}'`)) fail(`Catalogue prerequisite is missing required subject: ${requiredSubject}`);
}

const forbiddenPrerequisitePatterns = [
  /insert\s+into\s+(?:public\.)?(topics|app_settings|profiles|questions|draft_questions|tests|attempts|attempt_answers|payments|package_access|admin_audit_logs)\b/i,
  /auth\.users/i,
  /service_role/i,
  /sb_secret_/i,
];
for (const pattern of forbiddenPrerequisitePatterns) {
  if (pattern.test(prerequisite)) fail(`Catalogue prerequisite contains forbidden pattern: ${pattern}`);
}

// Production reference data remains versioned; never Supabase seed.
const approvedCatalogueTables = new Set(['boards', 'exams', 'subjects', 'topics', 'app_settings']);
const insertTargets = [...catalogue.matchAll(/insert\s+into\s+(?:public\.)?([a-zA-Z0-9_]+)/gi)].map((m) => m[1].toLowerCase());
if (!insertTargets.length) fail('Public catalogue migration contains no INSERT targets.');
for (const target of new Set(insertTargets)) {
  if (!approvedCatalogueTables.has(target)) fail(`Public catalogue migration writes to non-approved table: ${target}`);
}

const forbiddenCatalogueTerms = [
  /['"]app_name['"]/i,
  /['"]app_mark['"]/i,
  /['"]app_environment['"]/i,
  /insert\s+into\s+(?:public\.)?(profiles|questions|draft_questions|tests|attempts|attempt_answers|payments|package_access|admin_audit_logs)\b/i,
  /auth\.users/i,
  /service_role/i,
  /sb_secret_/i,
];
for (const pattern of forbiddenCatalogueTerms) {
  if (pattern.test(catalogue)) fail(`Public catalogue migration contains forbidden identity/test/user pattern: ${pattern}`);
}

if (process.exitCode) process.exit();
console.log('PASS: RankTiger PROD database initialization is migration-only; production seed execution is forbidden.');
console.log('PASS: Remote migration history is parsed from the remote column, must be an approved subset before write, and must exactly match after write.');
console.log('PASS: 18 historical migrations remain unchanged.');
console.log('PASS: 20-migration Patch 5.2 historical lock remains unchanged and is preserved by the active lock.');
console.log('PASS: Fresh-environment catalogue parent prerequisite sorts immediately before the locked Phase 3E topic migration.');
console.log('PASS: 25 approved migrations exactly match the source set and are checksum-locked for RankTiger PROD.');
console.log(`PASS: reviewed promotion additions: ${addedMigrations.join(', ')}`);
console.log(`PASS: prerequisite targets only: ${[...new Set(prereqTargets)].sort().join(', ')}`);
console.log(`PASS: versioned catalogue baseline targets only: ${[...new Set(insertTargets)].sort().join(', ')}`);
