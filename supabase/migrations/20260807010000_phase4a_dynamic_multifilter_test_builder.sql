-- ScoreMore Phase 4A: Dynamic Multi-Filter Test Builder
-- Date: 2026-08-07
-- Scope:
--   * package-aware published-question catalogue
--   * multi-value AND/OR filtering
--   * server-side select-all
--   * original PYQ, completed PYQ, sectional and custom fixed tests
--   * active/superseded package safety
--   * unique-master-question enforcement
--
-- This migration is additive. Do not edit any previously applied migration.

begin;

-- Supporting indexes for package/version filtering and package membership lookup.
create index if not exists import_batches_phase4a_supersedes_idx
  on public.import_batches (supersedes_package_id)
  where supersedes_package_id is not null;

create index if not exists questions_phase4a_import_batch_idx
  on public.questions (import_batch_id, question_status, subject_id, topic_id)
  where import_batch_id is not null;

create index if not exists question_occurrences_phase4a_batch_idx
  on public.question_occurrences (import_batch_id, question_id, subject_id, topic_id)
  where import_batch_id is not null;

-- -----------------------------------------------------------------------------
-- 1. Package-aware published-question catalogue
-- -----------------------------------------------------------------------------

create or replace view public.phase4a_question_package_catalogue as
with batch_meta as (
  select
    b.import_batch_id,
    b.package_id,
    coalesce(b.package_version, 1) as package_version,
    b.supersedes_package_id,
    b.status::text as import_status,
    b.board_id,
    b.exam_id,
    b.exam_year,
    b.exam_date,
    b.shift_no,
    b.paper_code,
    b.section_code,
    b.declared_total_questions,
    b.extracted_source_questions,
    b.missing_question_count,
    b.generated_supplement_count,
    b.paper_completeness_status::text as paper_completeness_status,
    b.created_at as package_created_at,
    not exists (
      select 1
      from public.import_batches newer
      where newer.supersedes_package_id = b.package_id
        and newer.package_id is not null
    ) as is_active_version
  from public.import_batches b
  where b.package_id is not null
),
occurrence_membership as (
  select
    concat('O:', o.occurrence_id::text) as membership_key,
    bm.import_batch_id,
    bm.package_id,
    bm.package_version,
    bm.supersedes_package_id,
    bm.import_status,
    bm.is_active_version,
    bm.declared_total_questions,
    bm.extracted_source_questions,
    bm.missing_question_count,
    bm.generated_supplement_count,
    bm.paper_completeness_status,
    bm.package_created_at,
    o.occurrence_id,
    q.question_id,
    'SOURCE_PYQ'::text as membership_type,
    coalesce(
      o.original_question_no,
      i.item_index,
      q.original_question_no,
      q.sort_order,
      2147483647
    )::integer as source_order,
    o.original_question_no,
    o.board_id,
    o.exam_id,
    o.exam_year,
    o.exam_date,
    o.shift_no,
    nullif(upper(btrim(o.paper_code)), '') as paper_code,
    nullif(upper(btrim(o.section_code)), '') as section_code,
    o.subject_id,
    coalesce(o.topic_id, q.topic_id) as topic_id,
    q.language,
    q.difficulty::text as difficulty,
    q.question_type::text as question_type,
    q.question_text,
    false as is_supplemental
  from public.question_occurrences o
  join public.questions q
    on q.question_id = o.question_id
   and q.question_status = 'PUBLISHED'
  join batch_meta bm
    on bm.import_batch_id = o.import_batch_id
  left join public.import_batch_items i
    on i.import_item_id = o.import_item_id
),
direct_batch_membership as (
  select
    concat('D:', bm.import_batch_id::text, ':', q.question_id) as membership_key,
    bm.import_batch_id,
    bm.package_id,
    bm.package_version,
    bm.supersedes_package_id,
    bm.import_status,
    bm.is_active_version,
    bm.declared_total_questions,
    bm.extracted_source_questions,
    bm.missing_question_count,
    bm.generated_supplement_count,
    bm.paper_completeness_status,
    bm.package_created_at,
    null::uuid as occurrence_id,
    q.question_id,
    case
      when coalesce(q.is_supplemental, false) then 'SUPPLEMENTAL_NORMAL'
      when q.question_type = 'PYQ' then 'SOURCE_PYQ'
      else 'PACKAGE_NORMAL'
    end::text as membership_type,
    coalesce(
      q.original_question_no,
      public.try_parse_integer(i.normalized_payload ->> 'sort_order'),
      i.item_index,
      q.sort_order,
      2147483647
    )::integer as source_order,
    q.original_question_no,
    coalesce(q.board_id, bm.board_id) as board_id,
    coalesce(q.exam_id, bm.exam_id) as exam_id,
    coalesce(q.exam_year, bm.exam_year) as exam_year,
    coalesce(q.exam_date, bm.exam_date) as exam_date,
    coalesce(q.shift_no, bm.shift_no) as shift_no,
    coalesce(nullif(upper(btrim(q.paper_code)), ''), nullif(upper(btrim(bm.paper_code)), '')) as paper_code,
    coalesce(nullif(upper(btrim(q.section_code)), ''), nullif(upper(btrim(bm.section_code)), '')) as section_code,
    q.subject_id,
    q.topic_id,
    q.language,
    q.difficulty::text as difficulty,
    q.question_type::text as question_type,
    q.question_text,
    coalesce(q.is_supplemental, false) as is_supplemental
  from public.questions q
  join batch_meta bm
    on bm.import_batch_id = q.import_batch_id
  left join public.import_batch_items i
    on i.import_item_id = q.import_item_id
  where q.question_status = 'PUBLISHED'
    and not exists (
      select 1
      from public.question_occurrences o
      where o.question_id = q.question_id
        and o.import_batch_id = bm.import_batch_id
    )
),
unassigned_membership as (
  select
    concat('U:', q.question_id) as membership_key,
    null::uuid as import_batch_id,
    null::text as package_id,
    null::integer as package_version,
    null::text as supersedes_package_id,
    null::text as import_status,
    true as is_active_version,
    null::integer as declared_total_questions,
    null::integer as extracted_source_questions,
    0::integer as missing_question_count,
    0::integer as generated_supplement_count,
    null::text as paper_completeness_status,
    q.created_at as package_created_at,
    null::uuid as occurrence_id,
    q.question_id,
    'UNASSIGNED'::text as membership_type,
    coalesce(q.original_question_no, q.sort_order, 2147483647)::integer as source_order,
    q.original_question_no,
    q.board_id,
    q.exam_id,
    q.exam_year,
    q.exam_date,
    q.shift_no,
    nullif(upper(btrim(q.paper_code)), '') as paper_code,
    nullif(upper(btrim(q.section_code)), '') as section_code,
    q.subject_id,
    q.topic_id,
    q.language,
    q.difficulty::text as difficulty,
    q.question_type::text as question_type,
    q.question_text,
    coalesce(q.is_supplemental, false) as is_supplemental
  from public.questions q
  where q.question_status = 'PUBLISHED'
    and q.import_batch_id is null
    and not exists (
      select 1 from occurrence_membership om where om.question_id = q.question_id
    )
),
all_memberships as (
  select * from occurrence_membership
  union all
  select * from direct_batch_membership
  union all
  select * from unassigned_membership
)
select
  m.*,
  b.board_name,
  e.exam_name,
  s.subject_name,
  t.topic_name,
  t.topic_code
