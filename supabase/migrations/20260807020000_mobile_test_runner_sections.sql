begin;

-- ScoreMore mobile test runner hardening.
--
-- This migration is forward-only. It does not rewrite existing attempts,
-- answers, published question text, raw source images or test definitions.

alter table public.attempt_questions
  add column if not exists visited_at timestamptz;

alter table public.questions
  add column if not exists student_image_refs jsonb not null default '[]'::jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.questions'::regclass
      and conname = 'questions_student_image_refs_array'
  ) then
    alter table public.questions
      add constraint questions_student_image_refs_array
      check (jsonb_typeof(student_image_refs) = 'array');
  end if;
end;
$$;

comment on column public.attempt_questions.visited_at is
  'First protected server visit used by the complete attempt navigator.';

comment on column public.questions.student_image_refs is
  'Admin-reviewed diagram-only image references allowed in the student test runner. Raw source captures remain in image_refs and are never returned during an attempt.';

-- Internal scoring primitive shared by manual and timed submission. It is not
-- executable by browser roles. Every public caller validates attempt ownership.
create or replace function public.finalize_attempt_internal(
  p_attempt_id uuid,
  p_final_status public.attempt_status
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attempt public.attempts%rowtype;
  v_test public.tests%rowtype;
  v_attempted integer;
  v_correct integer;
  v_wrong integer;
  v_skipped integer;
  v_score numeric(12,3);
  v_accuracy numeric(7,3);
  v_time integer;
begin
  if p_final_status not in ('SUBMITTED'::public.attempt_status, 'AUTO_SUBMITTED'::public.attempt_status) then
    raise exception 'Invalid final attempt status.' using errcode = 'P0001';
  end if;

  select * into v_attempt
  from public.attempts
  where attempt_id = p_attempt_id
  for update;

  if not found then
    raise exception 'Attempt not found.' using errcode = 'P0001';
  end if;

  if v_attempt.status <> 'IN_PROGRESS'::public.attempt_status then
    return jsonb_build_object(
      'attempt_id', v_attempt.attempt_id,
      'status', v_attempt.status,
      'score', v_attempt.score,
      'accuracy', v_attempt.accuracy,
      'attempted', v_attempt.attempted,
      'correct', v_attempt.correct,
      'wrong', v_attempt.wrong,
      'skipped', v_attempt.skipped,
      'time_taken_seconds', v_attempt.time_taken_seconds
    );
  end if;

  select * into v_test
  from public.tests
  where test_id = v_attempt.test_id;

  if not found then
    raise exception 'Attempt test configuration was not found.' using errcode = 'P0001';
  end if;

  update public.attempt_answers aa
  set correct_answer = q.correct_answer,
      is_correct = (aa.selected_answer = q.correct_answer),
      updated_at = now()
  from public.questions q
  where aa.attempt_id = p_attempt_id
    and aa.question_id = q.question_id;

  select
    count(*) filter (where aa.selected_answer is not null),
    count(*) filter (where aa.selected_answer is not null and aa.is_correct is true),
    count(*) filter (where aa.selected_answer is not null and aa.is_correct is false),
    count(*) filter (where aa.selected_answer is null)
  into v_attempted, v_correct, v_wrong, v_skipped
  from public.attempt_questions aq
  left join public.attempt_answers aa
    on aa.attempt_id = aq.attempt_id
   and aa.question_id = aq.question_id
  where aq.attempt_id = p_attempt_id;

  v_score := (v_correct * v_test.marks_per_question) - (v_wrong * v_test.negative_marks);
  v_accuracy := case
    when v_attempted = 0 then 0
    else round((v_correct::numeric / v_attempted::numeric) * 100, 3)
  end;
  v_time := greatest(0, extract(epoch from (now() - v_attempt.started_at))::integer);

  if p_final_status = 'AUTO_SUBMITTED'::public.attempt_status and v_test.duration_minutes > 0 then
    v_time := least(v_time, v_test.duration_minutes * 60);
  end if;

  update public.attempts
  set status = p_final_status,
      attempted = v_attempted,
      correct = v_correct,
      wrong = v_wrong,
      skipped = v_skipped,
      score = v_score,
      accuracy = v_accuracy,
      time_taken_seconds = v_time,
      submitted_at = now(),
      updated_at = now()
  where attempt_id = p_attempt_id;

  insert into public.mistake_book (
    user_id, question_id, latest_attempt_id, mistake_count,
    resolved, last_mistake_at
  )
  select v_attempt.user_id, aa.question_id, p_attempt_id, 1, false, now()
  from public.attempt_answers aa
  where aa.attempt_id = p_attempt_id
    and aa.is_correct is false
  on conflict (user_id, question_id)
  do update set
    latest_attempt_id = excluded.latest_attempt_id,
    mistake_count = public.mistake_book.mistake_count + 1,
    resolved = false,
    last_mistake_at = now(),
    updated_at = now();

  return jsonb_build_object(
    'attempt_id', p_attempt_id,
    'status', p_final_status,
    'score', v_score,
    'accuracy', v_accuracy,
    'attempted', v_attempted,
    'correct', v_correct,
    'wrong', v_wrong,
    'skipped', v_skipped,
    'time_taken_seconds', v_time
  );
end;
$$;

-- Full, protected navigation snapshot. It returns only identity, section and
-- answer/review/visit state; no correct answer, explanation or raw source image.
create or replace function public.get_attempt_navigation(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_attempt public.attempts%rowtype;
  v_duration integer;
  v_deadline timestamptz;
  v_seconds_remaining integer;
  v_items jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = 'P0001';
  end if;

  select a.*
  into v_attempt
  from public.attempts a
  where a.attempt_id = p_attempt_id
    and a.user_id = v_user_id;

  if not found then
    raise exception 'Attempt not found or access denied.' using errcode = 'P0001';
  end if;

  select duration_minutes into v_duration
  from public.tests
  where test_id = v_attempt.test_id;

  v_deadline := case
    when v_duration > 0 then v_attempt.started_at + make_interval(mins => v_duration)
    else null
  end;

  if v_attempt.status = 'IN_PROGRESS'::public.attempt_status
     and v_deadline is not null
     and now() >= v_deadline then
    perform public.finalize_attempt_internal(p_attempt_id, 'AUTO_SUBMITTED'::public.attempt_status);
    select * into v_attempt
    from public.attempts
    where attempt_id = p_attempt_id;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'position', aq.position,
        'question_id', aq.question_id,
        'subject_id', q.subject_id,
        'subject_name', s.subject_name,
        'section_code', q.section_code,
        'selected_answer', aa.selected_answer,
        'marked_review', coalesce(aa.marked_review, false),
        'visited_at', aq.visited_at
      ) order by aq.position
    ),
    '[]'::jsonb
  ) into v_items
  from public.attempt_questions aq
  join public.questions q on q.question_id = aq.question_id
  join public.subjects s on s.subject_id = q.subject_id
  left join public.attempt_answers aa
    on aa.attempt_id = aq.attempt_id
   and aa.question_id = aq.question_id
  where aq.attempt_id = p_attempt_id;

  v_seconds_remaining := case
    when v_attempt.status = 'IN_PROGRESS'::public.attempt_status and v_deadline is not null
      then greatest(0, floor(extract(epoch from (v_deadline - now())))::integer)
    else null
  end;

  return jsonb_build_object(
    'attempt_id', p_attempt_id,
    'status', v_attempt.status,
    'total_questions', v_attempt.total_questions,
    'started_at', v_attempt.started_at,
    'deadline_at', v_deadline,
    'seconds_remaining', v_seconds_remaining,
    'server_now', now(),
    'items', v_items
  );
