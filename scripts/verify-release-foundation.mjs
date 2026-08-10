import { createHash } from 'node:crypto';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const problems = [];
const pass = (condition, message) => { if (!condition) problems.push(message); };

const policy = JSON.parse(await readFile(resolve(ROOT, 'ranktiger-release.config.json'), 'utf8'));
pass(policy.product === 'RankTiger', 'Release policy product must be RankTiger.');
pass(policy.buildTarget === 'ranktiger', 'Release policy build target must be ranktiger.');
pass(policy.basePath === '/', 'RankTiger release base path must be /.');
pass(policy.workflowConfirmation === 'PREPARE_RANKTIGER_RC', 'Expected manual RC confirmation is missing.');
pass(policy.productionDeployEnabled === false, 'Patch 3 must not enable production deployment.');
pass(policy.productionDatabaseMigrationEnabled === false, 'Patch 3 must not enable production database migration.');

const workflowPath = resolve(ROOT, '.github/workflows/prepare-ranktiger-release.yml');
const workflow = await readFile(workflowPath, 'utf8');
pass(/workflow_dispatch\s*:/.test(workflow), 'RankTiger RC workflow must be manual workflow_dispatch only.');
pass(!/^\s*push\s*:/m.test(workflow), 'RankTiger RC workflow must not have a push trigger.');
pass(!/^\s*pull_request\s*:/m.test(workflow), 'RankTiger RC workflow must not have a pull_request trigger.');
pass(workflow.includes('PREPARE_RANKTIGER_RC'), 'RankTiger RC workflow must require explicit confirmation.');
pass(workflow.includes('RANKTIGER_SUPABASE_URL'), 'RankTiger RC workflow must use a separate PROD Supabase URL secret.');
pass(workflow.includes('RANKTIGER_SUPABASE_PUBLISHABLE_KEY'), 'RankTiger RC workflow must use a separate PROD publishable key secret.');
pass(workflow.includes('npm run build:ranktiger'), 'RankTiger RC workflow must use the RankTiger build target.');
pass(workflow.includes('npm run package:ranktiger'), 'RankTiger RC workflow must package the approved build.');
pass(workflow.includes('actions/upload-artifact@'), 'RankTiger RC workflow must upload a candidate artifact.');
pass(workflow.includes('package-lock.json'), 'RankTiger RC workflow must block until a dependency lockfile exists.');
pass(!workflow.includes('supabase db push'), 'Patch 3 RC workflow must not migrate production database.');
pass(!workflow.includes('SUPABASE_DB_PASSWORD'), 'Patch 3 RC workflow must not request a database password.');
pass(!workflow.includes('RANKTIGER_RELEASE_TOKEN'), 'Patch 3 RC workflow must not contain a RankTiger repository write token.');
pass(!/\bgit\s+push\b/.test(workflow), 'Patch 3 RC workflow must not push to the RankTiger repository.');

const pkg = JSON.parse(await readFile(resolve(ROOT, 'package.json'), 'utf8'));
pass(pkg.scripts?.['package:ranktiger'] === 'node scripts/package-ranktiger-release.mjs', 'package:ranktiger script is missing or changed.');
pass(pkg.scripts?.['verify:release-foundation'] === 'node scripts/verify-release-foundation.mjs', 'verify:release-foundation script is missing or changed.');
pass(pkg.scripts?.['verify:patch3'] === 'npm run verify:patch2 && npm run verify:release-foundation', 'verify:patch3 must include all earlier verifiers.');

const checksumFile = resolve(ROOT, 'docs/LOCKED_MIGRATION_CHECKSUMS_PATCH3.json');
const expected = JSON.parse(await readFile(checksumFile, 'utf8'));
for (const [name, expectedHash] of Object.entries(expected.migrations || {})) {
  const body = await readFile(resolve(ROOT, 'supabase/migrations', name));
  const actual = createHash('sha256').update(body).digest('hex');
  pass(actual === expectedHash, `Historical migration changed after lock: ${name}`);
}

const migrationNames = (await readdir(resolve(ROOT, 'supabase/migrations'))).filter((n) => n.endsWith('.sql'));
pass(migrationNames.length >= Object.keys(expected.migrations || {}).length, 'Migration history is unexpectedly smaller than the Patch 3 locked baseline.');

// Confirm the packager itself contains no deployment/write capability.
const packager = await readFile(resolve(ROOT, 'scripts/package-ranktiger-release.mjs'), 'utf8');
pass(!packager.includes('supabase db push'), 'Packager must never apply database migrations.');
pass(!/\bgit\s+push\b/.test(packager), 'Packager must never push repositories.');
pass(packager.includes('production_migration_applied_by_this_workflow: false'), 'Release metadata must explicitly state that Patch 3 does not migrate PROD.');
pass(packager.includes('ranktiger_repository_updated: false'), 'Release metadata must explicitly state that Patch 3 does not update RankTiger repo.');

// Basic SemVer policy examples (dependency-free smoke check).
const semver = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
pass(semver.test('1.0.0'), 'SemVer verifier rejected 1.0.0.');
pass(semver.test('1.0.0-rc.1'), 'SemVer verifier rejected 1.0.0-rc.1.');
pass(!semver.test('release-one'), 'SemVer verifier accepted an invalid version.');

if (problems.length) {
  console.error('PATCH 3 VERIFICATION FAILED');
  for (const item of problems) console.error(`- ${item}`);
  process.exit(1);
}

console.log('PASS: Patch 3 RankTiger release foundation is safe and candidate-only.');
console.log(`Locked historical migrations verified: ${Object.keys(expected.migrations || {}).length}`);
console.log('Production DB migration: DISABLED');
console.log('RankTiger repository push: DISABLED');
