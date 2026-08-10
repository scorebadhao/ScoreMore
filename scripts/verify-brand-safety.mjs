import { readFile } from 'node:fs/promises';
import { getBuildTarget } from '../build-targets.js';

const fail = (message) => {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
};
const assert = (condition, message) => {
  if (!condition) fail(message);
};

const scoremore = getBuildTarget('scoremore');
const ranktiger = getBuildTarget('ranktiger');
assert(scoremore.appName === 'ScoreMore', 'DEV product identity must remain ScoreMore.');
assert(ranktiger.appName === 'RankTiger', 'PROD product identity must remain RankTiger.');
assert(ranktiger.legacyBrandNames.includes('ScoreMore'), 'RankTiger must normalize legacy display-case ScoreMore backend text.');
assert(scoremore.cacheVersion !== ranktiger.cacheVersion, 'DEV and PROD browser namespaces must differ.');

const config = await readFile(new URL('../assets/js/config.js', import.meta.url), 'utf8');
assert(config.includes('resolvePublicSettings'), 'Public settings resolver is missing.');
assert(config.includes('brandRuntimeText'), 'Legacy brand display normalizer is missing.');
assert(config.includes('appName: APP_CONFIG.name'), 'Database app_name must not control runtime identity.');

const publicJs = await readFile(new URL('../assets/js/public.js', import.meta.url), 'utf8');
const studentJs = await readFile(new URL('../assets/js/student.js', import.meta.url), 'utf8');
for (const [file, source] of [['public.js', publicJs], ['student.js', studentJs]]) {
  assert(source.includes('resolvePublicSettings'), `${file} must use build-safe public settings.`);
  assert(source.includes('APP_CONFIG.cacheVersion}:pending-test-id'), `${file} must namespace pending-test state by build target.`);
  assert(!source.includes("'scoremore:pending-test-id'"), `${file} still contains the old hardcoded pending-test key.`);
}

const apiJs = await readFile(new URL('../assets/js/api.js', import.meta.url), 'utf8');
assert(apiJs.includes('brandRuntimeText(message, fallback)'), 'Backend display errors must be normalized to the active build brand.');

const seed = await readFile(new URL('../supabase/seed.sql', import.meta.url), 'utf8');
assert(!seed.includes("('app_name'"), 'Shared seed must not seed app_name.');
assert(!seed.includes("('app_mark'"), 'Shared seed must not seed app_mark.');
assert(!seed.includes("('app_environment'"), 'Shared seed must not seed app_environment.');
assert(!seed.includes('Initial ScoreMore public'), 'Shared seed must not contain ScoreMore-specific public descriptions.');
assert(seed.includes('BRAND SAFETY'), 'Shared seed must retain the brand-safety warning.');

const importEngine = await readFile(new URL('../assets/js/importEngine.js', import.meta.url), 'utf8');
assert(importEngine.includes("const IMPORT_SCHEMA = 'scoremore.question-import';"), 'Versioned import schema identifier must remain backward compatible.');
assert(importEngine.includes('scoremore-import-data'), 'HTML import protocol id must remain backward compatible.');

const pagesWorkflow = await readFile(new URL('../.github/workflows/deploy-pages.yml', import.meta.url), 'utf8');
assert(pagesWorkflow.includes('npm run build:scoremore'), 'Current GitHub Pages deployment must still build ScoreMore DEV only.');

if (!process.exitCode) {
  console.log('PASS: Patch 2 brand/config/seed safety is internally consistent.');
}
