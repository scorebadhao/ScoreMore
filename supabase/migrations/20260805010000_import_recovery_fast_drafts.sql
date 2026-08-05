-- ScoreMore import recovery and fast draft creation
-- Date: 2026-08-05
-- Fixes:
-- 1. AI_PROPOSED records incorrectly remaining INVALID after the legacy answer-source error is filtered.
-- 2. Large all-at-once draft imports timing out on mobile connections.
-- 3. Client timeouts leaving the admin unsure whether drafts were actually created.
-- 4. Safe recovery/reset of unreviewed drafts while preserving batch/item/audit history.

begin;

-- Preserve the Phase 3E compatibility validator, then repair its final status calculation.
alter function public.validate_import_question(jsonb)
  rename to validate_import_question_phase3e_compat_buggy;

create or replace function public.validate_import_question(p_question jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb := public.validate_import_question_phase3e_compat_buggy(p_question);
  v_status text := v_result ->> 'status';
  v_errors jsonb := coalesce(v_result -> 'errors', '[]'::jsonb);
  v_warnings jsonb := coalesce(v_result -> 'warnings', '[]'::jsonb);
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  -- Phase 3E intentionally removes INVALID_ANSWER_SOURCE for AI_PROPOSED, but the
  -- previous wrapper left the inherited INVALID status unchanged. Recompute only
  -- when no blocking error remains. Duplicate/conflict statuses are preserved.
  if v_status = 'INVALID' and jsonb_array_length(v_errors) = 0 then
    v_status := case
      when jsonb_array_length(v_warnings) > 0 then 'VALID_WITH_WARNINGS'
      else 'VALID'
    end;
  elsif jsonb_array_length(v_errors) > 0 then
    v_status := 'INVALID';
  elsif v_status in ('VALID', 'VALID_WITH_WARNINGS')
        and jsonb_array_length(v_warnings) > 0 then
    v_status := 'VALID_WITH_WARNINGS';
  end if;

  return jsonb_set(v_result, '{status}', to_jsonb(v_status), true);
end;
$$;

-- Keep reconciliation and action counters accurate after repairs, chunk imports,
-- resets, and timeout recovery.
create or replace function public.refresh_import_batch_action_totals(p_import_batch_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer := 0;
  v_valid integer := 0;
  v_warning integer := 0;
  v_error integer := 0;
  v_duplicate integer := 0;
  v_imported integer := 0;
  v_linked integer := 0;
  v_skipped integer := 0;
  v_remaining integer := 0;
  v_actioned integer := 0;
  v_blocked integer := 0;
begin
  select
    count(*),
    count(*) filter (where validation_status = 'VALID'),
    count(*) filter (where validation_status in ('VALID_WITH_WARNINGS', 'POSSIBLE_DUPLICATE')),
    count(*) filter (where validation_status in ('INVALID', 'ID_CONFLICT', 'ANSWER_CONFLICT', 'SOURCE_CONFLICT')),
    count(*) filter (where validation_status in ('EXACT_DUPLICATE', 'POSSIBLE_DUPLICATE')),
    count(*) filter (where validation_status = 'IMPORTED_TO_DRAFT'),
    count(*) filter (where validation_status = 'LINKED_TO_EXISTING'),
    count(*) filter (where resolution_action = 'SKIP_DUPLICATE'),
    count(*) filter (where validation_status in ('VALID', 'VALID_WITH_WARNINGS')),
    count(*) filter (where resolution_action <> 'NONE'),
    count(*) filter (where resolution_action = 'BLOCKED')
  into
    v_total, v_valid, v_warning, v_error, v_duplicate,
    v_imported, v_linked, v_skipped, v_remaining, v_actioned, v_blocked
  from public.import_batch_items
  where import_batch_id = p_import_batch_id;

  update public.import_batches
  set total_raw = v_total,
      total_valid = v_valid,
      total_warning = v_warning,
      total_error = v_error,
      total_duplicate = v_duplicate,
      total_draft = v_imported,
      total_linked = v_linked,
      total_skipped = v_skipped,
      status = case
        when v_error > 0 then 'DRY_RUN_COMPLETE_WITH_ERRORS'
        when v_warning > 0 or v_duplicate > 0 then 'DRY_RUN_COMPLETE_WITH_WARNINGS'
        else 'DRY_RUN_COMPLETE'
      end,
      draft_import_status = case
        when v_actioned = 0 then 'NOT_STARTED'
        when v_remaining = 0 and v_blocked = 0 then 'COMPLETE'
        else 'PARTIAL'
      end,
      draft_import_started_at = case
        when v_actioned > 0 then coalesce(draft_import_started_at, now())
        else draft_import_started_at
      end,
      draft_import_completed_at = case
        when v_actioned > 0 and v_remaining = 0 and v_blocked = 0 then coalesce(draft_import_completed_at, now())
        when v_remaining > 0 or v_blocked > 0 then null
        else draft_import_completed_at
      end,
      completed_at = coalesce(completed_at, now())
  where import_batch_id = p_import_batch_id;
end;
$$;

-- Return a lightweight report. Source images and duplicate raw payload copies stay
-- in the database and are loaded later through the draft review flow, not inside the
-- mobile reconciliation response.
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
        -- Avoid returning embedded base64 source previews and a second raw copy.
        'normalized_payload', (ibi.normalized_payload - 'image_refs' - 'group_text'),
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
        'resolution_action', ibi.resolution_action,
        'resolution_notes', ibi.resolution_notes,
        'resolved_by', ibi.resolved_by,
        'resolved_at', ibi.resolved_at,
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
        select count(*) from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.validation_status in ('VALID', 'VALID_WITH_WARNINGS')
      ),
      'imported_to_draft', (
        select count(*) from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.validation_status = 'IMPORTED_TO_DRAFT'
      ),
      'linked_to_existing', (
        select count(*) from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.validation_status = 'LINKED_TO_EXISTING'
      ),
      'skipped_duplicates', (
        select count(*) from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.resolution_action = 'SKIP_DUPLICATE'
      ),
      'actionable_occurrences', (
        select count(*) from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.validation_status = 'EXACT_DUPLICATE'
          and i.matched_question_id is not null
          and i.occurrence_key is not null
          and i.resolution_action = 'NONE'
      ),
      'repairable_items', (
        select count(*) from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.created_draft_id is null
          and (
            (i.validation_status = 'INVALID'
             and upper(coalesce(i.normalized_payload ->> 'answer_source', '')) = 'AI_PROPOSED')
            or (i.errors @> '[{"code":"DRAFT_INSERT_FAILED"}]'::jsonb)
            or (i.matched_draft_id is not null and not exists (
              select 1 from public.draft_questions d where d.draft_id = i.matched_draft_id
            ))
          )
      )
    ),
    'items', v_items,
    'report_mode', 'COMPACT_MOBILE'
  );
