begin;

-- ScoreMore Draft-First Image & Content Repair Workflow v1.0
--
-- New controlled order:
--   Import -> draft image/content repair -> final human review -> Publish Centre.
--
-- Historical published-question image repair remains supported. This migration
-- extends the same audited repair tables so a repair may belong to exactly one
-- active draft OR one published master question.

-- ---------------------------------------------------------------------------
-- 1. Draft repair state and immutable imported-content snapshots
-- ---------------------------------------------------------------------------

alter table public.draft_questions
  add column if not exists imported_question_text text,
  add column if not exists imported_options jsonb,
  add column if not exists student_image_refs jsonb not null default '[]'::jsonb,
  add column if not exists student_image_review_status text not null default 'NOT_APPLICABLE',
  add column if not exists student_image_reviewed_by uuid references public.profiles(user_id),
  add column if not exists student_image_reviewed_at timestamptz,
  add column if not exists student_image_review_note text,
  add column if not exists content_repair_version integer not null default 0,
  add column if not exists content_repaired_by uuid references public.profiles(user_id),
  add column if not exists content_repaired_at timestamptz,
  add column if not exists content_repair_note text,
  add column if not exists repair_revision integer not null default 0,
  add column if not exists reviewed_repair_revision integer;

alter table public.draft_questions
  drop constraint if exists draft_questions_student_image_review_status_check;

alter table public.draft_questions
  add constraint draft_questions_student_image_review_status_check
  check (student_image_review_status in (
    'NOT_APPLICABLE',
    'NEEDS_REVIEW',
    'SAFE_CROP_APPROVED',
    'NO_STUDENT_IMAGE_REQUIRED'
  ));

alter table public.draft_questions
  drop constraint if exists draft_questions_student_image_refs_array_check;

alter table public.draft_questions
  add constraint draft_questions_student_image_refs_array_check
  check (jsonb_typeof(student_image_refs) = 'array');

alter table public.draft_questions
  drop constraint if exists draft_questions_imported_options_object_check;

alter table public.draft_questions
  add constraint draft_questions_imported_options_object_check
  check (imported_options is null or jsonb_typeof(imported_options) = 'object');

alter table public.draft_questions
  drop constraint if exists draft_questions_repair_revision_check;

alter table public.draft_questions
  add constraint draft_questions_repair_revision_check
  check (
    repair_revision >= 0
    and content_repair_version >= 0
    and (reviewed_repair_revision is null or reviewed_repair_revision >= 0)
  );

update public.draft_questions
set
  imported_question_text = coalesce(imported_question_text, question_text),
  imported_options = coalesce(imported_options, options),
  student_image_refs = coalesce(student_image_refs, '[]'::jsonb),
  student_image_review_status = case
    when jsonb_array_length(coalesce(image_refs, '[]'::jsonb)) = 0 then 'NOT_APPLICABLE'
    else 'NEEDS_REVIEW'
  end
where imported_question_text is null
   or imported_options is null
   or student_image_review_status is null;

-- Existing non-visual verified drafts remain valid. Existing visual drafts must
-- pass the new repair-first gate and then be reviewed again.
update public.draft_questions
set reviewed_repair_revision = repair_revision
where question_status = 'DRAFT'
  and review_status = 'IN_REVIEW'
  and verification_status = 'VERIFIED'
  and jsonb_array_length(coalesce(image_refs, '[]'::jsonb)) = 0;

update public.draft_questions
set
  review_status = 'PENDING',
  verification_status = 'NEEDS_CHECK',
  reviewed_by = null,
  reviewed_at = null,
  reviewed_repair_revision = null
where question_status = 'DRAFT'
  and review_status = 'IN_REVIEW'
  and jsonb_array_length(coalesce(image_refs, '[]'::jsonb)) > 0;

create index if not exists draft_questions_repair_queue_idx
  on public.draft_questions(student_image_review_status, review_status, created_at desc)
  where question_status = 'DRAFT';

create index if not exists draft_questions_repair_revision_idx
  on public.draft_questions(repair_revision, reviewed_repair_revision)
  where question_status = 'DRAFT';

-- ---------------------------------------------------------------------------
-- 2. Extend audited image tables to target either draft or published question
-- ---------------------------------------------------------------------------

alter table public.question_image_repairs
  alter column question_id drop not null;

alter table public.question_image_repairs
  add column if not exists draft_id uuid references public.draft_questions(draft_id) on delete cascade;

alter table public.question_image_repairs
  drop constraint if exists question_image_repairs_exactly_one_target_check;

alter table public.question_image_repairs
  add constraint question_image_repairs_exactly_one_target_check
  check (
    (question_id is not null and draft_id is null)
    or (question_id is null and draft_id is not null)
  );

create unique index if not exists question_image_repairs_one_pending_draft_idx
  on public.question_image_repairs(draft_id)
  where draft_id is not null and status = 'PENDING';

create unique index if not exists question_image_repairs_one_approved_draft_idx
  on public.question_image_repairs(draft_id)
  where draft_id is not null and status = 'APPROVED';

create index if not exists question_image_repairs_draft_history_idx
  on public.question_image_repairs(draft_id, created_at desc)
  where draft_id is not null;

alter table public.question_image_review_decisions
  alter column question_id drop not null;

alter table public.question_image_review_decisions
  add column if not exists draft_id uuid references public.draft_questions(draft_id) on delete cascade;

alter table public.question_image_review_decisions
  drop constraint if exists question_image_review_decisions_exactly_one_target_check;

alter table public.question_image_review_decisions
  add constraint question_image_review_decisions_exactly_one_target_check
  check (
    (question_id is not null and draft_id is null)
    or (question_id is null and draft_id is not null)
  );

create unique index if not exists question_image_review_one_current_draft_idx
  on public.question_image_review_decisions(draft_id)
  where draft_id is not null and status = 'CURRENT';

create index if not exists question_image_review_draft_history_idx
  on public.question_image_review_decisions(draft_id, decided_at desc)
  where draft_id is not null;

comment on column public.draft_questions.imported_question_text is
  'Immutable baseline snapshot captured when the draft first enters ScoreMore. Repair edits never overwrite this snapshot.';
comment on column public.draft_questions.imported_options is
  'Immutable baseline option snapshot captured when the draft first enters ScoreMore.';
comment on column public.draft_questions.repair_revision is
  'Monotonic draft presentation revision. Content/image changes invalidate any human review tied to an older revision.';
comment on column public.draft_questions.reviewed_repair_revision is
  'Repair revision explicitly approved by final human review. Publish requires equality with repair_revision.';

-- ---------------------------------------------------------------------------
-- 3. Draft-state helpers and source-change protection
-- ---------------------------------------------------------------------------

create or replace function public.protect_draft_imported_snapshot()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.imported_question_text is distinct from old.imported_question_text
     or new.imported_options is distinct from old.imported_options then
    raise exception 'Imported question text/options are immutable audit snapshots.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists draft_questions_imported_snapshot_guard on public.draft_questions;
create trigger draft_questions_imported_snapshot_guard
before update of imported_question_text, imported_options on public.draft_questions
for each row execute function public.protect_draft_imported_snapshot();

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
    updated_at = now()
  where draft_id = p_draft_id
    and question_status = 'DRAFT'
    and review_status <> 'REJECTED';
end;
$$;

