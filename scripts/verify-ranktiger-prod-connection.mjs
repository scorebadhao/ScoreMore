import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const workflowPath = resolve(ROOT, '.github/workflows/verify-ranktiger-prod.yml');
const workflow = await readFile(workflowPath, 'utf8');
const problems = [];
const pass = (condition, message) => { if (!condition) problems.push(message); };

pass(/workflow_dispatch\s*:/.test(workflow), 'Patch 4 workflow must be manual workflow_dispatch only.');
pass(!/^\s*push\s*:/m.test(workflow), 'Patch 4 workflow must not have a push trigger.');
pass(!/^\s*pull_request\s*:/m.test(workflow), 'Patch 4 workflow must not have a pull_request trigger.');
pass(workflow.includes('VERIFY_RANKTIGER_PROD'), 'Patch 4 workflow must require exact VERIFY_RANKTIGER_PROD confirmation.');
pass(workflow.includes('RANKTIGER_SUPABASE_PROJECT_ID'), 'RankTiger PROD project ID secret is not used.');
pass(workflow.includes('RANKTIGER_SUPABASE_URL'), 'RankTiger PROD URL secret is not used.');
pass(workflow.includes('RANKTIGER_SUPABASE_PUBLISHABLE_KEY'), 'RankTiger PROD publishable key secret is not used.');
pass(workflow.includes('RANKTIGER_SUPABASE_DB_PASSWORD'), 'RankTiger PROD DB password secret is not used.');
pass(workflow.includes('SUPABASE_ACCESS_TOKEN'), 'Existing Supabase access token is not used.');
pass(workflow.includes('stejewkuikvqpqotjnnt'), 'ScoreMore DEV project-ID guard is missing.');
pass(workflow.includes('https://${RANKTIGER_SUPABASE_PROJECT_ID}.supabase.co'), 'URL/project-ID cross-check is missing.');
pass(workflow.includes('supabase projects list'), 'Management/API visibility check is missing.');
pass(workflow.includes('/auth/v1/settings'), 'Auth API publishable-key check is missing.');
pass(workflow.includes('supabase link --project-ref'), 'Database credential/link check is missing.');
pass(workflow.includes('supabase migration list --linked'), 'Read-only migration status check is missing.');

const forbidden = [
  'supabase db push',
  'supabase db reset',
  'supabase migration up',
  'supabase migration down',
  'supabase migration repair',
  'supabase seed ',
  'supabase config push',
  'supabase secrets set',
  'supabase secrets unset',
  'supabase functions deploy',
  'supabase projects delete',
  'supabase branches create',
  'supabase branches delete',
  'git push',
  'wrangler pages deploy',
  'wrangler deploy'
];

for (const token of forbidden) {
  pass(!workflow.toLowerCase().includes(token.toLowerCase()), `Forbidden mutation/deployment token present in Patch 4 workflow: ${token}`);
}

pass(!workflow.includes('sb_secret_'), 'A Supabase secret API key must never be embedded in the workflow.');
pass(!workflow.includes('service_role'), 'A service-role key must never be embedded in the workflow.');
pass(!workflow.includes('postgresql://'), 'A database connection string must never be embedded in the workflow.');

if (problems.length) {
  console.error('PATCH 4 VERIFICATION FAILED');
  for (const item of problems) console.error(`- ${item}`);
  process.exit(1);
}

console.log('PASS: Patch 4 RankTiger PROD verification workflow is manual, target-guarded, and non-migrating.');
console.log('Production migrations: DISABLED');
console.log('Seed writes: DISABLED');
console.log('RankTiger repository writes: DISABLED');
console.log('Cloudflare deployment: DISABLED');
