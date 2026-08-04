-- ScoreMore admin fixed-question test manager
-- Date: 2026-08-04
-- Purpose: atomically create/update a fixed-question-list test through an admin-only RPC.

begin;

create or replace function public.save_fixed_question_test(
  p_test_id text,
  p_test_name text,
  p_board_id text,
  p_exam_id text,
  p_subject_id text,
  p_topic_id text,
  p_test_type public.test_type,
  p_duration_minutes integer,
  p_marks_per_question numeric,
  p_negative_marks numeric,
  p_sort_order integer,
  p_question_ids text[],
  p_publish boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_test_id text := upper(trim(coalesce(p_test_id, '')));
  v_test_name text := trim(coalesce(p_test_name, ''));
  v_board_id text := upper(trim(coalesce(p_board_id, '')));
  v_exam_id text := upper(trim(coalesce(p_exam_id, '')));
  v_subject_id text := nullif(upper(trim(coalesce(p_subject_id, ''))), '');
  v_topic_id text := nullif(upper(trim(coalesce(p_topic_id, ''))), '');
  v_question_ids text[];
  v_question_count integer;
  v_distinct_count integer;
  v_valid_count integer;
  v_is_update boolean;
  v_status public.test_status;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if v_test_id !~ '^[A-Z0-9]+(?:-[A-Z0-9]+)+$' then
    raise exception 'Test ID must contain uppercase letters, numbers and hyphens only.' using errcode = 'P0001';
  end if;

  if v_test_name = '' then
    raise exception 'Test name is required.' using errcode = 'P0001';
  end if;

  if coalesce(p_duration_minutes, -1) < 0 then
    raise exception 'Duration cannot be negative.' using errcode = 'P0001';
  end if;

  if coalesce(p_marks_per_question, 0) <= 0 then
    raise exception 'Marks per question must be greater than zero.' using errcode = 'P0001';
  end if;

  if coalesce(p_negative_marks, -1) < 0 then
    raise exception 'Negative marks cannot be negative.' using errcode = 'P0001';
  end if;

  if p_test_type is null or p_test_type not in (
    'PYQ_FULL'::public.test_type,
    'PYQ_SECTIONAL'::public.test_type,
    'TOPIC_PRACTICE'::public.test_type,
    'FULL_MOCK'::public.test_type,
    'SECTIONAL_MOCK'::public.test_type,
    'DAILY_QUIZ'::public.test_type
  ) then
    raise exception 'This test type is not available in the current admin manager.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.boards
    where board_id = v_board_id and status = 'ACTIVE'
  ) then
    raise exception 'Active board not found.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.exams
    where exam_id = v_exam_id
      and board_id = v_board_id
      and status = 'ACTIVE'
  ) then
    raise exception 'The selected exam does not belong to the selected board.' using errcode = 'P0001';
  end if;

  if v_subject_id is not null and not exists (
    select 1 from public.subjects
    where subject_id = v_subject_id
      and exam_id = v_exam_id
      and status = 'ACTIVE'
  ) then
    raise exception 'The selected subject does not belong to the selected exam.' using errcode = 'P0001';
  end if;

  if v_topic_id is not null then
    if v_subject_id is null then
      raise exception 'Select a subject before selecting a topic.' using errcode = 'P0001';
    end if;

    if not exists (
      select 1 from public.topics
      where topic_id = v_topic_id
        and subject_id = v_subject_id
        and status = 'ACTIVE'
    ) then
      raise exception 'The selected topic does not belong to the selected subject.' using errcode = 'P0001';
    end if;
  end if;

  v_question_ids := array(
    select upper(trim(question_id))
    from unnest(coalesce(p_question_ids, array[]::text[])) as selected(question_id)
    where nullif(trim(question_id), '') is not null
  );

  v_question_count := coalesce(cardinality(v_question_ids), 0);
  if v_question_count = 0 then
    raise exception 'Select at least one published question.' using errcode = 'P0001';
  end if;

  select count(distinct question_id)
  into v_distinct_count
  from unnest(v_question_ids) as selected(question_id);

  if v_distinct_count <> v_question_count then
    raise exception 'The selected question list contains duplicates.' using errcode = 'P0001';
  end if;

  select count(*)
  into v_valid_count
  from unnest(v_question_ids) as selected(question_id)
  join public.questions q on q.question_id = selected.question_id
  where q.question_status = 'PUBLISHED'
    and q.board_id = v_board_id
    and q.exam_id = v_exam_id
    and (v_subject_id is null or q.subject_id = v_subject_id)
    and (v_topic_id is null or q.topic_id = v_topic_id);

  if v_valid_count <> v_question_count then
    raise exception 'One or more selected questions are unpublished or do not match the test catalogue selections.' using errcode = 'P0001';
  end if;

  if p_test_type in ('PYQ_FULL'::public.test_type, 'PYQ_SECTIONAL'::public.test_type)
     and exists (
       select 1
       from unnest(v_question_ids) as selected(question_id)
       join public.questions q on q.question_id = selected.question_id
       where q.question_type <> 'PYQ'
     ) then
    raise exception 'PYQ tests may contain only published PYQ questions.' using errcode = 'P0001';
  end if;

  select exists (select 1 from public.tests where test_id = v_test_id)
  into v_is_update;

  if v_is_update and exists (
    select 1 from public.attempts where test_id = v_test_id
  ) then
    raise exception 'This test already has attempts and is locked from structural changes.' using errcode = 'P0001';
  end if;

  v_status := case
    when coalesce(p_publish, false) then 'PUBLISHED'::public.test_status
    else 'DRAFT'::public.test_status
  end;

  insert into public.tests (
    test_id,
    board_id,
    exam_id,
    subject_id,
    topic_id,
    package_id,
    test_name,
    test_type,
    selection_mode,
    question_count,
    duration_minutes,
    marks_per_question,
    negative_marks,
    status,
    is_free,
    sort_order,
    question_filter,
    created_by
  ) values (
    v_test_id,
    v_board_id,
    v_exam_id,
    v_subject_id,
    v_topic_id,
    null,
    v_test_name,
    p_test_type,
    'FIXED_QUESTION_LIST',
    v_question_count,
    p_duration_minutes,
    p_marks_per_question,
    p_negative_marks,
    v_status,
    true,
    coalesce(p_sort_order, 0),
    '{}'::jsonb,
    v_admin
  )
  on conflict (test_id) do update set
    board_id = excluded.board_id,
    exam_id = excluded.exam_id,
    subject_id = excluded.subject_id,
    topic_id = excluded.topic_id,
    package_id = null,
    test_name = excluded.test_name,
    test_type = excluded.test_type,
    selection_mode = excluded.selection_mode,
    question_count = excluded.question_count,
    duration_minutes = excluded.duration_minutes,
    marks_per_question = excluded.marks_per_question,
    negative_marks = excluded.negative_marks,
    status = excluded.status,
    is_free = true,
    sort_order = excluded.sort_order,
    question_filter = '{}'::jsonb,
    updated_at = now();

  delete from public.test_question_links where test_id = v_test_id;

  insert into public.test_question_links (test_id, question_id, position)
  select v_test_id, selected.question_id, selected.sequence::integer
  from unnest(v_question_ids) with ordinality as selected(question_id, sequence)
  order by selected.sequence;

  insert into public.admin_audit_logs (
    admin_user_id,
    action,
    entity_type,
    entity_id,
    details
  ) values (
    v_admin,
    case when v_is_update then 'UPDATE_TEST' else 'CREATE_TEST' end,
    'TEST',
    v_test_id,
    jsonb_build_object(
      'status', v_status,
      'question_count', v_question_count,
      'selection_mode', 'FIXED_QUESTION_LIST'
    )
  );

  return jsonb_build_object(
    'test_id', v_test_id,
    'status', v_status,
    'question_count', v_question_count,
    'updated', v_is_update
  );
end;
$$;

revoke all on function public.save_fixed_question_test(
  text, text, text, text, text, text, public.test_type,
  integer, numeric, numeric, integer, text[], boolean
) from public, anon;

grant execute on function public.save_fixed_question_test(
  text, text, text, text, text, text, public.test_type,
  integer, numeric, numeric, integer, text[], boolean
) to authenticated;

commit;