create or replace function public.restore_draft_image_state_from_current_decision(p_draft_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_draft public.draft_questions%rowtype;
  v_decision public.question_image_review_decisions%rowtype;
  v_repair public.question_image_repairs%rowtype;
begin
  select * into v_draft
  from public.draft_questions
  where draft_id = p_draft_id
  for update;

  if not found then return; end if;

  if jsonb_array_length(coalesce(v_draft.image_refs, '[]'::jsonb)) = 0 then
    update public.draft_questions
    set
      student_image_refs = '[]'::jsonb,
      student_image_review_status = 'NOT_APPLICABLE',
      student_image_reviewed_by = null,
      student_image_reviewed_at = null,
      student_image_review_note = null,
      updated_at = now()
    where draft_id = p_draft_id;
    return;
  end if;

  select * into v_decision
  from public.question_image_review_decisions
  where draft_id = p_draft_id and status = 'CURRENT'
  order by decided_at desc
  limit 1;

  if not found then
    update public.draft_questions
    set
      student_image_refs = '[]'::jsonb,
      student_image_review_status = 'NEEDS_REVIEW',
      student_image_reviewed_by = null,
      student_image_reviewed_at = null,
      student_image_review_note = null,
      updated_at = now()
    where draft_id = p_draft_id;
    return;
  end if;

  if v_decision.source_image_fingerprint <> public.student_image_source_fingerprint(v_draft.image_refs) then
    update public.draft_questions
    set
      student_image_refs = '[]'::jsonb,
      student_image_review_status = 'NEEDS_REVIEW',
      student_image_reviewed_by = null,
      student_image_reviewed_at = null,
      student_image_review_note = null,
      updated_at = now()
    where draft_id = p_draft_id;
    return;
  end if;

  if v_decision.decision = 'NO_STUDENT_IMAGE_REQUIRED' then
    update public.draft_questions
    set
      student_image_refs = '[]'::jsonb,
      student_image_review_status = 'NO_STUDENT_IMAGE_REQUIRED',
      student_image_reviewed_by = v_decision.decided_by,
      student_image_reviewed_at = v_decision.decided_at,
      student_image_review_note = v_decision.admin_note,
      updated_at = now()
    where draft_id = p_draft_id;
    return;
  end if;

  select * into v_repair
  from public.question_image_repairs
  where repair_id = v_decision.repair_id
    and draft_id = p_draft_id
    and status = 'APPROVED';

  if not found then
    update public.draft_questions
    set
      student_image_refs = '[]'::jsonb,
      student_image_review_status = 'NEEDS_REVIEW',
      student_image_reviewed_by = null,
      student_image_reviewed_at = null,
      student_image_review_note = null,
      updated_at = now()
    where draft_id = p_draft_id;
    return;
  end if;

  update public.draft_questions
  set
    student_image_refs = jsonb_build_array(jsonb_build_object(
      'repair_id', v_repair.repair_id,
      'bucket', v_repair.storage_bucket,
      'path', v_repair.storage_path,
      'alt', v_repair.alt_text,
      'mime_type', v_repair.mime_type,
      'checksum_sha256', v_repair.checksum_sha256,
      'approved_at', v_repair.approved_at
    )),
    student_image_review_status = 'SAFE_CROP_APPROVED',
    student_image_reviewed_by = v_decision.decided_by,
    student_image_reviewed_at = v_decision.decided_at,
    student_image_review_note = v_decision.admin_note,
    updated_at = now()
  where draft_id = p_draft_id;
end;
$$;

create or replace function public.draft_student_image_ready(p_draft_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select case
      when jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) = 0 then
        d.student_image_review_status = 'NOT_APPLICABLE'
        and jsonb_array_length(coalesce(d.student_image_refs, '[]'::jsonb)) = 0
        and not exists (
          select 1 from public.question_image_repairs pr
          where pr.draft_id = d.draft_id and pr.status = 'PENDING'
        )
      else
        not exists (
          select 1 from public.question_image_repairs pr
          where pr.draft_id = d.draft_id and pr.status = 'PENDING'
        )
        and (
          (
            d.student_image_review_status = 'NO_STUDENT_IMAGE_REQUIRED'
            and jsonb_array_length(coalesce(d.student_image_refs, '[]'::jsonb)) = 0
            and exists (
              select 1
              from public.question_image_review_decisions x
              where x.draft_id = d.draft_id
                and x.status = 'CURRENT'
                and x.decision = 'NO_STUDENT_IMAGE_REQUIRED'
                and x.repair_id is null
                and x.source_image_fingerprint = public.student_image_source_fingerprint(d.image_refs)
            )
          )
          or
          (
            d.student_image_review_status = 'SAFE_CROP_APPROVED'
            and exists (
              select 1
              from public.question_image_review_decisions x
              join public.question_image_repairs r
                on r.repair_id = x.repair_id
               and r.draft_id = d.draft_id
               and r.status = 'APPROVED'
              where x.draft_id = d.draft_id
                and x.status = 'CURRENT'
                and x.decision = 'SAFE_CROP_APPROVED'
                and x.source_image_fingerprint = public.student_image_source_fingerprint(d.image_refs)
                and exists (
                  select 1
                  from jsonb_array_elements(coalesce(d.student_image_refs, '[]'::jsonb)) ref
                  where ref ->> 'repair_id' = r.repair_id::text
                    and ref ->> 'bucket' = r.storage_bucket
                    and ref ->> 'path' = r.storage_path
                )
                and exists (
                  select 1 from storage.objects o
                  where o.bucket_id = r.storage_bucket and o.name = r.storage_path
                )
            )
          )
        )
    end
    from public.draft_questions d
    where d.draft_id = p_draft_id
      and d.question_status = 'DRAFT'
      and d.review_status not in ('REJECTED', 'PUBLISHED')
  ), false);
$$;

create or replace function public.draft_questions_repair_state_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
begin
  if tg_op = 'INSERT' then
    new.imported_question_text := coalesce(new.imported_question_text, new.question_text);
    new.imported_options := coalesce(new.imported_options, new.options);
    new.student_image_refs := coalesce(new.student_image_refs, '[]'::jsonb);
    if jsonb_array_length(coalesce(new.image_refs, '[]'::jsonb)) = 0 then
      new.student_image_review_status := 'NOT_APPLICABLE';
      new.student_image_refs := '[]'::jsonb;
    else
      new.student_image_review_status := 'NEEDS_REVIEW';
      new.student_image_refs := '[]'::jsonb;
    end if;
    new.reviewed_repair_revision := null;
    return new;
  end if;

  if new.image_refs is distinct from old.image_refs then
    update public.question_image_review_decisions
    set status = 'REVOKED', revoked_by = v_admin, revoked_at = now()
    where draft_id = old.draft_id and status = 'CURRENT';

    update public.question_image_repairs
    set status = 'SUPERSEDED', removed_by = v_admin, removed_at = now()
    where draft_id = old.draft_id and status in ('PENDING', 'APPROVED');

    new.repair_revision := old.repair_revision + 1;
    new.review_status := 'PENDING';
    new.verification_status := 'NEEDS_CHECK';
    new.reviewed_by := null;
    new.reviewed_at := null;
    new.reviewed_repair_revision := null;
    new.student_image_refs := '[]'::jsonb;
    new.student_image_reviewed_by := null;
    new.student_image_reviewed_at := null;
    new.student_image_review_note := null;
    new.student_image_review_status := case
      when jsonb_array_length(coalesce(new.image_refs, '[]'::jsonb)) = 0 then 'NOT_APPLICABLE'
      else 'NEEDS_REVIEW'
    end;
  end if;

  return new;
end;
$$;

drop trigger if exists draft_questions_repair_state_guard on public.draft_questions;
create trigger draft_questions_repair_state_guard
before insert or update of image_refs on public.draft_questions
for each row execute function public.draft_questions_repair_state_guard();

create or replace function public.prevent_draft_delete_with_live_student_images()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.question_image_repairs r
    where r.draft_id = old.draft_id
      and r.status in ('PENDING', 'APPROVED')
  ) then
    raise exception 'Discard or remove active student-image repair files before deleting this draft.' using errcode = 'P0001';
  end if;
  return old;
end;
$$;

drop trigger if exists draft_questions_live_image_delete_guard on public.draft_questions;
create trigger draft_questions_live_image_delete_guard
before delete on public.draft_questions
for each row execute function public.prevent_draft_delete_with_live_student_images();

-- ---------------------------------------------------------------------------
-- 4. Draft repair queue and detail RPCs
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
  v_summary jsonb;
  v_items jsonb;
  v_total bigint;
