import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const root = process.cwd();
const workflowPath = path.join(root, '.github', 'workflows', 'initialize-ranktiger-prod-db.yml');
const checksumPath = path.join(root, 'docs', 'LOCKED_MIGRATION_CHECKSUMS_PATCH3.json');
const seedPath = path.join(root, 'supabase', 'seed.sql');

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

for (const required of [workflowPath, checksumPath, seedPath]) {
  if (!fs.existsSync(required)) fail(`Missing required Patch 5 file: ${path.relative(root, required)}`);
}
if (process.exitCode) process.exit();

const workflow = fs.readFileSync(workflowPath, 'utf8');
const seed = fs.readFileSync(seedPath, 'utf8');
const locked = JSON.parse(fs.readFileSync(checksumPath, 'utf8'));

const requiredWorkflowFragments = [
  'INITIALIZE_RANKTIGER_PROD',
  'RANKTIGER_SUPABASE_PROJECT_ID',
  'RANKTIGER_SUPABASE_DB_PASSWORD',
  'RANKTIGER_SUPABASE_URL',
  'RANKTIGER_SUPABASE_PUBLISHABLE_KEY',
  'SUPABASE_ACCESS_TOKEN',
  'supabase db push --dry-run --include-seed',
  'supabase db push --include-seed',
  'supabase migration list --linked',
  'verify-ranktiger-prod-database-init.mjs',
];
for (const fragment of requiredWorkflowFragments) {
  if (!workflow.includes(fragment)) fail(`Patch 5 workflow is missing required safety/apply fragment: ${fragment}`);
}

const forbiddenWorkflowPatterns = [
  /supabase\s+db\s+reset/i,
  /supabase\s+migration\s+(repair|down)/i,
  /git\s+push/i,
  /wrangler|cloudflare\/pages-action/i,
  /RANKTIGER_SUPABASE_SECRET/i,
  /SERVICE_ROLE/i,
  /sb_secret_/i,
];
for (const pattern of forbiddenWorkflowPatterns) {
  if (pattern.test(workflow)) fail(`Patch 5 workflow contains forbidden operation/pattern: ${pattern}`);
}

// The only shared ScoreMore secret allowed in the PROD workflow is the account-level access token.
const forbiddenDevSecrets = [
  'secrets.SUPABASE_DB_PASSWORD',
  'secrets.SUPABASE_PROJECT_ID',
  'secrets.VITE_SUPABASE_URL',
  'secrets.VITE_SUPABASE_PUBLISHABLE_KEY',
];
for (const secret of forbiddenDevSecrets) {
  if (workflow.includes(secret)) fail(`Patch 5 workflow must not reference ScoreMore DEV secret: ${secret}`);
}

// Existing migration history is immutable.
const migrations = locked?.migrations ?? {};
const names = Object.keys(migrations);
if (names.length !== 18) fail(`Expected 18 locked migrations, found ${names.length}.`);
for (const [name, expected] of Object.entries(migrations)) {
  const filePath = path.join(root, 'supabase', 'migrations', name);
  if (!fs.existsSync(filePath)) {
    fail(`Locked migration is missing: ${name}`);
    continue;
  }
  const actual = sha256(filePath);
  if (actual !== expected) fail(`Locked migration checksum mismatch: ${name}`);
}

// Seed is deliberately narrow: catalogue + public app content only.
const approvedSeedTables = new Set(['boards', 'exams', 'subjects', 'topics', 'app_settings']);
const insertTargets = [...seed.matchAll(/insert\s+into\s+(?:public\.)?([a-zA-Z0-9_]+)/gi)].map((m) => m[1].toLowerCase());
if (!insertTargets.length) fail('seed.sql contains no INSERT targets.');
for (const target of new Set(insertTargets)) {
  if (!approvedSeedTables.has(target)) fail(`Production seed writes to non-approved table: ${target}`);
}

const forbiddenSeedTerms = [
  /['"]app_name['"]/i,
  /['"]app_mark['"]/i,
  /['"]app_environment['"]/i,
  /insert\s+into\s+(?:public\.)?(profiles|questions|draft_questions|tests|attempts|attempt_answers|payments|package_access|admin_audit_logs)\b/i,
  /auth\.users/i,
  /service_role/i,
  /sb_secret_/i,
];
for (const pattern of forbiddenSeedTerms) {
  if (pattern.test(seed)) fail(`Production seed contains forbidden identity/test/user pattern: ${pattern}`);
}

if (process.exitCode) process.exit();
console.log('PASS: Patch 5 RankTiger PROD database initialization workflow is guarded and production seed is narrow/safe.');
console.log(`PASS: ${names.length} locked historical migration checksums match.`);
console.log(`PASS: production seed targets only: ${[...new Set(insertTargets)].sort().join(', ')}`);
