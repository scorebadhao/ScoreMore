-- ScoreMore Simple Test Builder + Catalogue Control verification
-- Read-only checks. Run as postgres in Supabase SQL Editor.

select version
from supabase_migrations.schema_migrations
where version = '20260806010000';

select
  to_regprocedure('public.save_fixed_question_test_v2(text,text,text,text,text,text,public.test_type,integer,numeric,numeric,integer,text[],boolean,integer,date,integer,text,text)') is not null
    as save_test_v2_exists,
  to_regprocedure('public.set_admin_test_status(text,public.test_status)') is not null
    as status_rpc_exists;

select
  test_id,
  test_name,
  test_type,
  status,
  question_count,
  exam_year,
  exam_date,
  shift_no,
  paper_code,
  section_code,
  sort_order
from public.tests
order by updated_at desc
limit 25;

select
  t.test_id,
  t.question_count as declared_questions,
  count(l.question_id) as linked_questions,
  count(*) filter (where q.question_status = 'PUBLISHED') as published_links
from public.tests t
left join public.test_question_links l on l.test_id = t.test_id
left join public.questions q on q.question_id = l.question_id
group by t.test_id, t.question_count
order by t.test_id;

select
  test_id,
  position,
  question_id
from public.test_question_links
where test_id = '<REPLACE_WITH_TEST_ID>'
order by position;
