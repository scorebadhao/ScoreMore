begin;

-- ScoreMore compulsory student-image readiness.
--
-- A published master question may keep raw source captures for admin audit, but
-- it is not student-ready until every visual source has one current audited
-- decision: an approved safe crop or an explicit NO_STUDENT_IMAGE_REQUIRED
-- confirmation. All trusted test-building and attempt paths use the same
-- database readiness predicate.

alter table public.questions
  add column if not exists student_image_review_status text not null default 'NEEDS_REVIEW',
  add column if not exists student_image_reviewed_by uuid references public.profiles(user_id),
  add column if not exists student_image_reviewed_at timestamptz,
  add column if not exists student_image_review_note text;

alter table public.questions
  drop constraint if exists questions_student_image_review_status_check;

alter table public.questions
  add constraint questions_student_image_review_status_check
  check (student_image_review_status in (
    'NOT_APPLICABLE',
    'NEEDS_REVIEW',
    'SAFE_CROP_APPROVED',
    'NO_STUDENT_IMAGE_REQUIRED'
  ));

create table public.question_image_review_decisions (
  decision_id uuid primary key default gen_random_uuid(),
  question_id text not null references public.questions(question_id) on delete cascade,
  decision text not null check (decision in ('SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED')),
  source_image_fingerprint text not null check (source_image_fingerprint ~ '^[0-9a-f]{64}$'),
  repair_id uuid references public.question_image_repairs(repair_id),
  admin_note text not null,
  status text not null default 'CURRENT' check (status in ('CURRENT', 'SUPERSEDED', 'REVOKED')),
  decided_by uuid not null references public.profiles(user_id),
  decided_at timestamptz not null default now(),
  revoked_by uuid references public.profiles(user_id),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint question_image_review_decision_repair_check check (
    (decision = 'SAFE_CROP_APPROVED' and repair_id is not null)
    or (decision = 'NO_STUDENT_IMAGE_REQUIRED' and repair_id is null)
  )
);

create unique index question_image_review_one_current_idx
  on public.question_image_review_decisions(question_id)
  where status = 'CURRENT';

create index question_image_review_history_idx
  on public.question_image_review_decisions(question_id, decided_at desc);

create trigger question_image_review_decisions_set_updated_at
before update on public.question_image_review_decisions
for each row execute function public.set_updated_at();

alter table public.question_image_review_decisions enable row level security;
revoke all on public.question_image_review_decisions from anon, authenticated;

comment on table public.question_image_review_decisions is
  'Immutable-style audited history of the current student-image decision for each visual published question. Direct browser access is denied.';

create or replace function public.student_image_source_fingerprint(p_image_refs jsonb)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(
    extensions.digest(
      convert_to(coalesce(p_image_refs, '[]'::jsonb)::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$$;

revoke all on function public.student_image_source_fingerprint(jsonb) from public, anon, authenticated;

-- Preserve already-audited approved crops from the preceding Image Repair
-- Centre migration. Untracked legacy student_image_refs deliberately remain
-- unresolved and must be reviewed again.
insert into public.question_image_review_decisions (
  question_id,
  decision,
  source_image_fingerprint,
  repair_id,
  admin_note,
  status,
  decided_by,
  decided_at
)
select
  q.question_id,
  'SAFE_CROP_APPROVED',
  public.student_image_source_fingerprint(q.image_refs),
  r.repair_id,
  coalesce(nullif(btrim(r.admin_note), ''), 'Approved through Student-safe Image Repair Centre'),
  'CURRENT',
  r.approved_by,
  r.approved_at
from public.questions q
join public.question_image_repairs r
  on r.question_id = q.question_id
 and r.status = 'APPROVED'
where q.question_status = 'PUBLISHED'
  and jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) > 0
  and r.approved_by is not null
  and r.approved_at is not null
  and exists (
    select 1
    from jsonb_array_elements(coalesce(q.student_image_refs, '[]'::jsonb)) ref
    where ref ->> 'repair_id' = r.repair_id::text
      and ref ->> 'bucket' = r.storage_bucket
      and ref ->> 'path' = r.storage_path
  )
on conflict do nothing;

update public.questions q
set
  student_image_review_status = case
    when jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) = 0
      then 'NOT_APPLICABLE'
    when exists (
      select 1
      from public.question_image_review_decisions d
      where d.question_id = q.question_id
        and d.status = 'CURRENT'
        and d.decision = 'SAFE_CROP_APPROVED'
    ) then 'SAFE_CROP_APPROVED'
    else 'NEEDS_REVIEW'
  end,
  student_image_reviewed_by = (
    select d.decided_by
    from public.question_image_review_decisions d
    where d.question_id = q.question_id and d.status = 'CURRENT'
    limit 1
  ),
  student_image_reviewed_at = (
    select d.decided_at
    from public.question_image_review_decisions d
    where d.question_id = q.question_id and d.status = 'CURRENT'
    limit 1
  ),
  student_image_review_note = (
    select d.admin_note
    from public.question_image_review_decisions d
    where d.question_id = q.question_id and d.status = 'CURRENT'
    limit 1
  ),
  student_image_refs = case
    when jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) = 0 then '[]'::jsonb
    when exists (
      select 1
      from public.question_image_review_decisions d
      where d.question_id = q.question_id
        and d.status = 'CURRENT'
        and d.decision = 'SAFE_CROP_APPROVED'
    ) then q.student_image_refs
    else '[]'::jsonb
  end;

