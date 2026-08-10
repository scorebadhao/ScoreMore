begin;

-- ScoreMore Student Hub v1
-- Home, Tests, Saved, Results and Profile are backed by protected RPCs.
-- ScoreBadhao data, sessions and backend logic are intentionally not used.

create index if not exists attempts_student_status_recent_idx
  on public.attempts(user_id, status, submitted_at desc, started_at desc);

create index if not exists attempt_questions_question_attempt_idx
  on public.attempt_questions(question_id, attempt_id);

create index if not exists attempt_answers_attempt_result_idx
  on public.attempt_answers(attempt_id, is_correct, marked_review);

create index if not exists bookmarks_student_recent_idx
  on public.bookmarks(user_id, created_at desc);

create index if not exists mistake_book_student_revision_idx
  on public.mistake_book(user_id, resolved, last_mistake_at desc);

create index if not exists tests_student_catalogue_idx
  on public.tests(status, test_type, subject_id, topic_id, exam_year, sort_order);

-- Student-owned writes must pass through validated functions. This also removes
-- the inherited direct mobile-number update grant.
revoke update on public.profiles from authenticated;
revoke insert, update, delete on public.bookmarks from authenticated;
revoke insert, update, delete on public.mistake_book from authenticated;

create or replace function public.student_can_access_test(p_test_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tests t
    where t.test_id = p_test_id
      and t.status = 'PUBLISHED'
      and public.test_is_student_ready(t.test_id)
      and (
        t.is_free
        or (
          t.package_id is not null
          and exists (
            select 1
            from public.package_access pa
            where pa.user_id = (select auth.uid())
              and pa.package_id = t.package_id
              and pa.access_status = 'ACTIVE'
              and pa.starts_at <= now()
              and (pa.expires_at is null or pa.expires_at > now())
          )
        )
      )
  );
$$;

create or replace function public.student_question_answer_unlocked(p_question_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1
      from public.attempt_questions aq
      join public.attempts a on a.attempt_id = aq.attempt_id
      where a.user_id = (select auth.uid())
        and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')
        and aq.question_id = p_question_id
    )
    and not exists (
      select 1
      from public.attempt_questions aq
      join public.attempts a on a.attempt_id = aq.attempt_id
      where a.user_id = (select auth.uid())
        and a.status = 'IN_PROGRESS'
        and aq.question_id = p_question_id
    );
$$;

revoke all on function public.student_can_access_test(text) from public, anon, authenticated;
revoke all on function public.student_question_answer_unlocked(text) from public, anon, authenticated;

