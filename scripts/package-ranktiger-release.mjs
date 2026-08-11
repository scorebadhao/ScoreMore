import { createHash } from 'node:crypto';
import { cp, mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve, relative, sep } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const DIST = resolve(ROOT, 'dist');
const POLICY_FILE = resolve(ROOT, 'ranktiger-release.config.json');
const PACKAGE_LOCK = resolve(ROOT, 'package-lock.json');

function fail(message) {
  console.error(`\nERROR: ${message}`);
  process.exit(1);
}

function normalizeVersion(value) {
  const version = String(value || '').trim().replace(/^v/i, '');
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(version)) {
    fail('RANKTIGER_RELEASE_VERSION must be SemVer, for example 1.0.0 or 1.0.0-rc.1.');
  }
  return version;
}

async function listFiles(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = resolve(dir, entry.name);
    if (entry.isDirectory()) out.push(...await listFiles(full));
    else if (entry.isFile()) out.push(full);
  }
  return out;
}

async function sha256File(path) {
  return createHash('sha256').update(await readFile(path)).digest('hex');
}

async function hashTree(dir) {
  const hash = createHash('sha256');
  const files = (await listFiles(dir)).sort((a, b) => a.localeCompare(b));
  for (const file of files) {
    const rel = relative(dir, file).split(sep).join('/');
    hash.update(rel);
    hash.update('\0');
    hash.update(await readFile(file));
    hash.update('\0');
  }
  return hash.digest('hex');
}

function resolveSourceCommit() {
  const envSha = String(process.env.GITHUB_SHA || '').trim();
  if (/^[0-9a-f]{7,40}$/i.test(envSha)) return envSha;
  try {
    return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return 'unknown';
  }
}

async function assertRankTigerDist() {
  try {
    if (!(await stat(DIST)).isDirectory()) fail('dist/ is not a directory. Run npm run build:ranktiger first.');
  } catch {
    fail('dist/ is missing. Run npm run build:ranktiger first.');
  }

  const requiredHtml = ['index.html', 'student.html', 'admin.html', 'test-builder.html'];
  for (const name of requiredHtml) {
    const path = resolve(DIST, name);
    let html;
    try {
      html = await readFile(path, 'utf8');
    } catch {
      fail(`dist/${name} is missing.`);
    }
    if (!html.includes('RankTiger')) fail(`dist/${name} does not identify the RankTiger build.`);
    if (html.includes('__APP_NAME__') || html.includes('__APP_MARK__')) fail(`dist/${name} still contains unresolved build placeholders.`);
    if (html.includes('/ScoreMore/')) fail(`dist/${name} still contains the ScoreMore GitHub Pages base path.`);
  }

  const files = await listFiles(DIST);
  const forbiddenPathParts = ['/.git/', '/.github/', '/supabase/', '/scripts/', '/docs/', '/node_modules/'];
  const forbiddenSecretMarkers = [
    'SUPABASE_SERVICE_ROLE_KEY',
    'SUPABASE_DB_PASSWORD',
    'SUPABASE_ACCESS_TOKEN',
    'RANKTIGER_RELEASE_TOKEN',
    'sb_secret_',
    'service_role',
    'postgresql://',
  ];

  for (const file of files) {
    const rel = `/${relative(DIST, file).split(sep).join('/')}`;
    const lower = rel.toLowerCase();
    if (lower.includes('/.env') || forbiddenPathParts.some((part) => lower.includes(part))) {
      fail(`Forbidden development/private path found in dist: ${rel}`);
    }
    if (lower.endsWith('.map')) fail(`Source map found in production package: ${rel}`);

    const info = await stat(file);
    if (info.size <= 5_000_000) {
      const body = await readFile(file, 'utf8').catch(() => '');
      for (const marker of forbiddenSecretMarkers) {
        if (body.includes(marker)) fail(`Forbidden secret/private marker "${marker}" found in dist file ${rel}.`);
      }
    }
  }

  return files.length;
}

const policy = JSON.parse(await readFile(POLICY_FILE, 'utf8'));
if (
  policy.schemaVersion !== 2
  || policy.product !== 'RankTiger'
  || policy.dependencyLockRequired !== true
  || policy.requiredMigrationCount !== 20
  || policy.productionDeployEnabled !== false
  || policy.productionDatabaseMigrationEnabled !== false
) {
  fail('Patch 6 release policy is not in the expected candidate-only safe mode.');
}

