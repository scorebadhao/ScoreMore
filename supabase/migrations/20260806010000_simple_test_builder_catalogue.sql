-- ScoreMore simple Test Builder + Catalogue Control
-- Adds paper-aware fixed-test saving and safe admin status changes.

begin;

create or replace function public.save_fixed_question_test_v2(
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
  p_publish boolean,
  p_exam_year integer default null,
  p_exam_date date default null,
  p_shift_no integer default null,
  p_paper_code text default null,
  p_section_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_test_id text := upper(trim(coalesce(p_test_id, '')));
  v_paper_code text := nullif(upper(trim(coalesce(p_paper_code, ''))), '');
  v_section_code text := nullif(upper(trim(coalesce(p_section_code, ''))), '');
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if p_exam_year is not null and (p_exam_year < 1900 or p_exam_year > 2200) then
    raise exception 'Exam year is outside the supported range.' using errcode = 'P0001';
  end if;

  if p_shift_no is not null and p_shift_no < 1 then
    raise exception 'Shift number must be greater than zero.' using errcode = 'P0001';
  end if;

  if p_test_type in ('PYQ_FULL'::public.test_type, 'PYQ_SECTIONAL'::public.test_type) then
    if p_exam_year is null then
      raise exception 'Exam year is required for a PYQ test.' using errcode = 'P0001';
    end if;
    if p_shift_no is null then
      raise exception 'Shift number is required for a PYQ test.' using errcode = 'P0001';
    end if;
    if v_paper_code is null then
      raise exception 'Paper code is required for a PYQ test.' using errcode = 'P0001';
    end if;
  end if;

  if p_test_type in (
    'PYQ_SECTIONAL'::public.test_type,
    'SECTIONAL_MOCK'::public.test_type,
    'TOPIC_PRACTICE'::public.test_type
  ) and nullif(upper(trim(coalesce(p_subject_id, ''))), '') is null then
    raise exception 'Subject is required for this test type.' using errcode = 'P0001';
  end if;

  v_result := public.save_fixed_question_test(
    p_test_id,
    p_test_name,
    p_board_id,
    p_exam_id,
    p_subject_id,
    p_topic_id,
    p_test_type,
    p_duration_minutes,
    p_marks_per_question,
    p_negative_marks,
    p_sort_order,
    p_question_ids,
    p_publish
  );

  update public.tests
  set
    exam_year = p_exam_year,
    exam_date = p_exam_date,
    shift_no = p_shift_no,
    paper_code = v_paper_code,
    section_code = v_section_code,
    updated_at = now()
  where test_id = v_test_id;

  return v_result || jsonb_build_object(
    'exam_year', p_exam_year,
    'exam_date', p_exam_date,
    'shift_no', p_shift_no,
    'paper_code', v_paper_code,
    'section_code', v_section_code
  );
end;
$$;

revoke all on function public.save_fixed_question_test_v2(
  text, text, text, text, text, text, public.test_type,
  integer, numeric, numeric, integer, text[], boolean,
  integer, date, integer, text, text
) from public, anon;

grant execute on function public.save_fixed_question_test_v2(
  text, text, text, text, text, text, public.test_type,
  integer, numeric, numeric, integer, text[], boolean,
  integer, date, integer, text, text
) to authenticated;

create or replace function public.set_admin_test_status(
  p_test_id text,
  p_status public.test_status
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_test_id text := upper(trim(coalesce(p_test_id, '')));
  v_test public.tests%rowtype;
  v_link_count integer;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if p_status not in (
    'DRAFT'::public.test_status,
    'PUBLISHED'::public.test_status,
    'ARCHIVED'::public.test_status
  ) then
    raise exception 'Unsupported test status.' using errcode = 'P0001';
  end if;

  select * into v_test
  from public.tests
  where test_id = v_test_id
  for update;

  if not found then
    raise exception 'Test not found.' using errcode = 'P0001';
  end if;

  if p_status = 'PUBLISHED'::public.test_status then
    select count(*) into v_link_count
    from public.test_question_links link
    join public.questions q on q.question_id = link.question_id
    where link.test_id = v_test_id
      and q.question_status = 'PUBLISHED';

    if v_link_count = 0 or v_link_count <> v_test.question_count then
      raise exception 'The test cannot be published because its published question links are incomplete.' using errcode = 'P0001';
    end if;
  end if;

  update public.tests
  set status = p_status, updated_at = now()
  where test_id = v_test_id;

  insert into public.admin_audit_logs (
    admin_user_id,
    action,
    entity_type,
    entity_id,
    details
  ) values (
    v_admin,
    'CHANGE_TEST_STATUS',
    'TEST',
    v_test_id,
    jsonb_build_object('from', v_test.status, 'to', p_status)
  );

  return jsonb_build_object(
    'test_id', v_test_id,
    'previous_status', v_test.status,
    'status', p_status
  );
end;
$$;

revoke all on function public.set_admin_test_status(text, public.test_status) from public, anon;
grant execute on function public.set_admin_test_status(text, public.test_status) to authenticated;

commit;
