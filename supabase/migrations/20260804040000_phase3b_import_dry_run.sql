-- ScoreMore Phase 3B: safe HTML package dry-run staging and reconciliation
-- Date: 2026-08-04
-- Scope: persistent dry-run batches/items, exact file/package reuse, intra-package
--        duplicate/conflict detection and admin-only report RPCs.
-- No draft question or published question is created by this migration.

begin;

-- Persist package-level validation messages alongside item-level reconciliation.
alter table public.import_batches
  add column package_errors jsonb not null default '[]'::jsonb,
  add column package_warnings jsonb not null default '[]'::jsonb;

alter table public.import_batches
  add constraint import_batches_package_errors_array
    check (jsonb_typeof(package_errors) = 'array'),
  add constraint import_batches_package_warnings_array
    check (jsonb_typeof(package_warnings) = 'array');

-- Canonical, database-shaped question payload used for item reconciliation.
-- Source wording and options are preserved; catalogue IDs and enums are normalized.
create or replace function public.normalize_import_question_payload(p_question jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_options jsonb := case
    when jsonb_typeof(p_question -> 'options') = 'object' then p_question -> 'options'
    else '{}'::jsonb
  end;
begin
  return jsonb_build_object(
    'source_record_id', nullif(btrim(p_question ->> 'source_record_id'), ''),
    'proposed_question_id', upper(nullif(btrim(p_question ->> 'proposed_question_id'), '')),
    'question_type', upper(nullif(btrim(p_question ->> 'question_type'), '')),
    'board_id', upper(nullif(btrim(p_question ->> 'board_id'), '')),
    'exam_id', upper(nullif(btrim(p_question ->> 'exam_id'), '')),
    'exam_year', public.try_parse_integer(p_question ->> 'exam_year'),
    'exam_date', public.try_parse_date(p_question ->> 'exam_date'),
    'shift_no', public.try_parse_integer(p_question ->> 'shift_no'),
    'paper_code', upper(nullif(btrim(p_question ->> 'paper_code'), '')),
    'original_question_no', public.try_parse_integer(p_question ->> 'original_question_no'),
    'sort_order', public.try_parse_integer(p_question ->> 'sort_order'),
    'subject_id', upper(nullif(btrim(p_question ->> 'subject_id'), '')),
    'topic_id', upper(nullif(btrim(p_question ->> 'topic_id'), '')),
    'section_code', upper(nullif(btrim(p_question ->> 'section_code'), '')),
    'language', upper(nullif(btrim(p_question ->> 'language'), '')),
    'difficulty', upper(nullif(btrim(p_question ->> 'difficulty'), '')),
    'source_page', public.try_parse_integer(p_question ->> 'source_page'),
    'source_question_id', nullif(btrim(p_question ->> 'source_question_id'), ''),
    'content_origin', upper(nullif(btrim(p_question ->> 'content_origin'), '')),
    'verification_status', upper(nullif(btrim(p_question ->> 'verification_status'), '')),
    'question_text', p_question ->> 'question_text',
    'options', jsonb_build_object(
      'A', v_options ->> 'A',
      'B', v_options ->> 'B',
      'C', v_options ->> 'C',
      'D', v_options ->> 'D'
    ),
    'correct_answer', upper(nullif(btrim(p_question ->> 'correct_answer'), '')),
    'answer_source', upper(nullif(btrim(p_question ->> 'answer_source'), '')),
    'explanation', p_question ->> 'explanation',
    'image_refs', case
      when jsonb_typeof(p_question -> 'image_refs') = 'array' then p_question -> 'image_refs'
      else '[]'::jsonb
    end,
    'content_id', nullif(btrim(p_question ->> 'content_id'), ''),
    'group_id', nullif(btrim(p_question ->> 'group_id'), ''),
    'group_type', upper(nullif(btrim(p_question ->> 'group_type'), '')),
    'group_text', p_question ->> 'group_text',
    'tags', case
      when jsonb_typeof(p_question -> 'tags') = 'array' then p_question -> 'tags'
      else '[]'::jsonb
    end
  );
end;
$$;

-- Strict server-side shape checks aligned to the versioned JSON Schema.
-- These prevent unsupported fields or wrong JSON types from being silently discarded.
create or replace function public.validate_import_manifest_shape(p_manifest jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_errors jsonb := '[]'::jsonb;
  v_key text;
  v_required text;
  v_source jsonb;
  v_defaults jsonb;
begin
  if p_manifest is null or jsonb_typeof(p_manifest) <> 'object' then
    return jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_PACKAGE_OBJECT',
      'message', 'The import payload must be a JSON object.',
      'path', '$'
    ));
  end if;

  for v_key in select jsonb_object_keys(p_manifest) loop
    if v_key not in ('schema', 'schema_version', 'package_id', 'generated_at', 'generator', 'source', 'defaults', 'questions') then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'UNSUPPORTED_FIELD',
        'message', format('Unsupported top-level field: %s', v_key),
        'path', format('$.%s', v_key)
      ));
    end if;
  end loop;

  foreach v_required in array array['schema', 'schema_version', 'package_id', 'source', 'defaults', 'questions'] loop
    if not (p_manifest ? v_required) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_TOP_LEVEL_FIELD',
        'message', format('%s is required.', v_required),
        'path', format('$.%s', v_required)
      ));
    end if;
  end loop;

  foreach v_key in array array['schema', 'schema_version', 'package_id', 'generated_at', 'generator'] loop
    if p_manifest ? v_key
       and p_manifest -> v_key <> 'null'::jsonb
       and jsonb_typeof(p_manifest -> v_key) <> 'string' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_JSON_TYPE',
        'message', format('%s must be JSON text.', v_key),
        'path', format('$.%s', v_key)
      ));
    end if;
  end loop;

  v_source := p_manifest -> 'source';
  if jsonb_typeof(v_source) = 'object' then
    for v_key in select jsonb_object_keys(v_source) loop
      if v_key not in ('source_type', 'original_file_name', 'board_id', 'exam_id', 'exam_year', 'exam_date', 'shift_no', 'paper_code', 'language', 'source_checksum_sha256', 'notes') then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'UNSUPPORTED_FIELD',
          'message', format('Unsupported source field: %s', v_key),
          'path', format('$.source.%s', v_key)
        ));
      end if;
    end loop;

    foreach v_required in array array['source_type', 'original_file_name', 'board_id', 'exam_id'] loop
      if not (v_source ? v_required)
         or jsonb_typeof(v_source -> v_required) <> 'string'
         or nullif(btrim(v_source ->> v_required), '') is null then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'INVALID_SOURCE_FIELD',
          'message', format('%s must be non-empty text.', v_required),
          'path', format('$.source.%s', v_required)
        ));
      end if;
    end loop;

    foreach v_key in array array['paper_code', 'language', 'source_checksum_sha256', 'notes'] loop
      if v_source ? v_key
         and v_source -> v_key <> 'null'::jsonb
         and jsonb_typeof(v_source -> v_key) <> 'string' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'INVALID_JSON_TYPE',
          'message', format('%s must be JSON text or null.', v_key),
          'path', format('$.source.%s', v_key)
        ));
      end if;
    end loop;

    foreach v_key in array array['exam_year', 'shift_no'] loop
      if v_source ? v_key and v_source -> v_key <> 'null'::jsonb then
        if jsonb_typeof(v_source -> v_key) <> 'number'
           or public.try_parse_integer(v_source ->> v_key) is null then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'code', 'INVALID_INTEGER',
            'message', format('%s must be a JSON integer or null.', v_key),
            'path', format('$.source.%s', v_key)
          ));
        end if;
      end if;
    end loop;

    if v_source ? 'exam_year'
       and public.try_parse_integer(v_source ->> 'exam_year') is not null
       and public.try_parse_integer(v_source ->> 'exam_year') not between 1900 and 2200 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_EXAM_YEAR',
        'message', 'exam_year must be between 1900 and 2200.',
        'path', '$.source.exam_year'
      ));
    end if;

    if v_source ? 'shift_no'
       and public.try_parse_integer(v_source ->> 'shift_no') is not null
       and public.try_parse_integer(v_source ->> 'shift_no') < 1 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_SHIFT_NO',
        'message', 'shift_no must be at least 1.',
        'path', '$.source.shift_no'
      ));
    end if;

    if v_source ? 'exam_date'
       and v_source -> 'exam_date' <> 'null'::jsonb
       and (
         jsonb_typeof(v_source -> 'exam_date') <> 'string'
         or public.try_parse_date(v_source ->> 'exam_date') is null
       ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_DATE',
        'message', 'exam_date must be a valid YYYY-MM-DD date or null.',
        'path', '$.source.exam_date'
      ));
    end if;

    if v_source ? 'source_checksum_sha256'
       and v_source -> 'source_checksum_sha256' <> 'null'::jsonb
       and (
         jsonb_typeof(v_source -> 'source_checksum_sha256') <> 'string'
         or (v_source ->> 'source_checksum_sha256') !~ '^[0-9a-f]{64}$'
       ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_SOURCE_CHECKSUM',
        'message', 'source_checksum_sha256 must be lowercase SHA-256 hex or null.',
        'path', '$.source.source_checksum_sha256'
      ));
    end if;
  end if;

  v_defaults := p_manifest -> 'defaults';
  if jsonb_typeof(v_defaults) = 'object' then
    for v_key in select jsonb_object_keys(v_defaults) loop
      if v_key not in ('question_type', 'board_id', 'exam_id', 'exam_year', 'exam_date', 'shift_no', 'paper_code', 'section_code', 'language', 'difficulty', 'content_origin', 'verification_status', 'answer_source', 'tags') then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'UNSUPPORTED_FIELD',
          'message', format('Unsupported defaults field: %s', v_key),
          'path', format('$.defaults.%s', v_key)
        ));
      end if;
    end loop;

    foreach v_key in array array[
      'question_type', 'board_id', 'exam_id', 'paper_code', 'section_code', 'language',
      'difficulty', 'content_origin', 'verification_status', 'answer_source'
    ] loop
      if v_defaults ? v_key
         and v_defaults -> v_key <> 'null'::jsonb
         and jsonb_typeof(v_defaults -> v_key) <> 'string' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'INVALID_JSON_TYPE',
          'message', format('%s must be JSON text or null.', v_key),
          'path', format('$.defaults.%s', v_key)
        ));
      end if;
    end loop;

    foreach v_key in array array['exam_year', 'shift_no'] loop
      if v_defaults ? v_key and v_defaults -> v_key <> 'null'::jsonb then
        if jsonb_typeof(v_defaults -> v_key) <> 'number'
           or public.try_parse_integer(v_defaults ->> v_key) is null then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'code', 'INVALID_INTEGER',
            'message', format('%s must be a JSON integer or null.', v_key),
            'path', format('$.defaults.%s', v_key)
          ));
        end if;
      end if;
    end loop;

    if v_defaults ? 'exam_year'
       and public.try_parse_integer(v_defaults ->> 'exam_year') is not null
       and public.try_parse_integer(v_defaults ->> 'exam_year') not between 1900 and 2200 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_EXAM_YEAR',
        'message', 'exam_year must be between 1900 and 2200.',
        'path', '$.defaults.exam_year'
      ));
    end if;

    if v_defaults ? 'shift_no'
       and public.try_parse_integer(v_defaults ->> 'shift_no') is not null
       and public.try_parse_integer(v_defaults ->> 'shift_no') < 1 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_SHIFT_NO',
        'message', 'shift_no must be at least 1.',
        'path', '$.defaults.shift_no'
      ));
    end if;

    if v_defaults ? 'exam_date'
       and v_defaults -> 'exam_date' <> 'null'::jsonb
       and (
         jsonb_typeof(v_defaults -> 'exam_date') <> 'string'
         or public.try_parse_date(v_defaults ->> 'exam_date') is null
       ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_DATE',
        'message', 'exam_date must be a valid YYYY-MM-DD date or null.',
        'path', '$.defaults.exam_date'
      ));
    end if;

    if v_defaults ? 'tags' then
      if jsonb_typeof(v_defaults -> 'tags') <> 'array' then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'INVALID_TAGS',
          'message', 'tags must be an array of unique text values.',
          'path', '$.defaults.tags'
        ));
      elsif exists (
        select 1 from jsonb_array_elements(v_defaults -> 'tags') as tag_rows(tag_value)
        where jsonb_typeof(tag_value) <> 'string'
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'NON_TEXT_TAG',
          'message', 'Every default tag must be JSON text.',
          'path', '$.defaults.tags'
        ));
      elsif (
        select count(*) <> count(distinct btrim(tag_value))
        from jsonb_array_elements_text(v_defaults -> 'tags') as tag_rows(tag_value)
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'DUPLICATE_TAG',
          'message', 'Default tags must contain unique trimmed values.',
          'path', '$.defaults.tags'
        ));
      end if;
    end if;
  end if;

  return v_errors;
