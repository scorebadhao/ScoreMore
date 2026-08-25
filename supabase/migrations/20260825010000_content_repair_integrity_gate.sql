begin;

-- ScoreMore Content Repair Integrity Gate v1.0
--
-- Keeps content completeness independent from student-image readiness:
--   Import -> Content/Image Repair -> Final Review -> Publish Centre.
-- A reviewer may return any active draft (including a non-visual draft) to
-- content repair. Publication then requires an explicit confirmation of the
-- exact repaired presentation revision against its source evidence.

-- ---------------------------------------------------------------------------
-- 1. Independent content-repair state and revision-bound source confirmation
-- ---------------------------------------------------------------------------

alter table public.draft_questions
  add column if not exists content_repair_status text not null default 'READY',
  add column if not exists content_repair_reason_code text,
  add column if not exists content_repair_reason_note text,
  add column if not exists content_repair_requested_by uuid references public.profiles(user_id),
  add column if not exists content_repair_requested_at timestamptz,
  add column if not exists content_repair_resolved_by uuid references public.profiles(user_id),
  add column if not exists content_repair_resolved_at timestamptz,
  add column if not exists content_source_confirmed_revision integer,
  add column if not exists content_source_confirmed_by uuid references public.profiles(user_id),
  add column if not exists content_source_confirmed_at timestamptz,
  add column if not exists content_source_review_note text;

alter table public.draft_questions
  drop constraint if exists draft_questions_content_repair_status_check;

alter table public.draft_questions
  add constraint draft_questions_content_repair_status_check
  check (content_repair_status in ('READY', 'NEEDS_REPAIR'));

alter table public.draft_questions
  drop constraint if exists draft_questions_content_repair_reason_check;

alter table public.draft_questions
  add constraint draft_questions_content_repair_reason_check
  check (
    content_repair_status = 'READY'
    or (
      content_repair_reason_code in (
        'INCOMPLETE_QUESTION',
        'MISSING_CONTEXT',
        'TRANSCRIPTION_ERROR',
        'OPTION_ERROR',
        'SOURCE_MISMATCH',
        'OTHER'
      )
      and length(btrim(coalesce(content_repair_reason_note, ''))) >= 10
      and content_repair_requested_by is not null
      and content_repair_requested_at is not null
    )
  );

alter table public.draft_questions
  drop constraint if exists draft_questions_content_source_confirmation_check;

alter table public.draft_questions
  add constraint draft_questions_content_source_confirmation_check
  check (
    (
      content_source_confirmed_revision is null
      and content_source_confirmed_by is null
      and content_source_confirmed_at is null
    )
    or (
      content_source_confirmed_revision >= 0
      and content_source_confirmed_by is not null
      and content_source_confirmed_at is not null
    )
  );

create index if not exists draft_questions_content_repair_queue_idx
  on public.draft_questions(content_repair_status, review_status, updated_at desc)
  where question_status = 'DRAFT';

create index if not exists draft_questions_content_confirmation_idx
  on public.draft_questions(content_source_confirmed_revision, repair_revision)
  where question_status = 'DRAFT' and review_status = 'IN_REVIEW';

comment on column public.draft_questions.content_repair_status is
  'Independent student-facing content readiness. NEEDS_REPAIR blocks Final Review and publication even when no source image exists.';
comment on column public.draft_questions.content_source_confirmed_revision is
  'Repair revision whose final text/options were explicitly compared with source/import evidence during Final Review.';

-- Existing approvals predate the explicit source/presentation confirmation.
-- Return them to the visible pending queue while preserving their proposed
-- answer, explanation and topic as reviewer inputs.
update public.draft_questions
set
  review_status = 'PENDING',
  verification_status = 'NEEDS_CHECK',
  reviewed_by = null,
  reviewed_at = null,
  reviewed_repair_revision = null,
  content_source_confirmed_revision = null,
  content_source_confirmed_by = null,
  content_source_confirmed_at = null,
  content_source_review_note = null,
  updated_at = now()
where question_status = 'DRAFT'
  and published_question_id is null
  and review_status = 'IN_REVIEW';

-- Every presentation revision change invalidates both academic review and the
-- source-content confirmation, including changes made by older image RPCs.
create or replace function public.clear_draft_content_confirmation_on_revision_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.repair_revision is distinct from old.repair_revision then
    new.content_source_confirmed_revision := null;
    new.content_source_confirmed_by := null;
    new.content_source_confirmed_at := null;
    new.content_source_review_note := null;
  end if;
  return new;
end;
$$;

drop trigger if exists zz_draft_questions_content_confirmation_guard on public.draft_questions;
create trigger zz_draft_questions_content_confirmation_guard
before update on public.draft_questions
for each row execute function public.clear_draft_content_confirmation_on_revision_change();

