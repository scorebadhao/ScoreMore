import { createHash } from 'node:crypto';
import { cp, mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve, relative, sep } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const DIST = resolve(ROOT, 'dist');
const POLICY_FILE = resolve(ROOT, 'ranktiger-release.config.json');

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
    return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim();
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
}

const policy = JSON.parse(await readFile(POLICY_FILE, 'utf8'));
if (policy.product !== 'RankTiger' || policy.productionDeployEnabled !== false || policy.productionDatabaseMigrationEnabled !== false) {
  fail('Patch 3 release policy is not in safe candidate-only mode.');
}

const version = normalizeVersion(process.env.RANKTIGER_RELEASE_VERSION || process.argv[2]);
await assertRankTigerDist();

const outputRoot = resolve(ROOT, policy.artifactDirectory);
const outputDist = resolve(outputRoot, 'dist');
await rm(outputRoot, { recursive: true, force: true });
await mkdir(outputRoot, { recursive: true });
await cp(DIST, outputDist, { recursive: true });

const migrationFiles = (await readdir(resolve(ROOT, 'supabase/migrations')))
  .filter((name) => name.endsWith('.sql'))
  .sort();

const metadata = {
  schema_version: 1,
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
  dist_sha256: await hashTree(outputDist),
  database: {
    migrations_in_source: migrationFiles.length,
    latest_source_migration: migrationFiles.at(-1) || null,
    production_migration_applied_by_this_workflow: false,
  },
  promotion: {
    ranktiger_repository_updated: false,
    cloudflare_deployed: false,
    note: 'Patch 3 release-candidate package only. Production promotion is intentionally disabled.',
  },
};

await writeFile(resolve(outputRoot, policy.releaseMetadataFile), `${JSON.stringify(metadata, null, 2)}\n`, 'utf8');
console.log(`RankTiger release candidate ${version} packaged at ${relative(ROOT, outputRoot)}/`);
console.log(`dist SHA-256: ${metadata.dist_sha256}`);