create or replace function public.get_student_home()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = 'P0001';
  end if;

  select jsonb_build_object(
    'profile', jsonb_build_object(
      'full_name', p.full_name,
      'target_board_id', p.target_board_id,
      'target_exam_id', p.target_exam_id,
      'target_board_name', b.board_name,
      'target_exam_name', e.exam_name,
      'language', p.language
    ),
    'summary', jsonb_build_object(
      'active_attempts', (select count(*) from public.attempts a where a.user_id = v_user_id and a.status = 'IN_PROGRESS'),
      'completed_attempts', (select count(*) from public.attempts a where a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')),
      'completed_tests', (select count(distinct a.test_id) from public.attempts a where a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')),
      'average_accuracy', coalesce((select round(avg(a.accuracy), 2) from public.attempts a where a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')), 0),
      'best_score', coalesce((select max(a.score) from public.attempts a where a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')), 0),
      'questions_solved', coalesce((select sum(a.attempted) from public.attempts a where a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')), 0),
      'bookmark_count', (select count(*) from public.bookmarks bm where bm.user_id = v_user_id),
      'mistake_count', (select count(*) from public.mistake_book mb where mb.user_id = v_user_id and not mb.resolved),
      'saved_count', (
        select count(*) from (
          select bm.question_id from public.bookmarks bm where bm.user_id = v_user_id
          union
          select mb.question_id from public.mistake_book mb where mb.user_id = v_user_id and not mb.resolved
        ) saved
      )
    ),
    'continue_attempt', (
      select jsonb_build_object(
        'attempt_id', a.attempt_id,
        'test_id', a.test_id,
        'test_name', t.test_name,
        'test_type', t.test_type,
        'started_at', a.started_at,
        'total_questions', a.total_questions,
        'answered', (select count(*) from public.attempt_answers aa where aa.attempt_id = a.attempt_id and aa.selected_answer is not null),
        'duration_minutes', t.duration_minutes
      )
      from public.attempts a
      join public.tests t on t.test_id = a.test_id
      where a.user_id = v_user_id and a.status = 'IN_PROGRESS'
      order by a.updated_at desc, a.started_at desc
      limit 1
    ),
    'recent_results', coalesce((
      select jsonb_agg(row_data order by submitted_at desc)
      from (
        select jsonb_build_object(
          'attempt_id', a.attempt_id,
          'test_id', a.test_id,
          'test_name', t.test_name,
          'test_type', t.test_type,
          'score', a.score,
          'accuracy', a.accuracy,
          'correct', a.correct,
          'wrong', a.wrong,
          'submitted_at', a.submitted_at
        ) as row_data, a.submitted_at
        from public.attempts a
        join public.tests t on t.test_id = a.test_id
        where a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')
        order by a.submitted_at desc
        limit 3
      ) recent
    ), '[]'::jsonb),
    'weak_subject', (
      select jsonb_build_object(
        'subject_id', ranked.subject_id,
        'subject_name', ranked.subject_name,
        'accuracy', ranked.accuracy,
        'question_count', ranked.question_count
      )
      from (
        select q.subject_id, s.subject_name,
               count(*) as question_count,
               round(100.0 * count(*) filter (where aa.is_correct is true) / nullif(count(*), 0), 2) as accuracy
        from public.attempts a
        join public.attempt_questions aq on aq.attempt_id = a.attempt_id
        join public.questions q on q.question_id = aq.question_id
        join public.subjects s on s.subject_id = q.subject_id
        left join public.attempt_answers aa on aa.attempt_id = aq.attempt_id and aa.question_id = aq.question_id
        where a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')
        group by q.subject_id, s.subject_name
        having count(*) >= 3
        order by accuracy asc, question_count desc, s.subject_name
        limit 1
      ) ranked
    ),
    'quick_counts', coalesce((
      select jsonb_object_agg(test_type, item_count)
      from (
        select t.test_type::text as test_type, count(*) as item_count
        from public.tests t
        where t.status = 'PUBLISHED' and public.test_is_student_ready(t.test_id)
        group by t.test_type
      ) counts
    ), '{}'::jsonb),
    'recommended_test', (
      select jsonb_build_object(
        'test_id', t.test_id,
        'test_name', t.test_name,
        'test_type', t.test_type,
        'question_count', t.question_count,
        'duration_minutes', t.duration_minutes,
        'is_free', t.is_free,
        'can_start', public.student_can_access_test(t.test_id)
      )
      from public.tests t
      where t.status = 'PUBLISHED'
        and public.test_is_student_ready(t.test_id)
        and not exists (
          select 1 from public.attempts a
          where a.user_id = v_user_id and a.test_id = t.test_id and a.status = 'IN_PROGRESS'
        )
      order by
        case when t.exam_id = p.target_exam_id then 0 else 1 end,
        case when public.student_can_access_test(t.test_id) then 0 else 1 end,
        t.sort_order,
        t.created_at desc
      limit 1
    ),
    'package_summary', jsonb_build_object(
      'active_count', (
        select count(*) from public.package_access pa
        where pa.user_id = v_user_id and pa.access_status = 'ACTIVE'
          and pa.starts_at <= now() and (pa.expires_at is null or pa.expires_at > now())
      ),
      'next_expiry', (
        select min(pa.expires_at) from public.package_access pa
        where pa.user_id = v_user_id and pa.access_status = 'ACTIVE'
          and pa.starts_at <= now() and pa.expires_at > now()
      )
    )
  ) into v_result
  from public.profiles p
  left join public.boards b on b.board_id = p.target_board_id
  left join public.exams e on e.exam_id = p.target_exam_id
  where p.user_id = v_user_id;

  if v_result is null then
    raise exception 'Student profile not found.' using errcode = 'P0001';
  end if;
  return v_result;
end;
$$;

create or replace function public.get_student_test_facets()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required.' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'test_types', coalesce((select jsonb_agg(value order by value) from (
      select distinct t.test_type::text as value from public.tests t
      where t.status = 'PUBLISHED' and public.test_is_student_ready(t.test_id)
    ) x), '[]'::jsonb),
    'subjects', coalesce((select jsonb_agg(jsonb_build_object('id', subject_id, 'name', subject_name) order by sort_order, subject_name) from (
      select s.subject_id, s.subject_name, s.sort_order
      from public.subjects s
      where s.status = 'ACTIVE'
    ) x), '[]'::jsonb),
    'topics', coalesce((select jsonb_agg(jsonb_build_object('id', topic_id, 'subject_id', subject_id, 'name', topic_name) order by topic_name) from (
      select tp.topic_id, tp.subject_id, tp.topic_name
      from public.topics tp
      where tp.status = 'ACTIVE'
    ) x), '[]'::jsonb),
    'years', coalesce((select jsonb_agg(value order by value desc) from (
      select distinct t.exam_year as value from public.tests t
      where t.status = 'PUBLISHED' and t.exam_year is not null and public.test_is_student_ready(t.test_id)
    ) x), '[]'::jsonb),
    'dates', coalesce((select jsonb_agg(value order by value desc) from (
      select distinct t.exam_date as value from public.tests t
      where t.status = 'PUBLISHED' and t.exam_date is not null and public.test_is_student_ready(t.test_id)
    ) x), '[]'::jsonb),
    'shifts', coalesce((select jsonb_agg(value order by value) from (
      select distinct t.shift_no as value from public.tests t
      where t.status = 'PUBLISHED' and t.shift_no is not null and public.test_is_student_ready(t.test_id)
    ) x), '[]'::jsonb)
  );
end;
$$;

create or replace function public.list_student_tests(
  p_test_type text default null,
  p_search text default null,
  p_subject_id text default null,
  p_topic_id text default null,
  p_exam_year integer default null,
  p_exam_date date default null,
  p_shift_no integer default null,
  p_access text default null,
  p_progress text default null,
  p_sort text default 'RECOMMENDED',
  p_page integer default 0,
  p_page_size integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_type text := upper(nullif(btrim(coalesce(p_test_type, '')), ''));
  v_search text := lower(nullif(btrim(coalesce(p_search, '')), ''));
  v_access text := upper(coalesce(nullif(btrim(coalesce(p_access, '')), ''), 'ALL'));
  v_progress text := upper(coalesce(nullif(btrim(coalesce(p_progress, '')), ''), 'ALL'));
  v_sort text := upper(coalesce(nullif(btrim(coalesce(p_sort, '')), ''), 'RECOMMENDED'));
  v_page integer := greatest(coalesce(p_page, 0), 0);
  v_page_size integer := least(greatest(coalesce(p_page_size, 12), 1), 50);
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  if v_access not in ('ALL', 'FREE', 'UNLOCKED', 'PREMIUM') then raise exception 'Invalid access filter.' using errcode = 'P0001'; end if;
  if v_progress not in ('ALL', 'NOT_STARTED', 'IN_PROGRESS', 'COMPLETED') then raise exception 'Invalid progress filter.' using errcode = 'P0001'; end if;
  if v_sort not in ('RECOMMENDED', 'NEWEST', 'OLDEST', 'PERFORMANCE', 'NAME') then raise exception 'Invalid test sort.' using errcode = 'P0001'; end if;

  with base as (
    select
      t.test_id, t.test_name, t.test_type::text, t.question_count, t.duration_minutes,
      t.marks_per_question, t.negative_marks, t.is_free, t.exam_year, t.exam_date,
      t.shift_no, t.paper_code, t.section_code, t.sort_order, t.created_at,
      b.board_id, b.board_name, e.exam_id, e.exam_name,
      s.subject_id, s.subject_name, tp.topic_id, tp.topic_name,
      pkg.package_id, pkg.package_name,
      case
        when t.is_free then 'FREE'
        when public.student_can_access_test(t.test_id) then 'UNLOCKED'
        else 'PREMIUM'
      end as access_state,
      public.student_can_access_test(t.test_id) as can_start,
      active_attempt.attempt_id as active_attempt_id,
      active_attempt.started_at as active_started_at,
      last_attempt.attempt_id as last_attempt_id,
      last_attempt.score as last_score,
      last_attempt.accuracy as last_accuracy,
      last_attempt.submitted_at as last_submitted_at,
      coalesce(stats.attempt_count, 0) as attempt_count,
      coalesce(stats.best_score, 0) as best_score,
      case
        when active_attempt.attempt_id is not null then 'IN_PROGRESS'
        when coalesce(stats.attempt_count, 0) > 0 then 'COMPLETED'
        else 'NOT_STARTED'
      end as progress_state
    from public.tests t
    join public.boards b on b.board_id = t.board_id
    join public.exams e on e.exam_id = t.exam_id
    left join public.subjects s on s.subject_id = t.subject_id
    left join public.topics tp on tp.topic_id = t.topic_id
    left join public.packages pkg on pkg.package_id = t.package_id
    left join lateral (
      select a.attempt_id, a.started_at
      from public.attempts a
      where a.user_id = v_user_id and a.test_id = t.test_id and a.status = 'IN_PROGRESS'
      order by a.started_at desc limit 1
    ) active_attempt on true
    left join lateral (
      select a.attempt_id, a.score, a.accuracy, a.submitted_at
      from public.attempts a
      where a.user_id = v_user_id and a.test_id = t.test_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')
      order by a.submitted_at desc limit 1
    ) last_attempt on true
    left join lateral (
      select count(*)::integer as attempt_count, max(a.score) as best_score
      from public.attempts a
      where a.user_id = v_user_id and a.test_id = t.test_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')
    ) stats on true
    where t.status = 'PUBLISHED' and public.test_is_student_ready(t.test_id)
  ), filtered as (
    select * from base x
    where (v_type is null or x.test_type = v_type)
      and (p_subject_id is null or p_subject_id = '' or x.subject_id = p_subject_id)
      and (p_topic_id is null or p_topic_id = '' or x.topic_id = p_topic_id)
      and (p_exam_year is null or x.exam_year = p_exam_year)
      and (p_exam_date is null or x.exam_date = p_exam_date)
      and (p_shift_no is null or x.shift_no = p_shift_no)
      and (v_access = 'ALL' or x.access_state = v_access)
      and (v_progress = 'ALL' or x.progress_state = v_progress)
      and (
        v_search is null
        or lower(concat_ws(' ', x.test_name, x.test_type, x.board_name, x.exam_name, x.subject_name, x.topic_name, x.exam_year, x.paper_code, x.section_code)) like '%' || v_search || '%'
      )
  ), ordered as (
    select f.*, count(*) over() as total_count
    from filtered f
    order by
      case when v_sort = 'RECOMMENDED' and f.progress_state = 'IN_PROGRESS' then 0 when v_sort = 'RECOMMENDED' and f.can_start then 1 else 2 end,
      case when v_sort = 'PERFORMANCE' then f.best_score end desc nulls last,
      case when v_sort = 'NEWEST' then f.created_at end desc nulls last,
      case when v_sort = 'OLDEST' then f.created_at end asc nulls last,
      case when v_sort = 'NAME' then lower(f.test_name) end asc nulls last,
      f.sort_order, f.created_at desc
    offset v_page * v_page_size
    limit v_page_size
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(to_jsonb(ordered) - 'total_count'), '[]'::jsonb),
    'total', coalesce(max(total_count), 0),
    'page', v_page,
    'page_size', v_page_size,
    'has_more', coalesce(max(total_count), 0) > ((v_page + 1) * v_page_size)
  ) into v_result
  from ordered;

  return coalesce(v_result, jsonb_build_object('items', '[]'::jsonb, 'total', 0, 'page', v_page, 'page_size', v_page_size, 'has_more', false));
end;
$$;

create or replace function public.get_attempt_bookmarks(p_attempt_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.attempts a where a.attempt_id = p_attempt_id and a.user_id = v_user_id) then
    raise exception 'Attempt not found or access denied.' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(bm.question_id order by aq.position)
    from public.bookmarks bm
    join public.attempt_questions aq on aq.question_id = bm.question_id and aq.attempt_id = p_attempt_id
    where bm.user_id = v_user_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.set_student_bookmark(
  p_question_id text,
  p_attempt_id uuid default null,
  p_saved boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  if p_question_id is null or btrim(p_question_id) = '' then raise exception 'Question ID is required.' using errcode = 'P0001'; end if;

  if coalesce(p_saved, true) then
    if p_attempt_id is null or not exists (
      select 1 from public.attempt_questions aq
      join public.attempts a on a.attempt_id = aq.attempt_id
      where aq.attempt_id = p_attempt_id and aq.question_id = p_question_id and a.user_id = v_user_id
    ) then
      raise exception 'You may save only a question from your own test attempt.' using errcode = 'P0001';
    end if;
    insert into public.bookmarks(user_id, question_id)
    values (v_user_id, p_question_id)
    on conflict (user_id, question_id) do nothing;
  else
    delete from public.bookmarks where user_id = v_user_id and question_id = p_question_id;
  end if;

  return jsonb_build_object('question_id', p_question_id, 'saved', coalesce(p_saved, true));
end;
$$;

create or replace function public.set_student_mistake_resolved(p_question_id text, p_resolved boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  update public.mistake_book
  set resolved = coalesce(p_resolved, true), updated_at = now()
  where user_id = v_user_id and question_id = p_question_id;
  if not found then raise exception 'Mistake record not found.' using errcode = 'P0001'; end if;
  return jsonb_build_object('question_id', p_question_id, 'resolved', coalesce(p_resolved, true));
end;
$$;

create or replace function public.list_student_saved(
  p_kind text default 'BOOKMARKS',
  p_search text default null,
  p_subject_id text default null,
  p_topic_id text default null,
  p_status text default 'ALL',
  p_offset integer default 0,
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_kind text := upper(coalesce(nullif(btrim(coalesce(p_kind, '')), ''), 'BOOKMARKS'));
  v_status text := upper(coalesce(nullif(btrim(coalesce(p_status, '')), ''), 'ALL'));
  v_search text := lower(nullif(btrim(coalesce(p_search, '')), ''));
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  if v_kind not in ('BOOKMARKS', 'MISTAKES') then raise exception 'Invalid saved-question kind.' using errcode = 'P0001'; end if;
  if v_status not in ('ALL', 'OPEN', 'RESOLVED') then raise exception 'Invalid mistake status.' using errcode = 'P0001'; end if;

  with saved as (
    select bm.question_id, bm.created_at as saved_at, null::integer as mistake_count,
           null::boolean as resolved, null::timestamptz as last_mistake_at, null::uuid as latest_attempt_id
    from public.bookmarks bm
    where v_kind = 'BOOKMARKS' and bm.user_id = v_user_id
    union all
    select mb.question_id, mb.created_at, mb.mistake_count, mb.resolved, mb.last_mistake_at, mb.latest_attempt_id
    from public.mistake_book mb
    where v_kind = 'MISTAKES' and mb.user_id = v_user_id
      and (v_status = 'ALL' or (v_status = 'OPEN' and not mb.resolved) or (v_status = 'RESOLVED' and mb.resolved))
  ), detailed as (
    select
      sv.question_id, sv.saved_at, sv.mistake_count, sv.resolved, sv.last_mistake_at, sv.latest_attempt_id,
      q.question_text, q.options, q.difficulty, q.subject_id, s.subject_name,
      q.topic_id, tp.topic_name, q.section_code, q.exam_year, q.original_question_no,
      case when public.student_question_answer_unlocked(q.question_id) then q.correct_answer else null end as correct_answer,
      case when public.student_question_answer_unlocked(q.question_id) then q.explanation else null end as explanation,
      case when public.student_question_answer_unlocked(q.question_id) then latest_answer.selected_answer else null end as selected_answer,
      not public.student_question_answer_unlocked(q.question_id) as answer_locked,
      case public.question_student_image_readiness(q.question_id)
        when 'SAFE_CROP_APPROVED' then q.student_image_refs
        else '[]'::jsonb
      end as image_refs,
      public.question_student_image_readiness(q.question_id) as image_state,
      exists (select 1 from public.bookmarks bm where bm.user_id = v_user_id and bm.question_id = q.question_id) as bookmarked
    from saved sv
    join public.questions q on q.question_id = sv.question_id
    join public.subjects s on s.subject_id = q.subject_id
    left join public.topics tp on tp.topic_id = q.topic_id
    left join lateral (
      select aa.selected_answer
      from public.attempt_answers aa
      join public.attempts a on a.attempt_id = aa.attempt_id
      where a.user_id = v_user_id and aa.question_id = q.question_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')
      order by a.submitted_at desc limit 1
    ) latest_answer on true
    where (p_subject_id is null or p_subject_id = '' or q.subject_id = p_subject_id)
      and (p_topic_id is null or p_topic_id = '' or q.topic_id = p_topic_id)
      and (
        v_search is null
        or lower(concat_ws(' ', q.question_id, q.question_text, s.subject_name, tp.topic_name, q.section_code)) like '%' || v_search || '%'
      )
  ), paged as (
    select d.*, count(*) over() as total_count
    from detailed d
    order by coalesce(d.last_mistake_at, d.saved_at) desc
    offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'kind', v_kind,
    'items', coalesce(jsonb_agg(to_jsonb(paged) - 'total_count'), '[]'::jsonb),
    'total', coalesce(max(total_count), 0),
    'has_more', coalesce(max(total_count), 0) > (v_offset + v_limit),
    'revision_test', (
      select jsonb_build_object(
        'test_id', t.test_id, 'test_name', t.test_name, 'test_type', t.test_type,
        'can_start', public.student_can_access_test(t.test_id)
      )
      from public.tests t
      where t.status = 'PUBLISHED'
        and public.test_is_student_ready(t.test_id)
        and t.test_type = (case when v_kind = 'BOOKMARKS' then 'BOOKMARK_REVISION'::public.test_type else 'MISTAKE_REVISION'::public.test_type end)
      order by t.sort_order, t.created_at desc limit 1
    )
  ) into v_result
  from paged;

  return coalesce(v_result, jsonb_build_object('kind', v_kind, 'items', '[]'::jsonb, 'total', 0, 'has_more', false, 'revision_test', null));
end;
$$;

create or replace function public.list_student_results(
  p_search text default null,
  p_sort text default 'NEWEST',
  p_page integer default 0,
  p_page_size integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_search text := lower(nullif(btrim(coalesce(p_search, '')), ''));
  v_sort text := upper(coalesce(nullif(btrim(coalesce(p_sort, '')), ''), 'NEWEST'));
  v_page integer := greatest(coalesce(p_page, 0), 0);
  v_page_size integer := least(greatest(coalesce(p_page_size, 12), 1), 50);
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  if v_sort not in ('NEWEST', 'OLDEST', 'SCORE', 'ACCURACY') then raise exception 'Invalid result sort.' using errcode = 'P0001'; end if;

  with filtered as (
    select
      a.attempt_id, a.test_id, a.status::text, a.total_questions, a.attempted,
      a.correct, a.wrong, a.skipped, a.score, a.accuracy, a.time_taken_seconds,
      a.started_at, a.submitted_at,
      t.test_name, t.test_type::text, t.marks_per_question, t.negative_marks,
      (a.total_questions * t.marks_per_question) as max_score,
      (a.wrong * t.negative_marks) as negative_mark_loss,
      b.board_name, e.exam_name, s.subject_name
    from public.attempts a
    join public.tests t on t.test_id = a.test_id
    join public.boards b on b.board_id = t.board_id
    join public.exams e on e.exam_id = t.exam_id
    left join public.subjects s on s.subject_id = t.subject_id
    where a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')
      and (v_search is null or lower(concat_ws(' ', t.test_name, t.test_type, b.board_name, e.exam_name, s.subject_name)) like '%' || v_search || '%')
  ), paged as (
    select f.*, count(*) over() as total_count
    from filtered f
    order by
      case when v_sort = 'NEWEST' then f.submitted_at end desc nulls last,
      case when v_sort = 'OLDEST' then f.submitted_at end asc nulls last,
      case when v_sort = 'SCORE' then f.score end desc nulls last,
      case when v_sort = 'ACCURACY' then f.accuracy end desc nulls last,
      f.submitted_at desc
    offset v_page * v_page_size limit v_page_size
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(to_jsonb(paged) - 'total_count'), '[]'::jsonb),
    'total', coalesce(max(total_count), 0),
    'page', v_page,
    'page_size', v_page_size,
    'has_more', coalesce(max(total_count), 0) > ((v_page + 1) * v_page_size)
  ) into v_result
  from paged;
  return coalesce(v_result, jsonb_build_object('items', '[]'::jsonb, 'total', 0, 'page', v_page, 'page_size', v_page_size, 'has_more', false));
end;
$$;

create or replace function public.get_student_result_detail(p_attempt_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_attempt public.attempts%rowtype;
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  select * into v_attempt from public.attempts a
  where a.attempt_id = p_attempt_id and a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED');
  if not found then raise exception 'Submitted result not found or access denied.' using errcode = 'P0001'; end if;

  select jsonb_build_object(
    'summary', jsonb_build_object(
      'attempt_id', a.attempt_id, 'test_id', a.test_id, 'test_name', t.test_name,
      'test_type', t.test_type, 'status', a.status, 'total_questions', a.total_questions,
      'attempted', a.attempted, 'correct', a.correct, 'wrong', a.wrong, 'skipped', a.skipped,
      'score', a.score, 'max_score', a.total_questions * t.marks_per_question,
      'accuracy', a.accuracy, 'time_taken_seconds', a.time_taken_seconds,
      'negative_mark_loss', a.wrong * t.negative_marks,
      'marks_per_question', t.marks_per_question, 'negative_marks', t.negative_marks,
      'started_at', a.started_at, 'submitted_at', a.submitted_at
    ),
    'subject_performance', coalesce((
      select jsonb_agg(jsonb_build_object(
        'subject_id', x.subject_id, 'subject_name', x.subject_name, 'total', x.total,
        'correct', x.correct, 'wrong', x.wrong, 'skipped', x.skipped,
        'accuracy', x.accuracy, 'average_time_seconds', x.average_time_seconds
      ) order by x.accuracy desc, x.subject_name)
      from (
        select q.subject_id, s.subject_name, count(*) as total,
          count(*) filter (where aa.is_correct is true) as correct,
          count(*) filter (where aa.selected_answer is not null and aa.is_correct is false) as wrong,
          count(*) filter (where aa.selected_answer is null) as skipped,
          round(100.0 * count(*) filter (where aa.is_correct is true) / nullif(count(*), 0), 2) as accuracy,
          round(avg(coalesce(aa.time_taken_seconds, 0)), 1) as average_time_seconds
        from public.attempt_questions aq
        join public.questions q on q.question_id = aq.question_id
        join public.subjects s on s.subject_id = q.subject_id
        left join public.attempt_answers aa on aa.attempt_id = aq.attempt_id and aa.question_id = aq.question_id
        where aq.attempt_id = p_attempt_id
        group by q.subject_id, s.subject_name
      ) x
    ), '[]'::jsonb),
    'topic_performance', coalesce((
      select jsonb_agg(jsonb_build_object(
        'topic_id', x.topic_id, 'topic_name', x.topic_name, 'subject_name', x.subject_name,
        'total', x.total, 'correct', x.correct, 'accuracy', x.accuracy
      ) order by x.accuracy asc, x.total desc)
      from (
        select q.topic_id, coalesce(tp.topic_name, 'Unclassified') as topic_name, s.subject_name,
          count(*) as total, count(*) filter (where aa.is_correct is true) as correct,
          round(100.0 * count(*) filter (where aa.is_correct is true) / nullif(count(*), 0), 2) as accuracy
        from public.attempt_questions aq
        join public.questions q on q.question_id = aq.question_id
        join public.subjects s on s.subject_id = q.subject_id
        left join public.topics tp on tp.topic_id = q.topic_id
        left join public.attempt_answers aa on aa.attempt_id = aq.attempt_id and aa.question_id = aq.question_id
        where aq.attempt_id = p_attempt_id
        group by q.topic_id, tp.topic_name, s.subject_name
      ) x
    ), '[]'::jsonb),
    'difficulty_performance', coalesce((
      select jsonb_agg(jsonb_build_object(
        'difficulty', x.difficulty, 'total', x.total, 'correct', x.correct,
        'wrong', x.wrong, 'skipped', x.skipped, 'accuracy', x.accuracy
      ) order by case x.difficulty when 'EASY' then 1 when 'MEDIUM' then 2 else 3 end)
      from (
        select q.difficulty, count(*) as total,
          count(*) filter (where aa.is_correct is true) as correct,
          count(*) filter (where aa.selected_answer is not null and aa.is_correct is false) as wrong,
          count(*) filter (where aa.selected_answer is null) as skipped,
          round(100.0 * count(*) filter (where aa.is_correct is true) / nullif(count(*), 0), 2) as accuracy
        from public.attempt_questions aq
        join public.questions q on q.question_id = aq.question_id
        left join public.attempt_answers aa on aa.attempt_id = aq.attempt_id and aa.question_id = aq.question_id
        where aq.attempt_id = p_attempt_id
        group by q.difficulty
      ) x
    ), '[]'::jsonb),
    'timing', jsonb_build_object(
      'total_seconds', a.time_taken_seconds,
      'average_seconds_per_question', round(a.time_taken_seconds::numeric / nullif(a.total_questions, 0), 1),
      'fastest_answer_seconds', (select min(aa.time_taken_seconds) from public.attempt_answers aa where aa.attempt_id = p_attempt_id and aa.selected_answer is not null),
      'slowest_answer_seconds', (select max(aa.time_taken_seconds) from public.attempt_answers aa where aa.attempt_id = p_attempt_id and aa.selected_answer is not null)
    ),
    'repeated_mistakes', (
      select count(*) from public.mistake_book mb
      join public.attempt_questions aq on aq.question_id = mb.question_id and aq.attempt_id = p_attempt_id
      where mb.user_id = v_user_id and mb.mistake_count > 1 and not mb.resolved
    ),
    'recommendation', (
      select jsonb_build_object(
        'subject_id', weak.subject_id,
        'subject_name', weak.subject_name,
        'accuracy', weak.accuracy,
        'message', 'Revise ' || weak.subject_name || ' and attempt a focused sectional test next.'
      )
      from (
        select q.subject_id, s.subject_name,
          round(100.0 * count(*) filter (where aa.is_correct is true) / nullif(count(*), 0), 2) as accuracy
        from public.attempt_questions aq
        join public.questions q on q.question_id = aq.question_id
        join public.subjects s on s.subject_id = q.subject_id
        left join public.attempt_answers aa on aa.attempt_id = aq.attempt_id and aa.question_id = aq.question_id
        where aq.attempt_id = p_attempt_id
        group by q.subject_id, s.subject_name
        order by accuracy asc, count(*) desc limit 1
      ) weak
    )
  ) into v_result
  from public.attempts a
  join public.tests t on t.test_id = a.test_id
  where a.attempt_id = p_attempt_id;

  return v_result;
end;
$$;

-- Replace the original submitted-attempt review signature with safe diagrams,
-- names and bookmark state. Raw source captures are never returned.
drop function if exists public.get_attempt_review(uuid, integer, integer);
create function public.get_attempt_review(
  p_attempt_id uuid,
  p_offset integer default 0,
  p_limit integer default 25
)
returns table (
  "position" integer,
  question_id text,
  question_text text,
  options jsonb,
  selected_answer text,
  correct_answer text,
  is_correct boolean,
  explanation text,
  subject_id text,
  subject_name text,
  topic_id text,
  topic_name text,
  difficulty text,
  time_taken_seconds integer,
  marked_review boolean,
  image_refs jsonb,
  bookmarked boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  if not exists (
    select 1 from public.attempts a
    where a.attempt_id = p_attempt_id and a.user_id = v_user_id
      and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')
  ) then
    raise exception 'Review is available only for your submitted attempt.' using errcode = 'P0001';
  end if;

  return query
  select aq.position, q.question_id, q.question_text, q.options,
         aa.selected_answer, q.correct_answer, aa.is_correct, q.explanation,
         q.subject_id, s.subject_name, q.topic_id, tp.topic_name, q.difficulty,
         coalesce(aa.time_taken_seconds, 0), coalesce(aa.marked_review, false),
         case public.question_student_image_readiness(q.question_id)
           when 'SAFE_CROP_APPROVED' then q.student_image_refs
           else '[]'::jsonb
         end,
         exists (select 1 from public.bookmarks bm where bm.user_id = v_user_id and bm.question_id = q.question_id)
  from public.attempt_questions aq
  join public.questions q on q.question_id = aq.question_id
  join public.subjects s on s.subject_id = q.subject_id
  left join public.topics tp on tp.topic_id = q.topic_id
  left join public.attempt_answers aa on aa.attempt_id = aq.attempt_id and aa.question_id = aq.question_id
  where aq.attempt_id = p_attempt_id
  order by aq.position
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 25), 1), 100);
end;
$$;

create or replace function public.get_student_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'user_id', p.user_id, 'email', p.email, 'mobile', p.mobile,
      'full_name', p.full_name, 'language', p.language,
      'target_board_id', p.target_board_id, 'target_exam_id', p.target_exam_id,
      'target_board_name', b.board_name, 'target_exam_name', e.exam_name,
      'status', p.status, 'created_at', p.created_at
    ),
    'boards', coalesce((select jsonb_agg(jsonb_build_object('board_id', x.board_id, 'board_name', x.board_name) order by x.sort_order, x.board_name)
      from public.boards x where x.status = 'ACTIVE'), '[]'::jsonb),
    'exams', coalesce((select jsonb_agg(jsonb_build_object('exam_id', x.exam_id, 'board_id', x.board_id, 'exam_name', x.exam_name) order by x.sort_order, x.exam_name)
      from public.exams x where x.status = 'ACTIVE'), '[]'::jsonb),
    'stats', jsonb_build_object(
      'completed_attempts', (select count(*) from public.attempts a where a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')),
      'average_accuracy', coalesce((select round(avg(a.accuracy), 2) from public.attempts a where a.user_id = v_user_id and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')), 0),
      'bookmarks', (select count(*) from public.bookmarks bm where bm.user_id = v_user_id),
      'open_mistakes', (select count(*) from public.mistake_book mb where mb.user_id = v_user_id and not mb.resolved)
    )
  ) into v_result
  from public.profiles p
  left join public.boards b on b.board_id = p.target_board_id
  left join public.exams e on e.exam_id = p.target_exam_id
  where p.user_id = v_user_id;
  if v_result is null then raise exception 'Student profile not found.' using errcode = 'P0001'; end if;
  return v_result;
end;
$$;

create or replace function public.update_student_profile(
  p_full_name text,
  p_language text,
  p_target_board_id text default null,
  p_target_exam_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_name text := btrim(coalesce(p_full_name, ''));
  v_language text := upper(btrim(coalesce(p_language, '')));
  v_board_id text := nullif(btrim(coalesce(p_target_board_id, '')), '');
  v_exam_id text := nullif(btrim(coalesce(p_target_exam_id, '')), '');
  v_exam_board text;
begin
  if v_user_id is null then raise exception 'Authentication required.' using errcode = 'P0001'; end if;
  if char_length(v_name) < 2 or char_length(v_name) > 100 then raise exception 'Full name must contain 2 to 100 characters.' using errcode = 'P0001'; end if;
  if v_language !~ '^[A-Z][A-Z_-]{1,31}$' then raise exception 'Choose a valid preferred language.' using errcode = 'P0001'; end if;
  if v_board_id is not null and not exists (select 1 from public.boards b where b.board_id = v_board_id and b.status = 'ACTIVE') then
    raise exception 'Selected board is unavailable.' using errcode = 'P0001';
  end if;
  if v_exam_id is not null then
    select e.board_id into v_exam_board from public.exams e where e.exam_id = v_exam_id and e.status = 'ACTIVE';
    if v_exam_board is null then raise exception 'Selected exam is unavailable.' using errcode = 'P0001'; end if;
    if v_board_id is null then v_board_id := v_exam_board; end if;
    if v_exam_board <> v_board_id then raise exception 'Selected exam does not belong to the selected board.' using errcode = 'P0001'; end if;
  end if;

  update public.profiles
  set full_name = v_name, language = v_language,
      target_board_id = v_board_id, target_exam_id = v_exam_id, updated_at = now()
  where user_id = v_user_id;
  if not found then raise exception 'Student profile not found.' using errcode = 'P0001'; end if;

  return public.get_student_profile();
end;
$$;

revoke all on function public.get_student_home() from public, anon, authenticated;
revoke all on function public.get_student_test_facets() from public, anon, authenticated;
revoke all on function public.list_student_tests(text,text,text,text,integer,date,integer,text,text,text,integer,integer) from public, anon, authenticated;
revoke all on function public.get_attempt_bookmarks(uuid) from public, anon, authenticated;
revoke all on function public.set_student_bookmark(text,uuid,boolean) from public, anon, authenticated;
revoke all on function public.set_student_mistake_resolved(text,boolean) from public, anon, authenticated;
revoke all on function public.list_student_saved(text,text,text,text,text,integer,integer) from public, anon, authenticated;
revoke all on function public.list_student_results(text,text,integer,integer) from public, anon, authenticated;
revoke all on function public.get_student_result_detail(uuid) from public, anon, authenticated;
revoke all on function public.get_attempt_review(uuid,integer,integer) from public, anon, authenticated;
revoke all on function public.get_student_profile() from public, anon, authenticated;
revoke all on function public.update_student_profile(text,text,text,text) from public, anon, authenticated;

grant execute on function public.get_student_home() to authenticated;
grant execute on function public.get_student_test_facets() to authenticated;
grant execute on function public.list_student_tests(text,text,text,text,integer,date,integer,text,text,text,integer,integer) to authenticated;
grant execute on function public.get_attempt_bookmarks(uuid) to authenticated;
grant execute on function public.set_student_bookmark(text,uuid,boolean) to authenticated;
grant execute on function public.set_student_mistake_resolved(text,boolean) to authenticated;
grant execute on function public.list_student_saved(text,text,text,text,text,integer,integer) to authenticated;
grant execute on function public.list_student_results(text,text,integer,integer) to authenticated;
grant execute on function public.get_student_result_detail(uuid) to authenticated;
grant execute on function public.get_attempt_review(uuid,integer,integer) to authenticated;
grant execute on function public.get_student_profile() to authenticated;
grant execute on function public.update_student_profile(text,text,text,text) to authenticated;

comment on function public.get_student_home() is 'Protected ScoreMore Student Hub dashboard snapshot for auth.uid().';
comment on function public.list_student_tests(text,text,text,text,integer,date,integer,text,text,text,integer,integer) is 'Server-filtered student-ready catalogue with package and attempt state for auth.uid().';
comment on function public.list_student_saved(text,text,text,text,text,integer,integer) is 'Bookmarks or mistake revision data with active-attempt answer protection and approved images only.';
comment on function public.get_student_result_detail(uuid) is 'Server-calculated analytics for one submitted attempt owned by auth.uid().';
comment on function public.update_student_profile(text,text,text,text) is 'Updates only safe student profile fields; email, mobile, role and authorization data remain immutable.';

commit;