-- Browser admins read/insert drafts under RLS, but workflow mutations must use
-- the audited security-definer RPCs. This prevents a direct PostgREST update
-- from fabricating repair/review confirmation fields.
create or replace function public.protect_draft_workflow_mutations()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('anon', 'authenticated') and (
    new.question_text is distinct from old.question_text
    or new.options is distinct from old.options
    or new.image_refs is distinct from old.image_refs
    or new.student_image_refs is distinct from old.student_image_refs
    or new.student_image_review_status is distinct from old.student_image_review_status
    or new.student_image_reviewed_by is distinct from old.student_image_reviewed_by
    or new.student_image_reviewed_at is distinct from old.student_image_reviewed_at
    or new.student_image_review_note is distinct from old.student_image_review_note
    or new.correct_answer is distinct from old.correct_answer
    or new.answer_source is distinct from old.answer_source
    or new.explanation is distinct from old.explanation
    or new.topic_id is distinct from old.topic_id
    or new.content_repair_status is distinct from old.content_repair_status
    or new.content_repair_reason_code is distinct from old.content_repair_reason_code
    or new.content_repair_reason_note is distinct from old.content_repair_reason_note
    or new.content_repair_requested_by is distinct from old.content_repair_requested_by
    or new.content_repair_requested_at is distinct from old.content_repair_requested_at
    or new.content_repair_resolved_by is distinct from old.content_repair_resolved_by
    or new.content_repair_resolved_at is distinct from old.content_repair_resolved_at
    or new.content_repair_version is distinct from old.content_repair_version
    or new.content_repaired_by is distinct from old.content_repaired_by
    or new.content_repaired_at is distinct from old.content_repaired_at
    or new.content_repair_note is distinct from old.content_repair_note
    or new.repair_revision is distinct from old.repair_revision
    or new.reviewed_repair_revision is distinct from old.reviewed_repair_revision
    or new.content_source_confirmed_revision is distinct from old.content_source_confirmed_revision
    or new.content_source_confirmed_by is distinct from old.content_source_confirmed_by
    or new.content_source_confirmed_at is distinct from old.content_source_confirmed_at
    or new.content_source_review_note is distinct from old.content_source_review_note
    or new.review_status is distinct from old.review_status
    or new.verification_status is distinct from old.verification_status
    or new.reviewed_by is distinct from old.reviewed_by
    or new.reviewed_at is distinct from old.reviewed_at
  ) then
    raise exception 'Use the audited ScoreMore repair/review RPC for workflow changes.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists draft_questions_protected_workflow_mutations on public.draft_questions;
create trigger draft_questions_protected_workflow_mutations
before update on public.draft_questions
for each row execute function public.protect_draft_workflow_mutations();

