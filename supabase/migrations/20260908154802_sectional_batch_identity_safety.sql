begin;

-- ScoreMore sectional-test identity safety and package batch creation.
-- Forward-only migration. Historical migrations remain untouched.
--
-- Fixes:
-- 1. A single package previously suggested the same Test ID for every subject.
-- 2. The fixed-list writer correctly treats an existing Test ID as an update, so
--    a second subject could replace the first subject's metadata and links.
-- 3. Admins previously had to create every package subject one at a time.

create or replace function public.phase4a_normalize_scope_array_v16(
  p_values text[]
)
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(
    array(
      select distinct upper(btrim(value))
      from unnest(coalesce(p_values, array[]::text[])) as item(value)
      where nullif(btrim(value), '') is not null
      order by upper(btrim(value))
    ),
    array[]::text[]
  );
$$;

create or replace function public.phase4a_saved_scope_array_v16(
  p_question_filter jsonb,
  p_key text
)
returns text[]
language sql
immutable
set search_path = public
as $$
  with candidate as (
    select case
      when jsonb_typeof(coalesce(p_question_filter, '{}'::jsonb) -> 'filters' -> p_key) = 'array'
        then coalesce(p_question_filter, '{}'::jsonb) -> 'filters' -> p_key
      when p_key = 'package_ids'
       and jsonb_typeof(coalesce(p_question_filter, '{}'::jsonb) -> 'import_package_ids') = 'array'
        then coalesce(p_question_filter, '{}'::jsonb) -> 'import_package_ids'
      when p_key = 'package_ids'
       and jsonb_typeof(coalesce(p_question_filter, '{}'::jsonb) -> 'source_package_ids') = 'array'
        then coalesce(p_question_filter, '{}'::jsonb) -> 'source_package_ids'
      when p_key = 'package_ids'
       and jsonb_typeof(coalesce(p_question_filter, '{}'::jsonb) -> 'identity_package_ids') = 'array'
        then coalesce(p_question_filter, '{}'::jsonb) -> 'identity_package_ids'
      when p_key = 'subject_ids'
       and jsonb_typeof(coalesce(p_question_filter, '{}'::jsonb) -> 'identity_subject_ids') = 'array'
        then coalesce(p_question_filter, '{}'::jsonb) -> 'identity_subject_ids'
      when p_key = 'topic_ids'
       and jsonb_typeof(coalesce(p_question_filter, '{}'::jsonb) -> 'identity_topic_ids') = 'array'
        then coalesce(p_question_filter, '{}'::jsonb) -> 'identity_topic_ids'
      else '[]'::jsonb
    end as values_json
  )
  select coalesce(
    array(
      select distinct upper(btrim(value))
      from candidate,
           jsonb_array_elements_text(candidate.values_json) as item(value)
      where nullif(btrim(value), '') is not null
      order by upper(btrim(value))
    ),
    array[]::text[]
  );
$$;

create or replace function public.phase4a_sectional_test_id_v16(
  p_package_id text,
  p_subject_id text
)
returns text
language sql
immutable
set search_path = public
as $$
  select trim(both '-' from regexp_replace(
    regexp_replace(
      upper(btrim(coalesce(p_package_id, ''))) || '-' ||
      upper(btrim(coalesce(p_subject_id, ''))) || '-SECTIONAL-TEST',
      '[^A-Z0-9-]+',
      '-',
      'g'
    ),
    '-+',
    '-',
    'g'
  ));
$$;

revoke all on function public.phase4a_normalize_scope_array_v16(text[]) from public, anon, authenticated;
revoke all on function public.phase4a_saved_scope_array_v16(jsonb,text) from public, anon, authenticated;
revoke all on function public.phase4a_sectional_test_id_v16(text,text) from public, anon, authenticated;

