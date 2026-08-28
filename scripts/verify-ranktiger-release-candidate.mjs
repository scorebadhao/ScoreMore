import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const EXPECTED_MIGRATION_LOCK_FILE = 'docs/LOCKED_MIGRATION_CHECKSUMS_RANKTIGER_25.json';
const EXPECTED_MIGRATION_COUNT = 25;
const problems = [];
const pass = (condition, message) => { if (!condition) problems.push(message); };
const sha256 = (body) => createHash('sha256').update(body).digest('hex');

const policy = JSON.parse(await readFile(resolve(ROOT, 'ranktiger-release.config.json'), 'utf8'));
pass(policy.schemaVersion === 2, 'RankTiger release policy schemaVersion must be 2.');
pass(policy.product === 'RankTiger', 'Release policy product must be RankTiger.');
pass(policy.sourceRepository === 'ScoreMore', 'Release policy source repository must remain ScoreMore.');
pass(policy.productionRepository === 'RankTiger', 'Release policy production repository must remain RankTiger.');
pass(policy.buildTarget === 'ranktiger', 'Release build target must be ranktiger.');
pass(policy.basePath === '/', 'RankTiger production base path must be /.');
pass(policy.dependencyLockRequired === true, 'RankTiger release candidate must require a committed dependency lock.');
pass(policy.requiredMigrationCount === EXPECTED_MIGRATION_COUNT, 'RankTiger release policy must recognize the approved 25-migration PROD baseline.');
pass(policy.requiredMigrationLockFile === EXPECTED_MIGRATION_LOCK_FILE, 'RankTiger release policy must use the immutable 25-migration lock.');
pass(policy.productionDeployEnabled === false, 'RankTiger release candidate must not enable production deployment.');
pass(policy.productionDatabaseMigrationEnabled === false, 'RankTiger release candidate must not migrate production database.');

const migrationLock = JSON.parse(await readFile(resolve(ROOT, EXPECTED_MIGRATION_LOCK_FILE), 'utf8'));
const lockedMigrations = migrationLock?.migrations ?? {};
const lockedMigrationNames = Object.keys(lockedMigrations).sort();
const sourceMigrationNames = (await readdir(resolve(ROOT, 'supabase/migrations')))
  .filter((name) => name.endsWith('.sql'))
  .sort();
pass(migrationLock.lock_version === 'RANKTIGER_25', 'RankTiger migration lock version must be RANKTIGER_25.');
pass(migrationLock.migration_count === EXPECTED_MIGRATION_COUNT, 'RankTiger migration lock metadata must declare 25 migrations.');
pass(lockedMigrationNames.length === EXPECTED_MIGRATION_COUNT, 'RankTiger migration lock must contain exactly 25 checksum entries.');
pass(JSON.stringify(sourceMigrationNames) === JSON.stringify(lockedMigrationNames), 'Source migration files must exactly match the approved RankTiger lock.');
for (const name of lockedMigrationNames) {
  const expected = lockedMigrations[name];
  const body = await readFile(resolve(ROOT, 'supabase/migrations', name));
  pass(/^[0-9a-f]{64}$/.test(expected) && sha256(body) === expected, `RankTiger migration checksum mismatch: ${name}`);
}


const devPagesWorkflow = await readFile(resolve(ROOT, '.github/workflows/deploy-pages.yml'), 'utf8');
pass(devPagesWorkflow.includes('if [ -f package-lock.json ]'), 'ScoreMore DEV Pages workflow must switch to the committed lock when it exists.');
pass(devPagesWorkflow.includes('npm ci --no-audit --no-fund'), 'ScoreMore DEV Pages workflow must use npm ci once the lock is committed.');