create or replace function public.question_student_image_readiness(p_question_id text)
returns text
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce((
    select case
      when jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) = 0
        then 'NOT_APPLICABLE'
      when q.student_image_review_status = 'SAFE_CROP_APPROVED'
       and exists (
         select 1
         from public.question_image_review_decisions d
         join public.question_image_repairs r
           on r.repair_id = d.repair_id
          and r.question_id = d.question_id
          and r.status = 'APPROVED'
         where d.question_id = q.question_id
           and d.status = 'CURRENT'
           and d.decision = 'SAFE_CROP_APPROVED'
           and d.source_image_fingerprint = public.student_image_source_fingerprint(q.image_refs)
           and exists (
             select 1
             from jsonb_array_elements(coalesce(q.student_image_refs, '[]'::jsonb)) ref
             where ref ->> 'repair_id' = r.repair_id::text
               and ref ->> 'bucket' = r.storage_bucket
               and ref ->> 'path' = r.storage_path
           )
       ) then 'SAFE_CROP_APPROVED'
      when q.student_image_review_status = 'NO_STUDENT_IMAGE_REQUIRED'
       and jsonb_array_length(coalesce(q.student_image_refs, '[]'::jsonb)) = 0
       and exists (
         select 1
         from public.question_image_review_decisions d
         where d.question_id = q.question_id
           and d.status = 'CURRENT'
           and d.decision = 'NO_STUDENT_IMAGE_REQUIRED'
           and d.source_image_fingerprint = public.student_image_source_fingerprint(q.image_refs)
       ) then 'NO_STUDENT_IMAGE_REQUIRED'
      else 'NEEDS_REVIEW'
    end
    from public.questions q
    where q.question_id = upper(btrim(p_question_id))
  ), 'UNKNOWN');
$$;

