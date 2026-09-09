begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Most published questions do not contain source images. The previous helper
-- called question_is_student_ready() for every linked question, which caused a
-- second primary-key lookup even though an image-free question is always
-- NOT_APPLICABLE under the locked readiness rules. Preserve the same result
-- while reserving the deeper image-safety check for questions that have images.
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
  select * into v_test
  from public.tests
  where test_id = upper(btrim(p_test_id));

  if not found then
    return false;
  end if;

  if v_test.selection_mode = 'FIXED_QUESTION_LIST'::public.selection_mode then
    select count(*) into v_ready_count
    from public.test_question_links link
    join public.questions q on q.question_id = link.question_id
    where link.test_id = v_test.test_id
      and q.question_status = 'PUBLISHED'
      and case
        when jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) = 0 then true
        else public.question_is_student_ready(q.question_id)
      end;

    return v_ready_count = v_test.question_count;
  end if;

  v_filter := coalesce(v_test.question_filter, '{}'::jsonb);
  select count(*) into v_ready_count
  from public.questions q
  where q.question_status = 'PUBLISHED'
    and case
      when jsonb_array_length(coalesce(q.image_refs, '[]'::jsonb)) = 0 then true
      else public.question_is_student_ready(q.question_id)
    end
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
end;
$$;