const bootstrap = await readFile(resolve(ROOT, '.github/workflows/bootstrap-package-lock.yml'), 'utf8');
pass(/workflow_dispatch\s*:/.test(bootstrap), 'Dependency-lock bootstrap workflow must be manual only.');
pass(!/^\s*push\s*:/m.test(bootstrap), 'Dependency-lock bootstrap must not run on push.');
pass(bootstrap.includes('BOOTSTRAP_SCOREMORE_LOCK'), 'Dependency-lock bootstrap confirmation gate is missing.');
pass(bootstrap.includes('npm install --package-lock-only --ignore-scripts --no-audit --no-fund'), 'Dependency-lock bootstrap must generate package-lock only.');
pass(bootstrap.includes('verify-dependency-lock.mjs'), 'Dependency-lock bootstrap must verify the generated lock.');
pass(bootstrap.includes('actions/upload-artifact@'), 'Dependency-lock bootstrap must upload the generated lock as an artifact.');
pass(!bootstrap.includes('secrets.'), 'Dependency-lock bootstrap must not access repository secrets.');
pass(!/\bgit\s+push\b/.test(bootstrap), 'Dependency-lock bootstrap must not push to GitHub.');
pass(!bootstrap.includes('supabase '), 'Dependency-lock bootstrap must not access Supabase.');

const workflow = await readFile(resolve(ROOT, '.github/workflows/prepare-ranktiger-release.yml'), 'utf8');
pass(/workflow_dispatch\s*:/.test(workflow), 'RankTiger release-candidate workflow must be manual only.');
pass(!/^\s*push\s*:/m.test(workflow), 'RankTiger release-candidate workflow must not run on push.');
pass(!/^\s*pull_request\s*:/m.test(workflow), 'RankTiger release-candidate workflow must not run on pull requests.');
pass(workflow.includes('PREPARE_RANKTIGER_RC'), 'RankTiger release-candidate confirmation gate is missing.');
pass(workflow.includes('package-lock.json'), 'RankTiger release candidate must require committed package-lock.json.');
pass(workflow.includes('npm ci --no-audit --no-fund'), 'RankTiger release candidate must install from the dependency lock using npm ci.');
pass(workflow.includes('npm run verify:patch6'), 'RankTiger release candidate must run the complete Patch 6 verifier chain.');
pass(workflow.includes('RANKTIGER_SUPABASE_PROJECT_ID'), 'RankTiger release candidate must use the PROD project ID for target guarding.');
pass(workflow.includes('RANKTIGER_SUPABASE_URL: ${{ secrets.RANKTIGER_SUPABASE_URL }}'), 'RankTiger packaging step must receive the same validated PROD Supabase URL.');
pass(workflow.includes('stejewkuikvqpqotjnnt'), 'RankTiger release candidate must explicitly guard against the ScoreMore DEV project ID.');
pass(workflow.includes('EXPECTED_URL'), 'RankTiger release candidate must cross-check PROD URL against project ID.');
pass(workflow.includes('RANKTIGER_SUPABASE_URL'), 'RankTiger release candidate must use the PROD Supabase URL secret.');
pass(workflow.includes('RANKTIGER_SUPABASE_PUBLISHABLE_KEY'), 'RankTiger release candidate must use the PROD publishable key secret.');
pass(workflow.includes('/auth/v1/settings'), 'RankTiger release candidate must verify the PROD Auth API read-only.');
pass(workflow.includes('boards?select=board_id&board_id=eq.GSSSB'), 'RankTiger release candidate must verify the PROD public catalogue baseline.');
pass(workflow.includes('npm run build:ranktiger'), 'RankTiger release candidate must build the RankTiger target.');
pass(workflow.includes('npm run package:ranktiger'), 'RankTiger release candidate must package the build.');
pass(workflow.includes('actions/upload-artifact@'), 'RankTiger release candidate must upload an artifact.');
pass(!workflow.includes('SUPABASE_DB_PASSWORD'), 'RankTiger release candidate must not use a database password.');
pass(!workflow.includes('SUPABASE_ACCESS_TOKEN'), 'RankTiger release candidate must not use a Supabase account access token.');
pass(!workflow.includes('RANKTIGER_RELEASE_TOKEN'), 'RankTiger release candidate must not use a production-repository write token.');
pass(!workflow.includes('supabase db push'), 'RankTiger release candidate must not migrate the database.');
pass(!workflow.includes('supabase migration'), 'RankTiger release candidate must not alter or manage migration history.');
pass(!/\bgit\s+push\b/.test(workflow), 'RankTiger release candidate must not push to any repository.');
pass(!/wrangler|cloudflare\/wrangler-action|cloudflare\/pages-action/i.test(workflow), 'RankTiger release candidate must not contain a Cloudflare deployment action/command.');