create or replace function public.question_is_student_ready(p_question_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.question_student_image_readiness(p_question_id) in (
    'NOT_APPLICABLE',
    'SAFE_CROP_APPROVED',
    'NO_STUDENT_IMAGE_REQUIRED'
  );
$$;

revoke all on function public.question_student_image_readiness(text) from public, anon, authenticated;
revoke all on function public.question_is_student_ready(text) from public, anon, authenticated;

create or replace function public.questions_image_source_change_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
begin
  if tg_op = 'UPDATE' and new.image_refs is distinct from old.image_refs then
    update public.question_image_review_decisions
    set status = 'REVOKED', revoked_by = v_admin, revoked_at = now()
    where question_id = new.question_id and status = 'CURRENT';

    update public.question_image_repairs
    set status = 'SUPERSEDED', removed_by = v_admin, removed_at = now()
    where question_id = new.question_id and status = 'APPROVED';
  end if;

  if jsonb_array_length(coalesce(new.image_refs, '[]'::jsonb)) = 0 then
    new.student_image_review_status := 'NOT_APPLICABLE';
  elsif tg_op = 'INSERT' or new.image_refs is distinct from old.image_refs then
    new.student_image_review_status := 'NEEDS_REVIEW';
  end if;

  if tg_op = 'INSERT' or new.image_refs is distinct from old.image_refs then
    new.student_image_refs := '[]'::jsonb;
    new.student_image_reviewed_by := null;
    new.student_image_reviewed_at := null;
    new.student_image_review_note := null;
  end if;

  return new;
end;
$$;

create or replace function public.questions_image_readiness_validate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source_count integer := jsonb_array_length(coalesce(new.image_refs, '[]'::jsonb));
begin
  if v_source_count = 0 then
    if new.student_image_review_status <> 'NOT_APPLICABLE'
       or jsonb_array_length(coalesce(new.student_image_refs, '[]'::jsonb)) > 0 then
      raise exception 'A question without source images must be NOT_APPLICABLE and have no student image references.' using errcode = 'P0001';
    end if;
    return new;
  end if;

  if new.student_image_review_status = 'NEEDS_REVIEW' then
    if jsonb_array_length(coalesce(new.student_image_refs, '[]'::jsonb)) > 0 then
      raise exception 'An unresolved visual question cannot have student image references.' using errcode = 'P0001';
    end if;
    return new;
  end if;

  if new.student_image_review_status = 'SAFE_CROP_APPROVED' then
    if not exists (
      select 1
      from public.question_image_review_decisions d
      join public.question_image_repairs r
        on r.repair_id = d.repair_id
       and r.question_id = d.question_id
       and r.status = 'APPROVED'
      where d.question_id = new.question_id
        and d.status = 'CURRENT'
        and d.decision = 'SAFE_CROP_APPROVED'
        and d.source_image_fingerprint = public.student_image_source_fingerprint(new.image_refs)
        and exists (
          select 1
          from jsonb_array_elements(coalesce(new.student_image_refs, '[]'::jsonb)) ref
          where ref ->> 'repair_id' = r.repair_id::text
            and ref ->> 'bucket' = r.storage_bucket
            and ref ->> 'path' = r.storage_path
        )
    ) then
      raise exception 'SAFE_CROP_APPROVED requires a current audited approved repair matching the source image.' using errcode = 'P0001';
    end if;
    return new;
  end if;

  if new.student_image_review_status = 'NO_STUDENT_IMAGE_REQUIRED' then
    if jsonb_array_length(coalesce(new.student_image_refs, '[]'::jsonb)) > 0
       or not exists (
         select 1
         from public.question_image_review_decisions d
         where d.question_id = new.question_id
           and d.status = 'CURRENT'
           and d.decision = 'NO_STUDENT_IMAGE_REQUIRED'
           and d.source_image_fingerprint = public.student_image_source_fingerprint(new.image_refs)
       ) then
      raise exception 'NO_STUDENT_IMAGE_REQUIRED requires a current audited decision and no student image references.' using errcode = 'P0001';
    end if;
    return new;
  end if;

  raise exception 'Unsupported student image review status.' using errcode = 'P0001';
end;
$$;

drop trigger if exists questions_10_image_source_change on public.questions;
create trigger questions_10_image_source_change
before insert or update of image_refs on public.questions
for each row execute function public.questions_image_source_change_guard();

drop trigger if exists questions_20_image_readiness_validate on public.questions;
create trigger questions_20_image_readiness_validate
before insert or update of image_refs, student_image_refs, student_image_review_status on public.questions
for each row execute function public.questions_image_readiness_validate();

-- The central Phase 4A catalogue filter now exposes only student-ready master
-- questions. All Phase 4A facets, search and server-side select-all use it.
create or replace function public.phase4a_filter_catalogue(
  p_filters jsonb default '{}'::jsonb
)
returns setof public.phase4a_question_package_catalogue
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_package_ids text[] := public.phase4a_text_array(p_filters, 'package_ids');
  v_board_ids text[] := public.phase4a_text_array(p_filters, 'board_ids');
  v_exam_ids text[] := public.phase4a_text_array(p_filters, 'exam_ids');
  v_subject_ids text[] := public.phase4a_text_array(p_filters, 'subject_ids');
  v_topic_ids text[] := public.phase4a_text_array(p_filters, 'topic_ids');
  v_languages text[] := public.phase4a_text_array(p_filters, 'languages');
  v_difficulties text[] := public.phase4a_text_array(p_filters, 'difficulties');
  v_question_types text[] := public.phase4a_text_array(p_filters, 'question_types');
  v_membership_types text[] := public.phase4a_text_array(p_filters, 'membership_types');
  v_section_codes text[] := public.phase4a_text_array(p_filters, 'section_codes');
  v_completeness text[] := public.phase4a_text_array(p_filters, 'completeness_statuses');
  v_exam_years integer[] := public.phase4a_int_array(p_filters, 'exam_years');
  v_shift_nos integer[] := public.phase4a_int_array(p_filters, 'shift_nos');
  v_include_superseded boolean := public.phase4a_bool(p_filters, 'include_superseded', false);
  v_include_supplemental boolean := public.phase4a_bool(p_filters, 'include_supplemental', true);
  v_include_unassigned boolean := public.phase4a_bool(p_filters, 'include_unassigned', true);
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  return query
  select c.*
  from public.phase4a_question_package_catalogue c
  where public.question_is_student_ready(c.question_id)
    and (v_include_superseded or c.is_active_version)
    and (v_include_unassigned or c.package_id is not null)
    and (v_include_supplemental or not c.is_supplemental)
    and (cardinality(v_package_ids) = 0 or c.package_id = any(v_package_ids))
    and (cardinality(v_board_ids) = 0 or c.board_id = any(v_board_ids))
    and (cardinality(v_exam_ids) = 0 or c.exam_id = any(v_exam_ids))
    and (cardinality(v_subject_ids) = 0 or c.subject_id = any(v_subject_ids))
    and (cardinality(v_topic_ids) = 0 or c.topic_id = any(v_topic_ids))
    and (cardinality(v_languages) = 0 or upper(c.language) = any(v_languages))
    and (cardinality(v_difficulties) = 0 or upper(c.difficulty) = any(v_difficulties))
    and (cardinality(v_question_types) = 0 or upper(c.question_type) = any(v_question_types))
    and (cardinality(v_membership_types) = 0 or upper(c.membership_type) = any(v_membership_types))
    and (cardinality(v_section_codes) = 0 or upper(coalesce(c.section_code, '')) = any(v_section_codes))
    and (cardinality(v_completeness) = 0 or upper(coalesce(c.paper_completeness_status, '')) = any(v_completeness))
    and (cardinality(v_exam_years) = 0 or c.exam_year = any(v_exam_years))
    and (cardinality(v_shift_nos) = 0 or c.shift_no = any(v_shift_nos));
end;
$$;

revoke all on function public.phase4a_filter_catalogue(jsonb) from public, anon, authenticated;

create or replace function public.test_is_student_ready(p_test_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_test public.tests%rowtype;
  v_ready_count integer;
  v_filter jsonb;
begin
  select * into v_test from public.tests where test_id = upper(btrim(p_test_id));
  if not found then return false; end if;

  if v_test.selection_mode = 'FIXED_QUESTION_LIST'::public.selection_mode then
    select count(*) into v_ready_count
    from public.test_question_links link
    join public.questions q on q.question_id = link.question_id
    where link.test_id = v_test.test_id
      and q.question_status = 'PUBLISHED'
      and public.question_is_student_ready(q.question_id);
    return v_ready_count = v_test.question_count;
  else
    v_filter := coalesce(v_test.question_filter, '{}'::jsonb);
    select count(*) into v_ready_count
    from public.questions q
    where q.question_status = 'PUBLISHED'
      and public.question_is_student_ready(q.question_id)
      and (v_filter ->> 'question_type' is null or q.question_type::text = v_filter ->> 'question_type')
      and (v_filter ->> 'board_id' is null or q.board_id = v_filter ->> 'board_id')
      and (v_filter ->> 'exam_id' is null or q.exam_id = v_filter ->> 'exam_id')
      and (v_filter ->> 'subject_id' is null or q.subject_id = v_filter ->> 'subject_id')
      and (v_filter ->> 'topic_id' is null or q.topic_id = v_filter ->> 'topic_id')
      and (v_filter ->> 'exam_year' is null or q.exam_year = (v_filter ->> 'exam_year')::integer)
      and (v_filter ->> 'exam_date' is null or q.exam_date = (v_filter ->> 'exam_date')::date)
      and (v_filter ->> 'shift_no' is null or q.shift_no = (v_filter ->> 'shift_no')::integer)
      and (v_filter ->> 'paper_code' is null or q.paper_code = v_filter ->> 'paper_code')
      and (v_filter ->> 'section_code' is null or q.section_code = v_filter ->> 'section_code')
      and (v_filter ->> 'difficulty' is null or q.difficulty = v_filter ->> 'difficulty');
    return v_ready_count >= v_test.question_count;
  end if;
end;
$$;

revoke all on function public.test_is_student_ready(text) from public, anon, authenticated;

create or replace function public.enforce_test_student_image_readiness()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'PUBLISHED'::public.test_status
     and not public.test_is_student_ready(new.test_id) then
    raise exception 'Test publication blocked: every selected visual question must complete Student-safe Image Repair review.' using errcode = 'P0001';
  end if;
  return null;
end;
$$;

drop trigger if exists tests_student_image_readiness_guard on public.tests;
create constraint trigger tests_student_image_readiness_guard
after insert or update on public.tests
deferrable initially deferred
for each row execute function public.enforce_test_student_image_readiness();

create or replace function public.enforce_question_student_ready_link()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.question_is_student_ready(new.question_id) then
    raise exception 'Question % is not student-ready. Complete Student-safe Image Repair review before adding it to a test.', new.question_id using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists test_question_links_student_image_guard on public.test_question_links;
create trigger test_question_links_student_image_guard
before insert or update of question_id on public.test_question_links
for each row execute function public.enforce_question_student_ready_link();

drop trigger if exists attempt_questions_student_image_guard on public.attempt_questions;
create trigger attempt_questions_student_image_guard
before insert or update of question_id on public.attempt_questions
for each row execute function public.enforce_question_student_ready_link();

-- Existing published fixed tests with unresolved visual questions disappear
-- from the student catalogue until the question is approved. Admin policies
-- continue to expose them for repair and management.
drop policy if exists tests_public_read on public.tests;
create policy tests_public_read
on public.tests for select to anon, authenticated
using (
  status = 'PUBLISHED'::public.test_status
  and (select public.test_is_student_ready(test_id))
);

create or replace function public.create_test_attempt(p_test_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_test public.tests%rowtype;
  v_attempt_id uuid;
  v_filter jsonb;
  v_total integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = 'P0001';
  end if;

  select * into v_test
  from public.tests
  where test_id = p_test_id and status = 'PUBLISHED';

  if not found then
    raise exception 'Published test not found.' using errcode = 'P0001';
  end if;

  if not v_test.is_free then
    if v_test.package_id is null or not exists (
      select 1 from public.package_access pa
      where pa.user_id = v_user_id
        and pa.package_id = v_test.package_id
        and pa.access_status = 'ACTIVE'
        and pa.starts_at <= now()
        and (pa.expires_at is null or pa.expires_at > now())
    ) then
      raise exception 'This test requires active package access.' using errcode = 'P0001';
    end if;
  end if;

  select attempt_id into v_attempt_id
  from public.attempts
  where user_id = v_user_id
    and test_id = p_test_id
    and status = 'IN_PROGRESS'
  order by started_at desc
  limit 1;

  if v_attempt_id is not null then
    return jsonb_build_object('attempt_id', v_attempt_id, 'resumed', true);
  end if;

  if not public.test_is_student_ready(v_test.test_id) then
    raise exception 'This test is temporarily unavailable because one or more visual questions still require Student-safe Image Repair review.' using errcode = 'P0001';
  end if;

  insert into public.attempts (user_id, test_id)
  values (v_user_id, p_test_id)
  returning attempt_id into v_attempt_id;

  if v_test.selection_mode = 'FIXED_QUESTION_LIST' then
    insert into public.attempt_questions (attempt_id, question_id, position)
    select v_attempt_id, link.question_id, row_number() over (order by link.position)::integer
    from public.test_question_links link
    join public.questions q on q.question_id = link.question_id
    where link.test_id = p_test_id
      and q.question_status = 'PUBLISHED'
      and public.question_is_student_ready(q.question_id)
    order by link.position
    limit v_test.question_count;
  else
    v_filter := coalesce(v_test.question_filter, '{}'::jsonb);

    if v_test.selection_mode in ('RANDOMIZED', 'PERSONALIZED') then
      insert into public.attempt_questions (attempt_id, question_id, position)
      select v_attempt_id, selected.question_id, selected.position
      from (
        select q.question_id, row_number() over (order by random())::integer as position
        from public.questions q
        where q.question_status = 'PUBLISHED'
          and public.question_is_student_ready(q.question_id)
          and (v_filter ->> 'question_type' is null or q.question_type::text = v_filter ->> 'question_type')
          and (v_filter ->> 'board_id' is null or q.board_id = v_filter ->> 'board_id')
          and (v_filter ->> 'exam_id' is null or q.exam_id = v_filter ->> 'exam_id')
          and (v_filter ->> 'subject_id' is null or q.subject_id = v_filter ->> 'subject_id')
          and (v_filter ->> 'topic_id' is null or q.topic_id = v_filter ->> 'topic_id')
          and (v_filter ->> 'exam_year' is null or q.exam_year = (v_filter ->> 'exam_year')::integer)
          and (v_filter ->> 'exam_date' is null or q.exam_date = (v_filter ->> 'exam_date')::date)
          and (v_filter ->> 'shift_no' is null or q.shift_no = (v_filter ->> 'shift_no')::integer)
          and (v_filter ->> 'paper_code' is null or q.paper_code = v_filter ->> 'paper_code')
          and (v_filter ->> 'section_code' is null or q.section_code = v_filter ->> 'section_code')
          and (v_filter ->> 'difficulty' is null or q.difficulty = v_filter ->> 'difficulty')
        limit v_test.question_count
      ) selected;
    else
      insert into public.attempt_questions (attempt_id, question_id, position)
      select v_attempt_id, selected.question_id, selected.position
      from (
        select q.question_id,
               row_number() over (
                 order by coalesce(q.original_question_no, q.sort_order, 2147483647), q.question_id
               )::integer as position
        from public.questions q
        where q.question_status = 'PUBLISHED'
          and public.question_is_student_ready(q.question_id)
          and (v_filter ->> 'question_type' is null or q.question_type::text = v_filter ->> 'question_type')
          and (v_filter ->> 'board_id' is null or q.board_id = v_filter ->> 'board_id')
          and (v_filter ->> 'exam_id' is null or q.exam_id = v_filter ->> 'exam_id')
          and (v_filter ->> 'subject_id' is null or q.subject_id = v_filter ->> 'subject_id')
          and (v_filter ->> 'topic_id' is null or q.topic_id = v_filter ->> 'topic_id')
          and (v_filter ->> 'exam_year' is null or q.exam_year = (v_filter ->> 'exam_year')::integer)
          and (v_filter ->> 'exam_date' is null or q.exam_date = (v_filter ->> 'exam_date')::date)
          and (v_filter ->> 'shift_no' is null or q.shift_no = (v_filter ->> 'shift_no')::integer)
          and (v_filter ->> 'paper_code' is null or q.paper_code = v_filter ->> 'paper_code')
          and (v_filter ->> 'section_code' is null or q.section_code = v_filter ->> 'section_code')
          and (v_filter ->> 'difficulty' is null or q.difficulty = v_filter ->> 'difficulty')
        limit v_test.question_count
      ) selected;
    end if;
  end if;

  select count(*) into v_total from public.attempt_questions where attempt_id = v_attempt_id;
  if v_total <> v_test.question_count then
    raise exception 'Test start blocked: only % of % required questions are student-ready.', v_total, v_test.question_count using errcode = 'P0001';
  end if;

  update public.attempts set total_questions = v_total where attempt_id = v_attempt_id;
  return jsonb_build_object('attempt_id', v_attempt_id, 'resumed', false, 'total_questions', v_total);
end;
$$;

create or replace function public.get_attempt_questions(
  p_attempt_id uuid,
  p_offset integer default 0,
  p_limit integer default 10
)
returns table (
  "position" integer,
  question_id text,
  subject_id text,
  subject_name text,
  section_code text,
  difficulty text,
  question_text text,
  options jsonb,
  image_refs jsonb,
  selected_answer text,
  marked_review boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_attempt public.attempts%rowtype;
  v_duration integer;
  v_deadline timestamptz;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = 'P0001';
  end if;

  select a.* into v_attempt
  from public.attempts a
  where a.attempt_id = p_attempt_id and a.user_id = v_user_id;

  if not found then
    raise exception 'Attempt not found or access denied.' using errcode = 'P0001';
  end if;

  select duration_minutes into v_duration from public.tests where test_id = v_attempt.test_id;
  if v_attempt.status <> 'IN_PROGRESS'::public.attempt_status then return; end if;

  v_deadline := case
    when v_duration > 0 then v_attempt.started_at + make_interval(mins => v_duration)
    else null
  end;

  if v_deadline is not null and now() >= v_deadline then
    perform public.finalize_attempt_internal(p_attempt_id, 'AUTO_SUBMITTED'::public.attempt_status);
    return;
  end if;

  return query
  select aq.position,
         q.question_id,
         q.subject_id,
         s.subject_name,
         q.section_code,
         q.difficulty,
         q.question_text,
         q.options,
         case public.question_student_image_readiness(q.question_id)
           when 'SAFE_CROP_APPROVED' then q.student_image_refs
           when 'NO_STUDENT_IMAGE_REQUIRED' then '[]'::jsonb
           when 'NOT_APPLICABLE' then '[]'::jsonb
           else jsonb_build_array(jsonb_build_object('blocked', true))
         end,
         aa.selected_answer,
         coalesce(aa.marked_review, false)
  from public.attempt_questions aq
  join public.questions q on q.question_id = aq.question_id
  join public.subjects s on s.subject_id = q.subject_id
  left join public.attempt_answers aa
    on aa.attempt_id = aq.attempt_id and aa.question_id = aq.question_id
  where aq.attempt_id = p_attempt_id
  order by aq.position
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 10), 1), 50);
end;
$$;

create or replace view public.student_image_repair_queue_state as
select
  q.question_id,
  q.question_text,
  q.question_type,
  q.exam_year,
  q.exam_date,
  q.shift_no,
  q.paper_code,
  q.original_question_no,
  q.section_code,
  q.subject_id,
  s.subject_name,
  jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) as source_image_count,
  jsonb_array_length(coalesce(q.student_image_refs, '[]'::jsonb)) as student_image_count,
  pending.repair_id as pending_repair_id,
  approved.repair_id as approved_repair_id,
  q.student_image_reviewed_at as approved_at,
  q.student_image_review_status,
  case
    when pending.repair_id is not null then 'PENDING'
    when public.question_student_image_readiness(q.question_id) = 'SAFE_CROP_APPROVED' then 'APPROVED'
    when public.question_student_image_readiness(q.question_id) = 'NO_STUDENT_IMAGE_REQUIRED' then 'NO_IMAGE_REQUIRED'
    else 'NEEDS_REPAIR'
  end as repair_status