create or replace function public.get_admin_analytics_v1(
  p_start_date date default ((now() at time zone 'Asia/Kolkata')::date - 29),
  p_end_date date default (now() at time zone 'Asia/Kolkata')::date,
  p_exam_id text default null,
  p_test_type public.test_type default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_from timestamptz;
  v_to timestamptz;
  v_exam_id text := nullif(btrim(coalesce(p_exam_id, '')), '');
  v_result jsonb;
  v_task_inbox jsonb;
begin
  if (select auth.uid()) is null or not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Choose a valid analytics date range.' using errcode = 'P0001';
  end if;
  if (p_end_date - p_start_date) > 365 then
    raise exception 'Analytics ranges cannot exceed 366 days.' using errcode = 'P0001';
  end if;
  if v_exam_id is not null and not exists (
    select 1 from public.exams e where e.exam_id = v_exam_id
  ) then
    raise exception 'Selected exam was not found.' using errcode = 'P0001';
  end if;

  v_from := p_start_date::timestamp at time zone 'Asia/Kolkata';
  v_to := (p_end_date + 1)::timestamp at time zone 'Asia/Kolkata';
  v_task_inbox := public.get_admin_task_inbox();

  with scoped_tests_base as materialized (
    select
      t.test_id,
      t.test_name,
      t.test_type,
      t.exam_id,
      t.status,
      t.selection_mode,
      t.question_count,
      t.marks_per_question
    from public.tests t
    where (v_exam_id is null or t.exam_id = v_exam_id)
      and (p_test_type is null or t.test_type = p_test_type)
  ), fixed_link_stats as materialized (
    select
      link.test_id,
      count(*)::integer as linked_count
    from public.test_question_links link
    join scoped_tests_base t on t.test_id = link.test_id
    where t.selection_mode = 'FIXED_QUESTION_LIST'
    group by link.test_id
  ), scoped_tests as materialized (
    select
      t.*,
      coalesce(stats.linked_count, 0) as linked_count,
      public.test_is_student_ready(t.test_id) as student_ready
    from scoped_tests_base t
    left join fixed_link_stats stats on stats.test_id = t.test_id
  ), scoped_attempts as materialized (
    select
      a.attempt_id,
      a.user_id,
      a.test_id,
      a.status,
      a.score,
      case
        when a.total_questions > 0 and t.marks_per_question > 0
          then 100.0 * a.score / (a.total_questions * t.marks_per_question)
        else null
      end as score_percentage,
      a.accuracy,
      a.time_taken_seconds,
      a.started_at,
      a.submitted_at,
      t.test_type,
      t.exam_id
    from public.attempts a
    join scoped_tests_base t on t.test_id = a.test_id
    where a.started_at >= v_from
      and a.started_at < v_to
  ), submitted_attempts as materialized (
    select *
    from scoped_attempts
    where status in ('SUBMITTED', 'AUTO_SUBMITTED')
  ), ready_tests as materialized (
    select t.test_id
    from scoped_tests t
    where t.status = 'PUBLISHED'
      and t.student_ready
  ), trend_days as (
    select generated_day::date as day
    from generate_series(p_start_date, p_end_date, interval '1 day') generated_day
  ), trend as (
    select
      d.day,
      count(a.attempt_id) as starts,
      count(a.attempt_id) filter (where a.status in ('SUBMITTED', 'AUTO_SUBMITTED')) as submissions,
      count(distinct a.user_id) as active_students
    from trend_days d
    left join scoped_attempts a
      on (a.started_at at time zone 'Asia/Kolkata')::date = d.day
    group by d.day
    order by d.day
  ), type_distribution as (
    select
      a.test_type,
      count(*) as starts,
      count(*) filter (where a.status in ('SUBMITTED', 'AUTO_SUBMITTED')) as submissions
    from scoped_attempts a
    group by a.test_type
    order by count(*) desc, a.test_type
  )
  select jsonb_build_object(
    'generated_at', current_timestamp,
    'timezone', 'Asia/Kolkata',
    'period', jsonb_build_object(
      'start_date', p_start_date,
      'end_date', p_end_date,
      'exam_id', v_exam_id,
      'test_type', p_test_type
    ),
    'overview', jsonb_build_object(
      'registered_students', (
        select count(*) from public.profiles p
        where p.role = 'STUDENT' and p.status = 'ACTIVE'
      ),
      'new_students', (
        select count(*) from public.profiles p
        where p.role = 'STUDENT'
          and p.status = 'ACTIVE'
          and p.created_at >= v_from
          and p.created_at < v_to
      ),
      'active_students', (select count(distinct user_id) from scoped_attempts),
      'test_starts', (select count(*) from scoped_attempts),
      'submitted_attempts', (select count(*) from submitted_attempts),
      'completion_rate', coalesce((
        select round(100.0 * count(*) filter (where status in ('SUBMITTED', 'AUTO_SUBMITTED')) / nullif(count(*), 0), 1)
        from scoped_attempts
      ), 0),
      'average_score', coalesce((select round(avg(score_percentage), 2) from submitted_attempts), 0),
      'average_accuracy', coalesce((select round(avg(accuracy), 1) from submitted_attempts), 0),
      'average_time_seconds', coalesce((select round(avg(time_taken_seconds)) from submitted_attempts), 0),
      'repeat_attempts', (
        select count(*)
        from scoped_attempts current_attempt
        where exists (
          select 1
          from public.attempts earlier
          where earlier.user_id = current_attempt.user_id
            and earlier.test_id = current_attempt.test_id
            and earlier.started_at < current_attempt.started_at
        )
      ),
      'published_tests', (select count(*) from ready_tests)
    ),
    'trend', coalesce((
      select jsonb_agg(jsonb_build_object(
        'date', day,
        'starts', starts,
        'submissions', submissions,
        'active_students', active_students
      ) order by day)
      from trend
    ), '[]'::jsonb),
    'test_type_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'test_type', test_type,
        'starts', starts,
        'submissions', submissions
      ) order by starts desc, test_type)
      from type_distribution
    ), '[]'::jsonb),
    'content_health', jsonb_build_object(
      'published_ready', (select count(*) from ready_tests),
      'published_not_ready', (
        select count(*) from scoped_tests t
        where t.status = 'PUBLISHED' and not t.student_ready
      ),
      'draft_tests', (
        select count(*) from scoped_tests t where t.status = 'DRAFT'
      ),
      'archived_tests', (
        select count(*) from scoped_tests t where t.status = 'ARCHIVED'
      ),
      'zero_question_links', (
        select count(*)
        from scoped_tests t
        where t.status <> 'ARCHIVED'
          and t.selection_mode = 'FIXED_QUESTION_LIST'
          and t.linked_count = 0
      ),
      'question_count_mismatch', (
        select count(*)
        from scoped_tests t
        where t.status <> 'ARCHIVED'
          and t.selection_mode = 'FIXED_QUESTION_LIST'
          and t.question_count <> t.linked_count
      ),
      'taxonomy_review', (
        select count(*)
        from scoped_tests t
        where t.status <> 'ARCHIVED'
          and (
            (upper(t.test_name) like '%PYQ%' and t.test_type not in ('PYQ_FULL', 'PYQ_SECTIONAL'))
            or
            (upper(t.test_name) like '%MOCK%' and t.test_type not in ('FULL_MOCK', 'SECTIONAL_MOCK'))
          )
      ),
      'task_inbox', jsonb_build_object(
        'draft_repairs', jsonb_build_object(
          'count', coalesce((v_task_inbox #>> '{draft_repairs,count}')::bigint, 0)
        ),
        'published_image_safety', jsonb_build_object(
          'count', coalesce((v_task_inbox #>> '{published_image_safety,count}')::bigint, 0)
        ),
        'final_reviews', jsonb_build_object(
          'count', coalesce((v_task_inbox #>> '{final_reviews,count}')::bigint, 0)
        ),
        'ready_to_publish', jsonb_build_object(
          'count', coalesce((v_task_inbox #>> '{ready_to_publish,count}')::bigint, 0)
        )
      )
    )
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.list_admin_test_analytics_v1(
  p_start_date date default ((now() at time zone 'Asia/Kolkata')::date - 29),
  p_end_date date default (now() at time zone 'Asia/Kolkata')::date,
  p_exam_id text default null,
  p_test_type public.test_type default null,
  p_offset integer default 0,
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_from timestamptz;
  v_to timestamptz;
  v_exam_id text := nullif(btrim(coalesce(p_exam_id, '')), '');
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_result jsonb;
begin
  if (select auth.uid()) is null or not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Choose a valid analytics date range.' using errcode = 'P0001';
  end if;
  if (p_end_date - p_start_date) > 365 then
    raise exception 'Analytics ranges cannot exceed 366 days.' using errcode = 'P0001';
  end if;
  if v_exam_id is not null and not exists (
    select 1 from public.exams e where e.exam_id = v_exam_id
  ) then
    raise exception 'Selected exam was not found.' using errcode = 'P0001';
  end if;

  v_from := p_start_date::timestamp at time zone 'Asia/Kolkata';
  v_to := (p_end_date + 1)::timestamp at time zone 'Asia/Kolkata';

  with scoped_tests_base as materialized (
    select
      t.test_id,
      t.test_name,
      t.test_type,
      t.exam_id,
      t.selection_mode,
      t.question_count,
      t.marks_per_question
    from public.tests t
    where t.status = 'PUBLISHED'
      and (v_exam_id is null or t.exam_id = v_exam_id)
      and (p_test_type is null or t.test_type = p_test_type)
  ), eligible_tests as materialized (
    select
      t.test_id,
      t.test_name,
      t.test_type,
      t.exam_id,
      t.marks_per_question,
      e.exam_name
    from scoped_tests_base t
    join public.exams e on e.exam_id = t.exam_id
    where public.test_is_student_ready(t.test_id)
  ), scoped_attempts as materialized (
    select
      a.attempt_id,
      a.test_id,
      a.status,
      a.score,
      a.total_questions,
      a.accuracy,
      a.started_at
    from public.attempts a
    join eligible_tests t on t.test_id = a.test_id
    where a.started_at >= v_from and a.started_at < v_to
  ), test_rows as materialized (
    select
      t.test_id,
      t.test_name,
      t.test_type,
      t.exam_id,
      t.exam_name,
      count(a.attempt_id) as starts,
      count(a.attempt_id) filter (where a.status in ('SUBMITTED', 'AUTO_SUBMITTED')) as submissions,
      coalesce(round(
        100.0 * count(a.attempt_id) filter (where a.status in ('SUBMITTED', 'AUTO_SUBMITTED'))
        / nullif(count(a.attempt_id), 0),
        1
      ), 0) as completion_rate,
      coalesce(round(avg(
        100.0 * a.score / nullif(a.total_questions * t.marks_per_question, 0)
      ) filter (where a.status in ('SUBMITTED', 'AUTO_SUBMITTED')), 2), 0) as average_score,
      coalesce(round(avg(a.accuracy) filter (where a.status in ('SUBMITTED', 'AUTO_SUBMITTED')), 1), 0) as average_accuracy,
      max(a.started_at) as last_started_at
    from eligible_tests t
    left join scoped_attempts a on a.test_id = t.test_id
    group by t.test_id, t.test_name, t.test_type, t.exam_id, t.exam_name, t.marks_per_question
  ), paged as (
    select *
    from test_rows
    order by starts desc, test_name, test_id
    offset v_offset
    limit v_limit
  )
  select jsonb_build_object(
    'total', (select count(*) from test_rows),
    'offset', v_offset,
    'limit', v_limit,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'test_id', test_id,
        'test_name', test_name,
        'test_type', test_type,
        'exam_id', exam_id,
        'exam_name', exam_name,
        'starts', starts,
        'submissions', submissions,
        'completion_rate', completion_rate,
        'average_score', average_score,
        'average_accuracy', average_accuracy,
        'last_started_at', last_started_at
      ) order by starts desc, test_name, test_id)
      from paged
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_admin_analytics_v1(date,date,text,public.test_type)
  from public, anon, authenticated;
revoke all on function public.list_admin_test_analytics_v1(date,date,text,public.test_type,integer,integer)
  from public, anon, authenticated;
grant execute on function public.get_admin_analytics_v1(date,date,text,public.test_type)
  to authenticated;
grant execute on function public.list_admin_test_analytics_v1(date,date,text,public.test_type,integer,integer)
  to authenticated;

comment on function public.test_is_student_ready(text) is
  'Server-owned student-readiness gate. Image-free published questions take the equivalent fast path; visual questions retain the complete image-safety review.';
comment on function public.get_admin_analytics_v1(date,date,text,public.test_type) is
  'Admin-only aggregate Analytics v1 summary using one set-based test-readiness pass. SECURITY INVOKER preserves table RLS and returns no student PII or answer data.';
comment on function public.list_admin_test_analytics_v1(date,date,text,public.test_type,integer,integer) is
  'Admin-only paginated test-performance aggregates using set-based readiness and normalized scores. SECURITY INVOKER preserves table RLS.';

commit;
