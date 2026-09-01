begin;

-- Keep the public promise focused on learning value. Infrastructure wording and
-- future commercial plans belong in operational documentation, not student UI.
insert into public.app_settings (setting_key, setting_value, description, is_public)
values (
  'hero_subtitle',
  'ચકાસેલ PYQ, વિભાગવાર પ્રેક્ટિસ, મોક ટેસ્ટ અને પ્રગતિ વિશ્લેષણ સાથે તૈયારી કરો.',
  'Landing page Gujarati learning-value statement.',
  true
)
on conflict (setting_key) do update set
  setting_value = excluded.setting_value,
  description = excluded.description,
  is_public = excluded.is_public,
  updated_at = now();

-- Counts represent published, student-ready tests only. Existing internal enum
-- values remain unchanged; the four categories are a presentation taxonomy.
create or replace function public.get_public_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with ready_tests as materialized (
    select t.test_type
    from public.tests t
    where t.status = 'PUBLISHED'
      and public.test_is_student_ready(t.test_id)
  )
  select jsonb_build_object(
    'mock_tests', (
      select count(*) from ready_tests where test_type = 'FULL_MOCK'
    ),
    'pyq_tests', (
      select count(*) from ready_tests where test_type = 'PYQ_FULL'
    ),
    'sectional_tests', (
      select count(*) from ready_tests where test_type in ('PYQ_SECTIONAL', 'SECTIONAL_MOCK')
    ),
    'topic_tests', (
      select count(*) from ready_tests where test_type = 'TOPIC_PRACTICE'
    ),
    -- Content-only compatibility fields can be removed after every public
    -- client is on the category-based homepage. Student-attempt totals are no
    -- longer exposed by this anonymous RPC.
    'published_questions', (
      select count(*)
      from public.questions q
      where q.question_status = 'PUBLISHED'
        and public.question_is_student_ready(q.question_id)
    ),
    'pyq_papers', (
      select count(distinct concat_ws('|', q.exam_id, q.exam_year, q.exam_date, q.shift_no, q.paper_code))
      from public.questions q
      where q.question_type = 'PYQ'
        and q.question_status = 'PUBLISHED'
        and public.question_is_student_ready(q.question_id)
    ),
    'published_tests', (select count(*) from ready_tests)
  );
$$;

revoke all on function public.get_public_stats() from public, anon, authenticated;
grant execute on function public.get_public_stats() to anon, authenticated;

comment on function public.get_public_stats() is
  'Anonymous content-only counts for the homepage; categories include only published student-ready tests and exclude student activity.';

commit;