create or replace function public.invalidate_draft_human_review(
  p_draft_id uuid,
  p_bump_revision boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.draft_questions
  set
    repair_revision = repair_revision + case when p_bump_revision then 1 else 0 end,
    review_status = 'PENDING',
    verification_status = 'NEEDS_CHECK',
    reviewed_by = null,
    reviewed_at = null,
    reviewed_repair_revision = null,
    content_source_confirmed_revision = null,
    content_source_confirmed_by = null,
    content_source_confirmed_at = null,
    content_source_review_note = null,
    updated_at = now()
  where draft_id = p_draft_id
    and question_status = 'DRAFT'
    and review_status <> 'REJECTED';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Exact, audited Final Review -> Content Repair transition
-- ---------------------------------------------------------------------------

create or replace function public.return_draft_to_content_repair(
  p_draft_id uuid,
  p_reason_code text,
  p_reason_note text,
  p_expected_repair_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft public.draft_questions%rowtype;
  v_reason_code text := upper(nullif(btrim(p_reason_code), ''));
  v_reason_note text := nullif(btrim(p_reason_note), '');
begin
  if v_admin is null or not public.is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  if v_reason_code is null or v_reason_code not in (
    'INCOMPLETE_QUESTION',
    'MISSING_CONTEXT',
    'TRANSCRIPTION_ERROR',
    'OPTION_ERROR',
    'SOURCE_MISMATCH',
    'OTHER'
  ) then
    raise exception 'Choose a valid content-repair reason.' using errcode = 'P0001';
  end if;
  if length(coalesce(v_reason_note, '')) < 10 then
    raise exception 'Describe the content problem in at least 10 characters.' using errcode = 'P0001';
  end if;

  select * into v_draft
  from public.draft_questions
  where draft_id = p_draft_id
  for update;

  if not found
     or v_draft.question_status <> 'DRAFT'
     or v_draft.review_status in ('REJECTED', 'PUBLISHED')
     or v_draft.published_question_id is not null then
    raise exception 'Active draft not found.' using errcode = 'P0001';
  end if;
  if p_expected_repair_revision is distinct from v_draft.repair_revision then
    raise exception 'This draft changed after Final Review loaded. Reload the latest revision before returning it to repair.' using errcode = 'P0001';
  end if;

  if v_draft.content_repair_status = 'NEEDS_REPAIR' then
    return to_jsonb(v_draft);
  end if;

  update public.draft_questions
  set
    content_repair_status = 'NEEDS_REPAIR',
    content_repair_reason_code = v_reason_code,
    content_repair_reason_note = v_reason_note,
    content_repair_requested_by = v_admin,
    content_repair_requested_at = now(),
    content_repair_resolved_by = null,
    content_repair_resolved_at = null,
    repair_revision = repair_revision + 1,
    review_status = 'PENDING',
    verification_status = 'NEEDS_CHECK',
    reviewed_by = null,
    reviewed_at = null,
    reviewed_repair_revision = null,
    updated_at = now()
  where draft_id = p_draft_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    'RETURN_DRAFT_TO_CONTENT_REPAIR',
    'DRAFT_QUESTION',
    p_draft_id::text,
    jsonb_build_object(
      'proposed_question_id', v_draft.proposed_question_id,
      'reason_code', v_reason_code,
      'reason_note', v_reason_note,
      'previous_repair_revision', v_draft.repair_revision,
      'new_repair_revision', v_draft.repair_revision + 1
    )
  );

  return (select to_jsonb(d) from public.draft_questions d where d.draft_id = p_draft_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Optimistic, audited content-repair mutations
-- ---------------------------------------------------------------------------

create or replace function public.save_draft_repair_content_v2(
  p_draft_id uuid,
  p_expected_repair_revision integer,
  p_question_text text,
  p_options jsonb,
  p_admin_note text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft public.draft_questions%rowtype;
  v_question_text text := btrim(coalesce(p_question_text, ''));
  v_options jsonb;
  v_note text := nullif(btrim(p_admin_note), '');
  v_changed boolean;
  v_resolving boolean;
begin
  if v_admin is null or not public.is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  select * into v_draft
  from public.draft_questions
  where draft_id = p_draft_id
  for update;

  if not found
     or v_draft.question_status <> 'DRAFT'
     or v_draft.review_status in ('REJECTED', 'PUBLISHED')
     or v_draft.published_question_id is not null then
    raise exception 'Active draft not found.' using errcode = 'P0001';
  end if;
  if p_expected_repair_revision is distinct from v_draft.repair_revision then
    raise exception 'This draft was changed by another admin. Reload the latest repair revision before saving.' using errcode = 'P0001';
  end if;

  if v_question_text = '' then
    raise exception 'Question text is required.' using errcode = 'P0001';
  end if;
  if coalesce(jsonb_typeof(p_options), '') <> 'object'
     or not (p_options ?& array['A','B','C','D']) then
    raise exception 'Options A, B, C and D are required.' using errcode = 'P0001';
  end if;

  v_options := jsonb_build_object(
    'A', btrim(coalesce(p_options ->> 'A', '')),
    'B', btrim(coalesce(p_options ->> 'B', '')),
    'C', btrim(coalesce(p_options ->> 'C', '')),
    'D', btrim(coalesce(p_options ->> 'D', ''))
  );

  if exists (select 1 from jsonb_each_text(v_options) o where btrim(o.value) = '') then
    raise exception 'All four option texts are required.' using errcode = 'P0001';
  end if;

  v_changed := v_question_text is distinct from v_draft.question_text
    or v_options is distinct from v_draft.options;
  v_resolving := v_draft.content_repair_status = 'NEEDS_REPAIR';

  if not v_changed and not v_resolving then
    return to_jsonb(v_draft);
  end if;
  if length(coalesce(v_note, '')) < 5 then
    raise exception 'Add a repair note of at least 5 characters.' using errcode = 'P0001';
  end if;

  update public.draft_questions
  set
    question_text = v_question_text,
    options = v_options,
    content_repair_version = content_repair_version + case when v_changed then 1 else 0 end,
    content_repaired_by = v_admin,
    content_repaired_at = now(),
    content_repair_note = v_note,
    content_repair_status = 'READY',
    content_repair_resolved_by = v_admin,
    content_repair_resolved_at = now(),
    repair_revision = repair_revision + 1,
    review_status = 'PENDING',
    verification_status = 'NEEDS_CHECK',
    reviewed_by = null,
    reviewed_at = null,
    reviewed_repair_revision = null,
    updated_at = now()
  where draft_id = p_draft_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    'RESOLVE_DRAFT_CONTENT_REPAIR',
    'DRAFT_QUESTION',
    p_draft_id::text,
    jsonb_build_object(
      'proposed_question_id', v_draft.proposed_question_id,
      'content_changed', v_changed,
      'resolved_returned_draft', v_resolving,
      'reason_code', v_draft.content_repair_reason_code,
      'before_question_text', v_draft.question_text,
      'after_question_text', v_question_text,
      'before_options', v_draft.options,
      'after_options', v_options,
      'admin_note', v_note,
      'previous_repair_revision', v_draft.repair_revision,
      'new_repair_revision', v_draft.repair_revision + 1
    )
  );

  return (select to_jsonb(d) from public.draft_questions d where d.draft_id = p_draft_id);
end;
$$;

create or replace function public.reset_draft_repair_content_v2(
  p_draft_id uuid,
  p_expected_repair_revision integer,
  p_admin_note text,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft public.draft_questions%rowtype;
  v_note text := nullif(btrim(p_admin_note), '');
  v_changed boolean;
  v_resolving boolean;
begin
  if v_admin is null or not public.is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;
  if p_confirmation is distinct from 'RESET_TO_IMPORTED_CONTENT' then
    raise exception 'Reset confirmation is required.' using errcode = 'P0001';
  end if;
  if length(coalesce(v_note, '')) < 5 then
    raise exception 'Add a reset reason of at least 5 characters.' using errcode = 'P0001';
  end if;

  select * into v_draft
  from public.draft_questions
  where draft_id = p_draft_id
  for update;

  if not found
     or v_draft.question_status <> 'DRAFT'
     or v_draft.review_status in ('REJECTED', 'PUBLISHED')
     or v_draft.published_question_id is not null then
    raise exception 'Active draft not found.' using errcode = 'P0001';
  end if;
  if p_expected_repair_revision is distinct from v_draft.repair_revision then
    raise exception 'This draft was changed by another admin. Reload the latest repair revision before resetting.' using errcode = 'P0001';
  end if;
  if nullif(btrim(v_draft.imported_question_text), '') is null
     or coalesce(jsonb_typeof(v_draft.imported_options), '') <> 'object'
     or not (v_draft.imported_options ?& array['A','B','C','D']) then
    raise exception 'The imported baseline is incomplete; repair the current content manually instead of resetting.' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from jsonb_each_text(v_draft.imported_options) o
    where btrim(o.value) = ''
  ) then
    raise exception 'The imported baseline contains an empty option; repair the current content manually instead of resetting.' using errcode = 'P0001';
  end if;

  v_changed := v_draft.question_text is distinct from v_draft.imported_question_text
    or v_draft.options is distinct from v_draft.imported_options;
  v_resolving := v_draft.content_repair_status = 'NEEDS_REPAIR';

  if not v_changed and not v_resolving then
    return to_jsonb(v_draft);
  end if;

  update public.draft_questions
  set
    question_text = imported_question_text,
    options = imported_options,
    content_repair_version = content_repair_version + case when v_changed then 1 else 0 end,
    content_repaired_by = v_admin,
    content_repaired_at = now(),
    content_repair_note = v_note,
    content_repair_status = 'READY',
    content_repair_resolved_by = v_admin,
    content_repair_resolved_at = now(),
    repair_revision = repair_revision + 1,
    review_status = 'PENDING',
    verification_status = 'NEEDS_CHECK',
    reviewed_by = null,
    reviewed_at = null,
    reviewed_repair_revision = null,
    updated_at = now()
  where draft_id = p_draft_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    'RESET_DRAFT_CONTENT_TO_IMPORTED_V2',
    'DRAFT_QUESTION',
    p_draft_id::text,
    jsonb_build_object(
      'proposed_question_id', v_draft.proposed_question_id,
      'content_changed', v_changed,
      'resolved_returned_draft', v_resolving,
      'reason_code', v_draft.content_repair_reason_code,
      'before_question_text', v_draft.question_text,
      'before_options', v_draft.options,
      'admin_note', v_note,
      'previous_repair_revision', v_draft.repair_revision,
      'new_repair_revision', v_draft.repair_revision + 1
    )
  );

  return (select to_jsonb(d) from public.draft_questions d where d.draft_id = p_draft_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Unified repair queue (visual drafts plus content-repair drafts)
-- ---------------------------------------------------------------------------

create or replace function public.list_draft_image_repair_queue(
  p_status text default 'NEEDS_REPAIR',
  p_search text default null,
  p_paper_code text default null,
  p_shift_no integer default null,
  p_section_code text default null,
  p_original_question_no integer default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := upper(coalesce(nullif(btrim(p_status), ''), 'NEEDS_REPAIR'));
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;
  if v_status not in (
    'NEEDS_REPAIR',
    'CONTENT_REPAIR',
    'IMAGE_REPAIR',
    'CONTENT_READY',
    'PENDING',
    'APPROVED',
    'NO_IMAGE_REQUIRED',
    'ALL'
  ) then
    raise exception 'Invalid draft repair status filter.' using errcode = 'P0001';
  end if;

  with base as (
    select
      d.draft_id,
      d.proposed_question_id,
      d.question_text,
      d.correct_answer,
      d.topic_id,
      d.question_type,
      d.exam_year,
      d.exam_date,
      d.shift_no,
      d.paper_code,
      d.original_question_no,
      d.section_code,
      d.subject_id,
      s.subject_name,
      d.source_page,
      d.source_question_id,
      d.review_status,
      d.verification_status,
      d.student_image_review_status,
      d.content_repair_status,
      d.content_repair_reason_code,
      d.content_repair_reason_note,
      d.content_repair_version,
      d.repair_revision,
      d.reviewed_repair_revision,
      d.content_source_confirmed_revision,
      jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) as source_image_count,
      jsonb_array_length(coalesce(d.student_image_refs, '[]'::jsonb)) as student_image_count,
      pending.repair_id as pending_repair_id
    from public.draft_questions d
    join public.subjects s on s.subject_id = d.subject_id
    left join lateral (
      select r.repair_id
      from public.question_image_repairs r
      where r.draft_id = d.draft_id and r.status = 'PENDING'
      order by r.created_at desc
      limit 1
    ) pending on true
    where d.question_status = 'DRAFT'
      and d.published_question_id is null
      and d.review_status not in ('REJECTED', 'PUBLISHED')
  ), filtered as (
    select
      b.*,
      case
        when b.content_repair_status = 'NEEDS_REPAIR' then 'CONTENT_REPAIR'
        when b.pending_repair_id is not null then 'PENDING'
        when b.source_image_count = 0 then 'CONTENT_READY'
        when b.student_image_review_status = 'SAFE_CROP_APPROVED' then 'APPROVED'
        when b.student_image_review_status = 'NO_STUDENT_IMAGE_REQUIRED' then 'NO_IMAGE_REQUIRED'
        else 'NEEDS_REPAIR'
      end as repair_status
    from base b
    where (
        b.source_image_count > 0
        or b.content_repair_status = 'NEEDS_REPAIR'
        or b.content_repair_version > 0
      )
      and (
        nullif(btrim(coalesce(p_search, '')), '') is null
        or b.proposed_question_id ilike '%' || btrim(p_search) || '%'
        or b.question_text ilike '%' || btrim(p_search) || '%'
      )
      and (nullif(btrim(coalesce(p_paper_code, '')), '') is null or b.paper_code = upper(btrim(p_paper_code)))
      and (p_shift_no is null or b.shift_no = p_shift_no)
      and (nullif(btrim(coalesce(p_section_code, '')), '') is null or b.section_code = upper(btrim(p_section_code)))
      and (p_original_question_no is null or b.original_question_no = p_original_question_no)
  ), visible as (
    select *
    from filtered f
    where v_status = 'ALL'
      or (v_status = 'NEEDS_REPAIR' and f.repair_status in ('CONTENT_REPAIR', 'NEEDS_REPAIR'))
      or (v_status = 'CONTENT_REPAIR' and f.content_repair_status = 'NEEDS_REPAIR')
      or (v_status = 'IMAGE_REPAIR' and f.source_image_count > 0 and f.repair_status in ('NEEDS_REPAIR', 'PENDING'))
      or (v_status = 'CONTENT_READY' and f.content_repair_status = 'READY' and f.content_repair_version > 0)
      or f.repair_status = v_status
  ), page_rows as (
    select *
    from visible
    order by exam_date nulls last, shift_no nulls last, original_question_no nulls last, proposed_question_id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'total_candidates', (select count(*) from filtered),
      'needs_repair', (select count(*) from filtered where repair_status in ('CONTENT_REPAIR', 'NEEDS_REPAIR')),
      'content_needs_repair', (select count(*) from filtered where content_repair_status = 'NEEDS_REPAIR'),
      'image_needs_repair', (select count(*) from filtered where source_image_count > 0 and repair_status = 'NEEDS_REPAIR'),
      'pending', (select count(*) from filtered where repair_status = 'PENDING'),
      'approved', (select count(*) from filtered where repair_status = 'APPROVED'),
      'no_image_required', (select count(*) from filtered where repair_status = 'NO_IMAGE_REQUIRED'),
      'content_ready', (select count(*) from filtered where content_repair_status = 'READY' and content_repair_version > 0),
      'content_edited', (select count(*) from filtered where content_repair_version > 0)
    ),
    'total', (select count(*) from visible),
    'limit', v_limit,
    'offset', v_offset,
    'items', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.exam_date nulls last, p.shift_no nulls last, p.original_question_no nulls last, p.proposed_question_id)
      from page_rows p
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Revision-bound Final Review with explicit source/presentation confirmation
-- ---------------------------------------------------------------------------

create or replace function public.review_draft_answer_topic_v2(
  p_draft_id uuid,
  p_expected_repair_revision integer,
  p_correct_answer text,
  p_answer_source text,
  p_explanation text,
  p_topic_id text,
  p_content_confirmation text,
  p_content_review_note text default null,
  p_answer_review_note text default null,
  p_admin_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft public.draft_questions%rowtype;
  v_answer text := upper(nullif(btrim(p_correct_answer), ''));
  v_source text := upper(nullif(btrim(p_answer_source), ''));
  v_topic text := upper(nullif(btrim(p_topic_id), ''));
  v_content_note text := nullif(btrim(p_content_review_note), '');
  v_source_count integer;
  v_content_note_required boolean;
begin
  if v_admin is null or not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  select * into v_draft
  from public.draft_questions
  where draft_id = p_draft_id
  for update;

  if not found then raise exception 'Draft not found.' using errcode = 'P0001'; end if;
  if v_draft.review_status = 'PUBLISHED'
     or v_draft.question_status <> 'DRAFT'
     or v_draft.published_question_id is not null then
    raise exception 'Published drafts cannot be edited.' using errcode = 'P0001';
  end if;
  if p_expected_repair_revision is distinct from v_draft.repair_revision then
    raise exception 'This presentation changed after Final Review loaded. Reload and review the latest revision.' using errcode = 'P0001';
  end if;
  if v_draft.content_repair_status <> 'READY' then
    raise exception 'Complete the requested content repair before Final Review.' using errcode = 'P0001';
  end if;

  if nullif(btrim(v_draft.question_text), '') is null then
    raise exception 'Question text is incomplete. Return the draft to Content Repair.' using errcode = 'P0001';
  end if;
  if coalesce(jsonb_typeof(v_draft.options), '') <> 'object'
     or not (v_draft.options ?& array['A','B','C','D']) then
    raise exception 'Options A, B, C and D are required. Return the draft to Content Repair.' using errcode = 'P0001';
  end if;
  if exists (select 1 from jsonb_each_text(v_draft.options) o where btrim(o.value) = '') then
    raise exception 'An option is blank. Return the draft to Content Repair.' using errcode = 'P0001';
  end if;

  v_source_count := jsonb_array_length(coalesce(v_draft.image_refs, '[]'::jsonb));
  if v_source_count = 0 then
    if v_draft.student_image_review_status <> 'NOT_APPLICABLE' then
      raise exception 'Non-visual draft image state is inconsistent. Repair the draft state before review.' using errcode = 'P0001';
    end if;
  elsif v_draft.student_image_review_status not in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED') then
    raise exception 'Complete Image & Content Repair before Final Review.' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.question_image_repairs r
    where r.draft_id = p_draft_id and r.status = 'PENDING'
  ) then
    raise exception 'Resolve or discard the pending student-image crop before Final Review.' using errcode = 'P0001';
  end if;
  if not public.draft_student_image_ready(p_draft_id) then
    raise exception 'The draft student-image decision is stale or incomplete. Reopen Image & Content Repair before Final Review.' using errcode = 'P0001';
  end if;

  if p_content_confirmation is distinct from 'SOURCE_PRESENTATION_CONFIRMED' then
    raise exception 'Confirm that the complete final question and options match the source/import evidence.' using errcode = 'P0001';
  end if;
  v_content_note_required := v_draft.content_repair_version > 0
    or v_draft.content_repair_reason_code is not null
    or coalesce(v_draft.source_quality::text, 'CLEAR') in ('LOW_RESOLUTION', 'CROPPED', 'DIAGRAM_REVIEW');
  if v_content_note_required and length(coalesce(v_content_note, '')) < 5 then
    raise exception 'Add a short content-verification note for this repaired or flagged source.' using errcode = 'P0001';
  end if;

  if v_answer not in ('A','B','C','D') then
    raise exception 'Choose a verified answer A, B, C or D.' using errcode = 'P0001';
  end if;
  if v_source is null
     or v_source = 'AI_PROPOSED'
     or v_source not in ('OFFICIAL_FINAL_KEY','OFFICIAL_PROVISIONAL_KEY','MANUALLY_VERIFIED','SOURCE_BOOK','ADMIN_CORRECTED') then
    raise exception 'Choose a human-verifiable answer source before approving Final Review.' using errcode = 'P0001';
  end if;
  if nullif(btrim(p_explanation), '') is null then
    raise exception 'A reviewed explanation is required.' using errcode = 'P0001';
  end if;
  if v_draft.question_type = 'PYQ' and v_topic is null then
    raise exception 'Select an approved primary topic before PYQ publication.' using errcode = 'P0001';
  end if;
  if v_topic is not null and not exists (
    select 1 from public.topics
    where topic_id = v_topic and subject_id = v_draft.subject_id and status = 'ACTIVE'
  ) then
    raise exception 'The selected topic does not belong to this subject.' using errcode = 'P0001';
  end if;
  if v_draft.source_quality = 'UNREADABLE' then
    raise exception 'An unreadable source must be corrected before verification.' using errcode = 'P0001';
  end if;
  if v_draft.source_option_anomaly = 'DUPLICATE_OPTIONS_PRINTED'
     and nullif(btrim(v_draft.source_option_anomaly_note), '') is null then
    raise exception 'Document the printed duplicate-option anomaly before Final Review.' using errcode = 'P0001';
  end if;

  update public.draft_questions
  set
    correct_answer = v_answer,
    answer_source = v_source::public.answer_source,
    explanation = btrim(p_explanation),
    topic_id = v_topic,
    topic_resolution_status = case
      when v_topic is null then 'UNRESOLVED'::public.topic_resolution_status
      else 'ADMIN_CONFIRMED'::public.topic_resolution_status
    end,
    verification_status = 'VERIFIED',
    review_status = 'IN_REVIEW',
    answer_review_note = nullif(btrim(p_answer_review_note), ''),
    admin_notes = nullif(btrim(p_admin_notes), ''),
    reviewed_by = v_admin,
    reviewed_at = now(),
    reviewed_repair_revision = repair_revision,
    content_source_confirmed_revision = repair_revision,
    content_source_confirmed_by = v_admin,
    content_source_confirmed_at = now(),
    content_source_review_note = v_content_note,
    updated_at = now()
  where draft_id = p_draft_id;

  if v_draft.import_item_id is not null then
    update public.topic_suggestions
    set
      matched_topic_id = v_topic,
      resolution_status = case
        when v_topic is null then 'UNRESOLVED'::public.topic_resolution_status
        else 'ADMIN_CONFIRMED'::public.topic_resolution_status
      end,
      resolved_by = v_admin,
      resolved_at = now(),
      updated_at = now()
    where import_item_id = v_draft.import_item_id;
  end if;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    'VERIFY_DRAFT_FINAL_PRESENTATION_V2',
    'DRAFT_QUESTION',
    p_draft_id::text,
    jsonb_build_object(
      'correct_answer', v_answer,
      'answer_source', v_source,
      'topic_id', v_topic,
      'previous_answer_source', v_draft.answer_source,
      'repair_revision', v_draft.repair_revision,
      'content_source_confirmed', true,
      'content_review_note', v_content_note
    )
  );

  return (select to_jsonb(d) from public.draft_questions d where d.draft_id = p_draft_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Server-side publication guard and Publish Centre filtering
-- ---------------------------------------------------------------------------

create or replace function public.guard_question_content_integrity()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_draft public.draft_questions%rowtype;
begin
  select * into v_draft
  from public.draft_questions
  where proposed_question_id = new.question_id
    and review_status <> 'PUBLISHED'
  order by updated_at desc
  limit 1;

  if not found then
    raise exception 'Published questions must originate from a reviewed draft.' using errcode = 'P0001';
  end if;
  if v_draft.content_repair_status <> 'READY' then
    raise exception 'Content repair is still required before publication.' using errcode = 'P0001';
  end if;
  if v_draft.content_source_confirmed_revision is null
     or v_draft.content_source_confirmed_revision <> v_draft.repair_revision then
    raise exception 'Final question text/options were not source-confirmed for the current repair revision.' using errcode = 'P0001';
  end if;
  if nullif(btrim(v_draft.question_text), '') is null then
    raise exception 'An incomplete question cannot be published.' using errcode = 'P0001';
  end if;
  if coalesce(jsonb_typeof(v_draft.options), '') <> 'object'
     or not (v_draft.options ?& array['A','B','C','D']) then
    raise exception 'Complete options A, B, C and D before publication.' using errcode = 'P0001';
  end if;
  if exists (select 1 from jsonb_each_text(v_draft.options) o where btrim(o.value) = '') then
    raise exception 'Blank option text blocks publication.' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists questions_content_integrity_before_publish on public.questions;
create trigger questions_content_integrity_before_publish
before insert on public.questions
for each row execute function public.guard_question_content_integrity();

create or replace function public.list_publish_queue(
  p_limit integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  with ready as (
    select d.*
    from public.draft_questions d
    where d.review_status = 'IN_REVIEW'
      and d.question_status = 'DRAFT'
      and d.published_question_id is null
      and d.verification_status = 'VERIFIED'
      and d.reviewed_repair_revision = d.repair_revision
      and d.content_repair_status = 'READY'
      and d.content_source_confirmed_revision = d.repair_revision
      and d.correct_answer is not null
      and d.answer_source is not null
      and d.answer_source <> 'AI_PROPOSED'
      and nullif(btrim(d.explanation), '') is not null
      and nullif(btrim(d.question_text), '') is not null
      and coalesce(jsonb_typeof(d.options), '') = 'object'
      and d.options ?& array['A','B','C','D']
      and not exists (select 1 from jsonb_each_text(d.options) o where btrim(o.value) = '')
      and coalesce(d.source_quality::text, 'CLEAR') <> 'UNREADABLE'
      and (
        (jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) = 0 and d.student_image_review_status = 'NOT_APPLICABLE')
        or
        (jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) > 0 and d.student_image_review_status in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED'))
      )
      and not exists (
        select 1 from public.question_image_repairs r
        where r.draft_id = d.draft_id and r.status = 'PENDING'
      )
      and public.draft_student_image_ready(d.draft_id)
      and (
        d.source_option_anomaly <> 'DUPLICATE_OPTIONS_PRINTED'
        or nullif(btrim(d.source_option_anomaly_note), '') is not null
      )
      and (
        d.question_type <> 'PYQ'
        or (d.topic_id is not null and d.topic_resolution_status in ('MATCHED', 'ADMIN_CONFIRMED'))
      )
  )
  select count(*) into v_total from ready;

  with ready as (
    select d.*
    from public.draft_questions d
    where d.review_status = 'IN_REVIEW'
      and d.question_status = 'DRAFT'
      and d.published_question_id is null
      and d.verification_status = 'VERIFIED'
      and d.reviewed_repair_revision = d.repair_revision
      and d.content_repair_status = 'READY'
      and d.content_source_confirmed_revision = d.repair_revision
      and d.correct_answer is not null
      and d.answer_source is not null
      and d.answer_source <> 'AI_PROPOSED'
      and nullif(btrim(d.explanation), '') is not null
      and nullif(btrim(d.question_text), '') is not null
      and coalesce(jsonb_typeof(d.options), '') = 'object'
      and d.options ?& array['A','B','C','D']
      and not exists (select 1 from jsonb_each_text(d.options) o where btrim(o.value) = '')
      and coalesce(d.source_quality::text, 'CLEAR') <> 'UNREADABLE'
      and (
        (jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) = 0 and d.student_image_review_status = 'NOT_APPLICABLE')
        or
        (jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) > 0 and d.student_image_review_status in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED'))
      )
      and not exists (
        select 1 from public.question_image_repairs r
        where r.draft_id = d.draft_id and r.status = 'PENDING'
      )
      and public.draft_student_image_ready(d.draft_id)
      and (
        d.source_option_anomaly <> 'DUPLICATE_OPTIONS_PRINTED'
        or nullif(btrim(d.source_option_anomaly_note), '') is not null
      )
      and (
        d.question_type <> 'PYQ'
        or (d.topic_id is not null and d.topic_resolution_status in ('MATCHED', 'ADMIN_CONFIRMED'))
      )
  )
  select coalesce(jsonb_agg(row_data order by reviewed_at nulls last, created_at, draft_id), '[]'::jsonb)
  into v_items
  from (
    select jsonb_build_object(
      'draft_id', d.draft_id,
      'proposed_question_id', d.proposed_question_id,
      'question_type', d.question_type,
      'subject_id', d.subject_id,
      'topic_id', d.topic_id,
      'question_text', d.question_text,
      'correct_answer', d.correct_answer,
      'answer_source', d.answer_source,
      'verification_status', d.verification_status,
      'review_status', d.review_status,
      'source_quality', d.source_quality,
      'source_option_anomaly', d.source_option_anomaly,
      'source_option_anomaly_note', d.source_option_anomaly_note,
      'is_supplemental', d.is_supplemental,
      'student_image_review_status', d.student_image_review_status,
      'content_repair_status', d.content_repair_status,
      'content_repair_version', d.content_repair_version,
      'repair_revision', d.repair_revision,
      'reviewed_repair_revision', d.reviewed_repair_revision,
      'content_source_confirmed_revision', d.content_source_confirmed_revision,
      'content_source_review_note', d.content_source_review_note,
      'reviewed_at', d.reviewed_at,
      'created_at', d.created_at
    ) as row_data,
    d.reviewed_at,
    d.created_at,
    d.draft_id
    from ready d
    order by d.reviewed_at nulls last, d.created_at, d.draft_id
    limit v_limit offset v_offset
  ) queue_rows;

  return jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'items', v_items
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Privilege boundary
-- ---------------------------------------------------------------------------