let packageLock;
try {
  packageLock = JSON.parse(await readFile(PACKAGE_LOCK, 'utf8'));
} catch {
  fail('package-lock.json is required before packaging a RankTiger release candidate.');
}
if (Number(packageLock.lockfileVersion) < 3) fail('package-lock.json must use lockfileVersion 3 or newer.');

const suppliedProductionProjectId = String(
  process.env.RANKTIGER_SUPABASE_PROJECT_ID
  || process.env.RANKTIGER_PROD_PROJECT_ID
  || '',
).trim();
const productionUrl = String(process.env.RANKTIGER_SUPABASE_URL || '').trim().replace(/\/+$/, '');

if (!productionUrl) {
  fail('RankTiger Supabase URL is missing.');
}

let parsedProductionUrl;
try {
  parsedProductionUrl = new URL(productionUrl);
} catch {
  fail('RankTiger Supabase URL is invalid.');
}
if (parsedProductionUrl.protocol !== 'https:') {
  fail('RankTiger Supabase URL must use HTTPS.');
}

const hostMatch = parsedProductionUrl.hostname.match(/^([a-z0-9]+)\.supabase\.co$/i);
if (!hostMatch) {
  fail('RankTiger Supabase URL must use the standard <project-ref>.supabase.co host.');
}
const productionProjectId = hostMatch[1];

if (productionProjectId === 'stejewkuikvqpqotjnnt') {
  fail('Refusing to package RankTiger candidate against the ScoreMore DEV project ID.');
}
if (suppliedProductionProjectId && suppliedProductionProjectId !== productionProjectId) {
  fail('Explicit RankTiger Supabase project ID does not match the RankTiger Supabase URL.');
}

if (String(process.env.RANKTIGER_PROD_PUBLIC_BASELINE_VERIFIED || '').toLowerCase() !== 'true') {
  fail('RankTiger PROD public baseline must be verified read-only before packaging the candidate.');
}

const version = normalizeVersion(process.env.RANKTIGER_RELEASE_VERSION || process.argv[2]);
const distFileCount = await assertRankTigerDist();

const outputRoot = resolve(ROOT, policy.artifactDirectory);
const outputDist = resolve(outputRoot, 'dist');
await rm(outputRoot, { recursive: true, force: true });
await mkdir(outputRoot, { recursive: true });
await cp(DIST, outputDist, { recursive: true });

const migrationFiles = (await readdir(resolve(ROOT, 'supabase/migrations')))
  .filter((name) => name.endsWith('.sql'))
  .sort();
if (migrationFiles.length !== policy.requiredMigrationCount) {
  fail(`Expected ${policy.requiredMigrationCount} approved migrations, found ${migrationFiles.length}.`);
}

const metadata = {
  schema_version: 2,
  product: 'RankTiger',
  environment: 'production',
  release_status: 'candidate',
  version,
  source_repository: process.env.GITHUB_REPOSITORY || policy.sourceRepository,
  source_commit: resolveSourceCommit(),
  source_ref: process.env.GITHUB_REF_NAME || 'local',
  build_target: policy.buildTarget,
  base_path: policy.basePath,
  built_at_utc: new Date().toISOString(),
  dist_file_count: distFileCount,
  dist_sha256: await hashTree(outputDist),
  dependencies: {
    package_lock_required: true,
    package_json_sha256: await sha256File(resolve(ROOT, 'package.json')),
    package_lock_sha256: await sha256File(PACKAGE_LOCK),
    package_lock_version: packageLock.lockfileVersion,
  },
  database: {
    migrations_in_source: migrationFiles.length,
    latest_source_migration: migrationFiles.at(-1) || null,
    required_migration_lock_file: policy.requiredMigrationLockFile,
    required_migration_count: policy.requiredMigrationCount,
    production_project_id: productionProjectId,
    production_public_baseline_verified_before_build: true,
    production_migration_applied_by_this_workflow: false,
  },
  promotion: {
    ranktiger_repository_updated: false,
    cloudflare_deployed: false,
    student_domain_deployed: false,
    note: 'Patch 6 release-candidate artifact only. Stable promotion remains intentionally disabled.',
  },
};

await writeFile(resolve(outputRoot, policy.releaseMetadataFile), `${JSON.stringify(metadata, null, 2)}\n`, 'utf8');
console.log(`RankTiger release candidate ${version} packaged at ${relative(ROOT, outputRoot)}/`);
console.log(`dist SHA-256: ${metadata.dist_sha256}`);
console.log(`package-lock SHA-256: ${metadata.dependencies.package_lock_sha256}`);
