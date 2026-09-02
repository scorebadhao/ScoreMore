begin;

-- Migration 28 normalized scores correctly in the summary RPC, but the
-- paginated RPC did not project marks_per_question into eligible_tests before
-- using it. Keep migration history immutable and repair the deployed function
-- forward-only.
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

  with eligible_tests as materialized (
    select
      t.test_id,
      t.test_name,
      t.test_type,
      t.exam_id,
      t.marks_per_question,
      e.exam_name
    from public.tests t
    join public.exams e on e.exam_id = t.exam_id
    where t.status = 'PUBLISHED'
      and (v_exam_id is null or t.exam_id = v_exam_id)
      and (p_test_type is null or t.test_type = p_test_type)
      and public.test_is_student_ready(t.test_id)
  ), scoped_attempts as materialized (
    select a.*
    from public.attempts a
    join eligible_tests t on t.test_id = a.test_id
    where a.started_at >= v_from and a.started_at < v_to
  ), test_rows as (
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
    group by t.test_id, t.test_name, t.test_type, t.exam_id, t.exam_name
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

revoke all on function public.list_admin_test_analytics_v1(date,date,text,public.test_type,integer,integer)
  from public, anon, authenticated;
grant execute on function public.list_admin_test_analytics_v1(date,date,text,public.test_type,integer,integer)
  to authenticated;

comment on function public.list_admin_test_analytics_v1(date,date,text,public.test_type,integer,integer) is
  'Admin-only, paginated test-performance aggregates with normalized score percentages. SECURITY INVOKER preserves table RLS.';

commit;