end;
$$;

-- Persist the first visit independently of answer selection. This lets a
-- refreshed or cross-device attempt distinguish unanswered from not visited.
create or replace function public.visit_attempt_question(
  p_attempt_id uuid,
  p_question_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_attempt public.attempts%rowtype;
  v_duration integer;
  v_deadline timestamptz;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = 'P0001';
  end if;

  select a.*
  into v_attempt
  from public.attempts a
  where a.attempt_id = p_attempt_id
    and a.user_id = v_user_id;

  if not found then
    raise exception 'Attempt not found or access denied.' using errcode = 'P0001';
  end if;

  select duration_minutes into v_duration
  from public.tests
  where test_id = v_attempt.test_id;

  if v_attempt.status <> 'IN_PROGRESS'::public.attempt_status then
    return jsonb_build_object('attempt_id', p_attempt_id, 'status', v_attempt.status, 'editable', false);
  end if;

  v_deadline := case
    when v_duration > 0 then v_attempt.started_at + make_interval(mins => v_duration)
    else null
  end;

  if v_deadline is not null and now() >= v_deadline then
    v_result := public.finalize_attempt_internal(p_attempt_id, 'AUTO_SUBMITTED'::public.attempt_status);
    return v_result || jsonb_build_object('expired', true, 'editable', false);
  end if;

  update public.attempt_questions
  set visited_at = coalesce(visited_at, now())
  where attempt_id = p_attempt_id
    and question_id = p_question_id;

  if not found then
    raise exception 'Attempt question not found.' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'attempt_id', p_attempt_id,
    'question_id', p_question_id,
    'status', 'IN_PROGRESS',
    'visited', true
  );