end;
$$;

create or replace function public.validate_import_raw_item_shape(p_item jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_errors jsonb := '[]'::jsonb;
  v_key text;
  v_required text;
  v_options jsonb;
  v_entry jsonb;
  v_index integer;
  v_count integer;
  v_distinct_count integer;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then
    return jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_QUESTION_OBJECT',
      'message', 'Each questions[] entry must be a JSON object.'
    ));
  end if;

  for v_key in select jsonb_object_keys(p_item) loop
    if v_key not in (
      'source_record_id', 'proposed_question_id', 'question_type', 'board_id', 'exam_id',
      'exam_year', 'exam_date', 'shift_no', 'paper_code', 'original_question_no',
      'sort_order', 'subject_id', 'topic_id', 'section_code', 'language', 'difficulty',
      'source_page', 'source_question_id', 'content_origin', 'verification_status',
      'question_text', 'options', 'correct_answer', 'answer_source', 'explanation',
      'image_refs', 'content_id', 'group_id', 'group_type', 'group_text', 'tags'
    ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'UNSUPPORTED_FIELD',
        'message', format('Unsupported question field: %s', v_key),
        'path', format('$.%s', v_key)
      ));
    end if;
  end loop;

  foreach v_required in array array['source_record_id', 'proposed_question_id', 'subject_id', 'sort_order', 'question_text', 'options'] loop
    if not (p_item ? v_required) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_QUESTION_FIELD',
        'message', format('%s is required in every questions[] item.', v_required),
        'path', format('$.%s', v_required)
      ));
    end if;
  end loop;

  foreach v_key in array array['source_record_id', 'proposed_question_id', 'subject_id', 'question_text'] loop
    if p_item ? v_key and jsonb_typeof(p_item -> v_key) <> 'string' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_JSON_TYPE',
        'message', format('%s must be JSON text.', v_key),
        'path', format('$.%s', v_key)
      ));
    end if;
  end loop;

  foreach v_key in array array['exam_year', 'shift_no', 'original_question_no', 'sort_order', 'source_page'] loop
    if p_item ? v_key and p_item -> v_key <> 'null'::jsonb then
      if jsonb_typeof(p_item -> v_key) <> 'number'
         or public.try_parse_integer(p_item ->> v_key) is null then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'INVALID_INTEGER',
          'message', format('%s must be a JSON integer or null.', v_key),
          'path', format('$.%s', v_key)
        ));
      end if;
    end if;
  end loop;

  if p_item ? 'exam_date'
     and p_item -> 'exam_date' <> 'null'::jsonb
     and (
       jsonb_typeof(p_item -> 'exam_date') <> 'string'
       or public.try_parse_date(p_item ->> 'exam_date') is null
     ) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_DATE',
      'message', 'exam_date must be a valid YYYY-MM-DD date or null.',
      'path', '$.exam_date'
    ));
  end if;

  foreach v_key in array array[
    'question_type', 'board_id', 'exam_id', 'exam_date', 'paper_code', 'topic_id',
    'section_code', 'language', 'difficulty', 'source_question_id', 'content_origin',
    'verification_status', 'correct_answer', 'answer_source', 'explanation', 'content_id',
    'group_id', 'group_type', 'group_text'
  ] loop
    if p_item ? v_key
       and p_item -> v_key <> 'null'::jsonb
       and jsonb_typeof(p_item -> v_key) <> 'string' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_JSON_TYPE',
        'message', format('%s must be JSON text or null.', v_key),
        'path', format('$.%s', v_key)
      ));
    end if;
  end loop;

  v_options := p_item -> 'options';
  if jsonb_typeof(v_options) = 'object' then
    if not (v_options ?& array['A', 'B', 'C', 'D'])
       or exists (
         select 1 from jsonb_object_keys(v_options) as keys(option_key)
         where option_key not in ('A', 'B', 'C', 'D')
       ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_OPTION_KEYS',
        'message', 'options must contain exactly A, B, C and D.',
        'path', '$.options'
      ));
    end if;

    if exists (
      select 1 from jsonb_each(v_options) as option_row(option_key, option_value)
      where jsonb_typeof(option_value) <> 'string'
    ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'NON_TEXT_OPTION',
        'message', 'Every option must be JSON text.',
        'path', '$.options'
      ));
    end if;
  end if;

  if p_item ? 'tags' then
    if jsonb_typeof(p_item -> 'tags') <> 'array' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_TAGS',
        'message', 'tags must be an array of unique text values.',
        'path', '$.tags'
      ));
    else
      if exists (
        select 1 from jsonb_array_elements(p_item -> 'tags') as tags(tag_value)
        where jsonb_typeof(tag_value) <> 'string'
      ) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'NON_TEXT_TAG',
          'message', 'Every tag must be JSON text.',
          'path', '$.tags'
        ));
      end if;

      select count(*), count(distinct tag_value)
      into v_count, v_distinct_count
      from jsonb_array_elements_text(p_item -> 'tags') as tags(tag_value);
      if v_count <> v_distinct_count then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'code', 'DUPLICATE_TAG',
          'message', 'tags must contain unique values.',
          'path', '$.tags'
        ));
      end if;
    end if;
  end if;

  if p_item ? 'image_refs' then
    if jsonb_typeof(p_item -> 'image_refs') <> 'array' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_IMAGE_REFS',
        'message', 'image_refs must be an array.',
        'path', '$.image_refs'
      ));
    else
      for v_entry, v_index in
        select value, ordinality::integer
        from jsonb_array_elements(p_item -> 'image_refs') with ordinality
      loop
        if jsonb_typeof(v_entry) = 'string' then
          if nullif(btrim(v_entry #>> '{}'), '') is null then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'code', 'INVALID_IMAGE_REF',
              'message', 'Image reference text cannot be empty.',
              'path', format('$.image_refs[%s]', v_index - 1)
            ));
          end if;
        elsif jsonb_typeof(v_entry) = 'object' then
          for v_key in select jsonb_object_keys(v_entry) loop
            if v_key not in ('ref', 'alt', 'source_page') then
              v_errors := v_errors || jsonb_build_array(jsonb_build_object(
                'code', 'UNSUPPORTED_FIELD',
                'message', format('Unsupported image reference field: %s', v_key),
                'path', format('$.image_refs[%s].%s', v_index - 1, v_key)
              ));
            end if;
          end loop;
          if not (v_entry ? 'ref')
             or jsonb_typeof(v_entry -> 'ref') <> 'string'
             or nullif(btrim(v_entry ->> 'ref'), '') is null then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'code', 'INVALID_IMAGE_REF',
              'message', 'Image reference objects require a non-empty text ref.',
              'path', format('$.image_refs[%s].ref', v_index - 1)
            ));
          end if;
          if v_entry ? 'alt'
             and v_entry -> 'alt' <> 'null'::jsonb
             and jsonb_typeof(v_entry -> 'alt') <> 'string' then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'code', 'INVALID_IMAGE_ALT',
              'message', 'Image alt must be JSON text or null.',
              'path', format('$.image_refs[%s].alt', v_index - 1)
            ));
          end if;
          if v_entry ? 'source_page'
             and v_entry -> 'source_page' <> 'null'::jsonb
             and (
               jsonb_typeof(v_entry -> 'source_page') <> 'number'
               or public.try_parse_integer(v_entry ->> 'source_page') is null
               or public.try_parse_integer(v_entry ->> 'source_page') < 1
             ) then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'code', 'INVALID_IMAGE_SOURCE_PAGE',
              'message', 'Image source_page must be a positive JSON integer or null.',
              'path', format('$.image_refs[%s].source_page', v_index - 1)
            ));
          end if;
        else
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'code', 'INVALID_IMAGE_REF',
            'message', 'Each image_refs item must be text or an object.',
            'path', format('$.image_refs[%s]', v_index - 1)
          ));
        end if;
      end loop;
    end if;
  end if;

  return v_errors;