from public.questions q
join public.subjects s on s.subject_id = q.subject_id
left join lateral (
  select r.repair_id
  from public.question_image_repairs r
  where r.question_id = q.question_id and r.status = 'PENDING'
  order by r.created_at desc limit 1
) pending on true
left join lateral (
  select r.repair_id
  from public.question_image_repairs r
  where r.question_id = q.question_id and r.status = 'APPROVED'
  order by r.approved_at desc nulls last limit 1
) approved on true
where q.question_status = 'PUBLISHED'
  and jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) > 0;

revoke all on table public.student_image_repair_queue_state from public, anon, authenticated;

create or replace function public.list_student_image_repair_queue(
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
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin access required.' using errcode = 'P0001';
  end if;
  if v_status not in ('NEEDS_REPAIR', 'PENDING', 'APPROVED', 'NO_IMAGE_REQUIRED', 'ALL') then
    raise exception 'Invalid image-repair status filter.' using errcode = 'P0001';
  end if;

  with matching as materialized (
    select *
    from public.student_image_repair_queue_state q
    where (
        nullif(btrim(coalesce(p_search, '')), '') is null
        or q.question_id ilike '%' || btrim(p_search) || '%'
        or q.question_text ilike '%' || btrim(p_search) || '%'
      )
      and (nullif(btrim(coalesce(p_paper_code, '')), '') is null or q.paper_code = upper(btrim(p_paper_code)))
      and (p_shift_no is null or q.shift_no = p_shift_no)
      and (nullif(btrim(coalesce(p_section_code, '')), '') is null or q.section_code = upper(btrim(p_section_code)))
      and (p_original_question_no is null or q.original_question_no = p_original_question_no)
  ), filtered as materialized (
    select * from matching where v_status = 'ALL' or repair_status = v_status
  ), page_rows as (
    select * from filtered
    order by
      case repair_status when 'NEEDS_REPAIR' then 1 when 'PENDING' then 2 when 'APPROVED' then 3 else 4 end,
      exam_date desc nulls last,
      shift_no nulls last,
      original_question_no nulls last,
      question_id
    offset greatest(coalesce(p_offset, 0), 0)
    limit least(greatest(coalesce(p_limit, 20), 1), 100)
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'total_candidates', (select count(*) from matching),
      'needs_repair', (select count(*) from matching where repair_status = 'NEEDS_REPAIR'),
      'pending', (select count(*) from matching where repair_status = 'PENDING'),
      'approved', (select count(*) from matching where repair_status = 'APPROVED'),
      'no_image_required', (select count(*) from matching where repair_status = 'NO_IMAGE_REQUIRED')
    ),
    'total', (select count(*) from filtered),
    'limit', least(greatest(coalesce(p_limit, 20), 1), 100),
    'offset', greatest(coalesce(p_offset, 0), 0),
    'items', coalesce((select jsonb_agg(to_jsonb(page_rows)) from page_rows), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.get_student_image_repair_detail(p_question_id text)
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
    'question', jsonb_build_object(
      'question_id', q.question_id,
      'question_type', q.question_type,
      'question_text', q.question_text,
      'options', q.options,
      'exam_year', q.exam_year,
      'exam_date', q.exam_date,
      'shift_no', q.shift_no,
      'paper_code', q.paper_code,
      'original_question_no', q.original_question_no,
      'section_code', q.section_code,
      'subject_id', q.subject_id,
      'subject_name', s.subject_name,
      'source_page', q.source_page,
      'image_refs', q.image_refs,
      'student_image_refs', q.student_image_refs,
      'student_image_review_status', public.question_student_image_readiness(q.question_id),
      'student_image_reviewed_by', q.student_image_reviewed_by,
      'student_image_reviewed_at', q.student_image_reviewed_at,
      'student_image_review_note', q.student_image_review_note
    ),
    'repairs', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from public.question_image_repairs r where r.question_id = q.question_id
    ), '[]'::jsonb),
    'decisions', coalesce((
      select jsonb_agg(to_jsonb(d) order by d.decided_at desc)
      from public.question_image_review_decisions d where d.question_id = q.question_id
    ), '[]'::jsonb)
  ) into v_result
  from public.questions q
  join public.subjects s on s.subject_id = q.subject_id
  where q.question_id = upper(btrim(p_question_id))
    and q.question_status = 'PUBLISHED';

  if v_result is null then
    raise exception 'Published question not found.' using errcode = 'P0001';
  end if;
  return v_result;