end;
$$;

-- Protected batch loader. Raw image_refs are intentionally not returned.
-- student_image_refs must contain an explicitly reviewed diagram-only crop.
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

  select a.*
  into v_attempt
  from public.attempts a
  where a.attempt_id = p_attempt_id
    and a.user_id = v_user_id;

  if not found then
    raise exception 'Attempt not found or access denied.' using errcode = 'P0001';
  end if;

  select duration_minutes into v_duration
  from public.tests
  where test_id = v_attempt.test_id;

  if v_attempt.status <> 'IN_PROGRESS'::public.attempt_status then
    return;
  end if;

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
         case
           when jsonb_array_length(q.student_image_refs) > 0 then q.student_image_refs
           when jsonb_array_length(q.image_refs) > 0 then jsonb_build_array(jsonb_build_object('blocked', true))
           else '[]'::jsonb
         end,
         aa.selected_answer,
         coalesce(aa.marked_review, false)
  from public.attempt_questions aq
  join public.questions q on q.question_id = aq.question_id
  join public.subjects s on s.subject_id = q.subject_id
  left join public.attempt_answers aa
    on aa.attempt_id = aq.attempt_id
   and aa.question_id = aq.question_id
  where aq.attempt_id = p_attempt_id
  order by aq.position
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 10), 1), 50);
end;
$$;