end;
$$;

-- Admin-only report for one persistent dry-run batch.
create or replace function public.get_import_batch_report(p_import_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch jsonb;
  v_items jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  select to_jsonb(ib) || jsonb_build_object(
    'source_file', jsonb_build_object(
      'source_file_id', sf.source_file_id,
      'original_file_name', sf.original_file_name,
      'mime_type', sf.mime_type,
      'file_size_bytes', sf.file_size_bytes,
      'checksum_sha256', sf.checksum_sha256,
      'storage_path', sf.storage_path
    )
  )
  into v_batch
  from public.import_batches ib
  left join public.source_files sf on sf.source_file_id = ib.source_file_id
  where ib.import_batch_id = p_import_batch_id;

  if v_batch is null then
    raise exception 'Import batch not found.' using errcode = 'P0001';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'import_item_id', ibi.import_item_id,
        'item_index', ibi.item_index,
        'source_record_id', ibi.source_record_id,
        'proposed_question_id', ibi.proposed_question_id,
        'raw_payload', ibi.raw_payload,
        'normalized_payload', ibi.normalized_payload,
        'strict_fingerprint', ibi.strict_fingerprint,
        'loose_fingerprint', ibi.loose_fingerprint,
        'occurrence_key', ibi.occurrence_key,
        'validation_status', ibi.validation_status,
        'errors', ibi.errors,
        'warnings', ibi.warnings,
        'duplicate_kind', ibi.duplicate_kind,
        'matched_question_id', ibi.matched_question_id,
        'matched_draft_id', ibi.matched_draft_id,
        'created_draft_id', ibi.created_draft_id,
        'created_at', ibi.created_at,
        'updated_at', ibi.updated_at
      ) order by ibi.item_index
    ),
    '[]'::jsonb
  )
  into v_items
  from public.import_batch_items ibi
  where ibi.import_batch_id = p_import_batch_id;

  return jsonb_build_object(
    'batch', v_batch,
    'summary', jsonb_build_object(
      'total', coalesce((v_batch ->> 'total_raw')::integer, 0),
      'valid', coalesce((v_batch ->> 'total_valid')::integer, 0),
      'warnings', coalesce((v_batch ->> 'total_warning')::integer, 0),
      'errors', coalesce((v_batch ->> 'total_error')::integer, 0),
      'duplicates', coalesce((v_batch ->> 'total_duplicate')::integer, 0),
      'ready_for_draft', (
        select count(*)
        from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.validation_status in ('VALID', 'VALID_WITH_WARNINGS')
      )
    ),
    'items', v_items
  );
