import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const MIGRATION = 'supabase/migrations/20260826212517_admin_task_inbox_published_image_queue.sql';
const problems = [];
const pass = (condition, message) => { if (!condition) problems.push(message); };

const [migration, api, admin, html, css, migrationReadme, pkgBody] = await Promise.all([
  readFile(resolve(ROOT, MIGRATION), 'utf8'),
  readFile(resolve(ROOT, 'assets/js/api.js'), 'utf8'),
  readFile(resolve(ROOT, 'assets/js/admin.js'), 'utf8'),
  readFile(resolve(ROOT, 'admin.html'), 'utf8'),
  readFile(resolve(ROOT, 'assets/css/main.css'), 'utf8'),
  readFile(resolve(ROOT, 'supabase/migrations/README.md'), 'utf8'),
  readFile(resolve(ROOT, 'package.json'), 'utf8'),
]);
const pkg = JSON.parse(pkgBody);
const htmlIds = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
const duplicateHtmlIds = [...new Set(htmlIds.filter((id, index) => htmlIds.indexOf(id) !== index))];

pass(/^begin;[\s\S]*commit;\s*$/.test(migration), 'Task Inbox migration must be one explicit transaction.');
pass(migration.includes('create or replace function public.get_admin_task_inbox()'), 'Server-owned Task Inbox RPC is missing.');
pass(/security definer\s+set search_path = public/.test(migration), 'Task Inbox RPC must be SECURITY DEFINER with a pinned search_path.');
pass(migration.includes('v_admin is null or not public.is_admin()'), 'Task Inbox RPC must enforce authenticated admin authorization internally.');
pass(migration.includes('revoke all on function public.get_admin_task_inbox() from public, anon, authenticated;'), 'Task Inbox RPC default execution grants are not fully revoked.');
pass(migration.includes('grant execute on function public.get_admin_task_inbox() to authenticated;'), 'Authenticated admins cannot call the Task Inbox RPC.');
for (const bucket of ['draft_repairs', 'published_image_safety', 'final_reviews', 'ready_to_publish']) {
  pass(migration.includes(`'${bucket}'`), `Task Inbox omits the ${bucket} bucket.`);
}
pass(migration.includes("not in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED')"), 'Published image-safety count does not exclude completed image decisions.');
pass(migration.includes('public.question_student_image_readiness(q.question_id)'), 'Published image-safety count does not use the authoritative readiness function.');
pass(migration.includes('where q.has_pending_image'), 'Published image-safety count omits pending replacement crops.');
pass(migration.includes('public.draft_student_image_ready(d.draft_id)'), 'Publish count does not preserve the authoritative draft image gate.');
pass(migration.includes("d.content_source_confirmed_revision = d.repair_revision"), 'Publish count does not preserve revision-bound source confirmation.');
pass(migration.includes("d.answer_source <> 'AI_PROPOSED'"), 'Publish count does not preserve the human answer-source gate.');

pass(api.includes("client.rpc('get_admin_task_inbox'"), 'Central browser API does not call the Task Inbox RPC.');
pass(admin.includes("openAdminTask('draft_repairs')"), 'Draft Task Inbox action is not bound.');
pass(admin.includes("openAdminTask('published_image_safety')"), 'Published image Task Inbox action is not bound.');
pass(admin.includes("openAdminTask('final_reviews')"), 'Final Review Task Inbox action is not bound.');
pass(admin.includes("openAdminTask('ready_to_publish')"), 'Publish Task Inbox action is not bound.');
pass(admin.includes('focusPublishedImageInRepair'), 'Exact published question routing is missing.');
pass(admin.includes('api.listStudentImageRepairQueue'), 'Published Image Safety does not reuse the protected server queue.');
pass(admin.includes('api.getStudentImageRepairDetail'), 'Published Image Safety cannot open the protected exact detail.');
pass(admin.includes('published-question-readonly'), 'Published question content is not visibly locked read-only.');
pass(!admin.includes('updatePublishedQuestion'), 'Published Image Safety must not add direct published-content editing.');

pass(html.includes('id="adminTaskInboxTitle"'), 'Task Inbox dashboard panel is missing.');
pass(html.includes('id="draftRepairQueueTab"') && html.includes('id="publishedImageRepairQueueTab"'), 'Separate repair queue tabs are missing.');
pass(html.includes('data-repair-queue-panel="draft"') && html.includes('data-repair-queue-panel="published"'), 'Draft and published repair queues are not separate panels.');
pass(html.includes('Published question text and answers are read-only here.'), 'Published Image Safety boundary is not explained to admins.');
pass(html.includes('question_is_student_ready(question_id)'), 'Student-readiness protection is not visible in the published safety workspace.');
pass(duplicateHtmlIds.length === 0, `Admin markup contains duplicate IDs: ${duplicateHtmlIds.join(', ')}`);
for (const id of [
  'adminTaskInboxMeta',
  'continueDraftRepairTask',
  'continuePublishedImageTask',
  'continueFinalReviewTask',
  'continuePublishTask',
  'publishedImageRepairFilters',
  'publishedImageRepairList',
  'publishedImageRepairStatus',
]) {
  pass(htmlIds.includes(id), `Admin markup is missing #${id}.`);
  pass(admin.includes(`document.getElementById('${id}')`), `Admin controller does not bind #${id}.`);
}

pass(css.includes('.repair-queue-tabs'), 'Separate repair queue tabs lack responsive styling.');
pass(css.includes('[data-repair-queue-panel][hidden]'), 'Inactive repair panels are not explicitly hidden.');
pass(css.includes('.admin-dashboard-card.is-recommended-task'), 'Recommended Task Inbox card styling is missing.');
pass(css.includes('.published-question-readonly'), 'Published read-only content styling is missing.');
pass(migrationReadme.includes(MIGRATION.split('/').at(-1)), 'Migration order documentation omits the Task Inbox migration.');
pass(pkg.scripts?.['verify:admin-task-inbox'] === 'node scripts/verify-admin-task-inbox.mjs', 'Task Inbox verifier script is not registered.');

if (problems.length) {
  console.error('ADMIN TASK INBOX VERIFICATION FAILED');
  for (const item of problems) console.error(`- ${item}`);
  process.exit(1);
}

console.log('PASS: ScoreMore Admin Task Inbox and Published Image Safety queue are wired end-to-end.');
console.log('Full-database workflow counts: SERVER-OWNED');
console.log('Continue actions: EXACT-RECORD ROUTING');
console.log('Published image work: SEPARATE AND CONTENT-READ-ONLY');
console.log('Draft/review/publish safety gates: PRESERVED');