begin
  if not public.is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  if v_status not in ('NEEDS_REPAIR', 'PENDING', 'APPROVED', 'NO_IMAGE_REQUIRED', 'ALL') then
    raise exception 'Invalid draft image-repair status filter.' using errcode = 'P0001';
  end if;

  with filtered as (
    select
      d.draft_id,
      d.proposed_question_id,
      d.question_text,
      d.question_type,
      d.exam_year,
      d.exam_date,
      d.shift_no,
      d.paper_code,
      d.original_question_no,
      d.section_code,
      d.subject_id,
      s.subject_name,
      d.review_status,
      d.verification_status,
      d.student_image_review_status,
      d.content_repair_version,
      d.repair_revision,
      d.reviewed_repair_revision,
      jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) as source_image_count,
      jsonb_array_length(coalesce(d.student_image_refs, '[]'::jsonb)) as student_image_count,
      pending.repair_id as pending_repair_id,
      case
        when pending.repair_id is not null then 'PENDING'
        when d.student_image_review_status = 'SAFE_CROP_APPROVED' then 'APPROVED'
        when d.student_image_review_status = 'NO_STUDENT_IMAGE_REQUIRED' then 'NO_IMAGE_REQUIRED'
        else 'NEEDS_REPAIR'
      end as repair_status
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
      and d.review_status not in ('REJECTED', 'PUBLISHED')
      and jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) > 0
      and (
        nullif(btrim(coalesce(p_search, '')), '') is null
        or d.proposed_question_id ilike '%' || btrim(p_search) || '%'
        or d.question_text ilike '%' || btrim(p_search) || '%'
      )
      and (nullif(btrim(coalesce(p_paper_code, '')), '') is null or d.paper_code = upper(btrim(p_paper_code)))
      and (p_shift_no is null or d.shift_no = p_shift_no)
      and (nullif(btrim(coalesce(p_section_code, '')), '') is null or d.section_code = upper(btrim(p_section_code)))
      and (p_original_question_no is null or d.original_question_no = p_original_question_no)
  )
  select jsonb_build_object(
    'total_candidates', count(*),
    'needs_repair', count(*) filter (where repair_status = 'NEEDS_REPAIR'),
    'pending', count(*) filter (where repair_status = 'PENDING'),
    'approved', count(*) filter (where repair_status = 'APPROVED'),
    'no_image_required', count(*) filter (where repair_status = 'NO_IMAGE_REQUIRED'),
    'content_edited', count(*) filter (where content_repair_version > 0)
  ) into v_summary
  from filtered;

  with filtered as (
    select
      d.draft_id,
      d.proposed_question_id,
      d.question_text,
      d.question_type,
      d.exam_year,
      d.exam_date,
      d.shift_no,
      d.paper_code,
      d.original_question_no,
      d.section_code,
      d.subject_id,
      s.subject_name,
      d.review_status,
      d.verification_status,
      d.student_image_review_status,
      d.content_repair_version,
      d.repair_revision,
      d.reviewed_repair_revision,
      jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) as source_image_count,
      jsonb_array_length(coalesce(d.student_image_refs, '[]'::jsonb)) as student_image_count,
      pending.repair_id as pending_repair_id,
      case
        when pending.repair_id is not null then 'PENDING'
        when d.student_image_review_status = 'SAFE_CROP_APPROVED' then 'APPROVED'
        when d.student_image_review_status = 'NO_STUDENT_IMAGE_REQUIRED' then 'NO_IMAGE_REQUIRED'
        else 'NEEDS_REPAIR'
      end as repair_status
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
      and d.review_status not in ('REJECTED', 'PUBLISHED')
      and jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) > 0
      and (
        nullif(btrim(coalesce(p_search, '')), '') is null
        or d.proposed_question_id ilike '%' || btrim(p_search) || '%'
        or d.question_text ilike '%' || btrim(p_search) || '%'
      )
      and (nullif(btrim(coalesce(p_paper_code, '')), '') is null or d.paper_code = upper(btrim(p_paper_code)))
      and (p_shift_no is null or d.shift_no = p_shift_no)
      and (nullif(btrim(coalesce(p_section_code, '')), '') is null or d.section_code = upper(btrim(p_section_code)))
      and (p_original_question_no is null or d.original_question_no = p_original_question_no)
  ), visible as (
    select * from filtered
    where v_status = 'ALL' or repair_status = v_status
  )
  select count(*) into v_total from visible;

  with filtered as (
    select
      d.draft_id,
      d.proposed_question_id,
      d.question_text,
      d.question_type,
      d.exam_year,
      d.exam_date,
      d.shift_no,
      d.paper_code,
      d.original_question_no,
      d.section_code,
      d.subject_id,
      s.subject_name,
      d.review_status,
      d.verification_status,
      d.student_image_review_status,
      d.content_repair_version,
      d.repair_revision,
      d.reviewed_repair_revision,
      jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) as source_image_count,
      jsonb_array_length(coalesce(d.student_image_refs, '[]'::jsonb)) as student_image_count,
      pending.repair_id as pending_repair_id,
      case
        when pending.repair_id is not null then 'PENDING'
        when d.student_image_review_status = 'SAFE_CROP_APPROVED' then 'APPROVED'
        when d.student_image_review_status = 'NO_STUDENT_IMAGE_REQUIRED' then 'NO_IMAGE_REQUIRED'
        else 'NEEDS_REPAIR'
      end as repair_status
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
      and d.review_status not in ('REJECTED', 'PUBLISHED')
      and jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)) > 0
      and (
        nullif(btrim(coalesce(p_search, '')), '') is null
        or d.proposed_question_id ilike '%' || btrim(p_search) || '%'
        or d.question_text ilike '%' || btrim(p_search) || '%'
      )
      and (nullif(btrim(coalesce(p_paper_code, '')), '') is null or d.paper_code = upper(btrim(p_paper_code)))
      and (p_shift_no is null or d.shift_no = p_shift_no)
      and (nullif(btrim(coalesce(p_section_code, '')), '') is null or d.section_code = upper(btrim(p_section_code)))
      and (p_original_question_no is null or d.original_question_no = p_original_question_no)
  ), visible as (
    select * from filtered
    where v_status = 'ALL' or repair_status = v_status
  )
  select coalesce(jsonb_agg(to_jsonb(v) order by
      v.exam_date nulls last,
      v.shift_no nulls last,
      v.original_question_no nulls last,
      v.proposed_question_id), '[]'::jsonb)
  into v_items
  from (
    select * from visible
    order by exam_date nulls last, shift_no nulls last, original_question_no nulls last, proposed_question_id
    limit v_limit offset v_offset
  ) v;

  return jsonb_build_object(
    'summary', coalesce(v_summary, '{}'::jsonb),
    'total', coalesce(v_total, 0),
    'limit', v_limit,
    'offset', v_offset,
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_draft_image_repair_detail(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  select jsonb_build_object(
    'question', to_jsonb(d) || jsonb_build_object(
      'question_id', d.proposed_question_id,
      'subject_name', s.subject_name,
      'source_image_count', jsonb_array_length(coalesce(d.image_refs, '[]'::jsonb)),
      'student_image_count', jsonb_array_length(coalesce(d.student_image_refs, '[]'::jsonb)),
      'content_edited', d.content_repair_version > 0
    ),
    'repairs', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from public.question_image_repairs r
      where r.draft_id = d.draft_id
    ), '[]'::jsonb),
    'decisions', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.decided_at desc)
      from public.question_image_review_decisions x
      where x.draft_id = d.draft_id
    ), '[]'::jsonb)
  ) into v_result
  from public.draft_questions d
  join public.subjects s on s.subject_id = d.subject_id
  where d.draft_id = p_draft_id
    and d.question_status = 'DRAFT'
    and d.review_status not in ('REJECTED', 'PUBLISHED');

  if v_result is null then
    raise exception 'Active draft not found.' using errcode = 'P0001';
  end if;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Content repair RPCs