from all_memberships m
join public.boards b on b.board_id = m.board_id
join public.exams e on e.exam_id = m.exam_id
join public.subjects s on s.subject_id = m.subject_id
left join public.topics t on t.topic_id = m.topic_id;

revoke all on table public.phase4a_question_package_catalogue from public, anon, authenticated;

comment on view public.phase4a_question_package_catalogue is
  'Admin-only source for Phase 4A. It maps each published master question to import-package memberships without copying question content.';

-- -----------------------------------------------------------------------------
-- 2. Internal JSON filter helpers
-- -----------------------------------------------------------------------------

create or replace function public.phase4a_text_array(
  p_filters jsonb,
  p_key text
)
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(
    array(
      select upper(btrim(value))
      from jsonb_array_elements_text(
        case
          when jsonb_typeof(coalesce(p_filters, '{}'::jsonb) -> p_key) = 'array'
            then coalesce(p_filters, '{}'::jsonb) -> p_key
          else '[]'::jsonb
        end
      ) as item(value)
      where nullif(btrim(value), '') is not null
    ),
    array[]::text[]
  );
$$;

create or replace function public.phase4a_int_array(
  p_filters jsonb,
  p_key text
)
returns integer[]
language sql
immutable
set search_path = public
as $$
  select coalesce(
    array(
      select parsed
      from (
        select public.try_parse_integer(value) as parsed
        from jsonb_array_elements_text(
          case
            when jsonb_typeof(coalesce(p_filters, '{}'::jsonb) -> p_key) = 'array'
              then coalesce(p_filters, '{}'::jsonb) -> p_key
            else '[]'::jsonb
          end
        ) as item(value)
      ) parsed_values
      where parsed is not null
    ),
    array[]::integer[]
  );
$$;

create or replace function public.phase4a_bool(
  p_filters jsonb,
  p_key text,
  p_default boolean
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when jsonb_typeof(coalesce(p_filters, '{}'::jsonb) -> p_key) = 'boolean'
      then (coalesce(p_filters, '{}'::jsonb) ->> p_key)::boolean
    else p_default
  end;
$$;

revoke all on function public.phase4a_text_array(jsonb,text) from public, anon, authenticated;
revoke all on function public.phase4a_int_array(jsonb,text) from public, anon, authenticated;
revoke all on function public.phase4a_bool(jsonb,text,boolean) from public, anon, authenticated;

-- OR is used inside each array. AND is used across different arrays.
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
  where (v_include_superseded or c.is_active_version)
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

-- -----------------------------------------------------------------------------
-- 3. Dynamic facets and filtered question stack
-- -----------------------------------------------------------------------------

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
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  with
  full_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb))
  ),
  package_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'package_ids')
  ),
  board_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'board_ids')
  ),
  exam_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'exam_ids')
  ),
  subject_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'subject_ids')
  ),
  topic_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'topic_ids')
  ),
  language_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'languages')
  ),
  difficulty_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'difficulties')
  ),
  type_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'question_types')
  ),
  membership_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'membership_types')
  ),
  year_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'exam_years')
  ),
  shift_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'shift_nos')
  ),
  section_rows as materialized (
    select * from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb) - 'section_codes')
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

