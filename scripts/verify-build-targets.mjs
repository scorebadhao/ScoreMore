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

assert(scoremore.appName === 'ScoreMore', 'ScoreMore target name changed unexpectedly.');
assert(scoremore.appMark === 'S+', 'ScoreMore target mark changed unexpectedly.');
assert(scoremore.base === '/ScoreMore/', 'ScoreMore target must keep /ScoreMore/ base path.');
assert(scoremore.environment === 'development', 'ScoreMore target must remain development.');
assert(ranktiger.appName === 'RankTiger', 'RankTiger target name changed unexpectedly.');
assert(ranktiger.appMark === 'RT', 'RankTiger target mark changed unexpectedly.');
assert(ranktiger.base === '/', 'RankTiger target must use root base path.');
assert(ranktiger.environment === 'production', 'RankTiger target must remain production.');

const htmlFiles = ['index.html', 'reset-password.html', 'student.html', 'admin.html', 'test-builder.html'];
for (const file of htmlFiles) {
  const source = await readFile(new URL(`../${file}`, import.meta.url), 'utf8');
  assert(source.includes('__APP_NAME__'), `${file} must contain the build-time app-name placeholder.`);

  for (const target of [scoremore, ranktiger]) {
    const rendered = source
      .replaceAll('__APP_NAME__', target.appName)
      .replaceAll('__APP_MARK__', target.appMark)
      .replaceAll('__APP_TAGLINE__', target.tagline)
      .replaceAll('__APP_ENVIRONMENT__', target.environment);
    assert(!rendered.includes('__APP_'), `${file} leaves an unresolved build placeholder for ${target.id}.`);
    assert(rendered.includes(target.appName), `${file} does not render ${target.appName}.`);
    if (target.id === 'ranktiger') {
      assert(!rendered.includes('ScoreMore'), `${file} leaks the ScoreMore display brand into the RankTiger build.`);
    }
  }
}

const pagesWorkflow = await readFile(new URL('../.github/workflows/deploy-pages.yml', import.meta.url), 'utf8');
assert(pagesWorkflow.includes('npm run build:scoremore'), 'GitHub Pages must explicitly build ScoreMore DEV.');

const dbWorkflow = await readFile(new URL('../.github/workflows/deploy-supabase.yml', import.meta.url), 'utf8');
assert(dbWorkflow.includes('DEPLOY_SCOREMORE_DEV'), 'Database workflow must require DEV-specific confirmation.');
assert(dbWorkflow.includes('stejewkuikvqpqotjnnt'), 'Database workflow must retain the locked ScoreMore DEV project-ref guard.');

if (!process.exitCode) {
  console.log('PASS: ScoreMore DEV / RankTiger PROD build-target foundation is internally consistent.');
}