end;
$$;

create or replace function public.find_import_batch_by_identity(
  p_package_id text,
  p_package_checksum_sha256 text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch public.import_batches%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  select * into v_batch
  from public.import_batches
  where (
      nullif(lower(btrim(p_package_checksum_sha256)), '') is not null
      and package_checksum_sha256 = lower(btrim(p_package_checksum_sha256))
    )
    or (
      nullif(lower(btrim(p_package_checksum_sha256)), '') is null
      and package_id = upper(nullif(btrim(p_package_id), ''))
    )
  order by created_at desc
  limit 1;

  if not found then return null; end if;

  return jsonb_build_object(
    'import_batch_id', v_batch.import_batch_id,
    'package_id', v_batch.package_id,
    'status', v_batch.status,
    'draft_import_status', v_batch.draft_import_status,
    'total_raw', v_batch.total_raw,
    'total_draft', v_batch.total_draft,
    'created_at', v_batch.created_at,
    'completed_at', v_batch.completed_at
  );
end;
$$;

-- Reconcile the item ledger with draft_questions. This is the authoritative answer
-- after a client timeout: if a draft exists, it is recorded; if it does not, the item
-- is returned to its current validation state.
create or replace function public.reconcile_import_batch_state(p_import_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_item public.import_batch_items%rowtype;
  v_validation jsonb;
  v_status public.import_item_status;
  v_draft_id uuid;
  v_found integer := 0;
  v_released integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.import_batches where import_batch_id = p_import_batch_id) then
    raise exception 'Import batch not found.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_import_batch_id::text));

  for v_item in
    select * from public.import_batch_items
    where import_batch_id = p_import_batch_id
    order by item_index
    for update
  loop
    select draft_id into v_draft_id
    from public.draft_questions
    where import_item_id = v_item.import_item_id
    order by created_at
    limit 1;

    if v_draft_id is not null then
      update public.import_batch_items
      set validation_status = 'IMPORTED_TO_DRAFT',
          created_draft_id = v_draft_id,
          matched_draft_id = v_draft_id,
          resolution_action = 'CREATE_DRAFT',
          resolution_notes = coalesce(resolution_notes, 'Recovered from the actual draft_questions state after a client timeout.'),
          resolved_by = coalesce(resolved_by, v_admin),
          resolved_at = coalesce(resolved_at, now())
      where import_item_id = v_item.import_item_id;
      v_found := v_found + 1;
    elsif v_item.validation_status = 'IMPORTED_TO_DRAFT'
       or v_item.created_draft_id is not null
       or (v_item.resolution_action = 'CREATE_DRAFT' and v_item.matched_draft_id is not null) then
      v_validation := public.validate_import_question(v_item.normalized_payload);
      v_status := (v_validation ->> 'status')::public.import_item_status;

      update public.import_batch_items
      set validation_status = v_status,
          errors = coalesce(v_validation -> 'errors', '[]'::jsonb),
          warnings = coalesce(v_validation -> 'warnings', '[]'::jsonb),
          duplicate_kind = coalesce(nullif(v_validation #>> '{duplicate,kind}', ''), 'NONE')::public.import_duplicate_kind,
          matched_question_id = nullif(v_validation #>> '{duplicate,matched_question_id}', ''),
          matched_draft_id = nullif(v_validation #>> '{duplicate,matched_draft_id}', '')::uuid,
          created_draft_id = null,
          strict_fingerprint = nullif(v_validation #>> '{fingerprints,strict}', ''),
          loose_fingerprint = nullif(v_validation #>> '{fingerprints,loose}', ''),
          occurrence_key = nullif(v_validation ->> 'occurrence_key', ''),
          resolution_action = 'NONE',
          resolution_notes = 'Recovered stale draft state; no corresponding draft_questions row exists.',
          resolved_by = v_admin,
          resolved_at = now()
      where import_item_id = v_item.import_item_id;
      v_released := v_released + 1;
    end if;
  end loop;

  perform public.refresh_import_batch_action_totals(p_import_batch_id);

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (v_admin, 'RECONCILE_IMPORT_BATCH_STATE', 'IMPORT_BATCH', p_import_batch_id::text,
    jsonb_build_object('drafts_found', v_found, 'stale_items_released', v_released));

  return jsonb_build_object(
    'import_batch_id', p_import_batch_id,
    'drafts_found', v_found,
    'stale_items_released', v_released
  );
end;
$$;

-- Repair the known Phase 3E AI_PROPOSED false-invalid condition and stale
-- draft-duplicate matches in small mobile-safe chunks. Genuine errors remain untouched.
create or replace function public.repair_ai_proposed_import_chunk(
  p_import_batch_id uuid,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_item public.import_batch_items%rowtype;
  v_validation jsonb;
  v_status public.import_item_status;
  v_processed integer := 0;
  v_repaired integer := 0;
  v_remaining integer := 0;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.import_batches where import_batch_id = p_import_batch_id) then
    raise exception 'Import batch not found.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_import_batch_id::text));

  for v_item in
    select * from public.import_batch_items
    where import_batch_id = p_import_batch_id
      and created_draft_id is null
      and not exists (
        select 1 from public.draft_questions d where d.import_item_id = import_batch_items.import_item_id
      )
      and (
        (
          validation_status = 'INVALID'
          and upper(coalesce(normalized_payload ->> 'answer_source', '')) = 'AI_PROPOSED'
        )
        or (errors @> '[{"code":"DRAFT_INSERT_FAILED"}]'::jsonb)
        or (
          matched_draft_id is not null
          and not exists (
            select 1 from public.draft_questions stale where stale.draft_id = import_batch_items.matched_draft_id
          )
        )
      )
    order by item_index
    limit v_limit
    for update
  loop
    v_processed := v_processed + 1;
    v_validation := public.validate_import_question(v_item.normalized_payload);
    v_status := (v_validation ->> 'status')::public.import_item_status;

    update public.import_batch_items
    set validation_status = v_status,
        errors = coalesce(v_validation -> 'errors', '[]'::jsonb),
        warnings = coalesce(v_validation -> 'warnings', '[]'::jsonb),
        duplicate_kind = coalesce(nullif(v_validation #>> '{duplicate,kind}', ''), 'NONE')::public.import_duplicate_kind,
        matched_question_id = nullif(v_validation #>> '{duplicate,matched_question_id}', ''),
        matched_draft_id = nullif(v_validation #>> '{duplicate,matched_draft_id}', '')::uuid,
        strict_fingerprint = nullif(v_validation #>> '{fingerprints,strict}', ''),
        loose_fingerprint = nullif(v_validation #>> '{fingerprints,loose}', ''),
        occurrence_key = nullif(v_validation ->> 'occurrence_key', ''),
        resolution_action = case when v_status in ('VALID','VALID_WITH_WARNINGS') then 'NONE' else resolution_action end,
        resolution_notes = case when v_status in ('VALID','VALID_WITH_WARNINGS') then 'Revalidated after the Phase 3E AI_PROPOSED status fix.' else resolution_notes end,
        resolved_by = case when v_status in ('VALID','VALID_WITH_WARNINGS') then v_admin else resolved_by end,
        resolved_at = case when v_status in ('VALID','VALID_WITH_WARNINGS') then now() else resolved_at end
    where import_item_id = v_item.import_item_id;

    if v_status in ('VALID','VALID_WITH_WARNINGS') then
      v_repaired := v_repaired + 1;
    end if;
  end loop;

  select count(*) into v_remaining
  from public.import_batch_items
  where import_batch_id = p_import_batch_id
    and created_draft_id is null
    and (
      (
        validation_status = 'INVALID'
        and upper(coalesce(normalized_payload ->> 'answer_source', '')) = 'AI_PROPOSED'
      )
      or (errors @> '[{"code":"DRAFT_INSERT_FAILED"}]'::jsonb)
      or (
        matched_draft_id is not null
        and not exists (
          select 1 from public.draft_questions stale where stale.draft_id = import_batch_items.matched_draft_id
        )
      )
    );

  perform public.refresh_import_batch_action_totals(p_import_batch_id);

  return jsonb_build_object(
    'import_batch_id', p_import_batch_id,
    'processed', v_processed,
    'repaired', v_repaired,
    'remaining', v_remaining
  );
end;
$$;

-- Small, resumable draft chunks. The frontend repeats this call until remaining = 0.
create or replace function public.import_next_valid_batch_chunk(
  p_import_batch_id uuid,
  p_limit integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_batch public.import_batches%rowtype;
  v_item public.import_batch_items%rowtype;
  v_payload jsonb;
  v_validation jsonb;
  v_status public.import_item_status;
  v_draft_id uuid;
  v_tags text[];
  v_limit integer := least(greatest(coalesce(p_limit, 10), 1), 25);
  v_processed integer := 0;
  v_imported integer := 0;
  v_skipped integer := 0;
  v_failed integer := 0;
  v_remaining integer := 0;
  v_draft_ids jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  select * into v_batch from public.import_batches
  where import_batch_id = p_import_batch_id
  for update;
  if not found then raise exception 'Import batch not found.' using errcode = 'P0001'; end if;
  if v_batch.status not like 'DRY_RUN_COMPLETE%' then
    raise exception 'The authoritative dry run must complete before draft creation.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_import_batch_id::text));

  for v_item in
    select * from public.import_batch_items
    where import_batch_id = p_import_batch_id
      and validation_status in ('VALID','VALID_WITH_WARNINGS')
    order by item_index
    limit v_limit
    for update
  loop
    v_processed := v_processed + 1;

    select draft_id into v_draft_id
    from public.draft_questions
    where import_item_id = v_item.import_item_id
    order by created_at
    limit 1;

    if v_draft_id is not null then
      update public.import_batch_items
      set validation_status = 'IMPORTED_TO_DRAFT',
          created_draft_id = v_draft_id,
          matched_draft_id = v_draft_id,
          resolution_action = 'CREATE_DRAFT',
          resolution_notes = 'Existing draft recovered during resumable import.',
          resolved_by = v_admin,
          resolved_at = now()
      where import_item_id = v_item.import_item_id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_validation := public.validate_import_question(v_item.normalized_payload);
    v_status := (v_validation ->> 'status')::public.import_item_status;

    update public.import_batch_items
    set validation_status = v_status,
        errors = coalesce(v_validation -> 'errors', '[]'::jsonb),
        warnings = coalesce(v_validation -> 'warnings', '[]'::jsonb),
        duplicate_kind = coalesce(nullif(v_validation #>> '{duplicate,kind}', ''), 'NONE')::public.import_duplicate_kind,
        matched_question_id = nullif(v_validation #>> '{duplicate,matched_question_id}', ''),
        matched_draft_id = nullif(v_validation #>> '{duplicate,matched_draft_id}', '')::uuid,
        strict_fingerprint = nullif(v_validation #>> '{fingerprints,strict}', ''),
        loose_fingerprint = nullif(v_validation #>> '{fingerprints,loose}', ''),
        occurrence_key = nullif(v_validation ->> 'occurrence_key', '')
    where import_item_id = v_item.import_item_id;

    if v_status not in ('VALID','VALID_WITH_WARNINGS') then
      update public.import_batch_items
      set resolution_action = case when v_status = 'EXACT_DUPLICATE' then 'SKIP_DUPLICATE' else 'BLOCKED' end,
          resolution_notes = 'Current-state revalidation stopped draft creation.',
          resolved_by = v_admin,
          resolved_at = now()
      where import_item_id = v_item.import_item_id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_payload := v_item.normalized_payload;
    select coalesce(array_agg(tag_value order by ordinality), '{}'::text[])
      into v_tags
    from jsonb_array_elements_text(coalesce(v_payload -> 'tags', '[]'::jsonb))
      with ordinality as tag_rows(tag_value, ordinality);

    begin
      insert into public.draft_questions (
        import_batch_id, question_type, proposed_question_id, board_id, exam_id,
        exam_year, exam_date, shift_no, paper_code, original_question_no,
        subject_id, topic_id, section_code, language, difficulty, question_text,
        options, correct_answer, explanation, image_refs, content_id,
        source_file_id, source_page, source_question_id, group_id, group_type,
        group_text, answer_source, verification_status, question_status,
        review_status, tags, created_by, sort_order, content_origin, import_item_id
      ) values (
        p_import_batch_id,
        (v_payload ->> 'question_type')::public.question_type,
        v_payload ->> 'proposed_question_id',
        v_payload ->> 'board_id',
        nullif(v_payload ->> 'exam_id',''),
        public.try_parse_integer(v_payload ->> 'exam_year'),
        public.try_parse_date(v_payload ->> 'exam_date'),
        public.try_parse_integer(v_payload ->> 'shift_no'),
        nullif(v_payload ->> 'paper_code',''),
        public.try_parse_integer(v_payload ->> 'original_question_no'),
        v_payload ->> 'subject_id',
        nullif(v_payload ->> 'topic_id',''),
        nullif(v_payload ->> 'section_code',''),
        v_payload ->> 'language',
        v_payload ->> 'difficulty',
        v_payload ->> 'question_text',
        v_payload -> 'options',
        nullif(v_payload ->> 'correct_answer',''),
        nullif(v_payload ->> 'explanation',''),
        coalesce(v_payload -> 'image_refs','[]'::jsonb),
        nullif(v_payload ->> 'content_id',''),
        v_batch.source_file_id,
        public.try_parse_integer(v_payload ->> 'source_page'),
        nullif(v_payload ->> 'source_question_id',''),
        nullif(v_payload ->> 'group_id',''),
        nullif(v_payload ->> 'group_type',''),
        nullif(v_payload ->> 'group_text',''),
        case when nullif(v_payload ->> 'answer_source','') is null then null
             else (v_payload ->> 'answer_source')::public.answer_source end,
        (v_payload ->> 'verification_status')::public.verification_status,
        'DRAFT', 'PENDING', v_tags, v_admin,
        public.try_parse_integer(v_payload ->> 'sort_order'),
        (v_payload ->> 'content_origin')::public.content_origin,
        v_item.import_item_id
      ) returning draft_id into v_draft_id;

      update public.import_batch_items
      set validation_status = 'IMPORTED_TO_DRAFT',
          created_draft_id = v_draft_id,
          matched_draft_id = v_draft_id,
          resolution_action = 'CREATE_DRAFT',
          resolution_notes = 'Created through the resumable mobile-safe draft importer.',
          resolved_by = v_admin,
          resolved_at = now()
      where import_item_id = v_item.import_item_id;

      v_draft_ids := v_draft_ids || jsonb_build_array(v_draft_id);
      v_imported := v_imported + 1;
    exception
      when unique_violation then
        select draft_id into v_draft_id from public.draft_questions
        where import_item_id = v_item.import_item_id limit 1;
        if v_draft_id is not null then
          update public.import_batch_items
          set validation_status = 'IMPORTED_TO_DRAFT',
              created_draft_id = v_draft_id,
              matched_draft_id = v_draft_id,
              resolution_action = 'CREATE_DRAFT',
              resolution_notes = 'Recovered an idempotent draft after a concurrent or timed-out request.',
              resolved_by = v_admin,
              resolved_at = now()
          where import_item_id = v_item.import_item_id;
        else
          v_validation := public.validate_import_question(v_item.normalized_payload);
          v_status := (v_validation ->> 'status')::public.import_item_status;
          update public.import_batch_items
          set validation_status = case when v_status in ('EXACT_DUPLICATE','POSSIBLE_DUPLICATE','ID_CONFLICT','ANSWER_CONFLICT','SOURCE_CONFLICT') then v_status else 'INVALID' end,
              errors = coalesce(v_validation -> 'errors','[]'::jsonb),
              warnings = coalesce(v_validation -> 'warnings','[]'::jsonb),
              resolution_action = case when v_status = 'EXACT_DUPLICATE' then 'SKIP_DUPLICATE' else 'BLOCKED' end,
              resolution_notes = 'Draft creation stopped by a duplicate or Question ID conflict.',
              resolved_by = v_admin,
              resolved_at = now()
          where import_item_id = v_item.import_item_id;
        end if;
        v_skipped := v_skipped + 1;
      when others then
        update public.import_batch_items
        set validation_status = 'INVALID',
            errors = errors || jsonb_build_array(jsonb_build_object(
              'code','DRAFT_INSERT_FAILED',
              'message','This record could not create a draft. Recheck the batch after the underlying issue is corrected.'
            )),
            resolution_action = 'BLOCKED',
            resolution_notes = 'Resumable draft chunk failed; no master question was published.',
            resolved_by = v_admin,
            resolved_at = now()
        where import_item_id = v_item.import_item_id;
        v_failed := v_failed + 1;
    end;
  end loop;

  select count(*) into v_remaining
  from public.import_batch_items
  where import_batch_id = p_import_batch_id
    and validation_status in ('VALID','VALID_WITH_WARNINGS');

  perform public.refresh_import_batch_action_totals(p_import_batch_id);

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (v_admin, 'IMPORT_DRAFT_CHUNK', 'IMPORT_BATCH', p_import_batch_id::text,
    jsonb_build_object('processed',v_processed,'imported',v_imported,'skipped',v_skipped,'failed',v_failed,'remaining',v_remaining));

  return jsonb_build_object(
    'import_batch_id', p_import_batch_id,
    'processed', v_processed,
    'imported', v_imported,
    'skipped', v_skipped,
    'failed', v_failed,
    'remaining', v_remaining,
    'draft_ids', v_draft_ids
  );
end;
$$;

-- Optional recovery action for an admin who wants to discard only untouched,
-- unpublished PENDING drafts from a failed/timed-out batch and start again.
create or replace function public.reset_unreviewed_import_batch_drafts(
  p_import_batch_id uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_item_id uuid;
  v_draft_id uuid;
  v_related_item_id uuid;
  v_related_item_ids uuid[] := '{}'::uuid[];
  v_related_batch_id uuid;
  v_related_batch_ids uuid[] := '{}'::uuid[];
  v_touched_batch_ids uuid[] := array[p_import_batch_id];
  v_validation jsonb;
  v_status public.import_item_status;
  v_deleted integer := 0;
  v_remaining_protected integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;
  if p_confirmation is distinct from 'RESET_UNREVIEWED_DRAFTS' then
    raise exception 'Type the required reset confirmation.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_import_batch_id::text));

  for v_item_id, v_draft_id in
    select d.import_item_id, d.draft_id
    from public.draft_questions d
    where d.import_batch_id = p_import_batch_id
      and d.import_item_id is not null
      and d.review_status = 'PENDING'
      and d.question_status = 'DRAFT'
      and d.reviewed_at is null
      and d.published_question_id is null
    order by d.created_at
    for update
  loop
    -- A later package may currently point to this draft as an exact duplicate.
    -- Clear those foreign-key references before deletion and revalidate them after.
    select coalesce(array_agg(import_item_id), '{}'::uuid[])
      into v_related_item_ids
    from public.import_batch_items
    where matched_draft_id = v_draft_id and import_item_id <> v_item_id;

    select coalesce(array_agg(distinct import_batch_id), '{}'::uuid[])
      into v_related_batch_ids
    from public.import_batch_items
    where import_item_id = any(v_related_item_ids);
    v_touched_batch_ids := v_touched_batch_ids || v_related_batch_ids;

    if cardinality(v_related_item_ids) > 0 then
      update public.import_batch_items
      set matched_draft_id = null,
          resolution_action = 'NONE',
          resolution_notes = 'Related unreviewed draft was reset; this record will be revalidated.',
          resolved_by = v_admin,
          resolved_at = now()
      where import_item_id = any(v_related_item_ids);
    end if;

    update public.import_batch_items
    set created_draft_id = null,
        matched_draft_id = null,
        resolution_action = 'NONE',
        resolution_notes = 'Unreviewed draft reset by administrator; reconciliation history retained.',
        resolved_by = v_admin,
        resolved_at = now()
    where import_item_id = v_item_id;

    delete from public.draft_questions where draft_id = v_draft_id;

    foreach v_related_item_id in array v_related_item_ids
    loop
      select normalized_payload into v_validation
      from public.import_batch_items where import_item_id = v_related_item_id;
      v_validation := public.validate_import_question(v_validation);
      v_status := (v_validation ->> 'status')::public.import_item_status;

      update public.import_batch_items
      set validation_status = v_status,
          errors = coalesce(v_validation -> 'errors','[]'::jsonb),
          warnings = coalesce(v_validation -> 'warnings','[]'::jsonb),
          duplicate_kind = coalesce(nullif(v_validation #>> '{duplicate,kind}',''),'NONE')::public.import_duplicate_kind,
          matched_question_id = nullif(v_validation #>> '{duplicate,matched_question_id}',''),
          matched_draft_id = nullif(v_validation #>> '{duplicate,matched_draft_id}','')::uuid,
          strict_fingerprint = nullif(v_validation #>> '{fingerprints,strict}',''),
          loose_fingerprint = nullif(v_validation #>> '{fingerprints,loose}',''),
          occurrence_key = nullif(v_validation ->> 'occurrence_key',''),
          resolution_action = 'NONE',
          resolution_notes = 'Revalidated after the related unreviewed draft was reset.',
          resolved_by = v_admin,
          resolved_at = now()
      where import_item_id = v_related_item_id;
    end loop;

    select normalized_payload into v_validation
    from public.import_batch_items where import_item_id = v_item_id;
    v_validation := public.validate_import_question(v_validation);
    v_status := (v_validation ->> 'status')::public.import_item_status;

    update public.import_batch_items
    set validation_status = v_status,
        errors = coalesce(v_validation -> 'errors','[]'::jsonb),
        warnings = coalesce(v_validation -> 'warnings','[]'::jsonb),
        duplicate_kind = coalesce(nullif(v_validation #>> '{duplicate,kind}',''),'NONE')::public.import_duplicate_kind,
        matched_question_id = nullif(v_validation #>> '{duplicate,matched_question_id}',''),
        matched_draft_id = nullif(v_validation #>> '{duplicate,matched_draft_id}','')::uuid,
        strict_fingerprint = nullif(v_validation #>> '{fingerprints,strict}',''),
        loose_fingerprint = nullif(v_validation #>> '{fingerprints,loose}',''),
        occurrence_key = nullif(v_validation ->> 'occurrence_key','')
    where import_item_id = v_item_id;

    v_deleted := v_deleted + 1;
  end loop;

  select count(*) into v_remaining_protected
  from public.draft_questions
  where import_batch_id = p_import_batch_id
    and review_status <> 'PUBLISHED';

  for v_related_batch_id in
    select distinct touched_batch_id from unnest(v_touched_batch_ids) as touched(touched_batch_id)
  loop
    perform public.refresh_import_batch_action_totals(v_related_batch_id);
  end loop;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (v_admin, 'RESET_UNREVIEWED_IMPORT_DRAFTS', 'IMPORT_BATCH', p_import_batch_id::text,
    jsonb_build_object('deleted_unreviewed_drafts',v_deleted,'protected_drafts_remaining',v_remaining_protected));

  return jsonb_build_object(
    'import_batch_id', p_import_batch_id,
    'deleted_unreviewed_drafts', v_deleted,
    'protected_drafts_remaining', v_remaining_protected
  );
end;
$$;

revoke all on function public.validate_import_question_phase3e_compat_buggy(jsonb) from public, anon, authenticated;
revoke all on function public.validate_import_question(jsonb) from public, anon, authenticated;
revoke all on function public.get_import_batch_report(uuid) from public, anon, authenticated;
revoke all on function public.find_import_batch_by_identity(text,text) from public, anon;
revoke all on function public.reconcile_import_batch_state(uuid) from public, anon;
revoke all on function public.repair_ai_proposed_import_chunk(uuid,integer) from public, anon;
revoke all on function public.import_next_valid_batch_chunk(uuid,integer) from public, anon;
revoke all on function public.reset_unreviewed_import_batch_drafts(uuid,text) from public, anon;

grant execute on function public.validate_import_question(jsonb) to authenticated;
grant execute on function public.get_import_batch_report(uuid) to authenticated;
grant execute on function public.find_import_batch_by_identity(text,text) to authenticated;
grant execute on function public.reconcile_import_batch_state(uuid) to authenticated;
grant execute on function public.repair_ai_proposed_import_chunk(uuid,integer) to authenticated;
grant execute on function public.import_next_valid_batch_chunk(uuid,integer) to authenticated;
grant execute on function public.reset_unreviewed_import_batch_drafts(uuid,text) to authenticated;

comment on function public.get_import_batch_report(uuid) is
  'Admin-only compact mobile report. Omits embedded image previews and duplicate raw payload copies from the response.';
comment on function public.reconcile_import_batch_state(uuid) is
  'Admin-only timeout recovery. Reconciles import items with actual draft_questions rows without publishing anything.';
comment on function public.import_next_valid_batch_chunk(uuid,integer) is
  'Admin-only resumable draft import in small chunks. Creates draft_questions only and never publishes master questions.';
comment on function public.reset_unreviewed_import_batch_drafts(uuid,text) is
  'Admin-only controlled reset for untouched PENDING drafts; preserves import and audit history.';

commit;