create or replace function public.search_phase4a_test_builder_questions(
  p_filters jsonb default '{}'::jsonb,
  p_search text default null,
  p_order text default 'PACKAGE_ORIGINAL',
  p_offset integer default 0,
  p_limit integer default 40
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_order text := upper(btrim(coalesce(p_order, 'PACKAGE_ORIGINAL')));
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_limit integer := least(greatest(coalesce(p_limit, 40), 1), 200);
  v_package_ids text[] := public.phase4a_text_array(p_filters, 'package_ids');
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if v_order not in ('PACKAGE_ORIGINAL', 'SUBJECT', 'TOPIC', 'QUESTION_ID', 'DETERMINISTIC_RANDOM') then
    raise exception 'Unsupported question ordering.' using errcode = 'P0001';
  end if;

  with filtered as materialized (
    select c.*
    from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb)) c
    where v_search = ''
       or lower(c.question_id) like '%' || v_search || '%'
       or lower(c.question_text) like '%' || v_search || '%'
       or lower(c.subject_name) like '%' || v_search || '%'
       or lower(coalesce(c.topic_name, '')) like '%' || v_search || '%'
       or lower(coalesce(c.topic_code, '')) like '%' || v_search || '%'
       or lower(coalesce(c.package_id, '')) like '%' || v_search || '%'
       or lower(coalesce(c.section_code, '')) like '%' || v_search || '%'
  ),
  grouped as materialized (
    select
      question_id,
      max(question_text) as question_text,
      max(question_type) as question_type,
      max(board_id) as board_id,
      max(board_name) as board_name,
      max(exam_id) as exam_id,
      max(exam_name) as exam_name,
      max(subject_id) as subject_id,
      max(subject_name) as subject_name,
      max(topic_id) as topic_id,
      max(topic_name) as topic_name,
      max(topic_code) as topic_code,
      max(language) as language,
      max(difficulty) as difficulty,
      min(source_order) as source_order,
      min(original_question_no) as original_question_no,
      min(coalesce(array_position(v_package_ids, package_id), 2147483647)) as package_rank,
      array_agg(distinct package_id order by package_id) filter (where package_id is not null) as package_ids,
      array_agg(distinct membership_type order by membership_type) as membership_types,
      count(*) as membership_count,
      count(distinct package_id) filter (where package_id is not null) as package_count,
      bool_or(is_supplemental) as is_supplemental,
      count(*) filter (where membership_type = 'SOURCE_PYQ') as source_memberships,
      count(*) filter (where is_supplemental) as supplemental_memberships
    from filtered
    group by question_id
  ),
  ordered as materialized (
    select
      g.*,
      row_number() over (
        order by
          case when v_order = 'PACKAGE_ORIGINAL' then g.package_rank end,
          case when v_order = 'PACKAGE_ORIGINAL' then g.source_order end,
          case when v_order = 'SUBJECT' then g.subject_name end,
          case when v_order = 'SUBJECT' then coalesce(g.topic_name, '') end,
          case when v_order = 'SUBJECT' then g.source_order end,
          case when v_order = 'TOPIC' then coalesce(g.topic_name, '') end,
          case when v_order = 'TOPIC' then g.subject_name end,
          case when v_order = 'TOPIC' then g.source_order end,
          case when v_order = 'QUESTION_ID' then g.question_id end,
          case when v_order = 'DETERMINISTIC_RANDOM' then md5(g.question_id) end,
          g.question_id
      ) as result_position
    from grouped g
  ),
  page as (
    select *
    from ordered
    order by result_position
    offset v_offset
    limit v_limit
  ),
  totals as (
    select
      count(*) as total,
      coalesce(sum(membership_count), 0) as memberships,
      coalesce(sum(greatest(membership_count - 1, 0)), 0) as repeated_memberships,
      count(*) filter (where is_supplemental) as supplemental_questions,
      count(*) filter (where source_memberships > 0) as source_questions
    from grouped
  )
  select jsonb_build_object(
    'total', totals.total,
    'offset', v_offset,
    'limit', v_limit,
    'order', v_order,
    'summary', jsonb_build_object(
      'unique_questions', totals.total,
      'matching_memberships', totals.memberships,
      'repeated_memberships', totals.repeated_memberships,
      'source_questions', totals.source_questions,
      'supplemental_questions', totals.supplemental_questions
    ),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'question_id', p.question_id,
          'question_text', p.question_text,
          'question_type', p.question_type,
          'board_id', p.board_id,
          'board_name', p.board_name,
          'exam_id', p.exam_id,
          'exam_name', p.exam_name,
          'subject_id', p.subject_id,
          'subject_name', p.subject_name,
          'topic_id', p.topic_id,
          'topic_name', p.topic_name,
          'topic_code', p.topic_code,
          'language', p.language,
          'difficulty', p.difficulty,
          'source_order', p.source_order,
          'original_question_no', p.original_question_no,
          'package_ids', coalesce(to_jsonb(p.package_ids), '[]'::jsonb),
          'membership_types', to_jsonb(p.membership_types),
          'membership_count', p.membership_count,
          'package_count', p.package_count,
          'is_supplemental', p.is_supplemental,
          'result_position', p.result_position
        ) order by p.result_position
      )
      from page p
    ), '[]'::jsonb)
  ) into v_result
  from totals;

  return v_result;
end;
$$;

revoke all on function public.search_phase4a_test_builder_questions(jsonb,text,text,integer,integer) from public, anon;
grant execute on function public.search_phase4a_test_builder_questions(jsonb,text,text,integer,integer) to authenticated;