-- ---------------------------------------------------------------------------

create or replace function public.save_draft_repair_content(
  p_draft_id uuid,
  p_question_text text,
  p_options jsonb,
  p_admin_note text default null
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
  v_changed boolean;
begin
  if v_admin is null or not public.is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;

  select * into v_draft
  from public.draft_questions
  where draft_id = p_draft_id
  for update;

  if not found or v_draft.question_status <> 'DRAFT' or v_draft.review_status in ('REJECTED', 'PUBLISHED') then
    raise exception 'Active draft not found.' using errcode = 'P0001';
  end if;

  if v_question_text = '' then
    raise exception 'Question text is required.' using errcode = 'P0001';
  end if;

  if jsonb_typeof(p_options) <> 'object'
     or not (p_options ?& array['A','B','C','D']) then
    raise exception 'Options A, B, C and D are required.' using errcode = 'P0001';
  end if;

  v_options := jsonb_build_object(
    'A', btrim(coalesce(p_options ->> 'A', '')),
    'B', btrim(coalesce(p_options ->> 'B', '')),
    'C', btrim(coalesce(p_options ->> 'C', '')),
    'D', btrim(coalesce(p_options ->> 'D', ''))
  );

  if exists (
    select 1 from jsonb_each_text(v_options) o where btrim(o.value) = ''
  ) then
    raise exception 'All four option texts are required.' using errcode = 'P0001';
  end if;

  v_changed := v_question_text is distinct from v_draft.question_text
    or v_options is distinct from v_draft.options;

  if not v_changed then
    return (select to_jsonb(d) from public.draft_questions d where d.draft_id = p_draft_id);
  end if;

  update public.draft_questions
  set
    imported_question_text = coalesce(imported_question_text, v_draft.question_text),
    imported_options = coalesce(imported_options, v_draft.options),
    question_text = v_question_text,
    options = v_options,
    content_repair_version = content_repair_version + 1,
    content_repaired_by = v_admin,
    content_repaired_at = now(),
    content_repair_note = coalesce(nullif(btrim(coalesce(p_admin_note, '')), ''), 'Corrected during Image & Content Repair'),
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
    'EDIT_DRAFT_CONTENT_DURING_REPAIR',
    'DRAFT_QUESTION',
    p_draft_id::text,
    jsonb_build_object(
      'proposed_question_id', v_draft.proposed_question_id,
      'before_question_text', v_draft.question_text,
      'after_question_text', v_question_text,
      'before_options', v_draft.options,
      'after_options', v_options,
      'admin_note', nullif(btrim(coalesce(p_admin_note, '')), '')
    )
  );

  return (select to_jsonb(d) from public.draft_questions d where d.draft_id = p_draft_id);
end;
$$;

create or replace function public.reset_draft_repair_content(
  p_draft_id uuid,
  p_admin_note text default null,
  p_confirmation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft public.draft_questions%rowtype;
begin
  if v_admin is null or not public.is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;
  if p_confirmation <> 'RESET_TO_IMPORTED_CONTENT' then
    raise exception 'Reset confirmation is required.' using errcode = 'P0001';
  end if;

  select * into v_draft
  from public.draft_questions
  where draft_id = p_draft_id
  for update;

  if not found or v_draft.question_status <> 'DRAFT' or v_draft.review_status in ('REJECTED', 'PUBLISHED') then
    raise exception 'Active draft not found.' using errcode = 'P0001';
  end if;
  if v_draft.imported_question_text is null or v_draft.imported_options is null then
    raise exception 'Imported baseline content is unavailable for this draft.' using errcode = 'P0001';
  end if;

  if v_draft.question_text is not distinct from v_draft.imported_question_text
     and v_draft.options is not distinct from v_draft.imported_options then
    return to_jsonb(v_draft);
  end if;

  update public.draft_questions
  set
    question_text = imported_question_text,
    options = imported_options,
    content_repair_version = content_repair_version + 1,
    content_repaired_by = v_admin,
    content_repaired_at = now(),
    content_repair_note = coalesce(nullif(btrim(coalesce(p_admin_note, '')), ''), 'Reset to imported content'),
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
    'RESET_DRAFT_CONTENT_TO_IMPORTED',
    'DRAFT_QUESTION',
    p_draft_id::text,
    jsonb_build_object(
      'proposed_question_id', v_draft.proposed_question_id,
      'before_question_text', v_draft.question_text,
      'before_options', v_draft.options,
      'admin_note', nullif(btrim(coalesce(p_admin_note, '')), '')
    )
  );

  return (select to_jsonb(d) from public.draft_questions d where d.draft_id = p_draft_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Draft image upload / approval / decision RPCs
-- ---------------------------------------------------------------------------

create or replace function public.register_draft_student_image_upload(
  p_draft_id uuid,
  p_storage_path text,
  p_original_file_name text,
  p_mime_type text,
  p_file_size_bytes bigint,
  p_checksum_sha256 text,
  p_pixel_width integer default null,
  p_pixel_height integer default null,
  p_alt_text text default 'Question diagram',
  p_admin_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft public.draft_questions%rowtype;
  v_previous_pending public.question_image_repairs%rowtype;
  v_new public.question_image_repairs%rowtype;
begin
  if v_admin is null or not public.is_admin() then raise exception 'Admin access required.' using errcode = 'P0001'; end if;
  if p_mime_type not in ('image/png', 'image/jpeg', 'image/webp') then raise exception 'Only PNG, JPEG and WebP crops are allowed.' using errcode = 'P0001'; end if;
  if p_file_size_bytes is null or p_file_size_bytes <= 0 or p_file_size_bytes > 5242880 then raise exception 'Student image must be between 1 byte and 5 MB.' using errcode = 'P0001'; end if;
  if lower(btrim(coalesce(p_checksum_sha256, ''))) !~ '^[0-9a-f]{64}$' then raise exception 'A valid SHA-256 checksum is required.' using errcode = 'P0001'; end if;
  if nullif(btrim(coalesce(p_alt_text, '')), '') is null then raise exception 'Student image alt text is required.' using errcode = 'P0001'; end if;
  if p_pixel_width is not null and (p_pixel_width < 1 or p_pixel_width > 8000) then raise exception 'Image width is outside the allowed range.' using errcode = 'P0001'; end if;
  if p_pixel_height is not null and (p_pixel_height < 1 or p_pixel_height > 8000) then raise exception 'Image height is outside the allowed range.' using errcode = 'P0001'; end if;

  select * into v_draft
  from public.draft_questions
  where draft_id = p_draft_id
  for update;

  if not found or v_draft.question_status <> 'DRAFT' or v_draft.review_status in ('REJECTED', 'PUBLISHED') then raise exception 'Active draft not found.' using errcode = 'P0001'; end if;
  if jsonb_array_length(coalesce(v_draft.image_refs, '[]'::jsonb)) = 0 then raise exception 'This draft has no source image requiring repair.' using errcode = 'P0001'; end if;

  if p_storage_path not like v_admin::text || '/draft-' || p_draft_id::text || '/%' then
    raise exception 'Storage path does not match this admin and draft.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'student-question-images' and o.name = p_storage_path
  ) then raise exception 'Uploaded student image object was not found.' using errcode = 'P0001'; end if;

  select * into v_previous_pending
  from public.question_image_repairs r
  where r.draft_id = p_draft_id and r.status = 'PENDING'
  for update;

  if found then
    update public.question_image_repairs
    set status = 'SUPERSEDED', removed_by = v_admin, removed_at = now()
    where repair_id = v_previous_pending.repair_id;
  end if;

  insert into public.question_image_repairs (
    draft_id, question_id, storage_bucket, storage_path, original_file_name, mime_type,
    file_size_bytes, checksum_sha256, pixel_width, pixel_height, alt_text,
    admin_note, status, uploaded_by
  ) values (
    p_draft_id, null, 'student-question-images', p_storage_path, btrim(p_original_file_name), p_mime_type,
    p_file_size_bytes, lower(btrim(p_checksum_sha256)), p_pixel_width, p_pixel_height, btrim(p_alt_text),
    nullif(btrim(coalesce(p_admin_note, '')), ''), 'PENDING', v_admin
  ) returning * into v_new;

  update public.draft_questions
  set
    student_image_refs = '[]'::jsonb,
    student_image_review_status = 'NEEDS_REVIEW',
    student_image_reviewed_by = null,
    student_image_reviewed_at = null,
    student_image_review_note = null,
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
    'REGISTER_DRAFT_STUDENT_IMAGE',
    'DRAFT_IMAGE_REPAIR',
    v_new.repair_id::text,
    jsonb_build_object(
      'draft_id', p_draft_id,
      'proposed_question_id', v_draft.proposed_question_id,
      'storage_path', p_storage_path,
      'checksum_sha256', lower(btrim(p_checksum_sha256)),
      'superseded_pending_repair_id', v_previous_pending.repair_id
    )
  );

  return jsonb_build_object(
    'draft_id', p_draft_id,
    'repair_id', v_new.repair_id,
    'status', v_new.status,
    'storage_bucket', v_new.storage_bucket,
    'storage_path', v_new.storage_path,
    'superseded_storage_path', v_previous_pending.storage_path
  );