-- Protected answer upsert with an authoritative server deadline.
create or replace function public.save_attempt_answer(
  p_attempt_id uuid,
  p_question_id text,
  p_selected_answer text default null,
  p_marked_review boolean default false,
  p_time_taken_seconds integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_attempt public.attempts%rowtype;
  v_duration integer;
  v_deadline timestamptz;
  v_answer_id uuid;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = 'P0001';
  end if;

  if p_selected_answer is not null and p_selected_answer not in ('A', 'B', 'C', 'D') then
    raise exception 'Selected answer must be A, B, C or D.' using errcode = 'P0001';
  end if;

  select a.*
  into v_attempt
  from public.attempts a
  where a.attempt_id = p_attempt_id
    and a.user_id = v_user_id;

  if not found then
    raise exception 'Attempt not found or access denied.' using errcode = 'P0001';
  end if;

  select duration_minutes into v_duration
  from public.tests
  where test_id = v_attempt.test_id;

  if v_attempt.status <> 'IN_PROGRESS'::public.attempt_status then
    return jsonb_build_object(
      'attempt_id', p_attempt_id,
      'status', v_attempt.status,
      'editable', false
    );
  end if;

  v_deadline := case
    when v_duration > 0 then v_attempt.started_at + make_interval(mins => v_duration)
    else null
  end;

  if v_deadline is not null and now() >= v_deadline then
    v_result := public.finalize_attempt_internal(p_attempt_id, 'AUTO_SUBMITTED'::public.attempt_status);
    return v_result || jsonb_build_object('expired', true, 'editable', false);
  end if;

  if not exists (
    select 1
    from public.attempt_questions aq
    where aq.attempt_id = p_attempt_id
      and aq.question_id = p_question_id
  ) then
    raise exception 'Attempt question not found.' using errcode = 'P0001';
  end if;

  insert into public.attempt_answers (
    attempt_id, question_id, user_id, selected_answer,
    time_taken_seconds, marked_review, answered_at
  ) values (
    p_attempt_id, p_question_id, v_user_id, p_selected_answer,
    greatest(coalesce(p_time_taken_seconds, 0), 0), coalesce(p_marked_review, false), now()
  )
  on conflict (attempt_id, question_id)
  do update set
    selected_answer = excluded.selected_answer,
    time_taken_seconds = greatest(public.attempt_answers.time_taken_seconds, excluded.time_taken_seconds),
    marked_review = excluded.marked_review,
    answered_at = now(),
    updated_at = now()
  returning answer_id into v_answer_id;

  update public.attempt_questions
  set visited_at = coalesce(visited_at, now())
  where attempt_id = p_attempt_id
    and question_id = p_question_id;

  return jsonb_build_object(
    'answer_id', v_answer_id,
    'attempt_id', p_attempt_id,
    'status', 'IN_PROGRESS',
    'selected_answer', p_selected_answer,
    'marked_review', coalesce(p_marked_review, false),
    'answered_at', now()
  );
end;
$$;

-- Manual submit becomes AUTO_SUBMITTED when the authoritative deadline has
-- already elapsed. Both paths use exactly the same server-side scoring.
create or replace function public.submit_test_attempt(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_attempt public.attempts%rowtype;
  v_duration integer;
  v_deadline timestamptz;
  v_final_status public.attempt_status;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = 'P0001';
  end if;

  select a.*
  into v_attempt
  from public.attempts a
  where a.attempt_id = p_attempt_id
    and a.user_id = v_user_id;

  if not found then
    raise exception 'Attempt not found or access denied.' using errcode = 'P0001';
  end if;

  select duration_minutes into v_duration
  from public.tests
  where test_id = v_attempt.test_id;

  if v_attempt.status <> 'IN_PROGRESS'::public.attempt_status then
    return public.finalize_attempt_internal(p_attempt_id, 'SUBMITTED'::public.attempt_status);
  end if;

  v_deadline := case
    when v_duration > 0 then v_attempt.started_at + make_interval(mins => v_duration)
    else null
  end;

  v_final_status := case
    when v_deadline is not null and now() >= v_deadline
      then 'AUTO_SUBMITTED'::public.attempt_status
    else 'SUBMITTED'::public.attempt_status
  end;

  return public.finalize_attempt_internal(p_attempt_id, v_final_status);
end;
$$;

revoke all on function public.finalize_attempt_internal(uuid, public.attempt_status) from public, anon, authenticated;
revoke all on function public.get_attempt_navigation(uuid) from public;
revoke all on function public.visit_attempt_question(uuid, text) from public;
revoke all on function public.get_attempt_questions(uuid, integer, integer) from public;
revoke all on function public.save_attempt_answer(uuid, text, text, boolean, integer) from public;
revoke all on function public.submit_test_attempt(uuid) from public;

grant execute on function public.get_attempt_navigation(uuid) to authenticated;
grant execute on function public.visit_attempt_question(uuid, text) to authenticated;
grant execute on function public.get_attempt_questions(uuid, integer, integer) to authenticated;
grant execute on function public.save_attempt_answer(uuid, text, text, boolean, integer) to authenticated;
grant execute on function public.submit_test_attempt(uuid) to authenticated;

comment on function public.get_attempt_navigation(uuid) is
  'Protected complete navigator and authoritative timer snapshot. Never returns answer keys or explanations.';

comment on function public.visit_attempt_question(uuid, text) is
  'Persists a student-owned attempt question visit without exposing attempt_questions directly.';

commit;