create or replace function public.select_all_phase4a_test_builder_question_ids(
  p_filters jsonb default '{}'::jsonb,
  p_search text default null,
  p_order text default 'PACKAGE_ORIGINAL'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_order text := upper(btrim(coalesce(p_order, 'PACKAGE_ORIGINAL')));
  v_package_ids text[] := public.phase4a_text_array(p_filters, 'package_ids');
  v_total integer;
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if v_order not in ('PACKAGE_ORIGINAL', 'SUBJECT', 'TOPIC', 'QUESTION_ID', 'DETERMINISTIC_RANDOM') then
    raise exception 'Unsupported question ordering.' using errcode = 'P0001';
  end if;

  with filtered as materialized (
    select c.*
    from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb)) c
    where v_search = ''
       or lower(c.question_id) like '%' || v_search || '%'
       or lower(c.question_text) like '%' || v_search || '%'
       or lower(c.subject_name) like '%' || v_search || '%'
       or lower(coalesce(c.topic_name, '')) like '%' || v_search || '%'
       or lower(coalesce(c.topic_code, '')) like '%' || v_search || '%'
       or lower(coalesce(c.package_id, '')) like '%' || v_search || '%'
       or lower(coalesce(c.section_code, '')) like '%' || v_search || '%'
  ),
  grouped as materialized (
    select
      question_id,
      max(subject_name) as subject_name,
      max(topic_name) as topic_name,
      min(source_order) as source_order,
      min(coalesce(array_position(v_package_ids, package_id), 2147483647)) as package_rank
    from filtered
    group by question_id
  ),
  ordered as materialized (
    select
      question_id,
      row_number() over (
        order by
          case when v_order = 'PACKAGE_ORIGINAL' then package_rank end,
          case when v_order = 'PACKAGE_ORIGINAL' then source_order end,
          case when v_order = 'SUBJECT' then subject_name end,
          case when v_order = 'SUBJECT' then coalesce(topic_name, '') end,
          case when v_order = 'SUBJECT' then source_order end,
          case when v_order = 'TOPIC' then coalesce(topic_name, '') end,
          case when v_order = 'TOPIC' then subject_name end,
          case when v_order = 'TOPIC' then source_order end,
          case when v_order = 'QUESTION_ID' then question_id end,
          case when v_order = 'DETERMINISTIC_RANDOM' then md5(question_id) end,
          question_id
      ) as result_position
    from grouped
  )
  select count(*) into v_total from ordered;

  if v_total > 5000 then
    raise exception 'The filtered stack contains more than 5000 unique questions. Narrow the filters before selecting all.' using errcode = 'P0001';
  end if;

  with filtered as materialized (
    select c.*
    from public.phase4a_filter_catalogue(coalesce(p_filters, '{}'::jsonb)) c
    where v_search = ''
       or lower(c.question_id) like '%' || v_search || '%'
       or lower(c.question_text) like '%' || v_search || '%'
       or lower(c.subject_name) like '%' || v_search || '%'
       or lower(coalesce(c.topic_name, '')) like '%' || v_search || '%'
       or lower(coalesce(c.topic_code, '')) like '%' || v_search || '%'
       or lower(coalesce(c.package_id, '')) like '%' || v_search || '%'
       or lower(coalesce(c.section_code, '')) like '%' || v_search || '%'
  ),
  grouped as materialized (
    select
      question_id,
      max(subject_name) as subject_name,
      max(topic_name) as topic_name,
      min(source_order) as source_order,
      min(coalesce(array_position(v_package_ids, package_id), 2147483647)) as package_rank,
      count(*) as membership_count
    from filtered
    group by question_id
  ),
  ordered as materialized (
    select
      question_id,
      membership_count,
      row_number() over (
        order by
          case when v_order = 'PACKAGE_ORIGINAL' then package_rank end,
          case when v_order = 'PACKAGE_ORIGINAL' then source_order end,
          case when v_order = 'SUBJECT' then subject_name end,
          case when v_order = 'SUBJECT' then coalesce(topic_name, '') end,
          case when v_order = 'SUBJECT' then source_order end,
          case when v_order = 'TOPIC' then coalesce(topic_name, '') end,
          case when v_order = 'TOPIC' then subject_name end,
          case when v_order = 'TOPIC' then source_order end,
          case when v_order = 'QUESTION_ID' then question_id end,
          case when v_order = 'DETERMINISTIC_RANDOM' then md5(question_id) end,
          question_id
      ) as result_position
    from grouped
  )
  select jsonb_build_object(
    'total', count(*),
    'question_ids', coalesce(jsonb_agg(question_id order by result_position), '[]'::jsonb),
    'repeated_memberships', coalesce(sum(greatest(membership_count - 1, 0)), 0),
    'order', v_order
  ) into v_result
  from ordered;

  return v_result;
end;
$$;

revoke all on function public.select_all_phase4a_test_builder_question_ids(jsonb,text,text) from public, anon;
grant execute on function public.select_all_phase4a_test_builder_question_ids(jsonb,text,text) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Authoritative test resolution, preview and save
-- -----------------------------------------------------------------------------