end;
$$;

-- Persist one authoritative dry run. It creates import_batches/import_batch_items only.
-- It never creates draft_questions and never publishes master questions.
create or replace function public.stage_import_dry_run(
  p_manifest jsonb,
  p_raw_file_checksum_sha256 text,
  p_package_checksum_sha256 text,
  p_source_file_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_package_validation jsonb;
  v_package_shape_errors jsonb;
  v_item_shape_errors jsonb;
  v_package_status text;
  v_existing_batch_id uuid;
  v_source_file public.source_files%rowtype;
  v_source jsonb;
  v_defaults jsonb;
  v_source_defaults jsonb;
  v_item jsonb;
  v_merged jsonb;
  v_normalized jsonb;
  v_validation jsonb;
  v_item_index integer;
  v_batch_id uuid;
  v_package_id text;
  v_package_checksum text := lower(nullif(btrim(p_package_checksum_sha256), ''));
  v_raw_checksum text := lower(nullif(btrim(p_raw_file_checksum_sha256), ''));
  v_source_checksum text;
  v_status public.import_item_status;
  v_duplicate_kind public.import_duplicate_kind;
  v_errors jsonb;
  v_warnings jsonb;
  v_strict text;
  v_loose text;
  v_occurrence_key text;
  v_matched_question_id text;
  v_matched_draft_id uuid;
  v_source_record_id text;
  v_db_source_record_id text;
  v_proposed_question_id text;
  v_previous public.import_batch_items%rowtype;
  v_previous_answer text;
  v_current_answer text;
  v_group_registry jsonb := '{}'::jsonb;
  v_group_conflicts text[] := array[]::text[];
  v_group_id text;
  v_group_type text;
  v_group_text text;
  v_group_existing jsonb;
  v_total integer := 0;
  v_valid integer := 0;
  v_warning integer := 0;
  v_error integer := 0;
  v_duplicate integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if v_raw_checksum is null or v_raw_checksum !~ '^[0-9a-f]{64}$' then
    raise exception 'A valid raw HTML SHA-256 checksum is required.' using errcode = 'P0001';
  end if;

  if v_package_checksum is null or v_package_checksum !~ '^[0-9a-f]{64}$' then
    raise exception 'A valid canonical package SHA-256 checksum is required.' using errcode = 'P0001';
  end if;

  v_package_validation := public.validate_import_package(
    p_manifest,
    v_package_checksum,
    v_raw_checksum
  );
  v_package_shape_errors := public.validate_import_manifest_shape(p_manifest);
  if jsonb_array_length(v_package_shape_errors) > 0 then
    v_package_validation := jsonb_set(
      jsonb_set(
        v_package_validation,
        '{errors}',
        coalesce(v_package_validation -> 'errors', '[]'::jsonb) || v_package_shape_errors,
        true
      ),
      '{status}',
      '"INVALID"'::jsonb,
      true
    );
  end if;
  v_package_status := v_package_validation ->> 'status';
  v_existing_batch_id := nullif(v_package_validation ->> 'existing_import_batch_id', '')::uuid;

  if v_package_status = 'EXACT_DUPLICATE' and v_existing_batch_id is not null then
    return public.get_import_batch_report(v_existing_batch_id)
      || jsonb_build_object('reused_existing_batch', true, 'package_validation', v_package_validation);
  end if;

  if v_package_status not in ('VALID', 'VALID_WITH_WARNINGS') then
    return jsonb_build_object(
      'created', false,
      'reused_existing_batch', false,
      'package_validation', v_package_validation,
      'batch', null,
      'summary', jsonb_build_object(
        'total', case when jsonb_typeof(p_manifest -> 'questions') = 'array' then jsonb_array_length(p_manifest -> 'questions') else 0 end,
        'valid', 0,
        'warnings', 0,
        'errors', 1,
        'duplicates', 0,
        'ready_for_draft', 0
      ),
      'items', '[]'::jsonb
    );
  end if;

  select * into v_source_file
  from public.source_files
  where source_file_id = p_source_file_id;

  if not found then
    raise exception 'The private HTML source file record was not found for this admin.' using errcode = 'P0001';
  end if;

  if v_source_file.checksum_sha256 is distinct from v_raw_checksum then
    raise exception 'The stored source-file checksum does not match the selected HTML file.' using errcode = 'P0001';
  end if;

  if lower(coalesce(v_source_file.mime_type, '')) not in ('text/html', 'application/xhtml+xml', '')
     and lower(v_source_file.original_file_name) !~ '\.(html?|xhtml)$' then
    raise exception 'Only HTML import packages may enter the Phase 3B dry run.' using errcode = 'P0001';
  end if;

  v_source := coalesce(p_manifest -> 'source', '{}'::jsonb);
  v_defaults := coalesce(p_manifest -> 'defaults', '{}'::jsonb);
  v_package_id := upper(btrim(p_manifest ->> 'package_id'));
  v_source_checksum := lower(nullif(btrim(v_source ->> 'source_checksum_sha256'), ''));

  insert into public.import_batches (
    import_method,
    source_type,
    source_file_id,
    board_id,
    exam_id,
    exam_year,
    exam_date,
    shift_no,
    subject_id,
    section_code,
    paper_code,
    total_raw,
    total_extracted,
    total_draft,
    total_published,
    status,
    metadata_version,
    remarks,
    created_by,
    package_id,
    package_checksum_sha256,
    source_checksum_sha256,
    schema_name,
    schema_version,
    package_manifest,
    package_errors,
    package_warnings
  ) values (
    'HTML_PACKAGE',
    nullif(btrim(v_source ->> 'source_type'), ''),
    p_source_file_id,
    upper(nullif(btrim(coalesce(v_defaults ->> 'board_id', v_source ->> 'board_id')), '')),
    upper(nullif(btrim(coalesce(v_defaults ->> 'exam_id', v_source ->> 'exam_id')), '')),
    public.try_parse_integer(coalesce(v_defaults ->> 'exam_year', v_source ->> 'exam_year')),
    public.try_parse_date(coalesce(v_defaults ->> 'exam_date', v_source ->> 'exam_date')),
    public.try_parse_integer(coalesce(v_defaults ->> 'shift_no', v_source ->> 'shift_no')),
    upper(nullif(btrim(v_defaults ->> 'subject_id'), '')),
    upper(nullif(btrim(v_defaults ->> 'section_code'), '')),
    upper(nullif(btrim(coalesce(v_defaults ->> 'paper_code', v_source ->> 'paper_code')), '')),
    jsonb_array_length(p_manifest -> 'questions'),
    jsonb_array_length(p_manifest -> 'questions'),
    0,
    0,
    'DRY_RUN_PROCESSING',
    p_manifest ->> 'schema_version',
    'Phase 3B authoritative dry-run reconciliation. No drafts created.',
    v_admin,
    v_package_id,
    v_package_checksum,
    v_source_checksum,
    p_manifest ->> 'schema',
    p_manifest ->> 'schema_version',
    p_manifest,
    coalesce(v_package_validation -> 'errors', '[]'::jsonb),
    coalesce(v_package_validation -> 'warnings', '[]'::jsonb)
  ) returning import_batch_id into v_batch_id;

  v_source_defaults := jsonb_build_object(
    'board_id', v_source -> 'board_id',
    'exam_id', v_source -> 'exam_id',
    'exam_year', v_source -> 'exam_year',
    'exam_date', v_source -> 'exam_date',
    'shift_no', v_source -> 'shift_no',
    'paper_code', v_source -> 'paper_code',
    'language', v_source -> 'language'
  );

  for v_item, v_item_index in
    select value, ordinality::integer
    from jsonb_array_elements(p_manifest -> 'questions') with ordinality
  loop
    v_total := v_total + 1;
    v_merged := v_source_defaults || v_defaults || v_item;
    v_normalized := public.normalize_import_question_payload(v_merged);
    v_validation := public.validate_import_question(v_normalized);

    v_status := (v_validation ->> 'status')::public.import_item_status;
    v_duplicate_kind := coalesce(nullif(v_validation #>> '{duplicate,kind}', ''), 'NONE')::public.import_duplicate_kind;
    v_errors := coalesce(v_validation -> 'errors', '[]'::jsonb);
    v_warnings := coalesce(v_validation -> 'warnings', '[]'::jsonb);
    v_item_shape_errors := public.validate_import_raw_item_shape(v_item);
    if jsonb_array_length(v_item_shape_errors) > 0 then
      v_errors := v_errors || v_item_shape_errors;
      v_status := 'INVALID';
    end if;
    v_strict := nullif(v_validation #>> '{fingerprints,strict}', '');
    v_loose := nullif(v_validation #>> '{fingerprints,loose}', '');
    v_occurrence_key := nullif(v_validation ->> 'occurrence_key', '');
    v_matched_question_id := nullif(v_validation #>> '{duplicate,matched_question_id}', '');
    v_matched_draft_id := nullif(v_validation #>> '{duplicate,matched_draft_id}', '')::uuid;
    v_source_record_id := nullif(btrim(v_normalized ->> 'source_record_id'), '');
    v_db_source_record_id := v_source_record_id;
    v_proposed_question_id := nullif(btrim(v_normalized ->> 'proposed_question_id'), '');
    v_current_answer := nullif(btrim(v_normalized ->> 'correct_answer'), '');

    -- Duplicate source_record_id inside the same package is a schema-level item error.
    if v_source_record_id is not null and exists (
      select 1 from public.import_batch_items
      where import_batch_id = v_batch_id
        and source_record_id = v_source_record_id
    ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'DUPLICATE_SOURCE_RECORD_ID',
        'message', 'source_record_id is repeated inside this package.'
      ));
      v_status := 'INVALID';
      v_db_source_record_id := null;
    end if;

    -- Same proposed ID inside the package.
    if v_status not in ('INVALID', 'ID_CONFLICT', 'ANSWER_CONFLICT', 'SOURCE_CONFLICT')
       and v_proposed_question_id is not null then
      select * into v_previous
      from public.import_batch_items
      where import_batch_id = v_batch_id
        and proposed_question_id = v_proposed_question_id
      order by item_index
      limit 1;

      if found then
        v_previous_answer := nullif(btrim(v_previous.normalized_payload ->> 'correct_answer'), '');
        if v_previous.strict_fingerprint = v_strict then
          if v_current_answer is not null
             and v_previous_answer is not null
             and v_current_answer <> v_previous_answer then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'code', 'ANSWER_CONFLICT',
              'message', 'The same proposed Question ID is repeated with a different correct answer.',
              'matched_item_index', v_previous.item_index
            ));
            v_status := 'ANSWER_CONFLICT';
            v_duplicate_kind := 'EXACT_ID';
          else
            v_status := 'EXACT_DUPLICATE';
            v_duplicate_kind := 'EXACT_ID';
            v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
              'code', 'DUPLICATE_ID_IN_PACKAGE',
              'message', 'The same Question ID and content already appeared earlier in this package.',
              'matched_item_index', v_previous.item_index
            ));
          end if;
        else
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'code', 'QUESTION_ID_CONFLICT',
            'message', 'The same proposed Question ID is repeated with different content.',
            'matched_item_index', v_previous.item_index
          ));
          v_status := 'ID_CONFLICT';
          v_duplicate_kind := 'ID_CONFLICT';
        end if;
      end if;
    end if;

    -- Same strict content inside the package, even when the proposed ID differs.
    if v_status not in ('INVALID', 'ID_CONFLICT', 'ANSWER_CONFLICT', 'SOURCE_CONFLICT', 'EXACT_DUPLICATE')
       and v_strict is not null then
      select * into v_previous
      from public.import_batch_items
      where import_batch_id = v_batch_id
        and strict_fingerprint = v_strict
      order by item_index
      limit 1;

      if found then
        v_previous_answer := nullif(btrim(v_previous.normalized_payload ->> 'correct_answer'), '');
        if v_current_answer is not null
           and v_previous_answer is not null
           and v_current_answer <> v_previous_answer then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'code', 'ANSWER_CONFLICT',
            'message', 'Identical question content is repeated with a different correct answer.',
            'matched_item_index', v_previous.item_index,
            'matched_question_id', v_previous.proposed_question_id
          ));
          v_status := 'ANSWER_CONFLICT';
          v_duplicate_kind := 'EXACT_CONTENT';
        else
          v_status := 'EXACT_DUPLICATE';
          v_duplicate_kind := 'EXACT_CONTENT';
          v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
            'code', 'DUPLICATE_CONTENT_IN_PACKAGE',
            'message', 'Identical master question content already appeared earlier in this package.',
            'matched_item_index', v_previous.item_index,
            'matched_question_id', v_previous.proposed_question_id
          ));
        end if;
      end if;
    end if;

    -- Same authentic occurrence inside the package cannot point to different content.
    if v_status not in ('INVALID', 'ID_CONFLICT', 'ANSWER_CONFLICT', 'SOURCE_CONFLICT')
       and v_occurrence_key is not null then
      select * into v_previous
      from public.import_batch_items
      where import_batch_id = v_batch_id
        and occurrence_key = v_occurrence_key
      order by item_index
      limit 1;

      if found then
        if v_previous.strict_fingerprint = v_strict then
          v_status := 'EXACT_DUPLICATE';
          v_duplicate_kind := 'SOURCE_OCCURRENCE';
          v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
            'code', 'DUPLICATE_SOURCE_OCCURRENCE_IN_PACKAGE',
            'message', 'This exact paper occurrence already appeared earlier in the package.',
            'matched_item_index', v_previous.item_index
          ));
        else
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'code', 'SOURCE_OCCURRENCE_CONFLICT',
            'message', 'The same paper occurrence is assigned to different question content.',
            'matched_item_index', v_previous.item_index
          ));
          v_status := 'SOURCE_CONFLICT';
          v_duplicate_kind := 'SOURCE_CONFLICT';
        end if;
      end if;
    end if;

    -- Loose matches inside the package are warning-only and never auto-merged.
    if v_status in ('VALID', 'VALID_WITH_WARNINGS') and v_loose is not null then
      select * into v_previous
      from public.import_batch_items
      where import_batch_id = v_batch_id
        and loose_fingerprint = v_loose
        and strict_fingerprint is distinct from v_strict
      order by item_index
      limit 1;

      if found then
        v_status := 'POSSIBLE_DUPLICATE';
        v_duplicate_kind := 'POSSIBLE_CONTENT';
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code', 'POSSIBLE_DUPLICATE_IN_PACKAGE',
          'message', 'A punctuation/spacing/option-order tolerant match exists earlier in this package.',
          'matched_item_index', v_previous.item_index,
          'matched_question_id', v_previous.proposed_question_id
        ));
      end if;
    end if;

    -- Track group metadata and mark every member invalid if the group is inconsistent.
    v_group_id := nullif(btrim(v_normalized ->> 'group_id'), '');
    v_group_type := nullif(btrim(v_normalized ->> 'group_type'), '');
    v_group_text := v_normalized ->> 'group_text';
    if v_group_id is not null then
      v_group_existing := v_group_registry -> v_group_id;
      if v_group_existing is null then
        v_group_registry := jsonb_set(
          v_group_registry,
          array[v_group_id],
          jsonb_build_object('group_type', v_group_type, 'group_text', v_group_text),
          true
        );
      elsif (v_group_existing ->> 'group_type') is distinct from v_group_type
         or (v_group_existing ->> 'group_text') is distinct from v_group_text then
        if not (v_group_id = any(v_group_conflicts)) then
          v_group_conflicts := array_append(v_group_conflicts, v_group_id);
        end if;
      end if;
    end if;

    insert into public.import_batch_items (
      import_batch_id,
      item_index,
      source_record_id,
      proposed_question_id,
      raw_payload,
      normalized_payload,
      strict_fingerprint,
      loose_fingerprint,
      occurrence_key,
      validation_status,
      errors,
      warnings,
      duplicate_kind,
      matched_question_id,
      matched_draft_id
    ) values (
      v_batch_id,
      v_item_index,
      v_db_source_record_id,
      v_proposed_question_id,
      v_item,
      v_normalized,
      v_strict,
      v_loose,
      v_occurrence_key,
      v_status,
      v_errors,
      v_warnings,
      v_duplicate_kind,
      v_matched_question_id,
      v_matched_draft_id
    );
  end loop;

  if cardinality(v_group_conflicts) > 0 then
    update public.import_batch_items
    set validation_status = 'INVALID',
        errors = errors || jsonb_build_array(jsonb_build_object(
          'code', 'GROUP_METADATA_CONFLICT',
          'message', 'Questions sharing this group_id do not use identical group_type and group_text.',
          'group_id', normalized_payload ->> 'group_id'
        ))
    where import_batch_id = v_batch_id
      and normalized_payload ->> 'group_id' = any(v_group_conflicts);
  end if;

  select
    count(*) filter (where validation_status = 'VALID'),
    count(*) filter (where validation_status in ('VALID_WITH_WARNINGS', 'POSSIBLE_DUPLICATE')),
    count(*) filter (where validation_status in ('INVALID', 'ID_CONFLICT', 'ANSWER_CONFLICT', 'SOURCE_CONFLICT')),
    count(*) filter (where validation_status in ('EXACT_DUPLICATE', 'POSSIBLE_DUPLICATE'))
  into v_valid, v_warning, v_error, v_duplicate
  from public.import_batch_items
  where import_batch_id = v_batch_id;

  update public.import_batches
  set total_valid = v_valid,
      total_warning = v_warning,
      total_error = v_error,
      total_duplicate = v_duplicate,
      status = case
        when v_error > 0 then 'DRY_RUN_COMPLETE_WITH_ERRORS'
        when v_warning > 0 or v_duplicate > 0 then 'DRY_RUN_COMPLETE_WITH_WARNINGS'
        else 'DRY_RUN_COMPLETE'
      end,
      completed_at = now()
  where import_batch_id = v_batch_id;

  insert into public.admin_audit_logs (
    admin_user_id,
    action,
    entity_type,
    entity_id,
    details
  ) values (
    v_admin,
    'IMPORT_DRY_RUN',
    'IMPORT_BATCH',
    v_batch_id::text,
    jsonb_build_object(
      'package_id', v_package_id,
      'package_checksum_sha256', v_package_checksum,
      'raw_file_checksum_sha256', v_raw_checksum,
      'total', v_total,
      'valid', v_valid,
      'warnings', v_warning,
      'errors', v_error,
      'duplicates', v_duplicate
    )
  );

  return public.get_import_batch_report(v_batch_id)
    || jsonb_build_object(
      'created', true,
      'reused_existing_batch', false,
      'package_validation', v_package_validation
    );