create or replace function public.save_phase4a_dynamic_test_v16(
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
  v_requested_packages text[] := public.phase4a_normalize_scope_array_v16(
    public.phase4a_text_array(coalesce(p_filters, '{}'::jsonb), 'package_ids')
  );
  v_requested_subjects text[] := public.phase4a_normalize_scope_array_v16(
    public.phase4a_text_array(coalesce(p_filters, '{}'::jsonb), 'subject_ids')
  );
  v_requested_topics text[] := public.phase4a_normalize_scope_array_v16(
    public.phase4a_text_array(coalesce(p_filters, '{}'::jsonb), 'topic_ids')
  );
  v_existing public.tests%rowtype;
  v_existing_mode text;
  v_existing_packages text[];
  v_existing_subjects text[];
  v_existing_topics text[];
  v_existing_found boolean := false;
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if nullif(v_test_id, '') is null then
    raise exception 'Test ID is required.' using errcode = 'P0001';
  end if;

  -- Serialize every v1.6 save for this identity so the check and delegated write
  -- cannot race with another v1.6 save using the same Test ID.
  perform pg_advisory_xact_lock(hashtext('scoremore:dynamic-test:' || v_test_id));

  select *
  into v_existing
  from public.tests
  where test_id = v_test_id;

  v_existing_found := found;

  if v_mode = 'PYQ_SECTIONAL' and cardinality(v_requested_subjects) = 0 then
    raise exception 'Select at least one subject for a sectional test.' using errcode = 'P0001';
  end if;

  if not v_existing_found
     and v_mode = 'PYQ_SECTIONAL'
     and cardinality(v_requested_packages) = 1
     and v_test_id = public.phase4a_sectional_test_id_v16(v_requested_packages[1], '') then
    raise exception 'The package-only sectional Test ID % is unsafe. Use a subject-specific Test ID; nothing was created.', v_test_id
      using errcode = 'P0001';
  end if;

  if v_existing_found then
    v_existing_mode := upper(nullif(btrim(v_existing.question_filter ->> 'builder_mode'), ''));
    v_existing_packages := public.phase4a_saved_scope_array_v16(v_existing.question_filter, 'package_ids');
    v_existing_subjects := public.phase4a_saved_scope_array_v16(v_existing.question_filter, 'subject_ids');
    v_existing_topics := public.phase4a_saved_scope_array_v16(v_existing.question_filter, 'topic_ids');

    if cardinality(v_existing_subjects) = 0 and v_existing.subject_id is not null then
      v_existing_subjects := array[upper(v_existing.subject_id)];
    end if;
    if cardinality(v_existing_topics) = 0 and v_existing.topic_id is not null then
      v_existing_topics := array[upper(v_existing.topic_id)];
    end if;

    if v_existing_mode is null
       or v_existing_mode <> v_mode
       or v_existing_packages is distinct from v_requested_packages
       or v_existing_subjects is distinct from v_requested_subjects
       or v_existing_topics is distinct from v_requested_topics then
      raise exception 'Test ID % already belongs to a different test scope. Nothing was overwritten. Use the generated subject-specific Test ID or edit the original test from its own scope.', v_test_id
        using errcode = 'P0001';
    end if;
  end if;

  v_result := public.save_phase4a_dynamic_test_v15(
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

  update public.tests
  set
    question_filter = coalesce(question_filter, '{}'::jsonb) || jsonb_build_object(
      'identity_schema', 'scoremore.phase4a-scope-v2',
      'identity_schema_version', 2,
      'identity_package_ids', to_jsonb(v_requested_packages),
      'identity_subject_ids', to_jsonb(v_requested_subjects),
      'identity_topic_ids', to_jsonb(v_requested_topics)
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
    'SAVE_PHASE4A_DYNAMIC_TEST_V16',
    'TEST',
    v_test_id,
    jsonb_build_object(
      'builder_mode', v_mode,
      'package_ids', to_jsonb(v_requested_packages),
      'subject_ids', to_jsonb(v_requested_subjects),
      'topic_ids', to_jsonb(v_requested_topics),
      'existing_scope_verified', v_existing_found,
      'publish_requested', coalesce(p_publish, false)
    )
  );

  return v_result || jsonb_build_object(
    'identity_schema', 'scoremore.phase4a-scope-v2',
    'identity_schema_version', 2,
    'identity_scope_verified', true
  );
end;
$$;

revoke all on function public.save_phase4a_dynamic_test_v16(
  text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean
) from public, anon;

grant execute on function public.save_phase4a_dynamic_test_v16(
  text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean
) to authenticated;

-- Browser writes must pass through v1.6 after this migration. The function
-- owner can still call the historical implementations internally.
revoke execute on function public.save_phase4a_dynamic_test_v15(
  text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean
) from authenticated;
revoke execute on function public.save_phase4a_dynamic_test(
  text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean
) from authenticated;

create or replace function public.phase4a_sectional_batch_plan_v1(
  p_package_ids text[],
  p_include_supplemental boolean default true
)
returns table (
  package_id text,
  subject_id text,
  subject_name text,
  question_count integer,
  source_pyq_count integer,
  supplemental_count integer,
  normal_count integer,
  proposed_test_type text,
  proposed_test_id text,
  proposed_test_name text,
  duration_minutes integer,
  existing_test_count integer,
  existing_test_id text,
  existing_test_name text,
  existing_status text,
  action_status text,
  action_message text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_package_ids text[] := public.phase4a_normalize_scope_array_v16(p_package_ids);
  v_missing_packages text;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if cardinality(v_package_ids) = 0 then
    raise exception 'Select at least one active import Package ID.' using errcode = 'P0001';
  end if;

  if cardinality(v_package_ids) > 10 then
    raise exception 'A sectional batch is limited to 10 packages at a time.' using errcode = 'P0001';
  end if;

  select string_agg(requested.package_id, ', ' order by requested.package_id)
  into v_missing_packages
  from unnest(v_package_ids) as requested(package_id)
  where not exists (
    select 1
    from public.import_batches b
    where b.package_id = requested.package_id
      and not exists (
        select 1
        from public.import_batches newer
        where newer.supersedes_package_id = b.package_id
          and newer.package_id is not null
      )
  );

  if v_missing_packages is not null then
    raise exception 'Package IDs are missing or superseded: %', v_missing_packages using errcode = 'P0001';
  end if;

  return query
  with question_memberships as materialized (
    select
      c.package_id,
      c.subject_id,
      c.subject_name,
      c.question_id,
      bool_or(c.membership_type = 'SOURCE_PYQ') as has_source_pyq,
      bool_or(c.is_supplemental) as has_supplemental,
      bool_or(c.question_type <> 'PYQ') as has_normal,
      min(c.exam_year) as exam_year,
      min(c.exam_date) as exam_date,
      min(c.shift_no) as shift_no
    from public.phase4a_question_package_catalogue c
    where c.package_id = any(v_package_ids)
      and c.is_active_version
      and (coalesce(p_include_supplemental, true) or not c.is_supplemental)
    group by c.package_id, c.subject_id, c.subject_name, c.question_id
  ),
  subject_groups as materialized (
    select
      q.package_id,
      q.subject_id,
      q.subject_name,
      count(*)::integer as question_count,
      (count(*) filter (where q.has_source_pyq))::integer as source_pyq_count,
      (count(*) filter (where q.has_supplemental))::integer as supplemental_count,
      (count(*) filter (where q.has_normal))::integer as normal_count,
      min(q.exam_year) as exam_year,
      min(q.exam_date) as exam_date,
      min(q.shift_no) as shift_no,
      public.phase4a_sectional_test_id_v16(q.package_id, q.subject_id) as proposed_test_id
    from question_memberships q
    group by q.package_id, q.subject_id, q.subject_name
  ),
  existing_scopes as materialized (
    select
      t.test_id,
      t.test_name,
      t.status::text as status,
      t.subject_id,
      t.topic_id,
      t.created_at,
      public.phase4a_saved_scope_array_v16(t.question_filter, 'package_ids') as package_ids,
      public.phase4a_saved_scope_array_v16(t.question_filter, 'subject_ids') as subject_ids,
      public.phase4a_saved_scope_array_v16(t.question_filter, 'topic_ids') as topic_ids
    from public.tests t
    where t.test_type in ('PYQ_SECTIONAL'::public.test_type, 'SECTIONAL_MOCK'::public.test_type)
  ),
  matches as materialized (
    select
      g.package_id,
      g.subject_id,
      count(e.test_id)::integer as existing_test_count,
      (array_agg(e.test_id order by (e.test_id = g.proposed_test_id) desc, e.created_at, e.test_id)
        filter (where e.test_id is not null))[1] as existing_test_id,
      (array_agg(e.test_name order by (e.test_id = g.proposed_test_id) desc, e.created_at, e.test_id)
        filter (where e.test_id is not null))[1] as existing_test_name,
      (array_agg(e.status order by (e.test_id = g.proposed_test_id) desc, e.created_at, e.test_id)
        filter (where e.test_id is not null))[1] as existing_status
    from subject_groups g
    left join existing_scopes e
      on (
        e.package_ids = array[g.package_id]
        or (
          cardinality(e.package_ids) = 0
          and e.test_id = public.phase4a_sectional_test_id_v16(g.package_id, '')
        )
      )
     and (
       e.subject_ids = array[g.subject_id]
       or (cardinality(e.subject_ids) = 0 and upper(coalesce(e.subject_id, '')) = g.subject_id)
     )
     and cardinality(e.topic_ids) = 0
     and e.topic_id is null
    group by g.package_id, g.subject_id
  ),
  planned as materialized (
    select
      g.*,
      m.existing_test_count,
      m.existing_test_id,
      m.existing_test_name,
      m.existing_status,
      collision.test_id as collision_test_id
    from subject_groups g
    join matches m using (package_id, subject_id)
    left join public.tests collision
      on collision.test_id = g.proposed_test_id
  )
  select
    p.package_id,
    p.subject_id,
    p.subject_name,
    p.question_count,
    p.source_pyq_count,
    p.supplemental_count,
    p.normal_count,
    case
      when p.supplemental_count = 0 and p.normal_count = 0 then 'PYQ_SECTIONAL'
      else 'SECTIONAL_MOCK'
    end as proposed_test_type,
    p.proposed_test_id,
    concat(
      p.subject_name,
      case
        when p.supplemental_count = 0 and p.normal_count = 0 then ' PYQ Sectional'
        else ' Completed Practice Sectional'
      end,
      ' · ',
      coalesce(to_char(p.exam_date, 'FMDD Mon YYYY'), p.exam_year::text, p.package_id),
      case when p.shift_no is not null then format(' · Shift %s', p.shift_no) else '' end
    ) as proposed_test_name,
    greatest(5, (ceil((p.question_count * 0.6) / 5.0) * 5)::integer) as duration_minutes,
    p.existing_test_count,
    p.existing_test_id,
    p.existing_test_name,
    p.existing_status,
    case
      when p.existing_test_count > 1 then 'BLOCKED_DUPLICATE_SCOPE'
      when p.collision_test_id is not null and p.collision_test_id is distinct from p.existing_test_id then 'BLOCKED_ID_CONFLICT'
      when p.existing_test_count = 1 then 'ALREADY_EXISTS'
      else 'CREATE_DRAFT'
    end as action_status,
    case
      when p.existing_test_count > 1 then 'More than one existing test claims this package and subject. Review duplicates before batch creation.'
      when p.collision_test_id is not null and p.collision_test_id is distinct from p.existing_test_id then format('Proposed Test ID %s already belongs to a different scope.', p.proposed_test_id)
      when p.existing_test_count = 1 then format('Existing test %s will be kept unchanged.', p.existing_test_id)
      else 'A new fixed-list draft will be created. Existing tests are never overwritten.'
    end as action_message
  from planned p
  order by array_position(v_package_ids, p.package_id), p.subject_name, p.subject_id;
end;
$$;

revoke all on function public.phase4a_sectional_batch_plan_v1(text[],boolean) from public, anon, authenticated;

create or replace function public.preview_phase4a_sectional_batch_v1(
  p_package_ids text[],
  p_include_supplemental boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_items jsonb;
  v_total integer;
  v_create integer;
  v_existing integer;
  v_blocked integer;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  with plan as materialized (
    select *
    from public.phase4a_sectional_batch_plan_v1(p_package_ids, p_include_supplemental)
  )
  select
    coalesce(jsonb_agg(to_jsonb(plan) order by plan.package_id, plan.subject_name, plan.subject_id), '[]'::jsonb),
    count(*)::integer,
    (count(*) filter (where plan.action_status = 'CREATE_DRAFT'))::integer,
    (count(*) filter (where plan.action_status = 'ALREADY_EXISTS'))::integer,
    (count(*) filter (where plan.action_status like 'BLOCKED_%'))::integer
  into v_items, v_total, v_create, v_existing, v_blocked
  from plan;

  if coalesce(v_total, 0) = 0 then
    raise exception 'The selected package set has no published, student-ready subject questions.' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'schema', 'scoremore.sectional-batch-preview-v1',
    'package_ids', to_jsonb(public.phase4a_normalize_scope_array_v16(p_package_ids)),
    'include_supplemental', coalesce(p_include_supplemental, true),
    'subject_count', v_total,
    'create_count', v_create,
    'existing_count', v_existing,
    'blocked_count', v_blocked,
    'can_create', v_create > 0 and v_blocked = 0,
    'items', v_items
  );
end;
$$;

revoke all on function public.preview_phase4a_sectional_batch_v1(text[],boolean) from public, anon;
grant execute on function public.preview_phase4a_sectional_batch_v1(text[],boolean) to authenticated;

create or replace function public.save_phase4a_sectional_batch_v1(
  p_package_ids text[],
  p_include_supplemental boolean default true,
  p_marks_per_question numeric default 1,
  p_negative_marks numeric default 0,
  p_sort_order_start integer default 1,
  p_confirmation text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_package_ids text[] := public.phase4a_normalize_scope_array_v16(p_package_ids);
  v_item record;
  v_result jsonb;
  v_created jsonb := '[]'::jsonb;
  v_created_count integer := 0;
  v_existing_count integer := 0;
  v_blocked_count integer := 0;
  v_plan_count integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if upper(btrim(coalesce(p_confirmation, ''))) <> 'CREATE_MISSING_SECTIONAL_DRAFTS' then
    raise exception 'Explicit batch draft confirmation is required.' using errcode = 'P0001';
  end if;

  if coalesce(p_marks_per_question, 0) <= 0 then
    raise exception 'Marks per question must be greater than zero.' using errcode = 'P0001';
  end if;

  if coalesce(p_negative_marks, -1) < 0 then
    raise exception 'Negative marks cannot be negative.' using errcode = 'P0001';
  end if;

  if coalesce(p_sort_order_start, -1) < 0 then
    raise exception 'Starting catalogue order cannot be negative.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('scoremore:sectional-batch:' || array_to_string(v_package_ids, '|')));

  select
    count(*)::integer,
    (count(*) filter (where plan.action_status = 'ALREADY_EXISTS'))::integer,
    (count(*) filter (where plan.action_status like 'BLOCKED_%'))::integer
  into v_plan_count, v_existing_count, v_blocked_count
  from public.phase4a_sectional_batch_plan_v1(v_package_ids, p_include_supplemental) plan;

  if v_plan_count = 0 then
    raise exception 'The selected package set has no published, student-ready subject questions.' using errcode = 'P0001';
  end if;

  if v_blocked_count > 0 then
    raise exception 'Sectional batch creation is blocked by % identity conflict(s). Review the preview; no test was created.', v_blocked_count
      using errcode = 'P0001';
  end if;

  for v_item in
    select *
    from public.phase4a_sectional_batch_plan_v1(v_package_ids, p_include_supplemental)
    where action_status = 'CREATE_DRAFT'
    order by array_position(v_package_ids, package_id), subject_name, subject_id
  loop
    -- The preview is deliberately recomputed inside this transaction, then every
    -- proposed identity is locked and checked again. If another admin creates the
    -- same ID between planning and this loop, the exception rolls back all drafts
    -- already created by this batch instead of converting the write into an edit.
    perform pg_advisory_xact_lock(hashtext('scoremore:dynamic-test:' || v_item.proposed_test_id));
    if exists (
      select 1
      from public.tests concurrent_test
      where concurrent_test.test_id = v_item.proposed_test_id
    ) then
      raise exception 'Test ID % was created while this batch was running. No sectional draft was created; preview again.', v_item.proposed_test_id
        using errcode = 'P0001';
    end if;

    v_result := public.save_phase4a_dynamic_test_v16(
      v_item.proposed_test_id,
      v_item.proposed_test_name,
      'PYQ_SECTIONAL',
      jsonb_build_object(
        'package_ids', jsonb_build_array(v_item.package_id),
        'subject_ids', jsonb_build_array(v_item.subject_id),
        'topic_ids', '[]'::jsonb,
        'include_supplemental', coalesce(p_include_supplemental, true),
        'include_superseded', false,
        'include_unassigned', false
      ),
      array[]::text[],
      'PACKAGE_ORIGINAL',
      null,
      v_item.duration_minutes,
      p_marks_per_question,
      p_negative_marks,
      coalesce(p_sort_order_start, 1) + v_created_count,
      false
    );

    v_created_count := v_created_count + 1;
    v_created := v_created || jsonb_build_array(jsonb_build_object(
      'test_id', v_item.proposed_test_id,
      'test_name', v_item.proposed_test_name,
      'package_id', v_item.package_id,
      'subject_id', v_item.subject_id,
      'question_count', v_item.question_count,
      'duration_minutes', v_item.duration_minutes,
      'status', 'DRAFT'
    ));
  end loop;

  insert into public.admin_audit_logs (
    admin_user_id,
    action,
    entity_type,
    entity_id,
    details
  ) values (
    v_admin,
    'CREATE_SECTIONAL_BATCH_DRAFTS',
    'TEST_BATCH',
    array_to_string(v_package_ids, ','),
    jsonb_build_object(
      'package_ids', to_jsonb(v_package_ids),
      'include_supplemental', coalesce(p_include_supplemental, true),
      'created_count', v_created_count,
      'existing_count', coalesce(v_existing_count, 0),
      'status', 'DRAFT'
    )
  );

  return jsonb_build_object(
    'schema', 'scoremore.sectional-batch-save-v1',
    'package_ids', to_jsonb(v_package_ids),
    'created_count', v_created_count,
    'existing_count', coalesce(v_existing_count, 0),
    'status', 'DRAFT',
    'created', v_created
  );
end;
$$;

revoke all on function public.save_phase4a_sectional_batch_v1(
  text[],boolean,numeric,numeric,integer,text
) from public, anon;

grant execute on function public.save_phase4a_sectional_batch_v1(
  text[],boolean,numeric,numeric,integer,text
) to authenticated;

comment on function public.save_phase4a_dynamic_test_v16(text,text,text,jsonb,text[],text,public.test_type,integer,numeric,numeric,integer,boolean) is
  'Admin-only Phase 4A v1.6 writer. Rejects an existing Test ID when its saved package, subject or topic scope differs, preventing cross-subject replacement.';
comment on function public.preview_phase4a_sectional_batch_v1(text[],boolean) is
  'Admin-only dry-run plan for one missing sectional draft per published subject in each selected active package. Existing legacy and v1.6 scopes are skipped.';
comment on function public.save_phase4a_sectional_batch_v1(text[],boolean,numeric,numeric,integer,text) is
  'Admin-only atomic creator for missing package-by-subject sectional drafts. Existing tests are never overwritten; any identity conflict aborts the transaction.';

commit;