create or replace function public.phase4a_resolve_test_questions(
  p_builder_mode text,
  p_filters jsonb default '{}'::jsonb,
  p_question_ids text[] default array[]::text[],
  p_order text default 'PACKAGE_ORIGINAL'
)
returns table (
  question_id text,
  position integer,
  package_id text,
  membership_type text,
  source_order integer,
  board_id text,
  exam_id text,
  exam_year integer,
  exam_date date,
  shift_no integer,
  paper_code text,
  section_code text,
  subject_id text,
  topic_id text,
  question_type text,
  is_supplemental boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_mode text := upper(btrim(coalesce(p_builder_mode, 'CUSTOM')));
  v_order text := upper(btrim(coalesce(p_order, 'PACKAGE_ORIGINAL')));
  v_package_ids text[] := public.phase4a_text_array(p_filters, 'package_ids');
  v_subject_ids text[] := public.phase4a_text_array(p_filters, 'subject_ids');
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if v_mode not in ('CUSTOM', 'PYQ_ORIGINAL', 'PYQ_COMPLETED', 'PYQ_SECTIONAL') then
    raise exception 'Unsupported Phase 4A builder mode.' using errcode = 'P0001';
  end if;

  if v_order not in ('PACKAGE_ORIGINAL', 'SUBJECT', 'TOPIC', 'QUESTION_ID', 'DETERMINISTIC_RANDOM', 'SELECTED') then
    raise exception 'Unsupported question ordering.' using errcode = 'P0001';
  end if;

  if v_mode in ('PYQ_ORIGINAL', 'PYQ_COMPLETED') and cardinality(v_package_ids) <> 1 then
    raise exception 'Select exactly one active import Package ID for this full-paper mode.' using errcode = 'P0001';
  end if;

  if v_mode = 'PYQ_SECTIONAL' and cardinality(v_package_ids) = 0 then
    raise exception 'Select at least one active import Package ID for a sectional test.' using errcode = 'P0001';
  end if;

  if v_mode = 'PYQ_SECTIONAL' and cardinality(v_subject_ids) = 0 then
    raise exception 'Select at least one subject for a sectional test.' using errcode = 'P0001';
  end if;

  if v_mode = 'CUSTOM' then
    return query
    with ids as materialized (
      select normalized.question_id, min(normalized.ordinality)::integer as selected_position
      from (
        select upper(btrim(value)) as question_id, ordinality
        from unnest(coalesce(p_question_ids, array[]::text[])) with ordinality as selected(value, ordinality)
        where nullif(btrim(value), '') is not null
      ) normalized
      group by normalized.question_id
    ),
    candidates as materialized (
      select
        ids.selected_position,
        c.*,
        row_number() over (
          partition by ids.question_id
          order by
            coalesce(array_position(v_package_ids, c.package_id), 2147483647),
            c.source_order,
            c.membership_key
        ) as candidate_rank
      from ids
      join public.questions q
        on q.question_id = ids.question_id
       and q.question_status = 'PUBLISHED'
      join public.phase4a_question_package_catalogue c
        on c.question_id = q.question_id
       and (public.phase4a_bool(p_filters, 'include_superseded', false) or c.is_active_version)
    )
    select
      c.question_id,
      row_number() over (
        order by
          case when v_order = 'SELECTED' then c.selected_position end,
          case when v_order = 'PACKAGE_ORIGINAL' then coalesce(array_position(v_package_ids, c.package_id), 2147483647) end,
          case when v_order = 'PACKAGE_ORIGINAL' then c.source_order end,
          case when v_order = 'SUBJECT' then c.subject_name end,
          case when v_order = 'SUBJECT' then coalesce(c.topic_name, '') end,
          case when v_order = 'SUBJECT' then c.source_order end,
          case when v_order = 'TOPIC' then coalesce(c.topic_name, '') end,
          case when v_order = 'TOPIC' then c.subject_name end,
          case when v_order = 'TOPIC' then c.source_order end,
          case when v_order = 'QUESTION_ID' then c.question_id end,
          case when v_order = 'DETERMINISTIC_RANDOM' then md5(c.question_id) end,
          c.selected_position,
          c.question_id
      )::integer as position,
      c.package_id,
      c.membership_type,
      c.source_order,
      c.board_id,
      c.exam_id,
      c.exam_year,
      c.exam_date,
      c.shift_no,
      c.paper_code,
      c.section_code,
      c.subject_id,
      c.topic_id,
      c.question_type,
      c.is_supplemental
    from candidates c
    where c.candidate_rank = 1;
    return;
  end if;

  if v_mode = 'PYQ_ORIGINAL' then
    return query
    with ranked as (
      select
        c.*,
        row_number() over (
          partition by c.question_id
          order by c.source_order, c.membership_key
        ) as duplicate_rank
      from public.phase4a_question_package_catalogue c
      where c.package_id = v_package_ids[1]
        and c.is_active_version
        and c.membership_type = 'SOURCE_PYQ'
        and c.question_type = 'PYQ'
        and not c.is_supplemental
    )
    select
      r.question_id,
      row_number() over (order by r.source_order, r.question_id)::integer as position,
      r.package_id,
      r.membership_type,
      r.source_order,
      r.board_id,
      r.exam_id,
      r.exam_year,
      r.exam_date,
      r.shift_no,
      r.paper_code,
      r.section_code,
      r.subject_id,
      r.topic_id,
      r.question_type,
      r.is_supplemental
    from ranked r
    where r.duplicate_rank = 1;
    return;
  end if;

  if v_mode = 'PYQ_COMPLETED' then
    return query
    with ranked as (
      select
        c.*,
        row_number() over (
          partition by c.question_id
          order by c.source_order, c.membership_key
        ) as duplicate_rank
      from public.phase4a_question_package_catalogue c
      where c.package_id = v_package_ids[1]
        and c.is_active_version
    )
    select
      r.question_id,
      row_number() over (order by r.source_order, r.question_id)::integer as position,
      r.package_id,
      r.membership_type,
      r.source_order,
      r.board_id,
      r.exam_id,
      r.exam_year,
      r.exam_date,
      r.shift_no,
      r.paper_code,
      r.section_code,
      r.subject_id,
      r.topic_id,
      r.question_type,
      r.is_supplemental
    from ranked r
    where r.duplicate_rank = 1;
    return;
  end if;

  return query
  with filtered as materialized (
    select c.*
    from public.phase4a_filter_catalogue(
      coalesce(p_filters, '{}'::jsonb)
      || jsonb_build_object('include_unassigned', false)
    ) c
  ),
  ranked as materialized (
    select
      c.*,
      row_number() over (
        partition by c.question_id
        order by
          coalesce(array_position(v_package_ids, c.package_id), 2147483647),
          c.source_order,
          c.membership_key
      ) as duplicate_rank
    from filtered c
  )
  select
    r.question_id,
    row_number() over (
      order by
        case when v_order = 'PACKAGE_ORIGINAL' then coalesce(array_position(v_package_ids, r.package_id), 2147483647) end,
        case when v_order = 'PACKAGE_ORIGINAL' then r.source_order end,
        case when v_order = 'SUBJECT' then r.subject_name end,
        case when v_order = 'SUBJECT' then coalesce(r.topic_name, '') end,
        case when v_order = 'SUBJECT' then r.source_order end,
        case when v_order = 'TOPIC' then coalesce(r.topic_name, '') end,
        case when v_order = 'TOPIC' then r.subject_name end,
        case when v_order = 'TOPIC' then r.source_order end,
        case when v_order = 'QUESTION_ID' then r.question_id end,
        case when v_order = 'DETERMINISTIC_RANDOM' then md5(r.question_id) end,
        r.question_id
    )::integer as position,
    r.package_id,
    r.membership_type,
    r.source_order,
    r.board_id,
    r.exam_id,
    r.exam_year,
    r.exam_date,
    r.shift_no,
    r.paper_code,
    r.section_code,
    r.subject_id,
    r.topic_id,
    r.question_type,
    r.is_supplemental
  from ranked r
  where r.duplicate_rank = 1;
end;
$$;

revoke all on function public.phase4a_resolve_test_questions(text,jsonb,text[],text) from public, anon, authenticated;

create or replace function public.preview_phase4a_dynamic_test(
  p_builder_mode text,
  p_filters jsonb default '{}'::jsonb,
  p_question_ids text[] default array[]::text[],
  p_order text default 'PACKAGE_ORIGINAL',
  p_custom_test_type public.test_type default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_mode text := upper(btrim(coalesce(p_builder_mode, 'CUSTOM')));
  v_package_ids text[] := public.phase4a_text_array(p_filters, 'package_ids');
  v_count integer;
  v_board_count integer;
  v_exam_count integer;
  v_subject_count integer;
  v_topic_count integer;
  v_supplemental integer;
  v_source integer;
  v_normal integer;
  v_repeated_memberships integer := 0;
  v_requested_custom integer := 0;
  v_test_type public.test_type;
  v_warnings jsonb := '[]'::jsonb;
  v_packages jsonb;
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  with resolved as materialized (
    select * from public.phase4a_resolve_test_questions(v_mode, p_filters, p_question_ids, p_order)
  )
  select
    count(*),
    count(distinct board_id),
    count(distinct exam_id),
    count(distinct subject_id),
    count(distinct topic_id) filter (where topic_id is not null),
    count(*) filter (where is_supplemental),
    count(*) filter (where membership_type = 'SOURCE_PYQ'),
    count(*) filter (where question_type <> 'PYQ')
  into
    v_count,
    v_board_count,
    v_exam_count,
    v_subject_count,
    v_topic_count,
    v_supplemental,
    v_source,
    v_normal
  from resolved;

  if v_mode = 'PYQ_ORIGINAL' then
    select greatest(count(*) - count(distinct question_id), 0)::integer
    into v_repeated_memberships
    from public.phase4a_question_package_catalogue
    where package_id = v_package_ids[1]
      and is_active_version
      and membership_type = 'SOURCE_PYQ'
      and question_type = 'PYQ'
      and not is_supplemental;
  elsif v_mode = 'PYQ_COMPLETED' then
    select greatest(count(*) - count(distinct question_id), 0)::integer
    into v_repeated_memberships
    from public.phase4a_question_package_catalogue
    where package_id = v_package_ids[1]
      and is_active_version;
  elsif v_mode = 'PYQ_SECTIONAL' then
    select greatest(count(*) - count(distinct question_id), 0)::integer
    into v_repeated_memberships
    from public.phase4a_filter_catalogue(
      coalesce(p_filters, '{}'::jsonb) || jsonb_build_object('include_unassigned', false)
    );
  end if;

  if v_mode = 'CUSTOM' then
    select greatest(count(*) - count(distinct c.question_id), 0)::integer
    into v_repeated_memberships
    from public.phase4a_question_package_catalogue c
    join (
      select distinct upper(btrim(value)) as question_id
      from unnest(coalesce(p_question_ids, array[]::text[])) as selected(value)
      where nullif(btrim(value), '') is not null
    ) requested on requested.question_id = c.question_id
    where public.phase4a_bool(p_filters, 'include_superseded', false) or c.is_active_version;

    select count(*) into v_requested_custom
    from (
      select distinct upper(btrim(value)) as question_id
      from unnest(coalesce(p_question_ids, array[]::text[])) as selected(value)
      where nullif(btrim(value), '') is not null
    ) requested;

    if v_requested_custom = 0 then
      raise exception 'Select at least one published question for a custom test.' using errcode = 'P0001';
    end if;

    if v_count <> v_requested_custom then
      raise exception 'One or more selected custom questions are unpublished or unavailable in the package catalogue.' using errcode = 'P0001';
    end if;
  end if;

  if v_count = 0 then
    raise exception 'No published question matches this builder configuration.' using errcode = 'P0001';
  end if;

  if v_board_count <> 1 or v_exam_count <> 1 then
    raise exception 'A test must contain questions from exactly one board and one exam.' using errcode = 'P0001';
  end if;

  v_test_type := case
    when v_mode = 'PYQ_ORIGINAL' then 'PYQ_FULL'::public.test_type
    when v_mode = 'PYQ_COMPLETED' then 'FULL_MOCK'::public.test_type
    when v_mode = 'PYQ_SECTIONAL' and v_supplemental = 0 and v_normal = 0 then 'PYQ_SECTIONAL'::public.test_type
    when v_mode = 'PYQ_SECTIONAL' then 'SECTIONAL_MOCK'::public.test_type
    else coalesce(p_custom_test_type, 'FULL_MOCK'::public.test_type)
  end;

  select coalesce(jsonb_agg(jsonb_build_object(
    'package_id', b.package_id,
    'package_version', b.package_version,
    'is_active', not exists (
      select 1 from public.import_batches newer where newer.supersedes_package_id = b.package_id
    ),
    'completeness_status', b.paper_completeness_status,
    'declared_total_questions', b.declared_total_questions,
    'extracted_source_questions', b.extracted_source_questions,
    'missing_question_count', b.missing_question_count,
    'generated_supplement_count', b.generated_supplement_count
  ) order by coalesce(array_position(v_package_ids, b.package_id), 2147483647)), '[]'::jsonb)
  into v_packages
  from public.import_batches b
  where b.package_id = any(v_package_ids);

  if cardinality(v_package_ids) > 1 then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'MULTIPLE_PACKAGES',
      'message', format('%s import packages are combined in this fixed test.', cardinality(v_package_ids))
    ));
  end if;

  if v_mode in ('PYQ_ORIGINAL', 'PYQ_COMPLETED') and (
    cardinality(public.phase4a_text_array(p_filters, 'subject_ids')) > 0
    or cardinality(public.phase4a_text_array(p_filters, 'topic_ids')) > 0
  ) then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'FULL_MODE_IGNORES_SECTION_FILTERS',
      'message', 'Subject and topic filters were used only to inspect the question stack. Full-paper resolution included the complete selected package.'
    ));
  end if;

  if v_repeated_memberships > 0 then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'UNIQUE_MASTER_COLLAPSE',
      'message', format('%s repeated package membership(s) were collapsed because ScoreMore links each master question only once per test.', v_repeated_memberships)
    ));
  end if;

  if v_supplemental > 0 then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'SUPPLEMENTAL_INCLUDED',
      'message', format('%s supplemental NORMAL question(s) are included. This test is not labelled as an exact original PYQ.', v_supplemental)
    ));
  end if;

  if exists (
    select 1
    from public.import_batches b
    where b.package_id = any(v_package_ids)
      and coalesce(b.paper_completeness_status::text, '') <> 'COMPLETE'
  ) then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'PARTIAL_PACKAGE',
      'message', 'At least one selected package is not a complete source paper. Review the package completeness labels.'
    ));
  end if;

  if v_mode = 'PYQ_ORIGINAL' and v_supplemental > 0 then
    raise exception 'Original PYQ mode cannot contain supplemental questions.' using errcode = 'P0001';
  end if;

  if v_mode = 'CUSTOM' and v_test_type in ('PYQ_FULL'::public.test_type, 'PYQ_SECTIONAL'::public.test_type) and v_normal > 0 then
    raise exception 'A custom PYQ test cannot contain NORMAL questions.' using errcode = 'P0001';
  end if;

  with resolved as materialized (
    select * from public.phase4a_resolve_test_questions(v_mode, p_filters, p_question_ids, p_order)
  ),
  metadata as (
    select
      min(board_id) as board_id,
      min(exam_id) as exam_id,
      case when count(distinct subject_id) = 1 then min(subject_id) end as catalogue_subject_id,
      case
        when count(distinct subject_id) = 1
         and count(distinct topic_id) filter (where topic_id is not null) = 1
          then min(topic_id) filter (where topic_id is not null)
      end as catalogue_topic_id,
      case when count(distinct exam_year) filter (where exam_year is not null) = 1 then min(exam_year) end as exam_year,
      case when count(distinct exam_date) filter (where exam_date is not null) = 1 then min(exam_date) end as exam_date,
      case when count(distinct shift_no) filter (where shift_no is not null) = 1 then min(shift_no) end as shift_no,
      case when count(distinct paper_code) filter (where paper_code is not null) = 1 then min(paper_code) end as paper_code,
      case when count(distinct section_code) filter (where section_code is not null) = 1 then min(section_code) end as section_code,
      coalesce(jsonb_agg(question_id order by position), '[]'::jsonb) as question_ids
    from resolved
  )
  select jsonb_build_object(
    'builder_mode', v_mode,
    'proposed_test_type', v_test_type,
    'question_count', v_count,
    'source_pyq_count', v_source,
    'supplemental_count', v_supplemental,
    'normal_count', v_normal,
    'repeated_memberships_removed', v_repeated_memberships,
    'subject_count', v_subject_count,
    'topic_count', v_topic_count,
    'board_id', metadata.board_id,
    'exam_id', metadata.exam_id,
    'catalogue_subject_id', metadata.catalogue_subject_id,
    'catalogue_topic_id', metadata.catalogue_topic_id,
    'exam_year', metadata.exam_year,
    'exam_date', metadata.exam_date,
    'shift_no', metadata.shift_no,
    'paper_code', metadata.paper_code,
    'section_code', metadata.section_code,
    'package_ids', to_jsonb(v_package_ids),
    'packages', v_packages,
    'ordering', upper(btrim(coalesce(p_order, 'PACKAGE_ORIGINAL'))),
    'duplicate_handling', 'UNIQUE_MASTER',
    'question_ids', metadata.question_ids,
    'warnings', v_warnings
  ) into v_result
  from metadata;

  return v_result;