end;
$$;

create or replace function public.approve_draft_student_image_repair(
  p_repair_id uuid,
  p_alt_text text,
  p_admin_note text default null,
  p_confirmation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_repair public.question_image_repairs%rowtype;
  v_previous public.question_image_repairs%rowtype;
  v_draft public.draft_questions%rowtype;
  v_source_hash text;
  v_decision_id uuid;
begin
  if v_admin is null or not public.is_admin() then raise exception 'Admin access required.' using errcode = 'P0001'; end if;
  if p_confirmation <> 'APPROVE_DRAFT_STUDENT_IMAGE' then raise exception 'Image approval confirmation is required.' using errcode = 'P0001'; end if;
  if nullif(btrim(coalesce(p_alt_text, '')), '') is null then raise exception 'Student image alt text is required.' using errcode = 'P0001'; end if;

  select * into v_repair
  from public.question_image_repairs
  where repair_id = p_repair_id and draft_id is not null
  for update;
  if not found or v_repair.status <> 'PENDING' then raise exception 'Pending draft student image was not found.' using errcode = 'P0001'; end if;

  select * into v_draft
  from public.draft_questions
  where draft_id = v_repair.draft_id
  for update;
  if not found or v_draft.question_status <> 'DRAFT' or v_draft.review_status in ('REJECTED', 'PUBLISHED') then raise exception 'Active draft not found.' using errcode = 'P0001'; end if;
  if jsonb_array_length(coalesce(v_draft.image_refs, '[]'::jsonb)) = 0 then raise exception 'This draft no longer has a visual source.' using errcode = 'P0001'; end if;

  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = v_repair.storage_bucket and o.name = v_repair.storage_path
  ) then raise exception 'Pending student image object is missing.' using errcode = 'P0001'; end if;

  select * into v_previous
  from public.question_image_repairs r
  where r.draft_id = v_repair.draft_id and r.status = 'APPROVED'
  for update;

  if found then
    update public.question_image_repairs
    set status = 'SUPERSEDED', removed_by = v_admin, removed_at = now()
    where repair_id = v_previous.repair_id;
  end if;

  update public.question_image_review_decisions
  set status = 'SUPERSEDED', revoked_by = v_admin, revoked_at = now()
  where draft_id = v_repair.draft_id and status = 'CURRENT';

  update public.question_image_repairs
  set
    status = 'APPROVED',
    alt_text = btrim(p_alt_text),
    admin_note = nullif(btrim(coalesce(p_admin_note, '')), ''),
    approved_by = v_admin,
    approved_at = now(),
    removed_by = null,
    removed_at = null
  where repair_id = p_repair_id
  returning * into v_repair;

  v_source_hash := public.student_image_source_fingerprint(v_draft.image_refs);

  insert into public.question_image_review_decisions (
    draft_id, question_id, decision, source_image_fingerprint, repair_id,
    admin_note, status, decided_by, decided_at
  ) values (
    v_repair.draft_id, null, 'SAFE_CROP_APPROVED', v_source_hash, v_repair.repair_id,
    coalesce(nullif(btrim(coalesce(p_admin_note, '')), ''), 'Approved safe crop before final human review'),
    'CURRENT', v_admin, now()
  ) returning decision_id into v_decision_id;

  update public.draft_questions
  set
    student_image_refs = jsonb_build_array(jsonb_build_object(
      'repair_id', v_repair.repair_id,
      'bucket', v_repair.storage_bucket,
      'path', v_repair.storage_path,
      'alt', v_repair.alt_text,
      'mime_type', v_repair.mime_type,
      'checksum_sha256', v_repair.checksum_sha256,
      'approved_at', v_repair.approved_at
    )),
    student_image_review_status = 'SAFE_CROP_APPROVED',
    student_image_reviewed_by = v_admin,
    student_image_reviewed_at = v_repair.approved_at,
    student_image_review_note = coalesce(nullif(btrim(coalesce(p_admin_note, '')), ''), 'Approved safe crop before final human review'),
    repair_revision = repair_revision + 1,
    review_status = 'PENDING',
    verification_status = 'NEEDS_CHECK',
    reviewed_by = null,
    reviewed_at = null,
    reviewed_repair_revision = null,
    updated_at = now()
  where draft_id = v_repair.draft_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    case when v_previous.repair_id is null then 'APPROVE_DRAFT_STUDENT_IMAGE' else 'REPLACE_DRAFT_STUDENT_IMAGE' end,
    'DRAFT_QUESTION',
    v_repair.draft_id::text,
    jsonb_build_object(
      'decision_id', v_decision_id,
      'repair_id', v_repair.repair_id,
      'storage_path', v_repair.storage_path,
      'replaced_repair_id', v_previous.repair_id,
      'replaced_storage_path', v_previous.storage_path
    )
  );

  return jsonb_build_object(
    'draft_id', v_repair.draft_id,
    'repair_id', v_repair.repair_id,
    'decision_id', v_decision_id,
    'status', v_repair.status,
    'readiness', 'SAFE_CROP_APPROVED',
    'approved_at', v_repair.approved_at,
    'replaced_storage_path', v_previous.storage_path
  );
end;
$$;

create or replace function public.discard_draft_student_image_upload(
  p_repair_id uuid,
  p_admin_note text default null,
  p_confirmation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_repair public.question_image_repairs%rowtype;
begin
  if v_admin is null or not public.is_admin() then raise exception 'Admin access required.' using errcode = 'P0001'; end if;
  if p_confirmation <> 'DISCARD_DRAFT_STUDENT_IMAGE' then raise exception 'Discard confirmation is required.' using errcode = 'P0001'; end if;

  select * into v_repair
  from public.question_image_repairs
  where repair_id = p_repair_id and draft_id is not null
  for update;
  if not found or v_repair.status <> 'PENDING' then raise exception 'Pending draft student image was not found.' using errcode = 'P0001'; end if;

  update public.question_image_repairs
  set
    status = 'REMOVED',
    admin_note = coalesce(nullif(btrim(coalesce(p_admin_note, '')), ''), admin_note),
    removed_by = v_admin,
    removed_at = now()
  where repair_id = p_repair_id;

  perform public.restore_draft_image_state_from_current_decision(v_repair.draft_id);

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    'DISCARD_DRAFT_STUDENT_IMAGE',
    'DRAFT_IMAGE_REPAIR',
    p_repair_id::text,
    jsonb_build_object('draft_id', v_repair.draft_id, 'storage_path', v_repair.storage_path, 'admin_note', p_admin_note)
  );

  return jsonb_build_object(
    'draft_id', v_repair.draft_id,
    'repair_id', v_repair.repair_id,
    'status', 'REMOVED',
    'storage_path', v_repair.storage_path
  );