end;
$$;

create or replace function public.approve_student_image_repair(
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
  v_source_hash text;
  v_decision_id uuid;
begin
  if v_admin is null or not public.is_admin() then raise exception 'Admin access required.' using errcode = 'P0001'; end if;
  if p_confirmation <> 'APPROVE_STUDENT_IMAGE' then raise exception 'Image approval confirmation is required.' using errcode = 'P0001'; end if;
  if nullif(btrim(coalesce(p_alt_text, '')), '') is null then raise exception 'Student image alt text is required.' using errcode = 'P0001'; end if;

  select * into v_repair from public.question_image_repairs where repair_id = p_repair_id for update;
  if not found or v_repair.status <> 'PENDING' then raise exception 'Pending student image was not found.' using errcode = 'P0001'; end if;

  select public.student_image_source_fingerprint(q.image_refs) into v_source_hash
  from public.questions q
  where q.question_id = v_repair.question_id
    and q.question_status = 'PUBLISHED'
    and jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) > 0
  for update;
  if not found then raise exception 'Published visual question not found.' using errcode = 'P0001'; end if;

  if not exists (select 1 from storage.objects o where o.bucket_id = v_repair.storage_bucket and o.name = v_repair.storage_path) then
    raise exception 'Pending student image object is missing.' using errcode = 'P0001';
  end if;

  select * into v_previous
  from public.question_image_repairs r
  where r.question_id = v_repair.question_id and r.status = 'APPROVED'
  for update;

  if found then
    update public.question_image_repairs
    set status = 'SUPERSEDED', removed_by = v_admin, removed_at = now()
    where repair_id = v_previous.repair_id;
  end if;

  update public.question_image_review_decisions
  set status = 'SUPERSEDED', revoked_by = v_admin, revoked_at = now()
  where question_id = v_repair.question_id and status = 'CURRENT';

  update public.question_image_repairs
  set status = 'APPROVED',
      alt_text = btrim(p_alt_text),
      admin_note = nullif(btrim(coalesce(p_admin_note, '')), ''),
      approved_by = v_admin,
      approved_at = now(),
      removed_by = null,
      removed_at = null
  where repair_id = p_repair_id
  returning * into v_repair;

  insert into public.question_image_review_decisions (
    question_id, decision, source_image_fingerprint, repair_id,
    admin_note, status, decided_by, decided_at
  ) values (
    v_repair.question_id, 'SAFE_CROP_APPROVED', v_source_hash, v_repair.repair_id,
    coalesce(nullif(btrim(coalesce(p_admin_note, '')), ''), 'Approved safe crop'),
    'CURRENT', v_admin, v_repair.approved_at
  ) returning decision_id into v_decision_id;

  update public.questions
  set student_image_refs = jsonb_build_array(jsonb_build_object(
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
      student_image_review_note = coalesce(nullif(btrim(coalesce(p_admin_note, '')), ''), 'Approved safe crop')
  where question_id = v_repair.question_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    case when v_previous.repair_id is null then 'APPROVE_STUDENT_IMAGE' else 'REPLACE_STUDENT_IMAGE' end,
    'QUESTION',
    v_repair.question_id,
    jsonb_build_object(
      'decision_id', v_decision_id,
      'repair_id', v_repair.repair_id,
      'storage_path', v_repair.storage_path,
      'source_image_fingerprint', v_source_hash,
      'replaced_repair_id', v_previous.repair_id,
      'replaced_storage_path', v_previous.storage_path,
      'admin_note', nullif(btrim(coalesce(p_admin_note, '')), '')
    )
  );

  return jsonb_build_object(
    'question_id', v_repair.question_id,
    'repair_id', v_repair.repair_id,
    'decision_id', v_decision_id,
    'status', v_repair.status,
    'readiness', 'SAFE_CROP_APPROVED',
    'approved_at', v_repair.approved_at,
    'replaced_storage_path', v_previous.storage_path
  );
end;
$$;

create or replace function public.mark_student_image_not_required(
  p_question_id text,
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
  v_question public.questions%rowtype;
  v_previous public.question_image_repairs%rowtype;
  v_source_hash text;
  v_decision_id uuid;
begin
  if v_admin is null or not public.is_admin() then raise exception 'Admin access required.' using errcode = 'P0001'; end if;
  if p_confirmation <> 'NO_STUDENT_IMAGE_REQUIRED' then raise exception 'No-image decision confirmation is required.' using errcode = 'P0001'; end if;
  if length(btrim(coalesce(p_admin_note, ''))) < 10 then
    raise exception 'Explain why the source image is audit evidence and not required by students (minimum 10 characters).' using errcode = 'P0001';
  end if;

  select * into v_question
  from public.questions
  where question_id = upper(btrim(p_question_id)) and question_status = 'PUBLISHED'
  for update;
  if not found or jsonb_array_length(coalesce(v_question.image_refs, '[]'::jsonb)) = 0 then
    raise exception 'Published visual question not found.' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.question_image_repairs
    where question_id = v_question.question_id and status = 'PENDING'
  ) then
    raise exception 'Discard the pending crop before confirming that no student image is required.' using errcode = 'P0001';
  end if;

  select * into v_previous
  from public.question_image_repairs
  where question_id = v_question.question_id and status = 'APPROVED'
  for update;

  if found then
    update public.question_image_repairs
    set status = 'SUPERSEDED', removed_by = v_admin, removed_at = now()
    where repair_id = v_previous.repair_id;
  end if;

  update public.question_image_review_decisions
  set status = 'SUPERSEDED', revoked_by = v_admin, revoked_at = now()
  where question_id = v_question.question_id and status = 'CURRENT';

  v_source_hash := public.student_image_source_fingerprint(v_question.image_refs);
  insert into public.question_image_review_decisions (
    question_id, decision, source_image_fingerprint, repair_id,
    admin_note, status, decided_by
  ) values (
    v_question.question_id, 'NO_STUDENT_IMAGE_REQUIRED', v_source_hash, null,
    btrim(p_admin_note), 'CURRENT', v_admin
  ) returning decision_id into v_decision_id;

  update public.questions
  set student_image_refs = '[]'::jsonb,
      student_image_review_status = 'NO_STUDENT_IMAGE_REQUIRED',
      student_image_reviewed_by = v_admin,
      student_image_reviewed_at = now(),
      student_image_review_note = btrim(p_admin_note)
  where question_id = v_question.question_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin, 'CONFIRM_NO_STUDENT_IMAGE_REQUIRED', 'QUESTION', v_question.question_id,
    jsonb_build_object(
      'decision_id', v_decision_id,
      'source_image_fingerprint', v_source_hash,
      'admin_note', btrim(p_admin_note),
      'superseded_repair_id', v_previous.repair_id,
      'superseded_storage_path', v_previous.storage_path
    )
  );

  return jsonb_build_object(
    'question_id', v_question.question_id,
    'decision_id', v_decision_id,
    'readiness', 'NO_STUDENT_IMAGE_REQUIRED',
    'storage_path', v_previous.storage_path
  );