exception
  when unique_violation then
    select import_batch_id into v_existing_batch_id
    from public.import_batches
    where package_id = upper(btrim(p_manifest ->> 'package_id'))
       or package_checksum_sha256 = v_package_checksum
    order by created_at desc
    limit 1;

    if v_existing_batch_id is not null then
      return public.get_import_batch_report(v_existing_batch_id)
        || jsonb_build_object('created', false, 'reused_existing_batch', true);
    end if;

    raise;
end;
$$;

-- Explicit privileges. These are authenticated admin RPCs; helpers remain internal.
revoke all on function public.normalize_import_question_payload(jsonb) from public, anon, authenticated;
revoke all on function public.validate_import_manifest_shape(jsonb) from public, anon, authenticated;
revoke all on function public.validate_import_raw_item_shape(jsonb) from public, anon, authenticated;
revoke all on function public.get_import_batch_report(uuid) from public, anon, authenticated;
revoke all on function public.stage_import_dry_run(jsonb, text, text, uuid) from public, anon, authenticated;

grant execute on function public.get_import_batch_report(uuid) to authenticated;
grant execute on function public.stage_import_dry_run(jsonb, text, text, uuid) to authenticated;

comment on function public.stage_import_dry_run(jsonb, text, text, uuid) is
  'Admin-only persistent Phase 3B validation. Creates reconciliation records only; never drafts or published questions.';

comment on function public.get_import_batch_report(uuid) is
  'Admin-only complete item-level reconciliation report for one import batch.';

commit;
