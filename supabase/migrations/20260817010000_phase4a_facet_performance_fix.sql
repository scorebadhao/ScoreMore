begin;

-- ScoreMore DEV — Dynamic Facet Performance Fix v1.0
-- Forward-only replacement of the facet RPC. Historical migrations remain untouched.
-- The previous RPC invoked phase4a_filter_catalogue() 13 times per refresh.
-- This version materializes the student-ready catalogue once, then derives every
-- self-excluding facet from that single in-memory rowset.

create or replace function public.get_phase4a_test_builder_facets(
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
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

  with
  base_rows as materialized (
    select c.*
    from public.phase4a_filter_catalogue(
      jsonb_build_object(
        'include_superseded', v_include_superseded,
        'include_supplemental', v_include_supplemental,
        'include_unassigned', v_include_unassigned,
        'completeness_statuses', to_jsonb(v_completeness)
      )
    ) c
  ),
  matched as materialized (
    select
      c.*,
      (cardinality(v_package_ids) = 0 or c.package_id = any(v_package_ids)) as m_package,
      (cardinality(v_board_ids) = 0 or c.board_id = any(v_board_ids)) as m_board,
      (cardinality(v_exam_ids) = 0 or c.exam_id = any(v_exam_ids)) as m_exam,
      (cardinality(v_subject_ids) = 0 or c.subject_id = any(v_subject_ids)) as m_subject,
      (cardinality(v_topic_ids) = 0 or c.topic_id = any(v_topic_ids)) as m_topic,
      (cardinality(v_languages) = 0 or upper(c.language) = any(v_languages)) as m_language,
      (cardinality(v_difficulties) = 0 or upper(c.difficulty) = any(v_difficulties)) as m_difficulty,
      (cardinality(v_question_types) = 0 or upper(c.question_type) = any(v_question_types)) as m_question_type,
      (cardinality(v_membership_types) = 0 or upper(c.membership_type) = any(v_membership_types)) as m_membership_type,
      (cardinality(v_exam_years) = 0 or c.exam_year = any(v_exam_years)) as m_exam_year,
      (cardinality(v_shift_nos) = 0 or c.shift_no = any(v_shift_nos)) as m_shift_no,
      (cardinality(v_section_codes) = 0 or upper(coalesce(c.section_code, '')) = any(v_section_codes)) as m_section_code
    from base_rows c
  ),
  full_rows as materialized (
    select * from matched
    where m_package and m_board and m_exam and m_subject and m_topic
      and m_language and m_difficulty and m_question_type and m_membership_type
      and m_exam_year and m_shift_no and m_section_code
  ),
  package_rows as materialized (
    select * from matched
    where m_board and m_exam and m_subject and m_topic
      and m_language and m_difficulty and m_question_type and m_membership_type
      and m_exam_year and m_shift_no and m_section_code
  ),
  board_rows as materialized (
    select * from matched
    where m_package and m_exam and m_subject and m_topic
      and m_language and m_difficulty and m_question_type and m_membership_type
      and m_exam_year and m_shift_no and m_section_code
  ),
  exam_rows as materialized (
    select * from matched
    where m_package and m_board and m_subject and m_topic
      and m_language and m_difficulty and m_question_type and m_membership_type
      and m_exam_year and m_shift_no and m_section_code
  ),
  subject_rows as materialized (
    select * from matched
    where m_package and m_board and m_exam and m_topic
      and m_language and m_difficulty and m_question_type and m_membership_type
      and m_exam_year and m_shift_no and m_section_code
  ),
  topic_rows as materialized (
    select * from matched
    where m_package and m_board and m_exam and m_subject
      and m_language and m_difficulty and m_question_type and m_membership_type
      and m_exam_year and m_shift_no and m_section_code
  ),
  language_rows as materialized (
    select * from matched
    where m_package and m_board and m_exam and m_subject and m_topic
      and m_difficulty and m_question_type and m_membership_type
      and m_exam_year and m_shift_no and m_section_code
  ),
  difficulty_rows as materialized (
    select * from matched
    where m_package and m_board and m_exam and m_subject and m_topic
      and m_language and m_question_type and m_membership_type
      and m_exam_year and m_shift_no and m_section_code
  ),
  type_rows as materialized (
    select * from matched
    where m_package and m_board and m_exam and m_subject and m_topic
      and m_language and m_difficulty and m_membership_type
      and m_exam_year and m_shift_no and m_section_code
  ),
  membership_rows as materialized (
    select * from matched
    where m_package and m_board and m_exam and m_subject and m_topic
      and m_language and m_difficulty and m_question_type
      and m_exam_year and m_shift_no and m_section_code
  ),
  year_rows as materialized (
    select * from matched
    where m_package and m_board and m_exam and m_subject and m_topic
      and m_language and m_difficulty and m_question_type and m_membership_type
      and m_shift_no and m_section_code
  ),
  shift_rows as materialized (
    select * from matched
    where m_package and m_board and m_exam and m_subject and m_topic
      and m_language and m_difficulty and m_question_type and m_membership_type
      and m_exam_year and m_section_code
  ),
  section_rows as materialized (
    select * from matched
    where m_package and m_board and m_exam and m_subject and m_topic
      and m_language and m_difficulty and m_question_type and m_membership_type
      and m_exam_year and m_shift_no
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'matching_memberships', (select count(*) from full_rows),
      'unique_questions', (select count(distinct question_id) from full_rows),
      'packages', (select count(distinct package_id) from full_rows where package_id is not null),
      'source_pyq', (select count(distinct question_id) from full_rows where membership_type = 'SOURCE_PYQ'),
      'supplemental', (select count(distinct question_id) from full_rows where is_supplemental),
      'repeated_memberships', greatest(
        (select count(*) from full_rows) - (select count(distinct question_id) from full_rows),
        0
      )
    ),
    'packages', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.is_active desc, option_row.package_created_at desc, option_row.value)
      from (
        select
          package_id as value,
          package_id as label,
          max(package_version) as package_version,
          bool_or(is_active_version) as is_active,
          max(paper_completeness_status) as completeness_status,
          max(declared_total_questions) as declared_total_questions,
          count(distinct question_id) as count,
          count(distinct question_id) filter (where membership_type = 'SOURCE_PYQ') as source_count,
          count(distinct question_id) filter (where is_supplemental) as supplemental_count,
          max(package_created_at) as package_created_at
        from package_rows
        where package_id is not null
        group by package_id
      ) option_row
    ), '[]'::jsonb),
    'boards', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.label)
      from (
        select board_id as value, max(board_name) as label, count(distinct question_id) as count
        from board_rows group by board_id
      ) option_row
    ), '[]'::jsonb),
    'exams', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.label)
      from (
        select exam_id as value, max(exam_name) as label, count(distinct question_id) as count
        from exam_rows group by exam_id
      ) option_row
    ), '[]'::jsonb),
    'subjects', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.label)
      from (
        select subject_id as value, max(subject_name) as label, count(distinct question_id) as count
        from subject_rows group by subject_id
      ) option_row
    ), '[]'::jsonb),
    'topics', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.label)
      from (
        select topic_id as value, max(topic_name) as label, max(topic_code) as code, count(distinct question_id) as count
        from topic_rows where topic_id is not null group by topic_id
      ) option_row
    ), '[]'::jsonb),
    'languages', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.value)
      from (
        select upper(language) as value, upper(language) as label, count(distinct question_id) as count
        from language_rows group by upper(language)
      ) option_row
    ), '[]'::jsonb),
    'difficulties', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.value)
      from (
        select upper(difficulty) as value, upper(difficulty) as label, count(distinct question_id) as count
        from difficulty_rows group by upper(difficulty)
      ) option_row
    ), '[]'::jsonb),
    'question_types', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.value)
      from (
        select upper(question_type) as value, upper(question_type) as label, count(distinct question_id) as count
        from type_rows group by upper(question_type)
      ) option_row
    ), '[]'::jsonb),
    'membership_types', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.value)
      from (
        select upper(membership_type) as value, replace(upper(membership_type), '_', ' ') as label, count(distinct question_id) as count
        from membership_rows group by upper(membership_type)
      ) option_row
    ), '[]'::jsonb),
    'exam_years', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.value desc)
      from (
        select exam_year as value, exam_year::text as label, count(distinct question_id) as count
        from year_rows where exam_year is not null group by exam_year
      ) option_row
    ), '[]'::jsonb),
    'shift_nos', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.value)
      from (
        select shift_no as value, concat('Shift ', shift_no) as label, count(distinct question_id) as count
        from shift_rows where shift_no is not null group by shift_no
      ) option_row
    ), '[]'::jsonb),
    'section_codes', coalesce((
      select jsonb_agg(to_jsonb(option_row) order by option_row.value)
      from (
        select upper(section_code) as value, replace(upper(section_code), '_', ' ') as label, count(distinct question_id) as count
        from section_rows where section_code is not null group by upper(section_code)
      ) option_row
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_phase4a_test_builder_facets(jsonb) from public, anon;
grant execute on function public.get_phase4a_test_builder_facets(jsonb) to authenticated;

comment on function public.get_phase4a_test_builder_facets(jsonb) is
  'Admin-only Phase 4A dynamic facet counts. Performance v1: one student-ready catalogue materialization per refresh with self-excluding facet semantics preserved.';

commit;