const packager = await readFile(resolve(ROOT, 'scripts/package-ranktiger-release.mjs'), 'utf8');
pass(packager.includes('package_lock_sha256'), 'Release metadata must record package-lock SHA-256.');
pass(packager.includes('required_migration_lock_file'), 'Release metadata must record the required migration lock file.');
pass(packager.includes('required_migration_lock_version'), 'Release metadata must record the required migration lock version.');
pass(packager.includes('required_migration_lock_sha256'), 'Release metadata must record the required migration lock checksum.');
pass(packager.includes('Source migration files do not exactly match'), 'Release packager must reject migration-file set drift.');
pass(packager.includes('Approved RankTiger migration checksum mismatch'), 'Release packager must verify every approved migration checksum.');
pass(packager.includes('production_project_id'), 'Release metadata must record the RankTiger PROD project ID used for the candidate.');
pass(packager.includes('hostMatch') && packager.includes('supabase\\.co'), 'Release packager must derive the RankTiger project reference from the validated Supabase URL.');
pass(packager.includes('suppliedProductionProjectId') && packager.includes('does not match the RankTiger Supabase URL'), 'Release packager must cross-check an explicit project ID when supplied.');
pass(packager.includes('process.env.RANKTIGER_SUPABASE_URL'), 'Release packager must cross-check the project ID against the validated RankTiger Supabase URL.');
pass(packager.includes('const productionProjectId = hostMatch[1]'), 'Release packager must bind project identity to the Supabase hostname instead of a brittle fixed-length check.');
pass(!packager.includes('/^[a-z0-9]{20}$/'), 'Release packager must not assume Supabase project references are exactly 20 characters.');
pass(packager.includes('production_public_baseline_verified_before_build'), 'Release metadata must record the read-only production baseline verification.');
pass(packager.includes('SECRET_LEAK_SCAN_VERSION = 2'), 'Release packager must use the credential-shaped Patch 6.4 secret leak scanner.');
pass(packager.includes('detectSecretLeak'), 'Release packager must run the credential-shaped secret leak detector against production assets.');
pass(packager.includes('sb_secret_[A-Za-z0-9_-]{20,}'), 'Release packager must reject actual Supabase sb_secret credentials.');
pass(!packager.includes("'sb_secret_',"), 'Release packager must not reject a harmless bare sb_secret_ marker used by browser-side redaction code.');
pass(packager.includes("payload?.role === 'service_role'"), 'Release packager must reject legacy service_role JWT credentials by decoded role.');
pass(!packager.includes('forbiddenSecretMarkers'), 'Release packager must not use the old marker-only secret scan.');
pass(!packager.includes('supabase db push'), 'Release packager must never migrate a database.');
pass(!/\bgit\s+push\b/.test(packager), 'Release packager must never push repositories.');

const pkg = JSON.parse(await readFile(resolve(ROOT, 'package.json'), 'utf8'));
pass(pkg.scripts?.['verify:dependency-lock'] === 'node scripts/verify-dependency-lock.mjs', 'verify:dependency-lock script is missing.');
pass(pkg.scripts?.['verify:ranktiger-rc'] === 'node scripts/verify-ranktiger-release-candidate.mjs', 'verify:ranktiger-rc script is missing.');
pass(pkg.scripts?.['verify:patch6'] === 'npm run verify:patch5 && npm run verify:ranktiger-rc && npm run verify:dependency-lock', 'verify:patch6 must include Patch 5 + RC structure + dependency lock.');

if (problems.length) {
  console.error('PATCH 6 RELEASE-CANDIDATE VERIFICATION FAILED');
  for (const item of problems) console.error(`- ${item}`);
  process.exit(1);
}

console.log('PASS: RankTiger 25-migration release-candidate machinery is candidate-only and production-safe.');
console.log('RankTiger repository push: DISABLED');
console.log('RankTiger PROD database migration: DISABLED');
console.log('Cloudflare deployment: DISABLED');
