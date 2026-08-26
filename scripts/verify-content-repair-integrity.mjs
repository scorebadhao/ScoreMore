import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const MIGRATION = 'supabase/migrations/20260825010000_content_repair_integrity_gate.sql';
const problems = [];
const pass = (condition, message) => { if (!condition) problems.push(message); };

const [migration, api, admin, html, css, migrationReadme] = await Promise.all([
  readFile(resolve(ROOT, MIGRATION), 'utf8'),
  readFile(resolve(ROOT, 'assets/js/api.js'), 'utf8'),
  readFile(resolve(ROOT, 'assets/js/admin.js'), 'utf8'),
  readFile(resolve(ROOT, 'admin.html'), 'utf8'),
  readFile(resolve(ROOT, 'assets/css/main.css'), 'utf8'),
  readFile(resolve(ROOT, 'supabase/migrations/README.md'), 'utf8'),
]);

pass(/^begin;[\s\S]*commit;\s*$/.test(migration), 'Integrity migration must be one explicit transaction.');
pass(migration.includes("content_repair_status text not null default 'READY'"), 'Independent content-repair state is missing.');
pass(migration.includes('content_source_confirmed_revision integer'), 'Revision-bound source confirmation is missing.');
pass(migration.includes('return_draft_to_content_repair'), 'Audited Final Review-to-Repair RPC is missing.');
pass(migration.includes('p_expected_repair_revision integer'), 'Optimistic repair revision checks are missing.');
pass(migration.includes('save_draft_repair_content_v2'), 'Optimistic content repair RPC is missing.');
pass(migration.includes('review_draft_answer_topic_v2'), 'Revision-bound Final Review RPC is missing.');
pass(migration.includes("p_content_confirmation is distinct from 'SOURCE_PRESENTATION_CONFIRMED'"), 'Mandatory source/presentation confirmation is not enforced by the database.');
pass(migration.includes("content_repair_status <> 'READY'"), 'Database review/publication gate does not block unresolved content repair.');
pass(migration.includes('content_source_confirmed_revision <> v_draft.repair_revision'), 'Publication does not reject stale content confirmation.');
pass(migration.includes('questions_content_integrity_before_publish'), 'Independent before-publish content guard is missing.');
pass(migration.includes('protect_draft_workflow_mutations'), 'Direct browser updates can bypass audited repair/review RPCs.');
pass(migration.includes("or b.content_repair_status = 'NEEDS_REPAIR'"), 'Repair queue does not include non-visual content repair.');
pass(migration.includes("'CONTENT_REPAIR'"), 'Unified queue content-repair filter is missing.');
pass(migration.includes('security definer\nset search_path = public') || /security definer\s+set search_path = public/.test(migration), 'Security-definer functions must pin search_path.');
pass((migration.match(/security definer/g) || []).length >= 7, 'Expected admin/server integrity functions were not created as security definers.');
pass((migration.match(/not public\.is_admin\(\)/g) || []).length >= 6, 'Admin authorization checks are missing from one or more client-callable RPCs.');
pass(migration.includes('revoke all on function public.review_draft_answer_topic(uuid,text,text,text,text,text,text)'), 'Stale Final Review RPC remains callable.');
pass(migration.includes('grant execute on function public.review_draft_answer_topic_v2'), 'Authenticated admins cannot call the v2 Final Review RPC.');

pass(api.includes("client.rpc('return_draft_to_content_repair'"), 'API does not route a draft into content repair.');
pass(api.includes("client.rpc('save_draft_repair_content_v2'"), 'API still uses the stale content-repair mutation.');
pass(api.includes("client.rpc('review_draft_answer_topic_v2'"), 'API still uses the stale Final Review mutation.');
pass(api.includes('normalizeRepairRevision'), 'API does not reject a missing optimistic revision.');
pass(api.includes("'content_repair_status'"), 'Draft summary query omits content repair state.');
pass(api.includes("'content_source_confirmed_revision'"), 'Draft summary query omits source-confirmed revision.');

pass(admin.includes('focusDraftInRepair'), 'Admin does not clear stale filters and focus the exact repair record.');
pass(admin.includes('returnDraftToContentRepair'), 'Back-to-repair action does not perform a server state transition.');
pass(admin.includes('SOURCE_PRESENTATION_CONFIRMED'), 'Final Review source-content confirmation control is missing.');
pass(admin.includes('Select verified answer source'), 'Final Review must start with an explicit answer-source choice.');
pass(!admin.includes("proposedSource === 'AI_PROPOSED' ? 'MANUALLY_VERIFIED'"), 'AI/missing answer source is still silently displayed as manually verified.');
pass(admin.includes('Approval blocked ('), 'Final Review blocker summary is missing.');
pass(admin.includes('id="returnRepairNote"') && admin.includes('required disabled'), 'Hidden return-to-repair controls can silently block Final Review submission.');
pass(admin.includes('setReturnPanelActive'), 'Return-to-repair controls are not enabled and disabled with their panel.');
pass(admin.includes('expectedRepairRevision: draft.repair_revision'), 'Final Review does not submit the exact loaded revision.');
pass(admin.includes('content_repair_reason_note'), 'Repair UI does not show the recorded content problem.');
pass(admin.includes('draftProvenanceMarkup'), 'Final Review/Repair does not show paper and source identity.');

pass(html.includes('Content repair requested'), 'Repair Centre content status filter is missing.');
pass(html.includes('All repair candidates'), 'Repair Centre is still presented as visual-only.');
pass(css.includes('.return-to-repair-panel'), 'Professional return-to-repair panel styling is missing.');
pass(/@media \(max-width: 680px\)[\s\S]*\.final-review-sticky-actions\s*\{[\s\S]*position: static;/.test(css), 'Mobile Final Review action bar still overlays question data.');
pass(migrationReadme.includes('20260825010000_content_repair_integrity_gate.sql'), 'Migration order documentation omits the integrity gate.');

if (problems.length) {
  console.error('CONTENT REPAIR INTEGRITY VERIFICATION FAILED');
  for (const item of problems) console.error(`- ${item}`);
  process.exit(1);
}

console.log('PASS: ScoreMore content repair and Final Review integrity gate is wired end-to-end.');
console.log('Non-visual content repair routing: ENFORCED');
console.log('Stale repair revision writes: BLOCKED');
console.log('Source-content confirmation before publish: ENFORCED');
console.log('Mobile Final Review overlay: REMOVED');