end;
$$;

revoke all on function public.preview_phase4a_dynamic_test(text,jsonb,text[],text,public.test_type) from public, anon;
grant execute on function public.preview_phase4a_dynamic_test(text,jsonb,text[],text,public.test_type) to authenticated;

create or replace function public.save_phase4a_dynamic_test(
  p_test_id text,
  p_test_name text,
  p_builder_mode text,
  p_filters jsonb default '{}'::jsonb,
  p_question_ids text[] default array[]::text[],
  p_order text default 'PACKAGE_ORIGINAL',
  p_custom_test_type public.test_type default null,
  p_duration_minutes integer default 60,
  p_marks_per_question numeric default 1,
  p_negative_marks numeric default 0,
  p_sort_order integer default 0,
  p_publish boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_preview jsonb;
  v_ids text[];
  v_result jsonb;
  v_test_type public.test_type;
  v_subject_id text;
  v_topic_id text;
  v_board_id text;
  v_exam_id text;
  v_exam_year integer;
  v_exam_date date;
  v_shift_no integer;
  v_paper_code text;
  v_section_code text;
  v_test_id text := upper(btrim(coalesce(p_test_id, '')));
  v_mode text := upper(btrim(coalesce(p_builder_mode, 'CUSTOM')));
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  v_preview := public.preview_phase4a_dynamic_test(
    v_mode,
    coalesce(p_filters, '{}'::jsonb),
    coalesce(p_question_ids, array[]::text[]),
    p_order,
    p_custom_test_type
  );

  select array_agg(question_id order by position)
  into v_ids
  from public.phase4a_resolve_test_questions(
    v_mode,
    coalesce(p_filters, '{}'::jsonb),
    coalesce(p_question_ids, array[]::text[]),
    p_order
  );

  v_board_id := v_preview ->> 'board_id';
  v_exam_id := v_preview ->> 'exam_id';
  v_subject_id := nullif(v_preview ->> 'catalogue_subject_id', '');
  v_topic_id := nullif(v_preview ->> 'catalogue_topic_id', '');
  v_test_type := (v_preview ->> 'proposed_test_type')::public.test_type;
  v_exam_year := public.try_parse_integer(v_preview ->> 'exam_year');
  v_exam_date := public.try_parse_date(v_preview ->> 'exam_date');
  v_shift_no := public.try_parse_integer(v_preview ->> 'shift_no');
  v_paper_code := nullif(upper(btrim(v_preview ->> 'paper_code')), '');
  v_section_code := nullif(upper(btrim(v_preview ->> 'section_code')), '');

  -- The existing locked fixed-list RPC remains the single structural writer.
  v_result := public.save_fixed_question_test(
    v_test_id,
    p_test_name,
    v_board_id,
    v_exam_id,
    v_subject_id,
    v_topic_id,
    v_test_type,
    p_duration_minutes,
    p_marks_per_question,
    p_negative_marks,
    p_sort_order,
    v_ids,
    p_publish
  );

  update public.tests
  set
    exam_year = v_exam_year,
    exam_date = v_exam_date,
    shift_no = v_shift_no,
    paper_code = v_paper_code,
    section_code = v_section_code,
    question_filter = jsonb_build_object(
      'schema', 'scoremore.phase4a-test-builder',
      'schema_version', 1,
      'builder_mode', v_mode,
      'import_package_ids', coalesce(v_preview -> 'package_ids', '[]'::jsonb),
      'filters', coalesce(p_filters, '{}'::jsonb),
      'ordering', upper(btrim(coalesce(p_order, 'PACKAGE_ORIGINAL'))),
      'duplicate_handling', 'UNIQUE_MASTER',
      'source_pyq_count', coalesce((v_preview ->> 'source_pyq_count')::integer, 0),
      'supplemental_count', coalesce((v_preview ->> 'supplemental_count')::integer, 0),
      'warnings', coalesce(v_preview -> 'warnings', '[]'::jsonb),
      'saved_at', now()
    ),
    updated_at = now()
  where test_id = v_test_id;

  insert into public.admin_audit_logs (
    admin_user_id,
    action,
    entity_type,
    entity_id,
    details
  ) values (
    v_admin,
    'SAVE_PHASE4A_DYNAMIC_TEST',
    'TEST',
    v_test_id,
    jsonb_build_object(
      'builder_mode', v_mode,
      'test_type', v_test_type,
      'question_count', cardinality(v_ids),
      'package_ids', v_preview -> 'package_ids',
      'published', coalesce(p_publish, false),
      'duplicate_handling', 'UNIQUE_MASTER'
    )
  );

  return v_result || jsonb_build_object(
    'builder_mode', v_mode,
    'test_type', v_test_type,
    'preview', v_preview
  );
end;
$$;

revoke all on function public.save_phase4a_dynamic_test(
  text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean
) from public, anon;

grant execute on function public.save_phase4a_dynamic_test(
  text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean
) to authenticated;

comment on function public.get_phase4a_test_builder_facets(jsonb) is
  'Admin-only dynamic multi-select facets. Values inside a group are OR; groups are AND.';
comment on function public.search_phase4a_test_builder_questions(jsonb,text,text,integer,integer) is
  'Admin-only paged unique-master question stack for Phase 4A.';
comment on function public.select_all_phase4a_test_builder_question_ids(jsonb,text,text) is
  'Admin-only server-side select-all for the current Phase 4A filter stack.';
comment on function public.preview_phase4a_dynamic_test(text,jsonb,text[],text,public.test_type) is
  'Resolves and validates a Phase 4A fixed test without writing it.';
comment on function public.save_phase4a_dynamic_test(text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean) is
  'Admin-only authoritative Phase 4A writer. It re-resolves filters, uses unique master questions and delegates fixed-list writes to save_fixed_question_test.';

commit;