end;
$$;

create or replace function public.reopen_student_image_review(
  p_question_id text,
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
  v_question public.questions%rowtype;
  v_decision_id uuid;
begin
  if v_admin is null or not public.is_admin() then raise exception 'Admin access required.' using errcode = 'P0001'; end if;
  if p_confirmation <> 'REOPEN_STUDENT_IMAGE_REVIEW' then raise exception 'Review reopening confirmation is required.' using errcode = 'P0001'; end if;
  if length(btrim(coalesce(p_admin_note, ''))) < 5 then raise exception 'Add a reason for reopening image review.' using errcode = 'P0001'; end if;

  select * into v_question
  from public.questions
  where question_id = upper(btrim(p_question_id)) and question_status = 'PUBLISHED'
  for update;
  if not found or public.question_student_image_readiness(v_question.question_id) <> 'NO_STUDENT_IMAGE_REQUIRED' then
    raise exception 'A current no-student-image decision was not found.' using errcode = 'P0001';
  end if;

  update public.question_image_review_decisions
  set status = 'REVOKED', revoked_by = v_admin, revoked_at = now()
  where question_id = v_question.question_id and status = 'CURRENT'
  returning decision_id into v_decision_id;

  update public.questions
  set student_image_refs = '[]'::jsonb,
      student_image_review_status = 'NEEDS_REVIEW',
      student_image_reviewed_by = null,
      student_image_reviewed_at = null,
      student_image_review_note = null
  where question_id = v_question.question_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin, 'REOPEN_STUDENT_IMAGE_REVIEW', 'QUESTION', v_question.question_id,
    jsonb_build_object('decision_id', v_decision_id, 'admin_note', btrim(p_admin_note))
  );

  return jsonb_build_object(
    'question_id', v_question.question_id,
    'decision_id', v_decision_id,
    'readiness', 'NEEDS_REVIEW'
  );