end;
$$;

create or replace function public.remove_draft_approved_student_image(
  p_draft_id uuid,
  p_admin_note text default null,
  p_confirmation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft public.draft_questions%rowtype;
  v_repair public.question_image_repairs%rowtype;
  v_decision_id uuid;
begin
  if v_admin is null or not public.is_admin() then raise exception 'Admin access required.' using errcode = 'P0001'; end if;
  if p_confirmation <> 'REMOVE_DRAFT_STUDENT_IMAGE' then raise exception 'Removal confirmation is required.' using errcode = 'P0001'; end if;
  if length(btrim(coalesce(p_admin_note, ''))) < 5 then raise exception 'Add a reason for removing the approved student image.' using errcode = 'P0001'; end if;

  select * into v_draft from public.draft_questions where draft_id = p_draft_id for update;
  if not found or v_draft.question_status <> 'DRAFT' then raise exception 'Active draft not found.' using errcode = 'P0001'; end if;

  select * into v_repair
  from public.question_image_repairs
  where draft_id = p_draft_id and status = 'APPROVED'
  for update;
  if not found then raise exception 'This draft has no approved student image.' using errcode = 'P0001'; end if;

  update public.question_image_repairs
  set status = 'REMOVED', admin_note = btrim(p_admin_note), removed_by = v_admin, removed_at = now()
  where repair_id = v_repair.repair_id;

  update public.question_image_review_decisions
  set status = 'REVOKED', revoked_by = v_admin, revoked_at = now()
  where draft_id = p_draft_id and status = 'CURRENT'
  returning decision_id into v_decision_id;

  update public.draft_questions
  set
    student_image_refs = '[]'::jsonb,
    student_image_review_status = 'NEEDS_REVIEW',
    student_image_reviewed_by = null,
    student_image_reviewed_at = null,
    student_image_review_note = null,
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
    'REMOVE_DRAFT_STUDENT_IMAGE',
    'DRAFT_QUESTION',
    p_draft_id::text,
    jsonb_build_object('decision_id', v_decision_id, 'repair_id', v_repair.repair_id, 'storage_path', v_repair.storage_path, 'admin_note', btrim(p_admin_note))
  );

  return jsonb_build_object(
    'draft_id', p_draft_id,
    'repair_id', v_repair.repair_id,
    'decision_id', v_decision_id,
    'readiness', 'NEEDS_REVIEW',
    'storage_path', v_repair.storage_path
  );
end;
$$;

create or replace function public.mark_draft_student_image_not_required(
  p_draft_id uuid,
  p_admin_note text,
  p_confirmation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft public.draft_questions%rowtype;
  v_previous public.question_image_repairs%rowtype;
  v_source_hash text;
  v_decision_id uuid;
begin
  if v_admin is null or not public.is_admin() then raise exception 'Admin access required.' using errcode = 'P0001'; end if;
  if p_confirmation <> 'NO_DRAFT_STUDENT_IMAGE_REQUIRED' then raise exception 'No-image decision confirmation is required.' using errcode = 'P0001'; end if;
  if length(btrim(coalesce(p_admin_note, ''))) < 10 then raise exception 'Explain why students do not need the source image (minimum 10 characters).' using errcode = 'P0001'; end if;

  select * into v_draft
  from public.draft_questions
  where draft_id = p_draft_id
  for update;
  if not found or v_draft.question_status <> 'DRAFT' or v_draft.review_status in ('REJECTED', 'PUBLISHED') then raise exception 'Active draft not found.' using errcode = 'P0001'; end if;
  if jsonb_array_length(coalesce(v_draft.image_refs, '[]'::jsonb)) = 0 then raise exception 'This draft has no source image requiring a decision.' using errcode = 'P0001'; end if;

  if exists (select 1 from public.question_image_repairs where draft_id = p_draft_id and status = 'PENDING') then
    raise exception 'Discard the pending crop before confirming that no student image is required.' using errcode = 'P0001';
  end if;

  select * into v_previous
  from public.question_image_repairs
  where draft_id = p_draft_id and status = 'APPROVED'
  for update;

  if found then
    update public.question_image_repairs
    set status = 'SUPERSEDED', removed_by = v_admin, removed_at = now()
    where repair_id = v_previous.repair_id;
  end if;

  update public.question_image_review_decisions
  set status = 'SUPERSEDED', revoked_by = v_admin, revoked_at = now()
  where draft_id = p_draft_id and status = 'CURRENT';

  v_source_hash := public.student_image_source_fingerprint(v_draft.image_refs);

  insert into public.question_image_review_decisions (
    draft_id, question_id, decision, source_image_fingerprint, repair_id,
    admin_note, status, decided_by
  ) values (
    p_draft_id, null, 'NO_STUDENT_IMAGE_REQUIRED', v_source_hash, null,
    btrim(p_admin_note), 'CURRENT', v_admin
  ) returning decision_id into v_decision_id;

  update public.draft_questions
  set
    student_image_refs = '[]'::jsonb,
    student_image_review_status = 'NO_STUDENT_IMAGE_REQUIRED',
    student_image_reviewed_by = v_admin,
    student_image_reviewed_at = now(),
    student_image_review_note = btrim(p_admin_note),
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
    'CONFIRM_DRAFT_NO_STUDENT_IMAGE_REQUIRED',
    'DRAFT_QUESTION',
    p_draft_id::text,
    jsonb_build_object(
      'decision_id', v_decision_id,
      'source_image_fingerprint', v_source_hash,
      'admin_note', btrim(p_admin_note),
      'superseded_repair_id', v_previous.repair_id,
      'superseded_storage_path', v_previous.storage_path
    )
  );

  return jsonb_build_object(
    'draft_id', p_draft_id,
    'decision_id', v_decision_id,
    'readiness', 'NO_STUDENT_IMAGE_REQUIRED',
    'storage_path', v_previous.storage_path
  );
end;
$$;

