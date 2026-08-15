begin;

-- ScoreMore Phase 4A Safety & Efficiency v1
-- Forward-only migration. Historical migrations remain untouched.
--
-- Goals:
-- 1. Keep existing Phase 4A writer as the structural source of truth.
-- 2. Add mode-aware preview severity / publication blockers.
-- 3. Prevent multi-package sectional tests from using a single-package-looking test ID.
-- 4. Preserve all selected package IDs as explicit provenance on the saved test.

create or replace function public.phase4a_assess_preview_v15(
  p_preview jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_preview jsonb := coalesce(p_preview, '{}'::jsonb);
  v_mode text := upper(btrim(coalesce(v_preview ->> 'builder_mode', 'CUSTOM')));
  v_issue jsonb;
  v_code text;
  v_severity text;
  v_issues jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_question_count integer := coalesce(public.try_parse_integer(v_preview ->> 'question_count'), 0);
  v_repeated integer := coalesce(public.try_parse_integer(v_preview ->> 'repeated_memberships_removed'), 0);
  v_packages jsonb := case
    when jsonb_typeof(v_preview -> 'packages') = 'array' then v_preview -> 'packages'
    else '[]'::jsonb
  end;
  v_package_count integer := 0;
  v_declared integer := null;
  v_extracted integer := null;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  v_package_count := jsonb_array_length(v_packages);

  for v_issue in
    select value
    from jsonb_array_elements(
      case
        when jsonb_typeof(v_preview -> 'warnings') = 'array' then v_preview -> 'warnings'
        else '[]'::jsonb
      end
    )
  loop
    v_code := upper(btrim(coalesce(v_issue ->> 'code', 'WARNING')));
    v_severity := case
      when v_code = 'PARTIAL_PACKAGE' and v_mode = 'PYQ_ORIGINAL' then 'BLOCKER'
      when v_code = 'UNIQUE_MASTER_COLLAPSE' and v_mode = 'PYQ_ORIGINAL' then 'BLOCKER'
      when v_code = 'MULTIPLE_PACKAGES' and v_mode in ('PYQ_SECTIONAL', 'CUSTOM') then 'INFO'
      when v_code = 'PARTIAL_PACKAGE' and v_mode in ('PYQ_SECTIONAL', 'PYQ_COMPLETED') then 'INFO'
      when v_code = 'SUPPLEMENTAL_INCLUDED' and v_mode = 'PYQ_COMPLETED' then 'INFO'
      when v_code = 'FULL_MODE_IGNORES_SECTION_FILTERS' then 'INFO'
      when v_code = 'UNIQUE_MASTER_COLLAPSE' then 'INFO'
      else 'WARNING'
    end;

    v_issue := v_issue || jsonb_build_object('severity', v_severity);
    v_issues := v_issues || jsonb_build_array(v_issue);
    if v_severity = 'BLOCKER' then
      v_blockers := v_blockers || jsonb_build_array(v_issue);
    else
      v_warnings := v_warnings || jsonb_build_array(v_issue);
    end if;
  end loop;

  -- Exact original-paper publication must remain genuinely complete.
  if v_mode = 'PYQ_ORIGINAL' then
    if v_package_count <> 1 then
      v_issue := jsonb_build_object(
        'code', 'ORIGINAL_REQUIRES_ONE_PACKAGE',
        'severity', 'BLOCKER',
        'message', 'Original full PYQ publication requires exactly one source package.'
      );
      v_issues := v_issues || jsonb_build_array(v_issue);
      v_blockers := v_blockers || jsonb_build_array(v_issue);
    else
      v_declared := public.try_parse_integer(v_packages -> 0 ->> 'declared_total_questions');
      v_extracted := public.try_parse_integer(v_packages -> 0 ->> 'extracted_source_questions');

      if v_extracted is not null and v_extracted > 0 and v_question_count <> v_extracted then
        v_issue := jsonb_build_object(
          'code', 'ORIGINAL_SOURCE_COUNT_MISMATCH',
          'severity', 'BLOCKER',
          'message', format(
            'Original full PYQ resolved %s unique master question(s), but the source package contains %s extracted source question(s).',
            v_question_count,
            v_extracted
          )
        );
        v_issues := v_issues || jsonb_build_array(v_issue);
        v_blockers := v_blockers || jsonb_build_array(v_issue);
      end if;

      if v_declared is not null and v_declared > 0 and v_question_count <> v_declared then
        v_issue := jsonb_build_object(
          'code', 'ORIGINAL_DECLARED_COUNT_MISMATCH',
          'severity', 'BLOCKER',
          'message', format(
            'Original full PYQ resolved %s question(s), but the source package declares %s total question(s).',
            v_question_count,
            v_declared
          )
        );
        v_issues := v_issues || jsonb_build_array(v_issue);
        v_blockers := v_blockers || jsonb_build_array(v_issue);
      end if;
    end if;

    if v_repeated > 0 and not exists (
      select 1
      from jsonb_array_elements(v_blockers) as blocker(value)
      where blocker.value ->> 'code' = 'UNIQUE_MASTER_COLLAPSE'
    ) then
      v_issue := jsonb_build_object(
        'code', 'ORIGINAL_REPEAT_COLLAPSE',
        'severity', 'BLOCKER',
        'message', 'Original full PYQ publication is blocked because repeated package memberships would be collapsed into one master-question link.'
      );
      v_issues := v_issues || jsonb_build_array(v_issue);
      v_blockers := v_blockers || jsonb_build_array(v_issue);
    end if;
  end if;

  return v_preview || jsonb_build_object(
    'safety_schema', 'scoremore.phase4a-safety-v1',
    'safety_schema_version', 1,
    'issues_v15', v_issues,
    'warnings_v15', v_warnings,
    'publish_blockers', v_blockers,
    'publish_ready', jsonb_array_length(v_blockers) = 0
  );
end;
$$;

revoke all on function public.phase4a_assess_preview_v15(jsonb) from public, anon;
grant execute on function public.phase4a_assess_preview_v15(jsonb) to authenticated;

create or replace function public.preview_phase4a_dynamic_test_v15(
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
  v_preview jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  v_preview := public.preview_phase4a_dynamic_test(
    p_builder_mode,
    coalesce(p_filters, '{}'::jsonb),
    coalesce(p_question_ids, array[]::text[]),
    p_order,
    p_custom_test_type
  );

  return public.phase4a_assess_preview_v15(v_preview);
end;
$$;

revoke all on function public.preview_phase4a_dynamic_test_v15(text,jsonb,text[],text,public.test_type) from public, anon;
grant execute on function public.preview_phase4a_dynamic_test_v15(text,jsonb,text[],text,public.test_type) to authenticated;

create or replace function public.save_phase4a_dynamic_test_v15(
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
  v_mode text := upper(btrim(coalesce(p_builder_mode, 'CUSTOM')));
  v_test_id text := upper(btrim(coalesce(p_test_id, '')));
  v_package_ids text[] := public.phase4a_text_array(coalesce(p_filters, '{}'::jsonb), 'package_ids');
  v_package_id text;
  v_identity_scope text;
  v_preview jsonb;
  v_blocker_message text;
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if nullif(v_test_id, '') is null then
    raise exception 'Test ID is required.' using errcode = 'P0001';
  end if;

  v_preview := public.preview_phase4a_dynamic_test_v15(
    v_mode,
    coalesce(p_filters, '{}'::jsonb),
    coalesce(p_question_ids, array[]::text[]),
    p_order,
    p_custom_test_type
  );

  if v_mode = 'PYQ_SECTIONAL' and cardinality(v_package_ids) > 1 then
    foreach v_package_id in array v_package_ids loop
      if v_test_id = v_package_id or v_test_id like v_package_id || '-%' then
        raise exception 'A multi-package sectional test ID must be neutral and must not imply that the test belongs to one selected package.' using errcode = 'P0001';
      end if;
    end loop;
  end if;

  if coalesce(p_publish, false) and not coalesce((v_preview ->> 'publish_ready')::boolean, false) then
    select string_agg(coalesce(item.issue ->> 'message', item.issue ->> 'code', 'Publication blocker'), '; ')
    into v_blocker_message
    from jsonb_array_elements(coalesce(v_preview -> 'publish_blockers', '[]'::jsonb)) as item(issue);

    raise exception 'Publication blocked: %', coalesce(v_blocker_message, 'Resolve the preview blockers first.') using errcode = 'P0001';
  end if;

  v_result := public.save_phase4a_dynamic_test(
    v_test_id,
    p_test_name,
    v_mode,
    coalesce(p_filters, '{}'::jsonb),
    coalesce(p_question_ids, array[]::text[]),
    p_order,
    p_custom_test_type,
    p_duration_minutes,
    p_marks_per_question,
    p_negative_marks,
    p_sort_order,
    p_publish
  );

  v_identity_scope := case
    when cardinality(v_package_ids) = 0 then 'NO_PACKAGE'
    when cardinality(v_package_ids) = 1 then 'SINGLE_PACKAGE'
    else 'MULTI_PACKAGE'
  end;

  update public.tests
  set
    question_filter = coalesce(question_filter, '{}'::jsonb) || jsonb_build_object(
      'safety_schema', 'scoremore.phase4a-safety-v1',
      'safety_schema_version', 1,
      'identity_scope', v_identity_scope,
      'source_package_count', cardinality(v_package_ids),
      'source_package_ids', to_jsonb(v_package_ids),
      'publish_assessment', jsonb_build_object(
        'publish_ready', coalesce((v_preview ->> 'publish_ready')::boolean, false),
        'warnings', coalesce(v_preview -> 'warnings_v15', '[]'::jsonb),
        'blockers', coalesce(v_preview -> 'publish_blockers', '[]'::jsonb)
      )
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
    'SAVE_PHASE4A_DYNAMIC_TEST_V15',
    'TEST',
    v_test_id,
    jsonb_build_object(
      'builder_mode', v_mode,
      'identity_scope', v_identity_scope,
      'source_package_ids', to_jsonb(v_package_ids),
      'source_package_count', cardinality(v_package_ids),
      'publish_requested', coalesce(p_publish, false),
      'publish_ready', coalesce((v_preview ->> 'publish_ready')::boolean, false),
      'warning_count', jsonb_array_length(coalesce(v_preview -> 'warnings_v15', '[]'::jsonb)),
      'blocker_count', jsonb_array_length(coalesce(v_preview -> 'publish_blockers', '[]'::jsonb))
    )
  );

  return v_result || jsonb_build_object(
    'safety_schema', 'scoremore.phase4a-safety-v1',
    'safety_schema_version', 1,
    'preview', v_preview,
    'identity_scope', v_identity_scope,
    'source_package_ids', to_jsonb(v_package_ids)
  );
end;
$$;

revoke all on function public.save_phase4a_dynamic_test_v15(
  text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean
) from public, anon;

grant execute on function public.save_phase4a_dynamic_test_v15(
  text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean
) to authenticated;

comment on function public.phase4a_assess_preview_v15(jsonb) is
  'ScoreMore Phase 4A v1.5 mode-aware preview assessment. Separates informational warnings from publication blockers without weakening the original resolver.';
comment on function public.preview_phase4a_dynamic_test_v15(text,jsonb,text[],text,public.test_type) is
  'Admin-only Phase 4A v1.5 preview wrapper with publication readiness and mode-aware issue severity.';
comment on function public.save_phase4a_dynamic_test_v15(text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean) is
  'Admin-only Phase 4A v1.5 safety wrapper. Preserves the locked fixed-list writer, adds publish blockers and explicit multi-package provenance.';

commit;