end;
$$;

create or replace function public.remove_approved_student_image(
  p_question_id text,
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
  v_question public.questions%rowtype;
  v_repair public.question_image_repairs%rowtype;
  v_decision_id uuid;
begin
  if v_admin is null or not public.is_admin() then raise exception 'Admin access required.' using errcode = 'P0001'; end if;
  if p_confirmation <> 'REMOVE_STUDENT_IMAGE' then raise exception 'Removal confirmation is required.' using errcode = 'P0001'; end if;
  if length(btrim(coalesce(p_admin_note, ''))) < 5 then raise exception 'Add a reason for removing the approved student image.' using errcode = 'P0001'; end if;

  select * into v_question
  from public.questions
  where question_id = upper(btrim(p_question_id)) and question_status = 'PUBLISHED'
  for update;
  if not found then raise exception 'Published question not found.' using errcode = 'P0001'; end if;

  select * into v_repair
  from public.question_image_repairs
  where question_id = v_question.question_id and status = 'APPROVED'
  for update;
  if not found or public.question_student_image_readiness(v_question.question_id) <> 'SAFE_CROP_APPROVED' then
    raise exception 'This question has no current approved student image.' using errcode = 'P0001';
  end if;

  update public.question_image_repairs
  set status = 'REMOVED', admin_note = btrim(p_admin_note), removed_by = v_admin, removed_at = now()
  where repair_id = v_repair.repair_id;

  update public.question_image_review_decisions
  set status = 'REVOKED', revoked_by = v_admin, revoked_at = now()
  where question_id = v_question.question_id and status = 'CURRENT'
  returning decision_id into v_decision_id;

  update public.questions
  set student_image_refs = '[]'::jsonb,
      student_image_review_status = 'NEEDS_REVIEW',
      student_image_reviewed_by = null,
      student_image_reviewed_at = null,
      student_image_review_note = null
  where question_id = v_question.question_id;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin, 'REMOVE_STUDENT_IMAGE', 'QUESTION', v_question.question_id,
    jsonb_build_object(
      'decision_id', v_decision_id,
      'repair_id', v_repair.repair_id,
      'storage_path', v_repair.storage_path,
      'admin_note', btrim(p_admin_note)
    )
  );

  return jsonb_build_object(
    'question_id', v_question.question_id,
    'repair_id', v_repair.repair_id,
    'decision_id', v_decision_id,
    'readiness', 'NEEDS_REVIEW',
    'storage_path', v_repair.storage_path
  );