create or replace function public.reopen_draft_student_image_review(
  p_draft_id uuid,
  p_admin_note text,
  p_confirmation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft public.draft_questions%rowtype;
  v_decision public.question_image_review_decisions%rowtype;
  v_repair public.question_image_repairs%rowtype;
begin
  if v_admin is null or not public.is_admin() then raise exception 'Admin access required.' using errcode = 'P0001'; end if;
  if p_confirmation <> 'REOPEN_DRAFT_STUDENT_IMAGE_REVIEW' then raise exception 'Review reopening confirmation is required.' using errcode = 'P0001'; end if;
  if length(btrim(coalesce(p_admin_note, ''))) < 5 then raise exception 'Add a reason for reopening image review.' using errcode = 'P0001'; end if;

  select * into v_draft from public.draft_questions where draft_id = p_draft_id for update;
  if not found or v_draft.question_status <> 'DRAFT' then raise exception 'Active draft not found.' using errcode = 'P0001'; end if;

  select * into v_decision
  from public.question_image_review_decisions
  where draft_id = p_draft_id and status = 'CURRENT'
  for update;
  if not found then raise exception 'No current draft image decision was found.' using errcode = 'P0001'; end if;

  if v_decision.repair_id is not null then
    select * into v_repair from public.question_image_repairs where repair_id = v_decision.repair_id for update;
    if found and v_repair.status = 'APPROVED' then
      update public.question_image_repairs
      set status = 'SUPERSEDED', removed_by = v_admin, removed_at = now()
      where repair_id = v_repair.repair_id;
    end if;
  end if;

  update public.question_image_review_decisions
  set status = 'REVOKED', revoked_by = v_admin, revoked_at = now()
  where decision_id = v_decision.decision_id;

  update public.draft_questions
  set
    student_image_refs = '[]'::jsonb,
    student_image_review_status = 'NEEDS_REVIEW',
    student_image_reviewed_by = null,
    student_image_reviewed_at = null,
    student_image_review_note = null,
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
    'REOPEN_DRAFT_STUDENT_IMAGE_REVIEW',
    'DRAFT_QUESTION',
    p_draft_id::text,
    jsonb_build_object('decision_id', v_decision.decision_id, 'admin_note', btrim(p_admin_note))
  );

  return jsonb_build_object(
    'draft_id', p_draft_id,
    'decision_id', v_decision.decision_id,
    'readiness', 'NEEDS_REVIEW',
    'storage_path', v_repair.storage_path
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Final human review must see/approve the repaired presentation revision
-- ---------------------------------------------------------------------------

create or replace function public.review_draft_answer_topic(
  p_draft_id uuid,
  p_correct_answer text,
  p_answer_source text,
  p_explanation text,
  p_topic_id text,
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
  v_source_count integer;
begin
  if not public.is_admin() then raise exception 'Admin authorization required.' using errcode = 'P0001'; end if;
  select * into v_draft from public.draft_questions where draft_id = p_draft_id for update;
  if not found then raise exception 'Draft not found.' using errcode = 'P0001'; end if;
  if v_draft.review_status = 'PUBLISHED' or v_draft.question_status <> 'DRAFT' then raise exception 'Published drafts cannot be edited.' using errcode = 'P0001'; end if;

  v_source_count := jsonb_array_length(coalesce(v_draft.image_refs, '[]'::jsonb));
  if v_source_count = 0 then
    if v_draft.student_image_review_status <> 'NOT_APPLICABLE' then
      raise exception 'Non-visual draft image state is inconsistent. Repair state before review.' using errcode = 'P0001';
    end if;
  elsif v_draft.student_image_review_status not in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED') then
    raise exception 'Complete Image & Content Repair before final human review.' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.question_image_repairs r
    where r.draft_id = p_draft_id and r.status = 'PENDING'
  ) then
    raise exception 'Resolve or discard the pending student-image crop before final human review.' using errcode = 'P0001';
  end if;
  if not public.draft_student_image_ready(p_draft_id) then
    raise exception 'The draft student-image decision is stale or incomplete. Reopen Image & Content Repair before final review.' using errcode = 'P0001';
  end if;

  if v_answer not in ('A','B','C','D') then raise exception 'Choose a verified answer A, B, C or D.' using errcode = 'P0001'; end if;
  if v_source is null or v_source = 'AI_PROPOSED' or v_source not in ('OFFICIAL_FINAL_KEY','OFFICIAL_PROVISIONAL_KEY','MANUALLY_VERIFIED','SOURCE_BOOK','ADMIN_CORRECTED') then
    raise exception 'Choose a human-verifiable answer source before saving review.' using errcode = 'P0001';
  end if;
  if nullif(btrim(p_explanation), '') is null then raise exception 'A reviewed explanation is required.' using errcode = 'P0001'; end if;
  if v_draft.question_type = 'PYQ' and v_topic is null then raise exception 'Select an approved primary topic before PYQ publication.' using errcode = 'P0001'; end if;
  if v_topic is not null and not exists (select 1 from public.topics where topic_id = v_topic and subject_id = v_draft.subject_id and status = 'ACTIVE') then
    raise exception 'The selected topic does not belong to this subject.' using errcode = 'P0001';
  end if;
  if v_draft.source_quality = 'UNREADABLE' then raise exception 'An unreadable source must be corrected before verification.' using errcode = 'P0001'; end if;

  update public.draft_questions set
    correct_answer = v_answer,
    answer_source = v_source::public.answer_source,
    explanation = btrim(p_explanation),
    topic_id = v_topic,
    topic_resolution_status = case when v_topic is null then 'UNRESOLVED'::public.topic_resolution_status else 'ADMIN_CONFIRMED'::public.topic_resolution_status end,
    verification_status = 'VERIFIED',
    review_status = 'IN_REVIEW',
    answer_review_note = nullif(btrim(p_answer_review_note), ''),
    admin_notes = nullif(btrim(p_admin_notes), ''),
    reviewed_by = v_admin,
    reviewed_at = now(),
    reviewed_repair_revision = repair_revision,
    updated_at = now()
  where draft_id = p_draft_id;

  if v_draft.import_item_id is not null then
    update public.topic_suggestions set
      matched_topic_id = v_topic,
      resolution_status = case when v_topic is null then 'UNRESOLVED'::public.topic_resolution_status else 'ADMIN_CONFIRMED'::public.topic_resolution_status end,
      resolved_by = v_admin,
      resolved_at = now(),
      updated_at = now()
    where import_item_id = v_draft.import_item_id;
  end if;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (v_admin, 'VERIFY_DRAFT_ANSWER_TOPIC', 'DRAFT_QUESTION', p_draft_id::text,
    jsonb_build_object(
      'correct_answer', v_answer,
      'answer_source', v_source,
      'topic_id', v_topic,
      'previous_answer_source', v_draft.answer_source,
      'repair_revision', v_draft.repair_revision
    ));

  return (select to_jsonb(d) from public.draft_questions d where d.draft_id = p_draft_id);
end;
$$;

create or replace function public.guard_question_publication_phase3e()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_draft public.draft_questions%rowtype;
  v_source_count integer;
begin
  select * into v_draft from public.draft_questions
  where proposed_question_id = new.question_id and review_status <> 'PUBLISHED'
  order by updated_at desc limit 1;
  if not found then raise exception 'Published questions must originate from a reviewed draft.' using errcode = 'P0001'; end if;
  if v_draft.review_status <> 'IN_REVIEW' then raise exception 'Final human review must be completed before publication.' using errcode = 'P0001'; end if;
  if v_draft.answer_source is null or v_draft.answer_source = 'AI_PROPOSED' then raise exception 'AI-proposed or missing answers must be human-confirmed before publication.' using errcode = 'P0001'; end if;
  if v_draft.verification_status <> 'VERIFIED' then raise exception 'Save the human answer/topic review before publication.' using errcode = 'P0001'; end if;
  if v_draft.reviewed_repair_revision is null or v_draft.reviewed_repair_revision <> v_draft.repair_revision then
    raise exception 'Draft presentation changed after review. Review the final repaired version again.' using errcode = 'P0001';
  end if;
  if nullif(btrim(v_draft.explanation), '') is null then raise exception 'A reviewed explanation is required before publication.' using errcode = 'P0001'; end if;
  if v_draft.question_type = 'PYQ' and (v_draft.topic_id is null or v_draft.topic_resolution_status not in ('MATCHED','ADMIN_CONFIRMED')) then
    raise exception 'An approved primary topic is required before PYQ publication.' using errcode = 'P0001';
  end if;
  if v_draft.source_quality = 'UNREADABLE' then raise exception 'Unreadable source content cannot be published.' using errcode = 'P0001'; end if;
  if v_draft.is_supplemental and v_draft.question_type <> 'NORMAL' then
    raise exception 'Supplemental generated questions cannot be published as PYQ.' using errcode = 'P0001';
  end if;

  if not public.draft_student_image_ready(v_draft.draft_id) then
    raise exception 'Draft image/content repair state is stale or incomplete. Repair and review the final presentation again.' using errcode = 'P0001';
  end if;

  v_source_count := jsonb_array_length(coalesce(v_draft.image_refs, '[]'::jsonb));
  if v_source_count = 0 then
    if v_draft.student_image_review_status <> 'NOT_APPLICABLE' then
      raise exception 'Non-visual draft image readiness is inconsistent.' using errcode = 'P0001';
    end if;
  else
    if v_draft.student_image_review_status not in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED') then
      raise exception 'Visual draft is not image-ready for publication.' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.question_image_repairs r where r.draft_id = v_draft.draft_id and r.status = 'PENDING') then
      raise exception 'A pending student-image crop blocks publication.' using errcode = 'P0001';
    end if;
    if not exists (
      select 1
      from public.question_image_review_decisions x
      left join public.question_image_repairs r on r.repair_id = x.repair_id
      where x.draft_id = v_draft.draft_id
        and x.status = 'CURRENT'
        and x.source_image_fingerprint = public.student_image_source_fingerprint(v_draft.image_refs)
        and (
          (x.decision = 'NO_STUDENT_IMAGE_REQUIRED' and x.repair_id is null and jsonb_array_length(coalesce(v_draft.student_image_refs, '[]'::jsonb)) = 0)
          or
          (x.decision = 'SAFE_CROP_APPROVED' and r.draft_id = v_draft.draft_id and r.status = 'APPROVED'
            and exists (
              select 1 from jsonb_array_elements(coalesce(v_draft.student_image_refs, '[]'::jsonb)) ref
              where ref ->> 'repair_id' = r.repair_id::text
                and ref ->> 'bucket' = r.storage_bucket
                and ref ->> 'path' = r.storage_path
            )
          )
        )
    ) then
      raise exception 'Visual draft lacks a current audited student-image decision matching its source.' using errcode = 'P0001';
    end if;
  end if;

  -- Preserve the existing Phase 3E publication enrichment. Replacing this
  -- guard must never regress the fields copied from the reviewed draft.
  new.transcription_confidence := v_draft.transcription_confidence;
  new.answer_confidence := v_draft.answer_confidence;
  new.topic_confidence := v_draft.topic_confidence;
  new.source_quality := v_draft.source_quality;
  new.answer_review_note := v_draft.answer_review_note;
  new.suggested_topic_code := v_draft.suggested_topic_code;
  new.suggested_topic_name := v_draft.suggested_topic_name;
  new.topic_resolution_status := v_draft.topic_resolution_status;
  new.is_supplemental := v_draft.is_supplemental;
  new.supplement_reason := v_draft.supplement_reason;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Publish Centre now requires the reviewed repair revision