revoke all on function public.clear_draft_content_confirmation_on_revision_change() from public, anon, authenticated;
revoke all on function public.protect_draft_workflow_mutations() from public, anon, authenticated;
revoke all on function public.invalidate_draft_human_review(uuid, boolean) from public, anon, authenticated;
revoke all on function public.guard_question_content_integrity() from public, anon, authenticated;

revoke all on function public.return_draft_to_content_repair(uuid,text,text,integer) from public, anon, authenticated;
revoke all on function public.save_draft_repair_content_v2(uuid,integer,text,jsonb,text) from public, anon, authenticated;
revoke all on function public.reset_draft_repair_content_v2(uuid,integer,text,text) from public, anon, authenticated;
revoke all on function public.review_draft_answer_topic_v2(uuid,integer,text,text,text,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.list_draft_image_repair_queue(text,text,text,integer,text,integer,integer,integer) from public, anon, authenticated;
revoke all on function public.list_publish_queue(integer,integer) from public, anon, authenticated;

-- Disable stale mutation contracts so an older admin bundle fails loudly
-- instead of recording a review without the new integrity confirmation.
revoke all on function public.save_draft_repair_content(uuid,text,jsonb,text) from public, anon, authenticated;
revoke all on function public.reset_draft_repair_content(uuid,text,text) from public, anon, authenticated;
revoke all on function public.review_draft_answer_topic(uuid,text,text,text,text,text,text) from public, anon, authenticated;

grant execute on function public.return_draft_to_content_repair(uuid,text,text,integer) to authenticated;
grant execute on function public.save_draft_repair_content_v2(uuid,integer,text,jsonb,text) to authenticated;
grant execute on function public.reset_draft_repair_content_v2(uuid,integer,text,text) to authenticated;
grant execute on function public.review_draft_answer_topic_v2(uuid,integer,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.list_draft_image_repair_queue(text,text,text,integer,text,integer,integer,integer) to authenticated;
grant execute on function public.list_publish_queue(integer,integer) to authenticated;

comment on function public.return_draft_to_content_repair(uuid,text,text,integer) is
  'Admin-only audited state transition that routes the exact visual or non-visual draft from Final Review into Content Repair.';
comment on function public.save_draft_repair_content_v2(uuid,integer,text,jsonb,text) is
  'Admin-only optimistic content repair. Resolves NEEDS_REPAIR, increments repair_revision and invalidates prior review/confirmation.';
comment on function public.review_draft_answer_topic_v2(uuid,integer,text,text,text,text,text,text,text,text) is
  'Admin-only Final Review of the exact repair revision, requiring explicit source/presentation confirmation before Publish Centre eligibility.';
comment on function public.list_draft_image_repair_queue(text,text,text,integer,text,integer,integer,integer) is
  'Unified admin repair queue for visual-image work and independent content repair, including non-visual drafts.';

commit;