end;
$$;

create or replace function public.get_public_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'published_questions', (
      select count(*) from public.questions q
      where q.question_status = 'PUBLISHED' and public.question_is_student_ready(q.question_id)
    ),
    'pyq_papers', (
      select count(distinct concat_ws('|', q.exam_id, q.exam_year, q.exam_date, q.shift_no, q.paper_code))
      from public.questions q
      where q.question_type = 'PYQ'
        and q.question_status = 'PUBLISHED'
        and public.question_is_student_ready(q.question_id)
    ),
    'published_tests', (
      select count(*) from public.tests t
      where t.status = 'PUBLISHED' and public.test_is_student_ready(t.test_id)
    ),
    'student_attempts', (
      select count(*) from public.attempts where status in ('SUBMITTED', 'AUTO_SUBMITTED')
    )
  );
$$;

revoke all on function public.create_test_attempt(text) from public, anon;
revoke all on function public.get_attempt_questions(uuid,integer,integer) from public, anon;
revoke all on function public.list_student_image_repair_queue(text,text,text,integer,text,integer,integer,integer) from public, anon, authenticated;
revoke all on function public.get_student_image_repair_detail(text) from public, anon, authenticated;
revoke all on function public.approve_student_image_repair(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public.mark_student_image_not_required(text,text,text) from public, anon, authenticated;
revoke all on function public.reopen_student_image_review(text,text,text) from public, anon, authenticated;
revoke all on function public.remove_approved_student_image(text,text,text) from public, anon, authenticated;

grant execute on function public.create_test_attempt(text) to authenticated;
grant execute on function public.get_attempt_questions(uuid,integer,integer) to authenticated;
grant execute on function public.test_is_student_ready(text) to anon, authenticated;
grant execute on function public.list_student_image_repair_queue(text,text,text,integer,text,integer,integer,integer) to authenticated;
grant execute on function public.get_student_image_repair_detail(text) to authenticated;
grant execute on function public.approve_student_image_repair(uuid,text,text,text) to authenticated;
grant execute on function public.mark_student_image_not_required(text,text,text) to authenticated;
grant execute on function public.reopen_student_image_review(text,text,text) to authenticated;
grant execute on function public.remove_approved_student_image(text,text,text) to authenticated;

comment on function public.question_is_student_ready(text) is
  'Authoritative readiness predicate used by builders, publication guards, catalogue policies and new-attempt materialization.';
comment on function public.mark_student_image_not_required(text,text,text) is
  'Admin-only audited decision that a raw source image is verification evidence and students require no image.';
comment on function public.reopen_student_image_review(text,text,text) is
  'Admin-only audited revocation of a NO_STUDENT_IMAGE_REQUIRED decision.';

commit;