-- ---------------------------------------------------------------------------

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
  if not public.is_admin() then raise exception 'Admin authorization required.' using errcode = 'P0001'; end if;

  with ready as (
    select d.*
    from public.draft_questions d
    where d.review_status = 'IN_REVIEW'
      and d.question_status = 'DRAFT'
      and d.published_question_id is null
      and d.verification_status = 'VERIFIED'
      and d.reviewed_repair_revision = d.repair_revision
      and d.correct_answer is not null
      and d.answer_source is not null
      and d.answer_source <> 'AI_PROPOSED'
      and nullif(btrim(d.explanation), '') is not null
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
      and d.correct_answer is not null
      and d.answer_source is not null
      and d.answer_source <> 'AI_PROPOSED'
      and nullif(btrim(d.explanation), '') is not null
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
      'content_repair_version', d.content_repair_version,
      'repair_revision', d.repair_revision,
      'reviewed_repair_revision', d.reviewed_repair_revision,
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

  return jsonb_build_object('total', v_total, 'limit', v_limit, 'offset', v_offset, 'items', v_items);
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Atomic promotion of pre-publication repair audit to the master question
-- ---------------------------------------------------------------------------

create or replace function public.promote_draft_image_state_after_question_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_draft public.draft_questions%rowtype;
begin
  select * into v_draft
  from public.draft_questions d
  where d.proposed_question_id = new.question_id
    and d.review_status = 'IN_REVIEW'
    and d.question_status = 'DRAFT'
  order by d.updated_at desc
  limit 1;

  if not found then return new; end if;

  if jsonb_array_length(coalesce(v_draft.image_refs, '[]'::jsonb)) = 0 then
    return new;
  end if;

  -- Publication guard has already required a current audited decision.
  update public.question_image_repairs
  set question_id = new.question_id, draft_id = null
  where draft_id = v_draft.draft_id;

  update public.question_image_review_decisions
  set question_id = new.question_id, draft_id = null
  where draft_id = v_draft.draft_id;

  -- Existing questions_image_readiness_validate rechecks the transferred audit.
  update public.questions
  set
    student_image_refs = v_draft.student_image_refs,
    student_image_review_status = v_draft.student_image_review_status,
    student_image_reviewed_by = v_draft.student_image_reviewed_by,
    student_image_reviewed_at = v_draft.student_image_reviewed_at,
    student_image_review_note = v_draft.student_image_review_note
  where question_id = new.question_id;

  return new;
end;
$$;

drop trigger if exists questions_promote_draft_image_state_after_insert on public.questions;
create trigger questions_promote_draft_image_state_after_insert
after insert on public.questions
for each row execute function public.promote_draft_image_state_after_question_insert();

-- ---------------------------------------------------------------------------
-- 10. Privilege boundary
-- ---------------------------------------------------------------------------

revoke all on function public.protect_draft_imported_snapshot() from public, anon, authenticated;
revoke all on function public.invalidate_draft_human_review(uuid, boolean) from public, anon, authenticated;
revoke all on function public.restore_draft_image_state_from_current_decision(uuid) from public, anon, authenticated;
revoke all on function public.draft_student_image_ready(uuid) from public, anon, authenticated;
revoke all on function public.draft_questions_repair_state_guard() from public, anon, authenticated;
revoke all on function public.prevent_draft_delete_with_live_student_images() from public, anon, authenticated;
revoke all on function public.promote_draft_image_state_after_question_insert() from public, anon, authenticated;

revoke all on function public.list_draft_image_repair_queue(text,text,text,integer,text,integer,integer,integer) from public, anon, authenticated;
revoke all on function public.get_draft_image_repair_detail(uuid) from public, anon, authenticated;
revoke all on function public.save_draft_repair_content(uuid,text,jsonb,text) from public, anon, authenticated;
revoke all on function public.reset_draft_repair_content(uuid,text,text) from public, anon, authenticated;
revoke all on function public.register_draft_student_image_upload(uuid,text,text,text,bigint,text,integer,integer,text,text) from public, anon, authenticated;
revoke all on function public.approve_draft_student_image_repair(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public.discard_draft_student_image_upload(uuid,text,text) from public, anon, authenticated;
revoke all on function public.remove_draft_approved_student_image(uuid,text,text) from public, anon, authenticated;
revoke all on function public.mark_draft_student_image_not_required(uuid,text,text) from public, anon, authenticated;
revoke all on function public.reopen_draft_student_image_review(uuid,text,text) from public, anon, authenticated;
revoke all on function public.review_draft_answer_topic(uuid,text,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.list_publish_queue(integer,integer) from public, anon, authenticated;

grant execute on function public.list_draft_image_repair_queue(text,text,text,integer,text,integer,integer,integer) to authenticated;
grant execute on function public.get_draft_image_repair_detail(uuid) to authenticated;
grant execute on function public.save_draft_repair_content(uuid,text,jsonb,text) to authenticated;
grant execute on function public.reset_draft_repair_content(uuid,text,text) to authenticated;
grant execute on function public.register_draft_student_image_upload(uuid,text,text,text,bigint,text,integer,integer,text,text) to authenticated;
grant execute on function public.approve_draft_student_image_repair(uuid,text,text,text) to authenticated;
grant execute on function public.discard_draft_student_image_upload(uuid,text,text) to authenticated;
grant execute on function public.remove_draft_approved_student_image(uuid,text,text) to authenticated;
grant execute on function public.mark_draft_student_image_not_required(uuid,text,text) to authenticated;
grant execute on function public.reopen_draft_student_image_review(uuid,text,text) to authenticated;
grant execute on function public.review_draft_answer_topic(uuid,text,text,text,text,text,text) to authenticated;
grant execute on function public.list_publish_queue(integer,integer) to authenticated;

comment on function public.list_draft_image_repair_queue(text,text,text,integer,text,integer,integer,integer) is
  'Admin-only repair-first queue for active visual drafts. Final human review is blocked until each visual draft is resolved.';
comment on function public.save_draft_repair_content(uuid,text,jsonb,text) is
  'Admin-only question/option correction during draft repair. Every edit increments repair_revision and invalidates prior human verification.';
comment on function public.promote_draft_image_state_after_question_insert() is
  'Atomically transfers draft image repair audit/history to the published master question inside publish_draft_question().';

commit;
