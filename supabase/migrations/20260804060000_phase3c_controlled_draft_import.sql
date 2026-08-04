-- ScoreMore Phase 3C: controlled import from reconciled HTML batch items to draft_questions
-- Date: 2026-08-04
-- Scope: idempotent draft creation, authoritative revalidation, explicit duplicate
--        occurrence linking, reconciliation actions and audit history.
-- No imported record is inserted directly into public.questions.

begin;

alter table public.import_batches
  add column draft_import_status text not null default 'NOT_STARTED',
  add column total_linked integer not null default 0,
  add column total_skipped integer not null default 0,
  add column draft_import_started_at timestamptz,
  add column draft_import_completed_at timestamptz;

alter table public.import_batches
  add constraint import_batches_draft_import_status_check
    check (draft_import_status in ('NOT_STARTED', 'PARTIAL', 'COMPLETE')),
  add constraint import_batches_phase3c_counts_nonnegative
    check (total_linked >= 0 and total_skipped >= 0);

alter table public.import_batch_items
  add column resolution_action text not null default 'NONE',
  add column resolution_notes text,
  add column resolved_by uuid references public.profiles(user_id),
  add column resolved_at timestamptz;

alter table public.import_batch_items
  add constraint import_batch_items_resolution_action_check
    check (resolution_action in (
      'NONE',
      'CREATE_DRAFT',
      'LINK_OCCURRENCE',
      'SKIP_DUPLICATE',
      'BLOCKED'
    ));

create or replace function public.refresh_import_batch_action_totals(p_import_batch_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_imported integer := 0;
  v_linked integer := 0;
  v_skipped integer := 0;
  v_remaining integer := 0;
  v_actioned integer := 0;
begin
  select
    count(*) filter (where validation_status = 'IMPORTED_TO_DRAFT'),
    count(*) filter (where validation_status = 'LINKED_TO_EXISTING'),
    count(*) filter (where resolution_action = 'SKIP_DUPLICATE'),
    count(*) filter (where validation_status in ('VALID', 'VALID_WITH_WARNINGS')),
    count(*) filter (where resolution_action <> 'NONE')
  into v_imported, v_linked, v_skipped, v_remaining, v_actioned
  from public.import_batch_items
  where import_batch_id = p_import_batch_id;

  update public.import_batches
  set total_draft = v_imported,
      total_linked = v_linked,
      total_skipped = v_skipped,
      draft_import_status = case
        when v_actioned = 0 then 'NOT_STARTED'
        when v_remaining = 0 then 'COMPLETE'
        else 'PARTIAL'
      end,
      draft_import_started_at = case
        when v_actioned > 0 then coalesce(draft_import_started_at, now())
        else draft_import_started_at
      end,
      draft_import_completed_at = case
        when v_actioned > 0 and v_remaining = 0 then coalesce(draft_import_completed_at, now())
        when v_remaining > 0 then null
        else draft_import_completed_at
      end
  where import_batch_id = p_import_batch_id;
end;
$$;

-- Replace the report RPC so Phase 3C actions and counters are visible to the admin UI.
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
        select count(*)
        from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.validation_status in ('VALID', 'VALID_WITH_WARNINGS')
      ),
      'imported_to_draft', (
        select count(*)
        from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.validation_status = 'IMPORTED_TO_DRAFT'
      ),
      'linked_to_existing', (
        select count(*)
        from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.validation_status = 'LINKED_TO_EXISTING'
      ),
      'skipped_duplicates', (
        select count(*)
        from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.resolution_action = 'SKIP_DUPLICATE'
      ),
      'actionable_occurrences', (
        select count(*)
        from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.validation_status = 'EXACT_DUPLICATE'
          and i.matched_question_id is not null
          and i.occurrence_key is not null
          and i.resolution_action = 'NONE'
      )
    ),
    'items', v_items
  );
end;
$$;

create or replace function public.import_valid_batch_items_to_drafts(
  p_import_batch_id uuid,
  p_import_item_ids uuid[] default null
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
  v_duplicate_kind public.import_duplicate_kind;
  v_matched_question_id text;
  v_matched_draft_id uuid;
  v_draft_id uuid;
  v_tags text[];
  v_results jsonb := '[]'::jsonb;
  v_requested_count integer := 0;
  v_imported_count integer := 0;
  v_skipped_count integer := 0;
  v_failed_count integer := 0;
  v_revalidated_count integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  select * into v_batch
  from public.import_batches
  where import_batch_id = p_import_batch_id
  for update;

  if not found then
    raise exception 'Import batch not found.' using errcode = 'P0001';
  end if;

  if v_batch.import_method is distinct from 'HTML_PACKAGE' then
    raise exception 'Only reconciled HTML import batches may create drafts through Phase 3C.' using errcode = 'P0001';
  end if;

  if v_batch.status not like 'DRY_RUN_COMPLETE%' then
    raise exception 'The authoritative dry run must complete before draft creation.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_import_batch_id::text));

  if p_import_item_ids is not null then
    if cardinality(p_import_item_ids) = 0 then
      raise exception 'Select at least one reconciled record.' using errcode = 'P0001';
    end if;

    if exists (
      select 1
      from unnest(p_import_item_ids) requested(import_item_id)
      where not exists (
        select 1
        from public.import_batch_items i
        where i.import_item_id = requested.import_item_id
          and i.import_batch_id = p_import_batch_id
      )
    ) then
      raise exception 'One or more selected records do not belong to this import batch.' using errcode = 'P0001';
    end if;
  end if;

  for v_item in
    select *
    from public.import_batch_items i
    where i.import_batch_id = p_import_batch_id
      and (p_import_item_ids is null or i.import_item_id = any(p_import_item_ids))
    order by i.item_index
    for update
  loop
    v_requested_count := v_requested_count + 1;

    if v_item.validation_status = 'IMPORTED_TO_DRAFT' and v_item.created_draft_id is not null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'import_item_id', v_item.import_item_id,
        'item_index', v_item.item_index,
        'status', 'ALREADY_IMPORTED',
        'draft_id', v_item.created_draft_id
      ));
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    if v_item.validation_status not in ('VALID', 'VALID_WITH_WARNINGS') then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'import_item_id', v_item.import_item_id,
        'item_index', v_item.item_index,
        'status', 'NOT_ELIGIBLE',
        'validation_status', v_item.validation_status
      ));
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    -- Revalidate against the current database immediately before creating a draft.
    v_validation := public.validate_import_question(v_item.normalized_payload);
    v_revalidated_count := v_revalidated_count + 1;
    v_status := (v_validation ->> 'status')::public.import_item_status;
    v_duplicate_kind := coalesce(
      nullif(v_validation #>> '{duplicate,kind}', ''),
      'NONE'
    )::public.import_duplicate_kind;
    v_matched_question_id := nullif(v_validation #>> '{duplicate,matched_question_id}', '');
    v_matched_draft_id := nullif(v_validation #>> '{duplicate,matched_draft_id}', '')::uuid;

    update public.import_batch_items
    set validation_status = v_status,
        errors = coalesce(v_validation -> 'errors', '[]'::jsonb),
        warnings = coalesce(v_validation -> 'warnings', '[]'::jsonb),
        duplicate_kind = v_duplicate_kind,
        matched_question_id = v_matched_question_id,
        matched_draft_id = v_matched_draft_id,
        strict_fingerprint = nullif(v_validation #>> '{fingerprints,strict}', ''),
        loose_fingerprint = nullif(v_validation #>> '{fingerprints,loose}', ''),
        occurrence_key = nullif(v_validation ->> 'occurrence_key', '')
    where import_item_id = v_item.import_item_id;

    if v_status not in ('VALID', 'VALID_WITH_WARNINGS') then
      update public.import_batch_items
      set resolution_action = case
            when v_status = 'EXACT_DUPLICATE'
                 and (nullif(v_validation ->> 'occurrence_key', '') is null
                      or v_matched_question_id is null)
              then 'SKIP_DUPLICATE'
            else resolution_action
          end,
          resolution_notes = case
            when v_status = 'EXACT_DUPLICATE'
                 and (nullif(v_validation ->> 'occurrence_key', '') is null
                      or v_matched_question_id is null)
              then 'Skipped during Phase 3C revalidation because matching content already exists.'
            else resolution_notes
          end,
          resolved_by = case
            when v_status = 'EXACT_DUPLICATE'
                 and (nullif(v_validation ->> 'occurrence_key', '') is null
                      or v_matched_question_id is null)
              then v_admin
            else resolved_by
          end,
          resolved_at = case
            when v_status = 'EXACT_DUPLICATE'
                 and (nullif(v_validation ->> 'occurrence_key', '') is null
                      or v_matched_question_id is null)
              then now()
            else resolved_at
          end
      where import_item_id = v_item.import_item_id;

      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'import_item_id', v_item.import_item_id,
        'item_index', v_item.item_index,
        'status', 'REVALIDATION_BLOCKED',
        'validation_status', v_status,
        'matched_question_id', v_matched_question_id,
        'matched_draft_id', v_matched_draft_id
      ));
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_item.normalized_payload;

    select coalesce(array_agg(tag_value order by ordinality), '{}'::text[])
    into v_tags
    from jsonb_array_elements_text(coalesce(v_payload -> 'tags', '[]'::jsonb))
      with ordinality as tag_rows(tag_value, ordinality);

    begin
      insert into public.draft_questions (
        import_batch_id,
        question_type,
        proposed_question_id,
        board_id,
        exam_id,
        exam_year,
        exam_date,
        shift_no,
        paper_code,
        original_question_no,
        subject_id,
        topic_id,
        section_code,
        language,
        difficulty,
        question_text,
        options,
        correct_answer,
        explanation,
        image_refs,
        content_id,
        source_file_id,
        source_page,
        source_question_id,
        group_id,
        group_type,
        group_text,
        answer_source,
        verification_status,
        question_status,
        review_status,
        tags,
        created_by,
        sort_order,
        content_origin,
        import_item_id
      ) values (
        p_import_batch_id,
        (v_payload ->> 'question_type')::public.question_type,
        v_payload ->> 'proposed_question_id',
        v_payload ->> 'board_id',
        nullif(v_payload ->> 'exam_id', ''),
        public.try_parse_integer(v_payload ->> 'exam_year'),
        public.try_parse_date(v_payload ->> 'exam_date'),
        public.try_parse_integer(v_payload ->> 'shift_no'),
        nullif(v_payload ->> 'paper_code', ''),
        public.try_parse_integer(v_payload ->> 'original_question_no'),
        v_payload ->> 'subject_id',
        nullif(v_payload ->> 'topic_id', ''),
        nullif(v_payload ->> 'section_code', ''),
        v_payload ->> 'language',
        v_payload ->> 'difficulty',
        v_payload ->> 'question_text',
        v_payload -> 'options',
        nullif(v_payload ->> 'correct_answer', ''),
        nullif(v_payload ->> 'explanation', ''),
        coalesce(v_payload -> 'image_refs', '[]'::jsonb),
        nullif(v_payload ->> 'content_id', ''),
        v_batch.source_file_id,
        public.try_parse_integer(v_payload ->> 'source_page'),
        nullif(v_payload ->> 'source_question_id', ''),
        nullif(v_payload ->> 'group_id', ''),
        nullif(v_payload ->> 'group_type', ''),
        nullif(v_payload ->> 'group_text', ''),
        case
          when nullif(v_payload ->> 'answer_source', '') is null then null
          else (v_payload ->> 'answer_source')::public.answer_source
        end,
        (v_payload ->> 'verification_status')::public.verification_status,
        'DRAFT',
        'PENDING',
        v_tags,
        v_admin,
        public.try_parse_integer(v_payload ->> 'sort_order'),
        (v_payload ->> 'content_origin')::public.content_origin,
        v_item.import_item_id
      )
      returning draft_id into v_draft_id;

      update public.import_batch_items
      set validation_status = 'IMPORTED_TO_DRAFT',
          created_draft_id = v_draft_id,
          matched_draft_id = v_draft_id,
          resolution_action = 'CREATE_DRAFT',
          resolution_notes = 'Created through the controlled Phase 3C import RPC after current-state revalidation.',
          resolved_by = v_admin,
          resolved_at = now()
      where import_item_id = v_item.import_item_id;

      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'import_item_id', v_item.import_item_id,
        'item_index', v_item.item_index,
        'status', 'IMPORTED_TO_DRAFT',
        'draft_id', v_draft_id
      ));
      v_imported_count := v_imported_count + 1;
    exception
      when unique_violation then
        v_validation := public.validate_import_question(v_item.normalized_payload);
        v_status := (v_validation ->> 'status')::public.import_item_status;
        v_matched_question_id := nullif(v_validation #>> '{duplicate,matched_question_id}', '');
        v_matched_draft_id := nullif(v_validation #>> '{duplicate,matched_draft_id}', '')::uuid;

        update public.import_batch_items
        set validation_status = case
              when v_status in ('EXACT_DUPLICATE', 'POSSIBLE_DUPLICATE', 'ID_CONFLICT', 'ANSWER_CONFLICT', 'SOURCE_CONFLICT')
                then v_status
              else 'INVALID'
            end,
            errors = case
              when v_status in ('EXACT_DUPLICATE', 'POSSIBLE_DUPLICATE', 'ID_CONFLICT', 'ANSWER_CONFLICT', 'SOURCE_CONFLICT')
                then coalesce(v_validation -> 'errors', '[]'::jsonb)
              else errors || jsonb_build_array(jsonb_build_object(
                'code', 'DRAFT_INSERT_CONFLICT',
                'message', 'A concurrent insert created conflicting question content or Question ID.'
              ))
            end,
            warnings = coalesce(v_validation -> 'warnings', warnings),
            duplicate_kind = coalesce(
              nullif(v_validation #>> '{duplicate,kind}', ''),
              duplicate_kind::text
            )::public.import_duplicate_kind,
            matched_question_id = v_matched_question_id,
            matched_draft_id = v_matched_draft_id,
            resolution_action = case
              when v_status = 'EXACT_DUPLICATE' then 'SKIP_DUPLICATE'
              else 'BLOCKED'
            end,
            resolution_notes = 'Draft creation was stopped by a concurrent duplicate or conflict.',
            resolved_by = v_admin,
            resolved_at = now()
        where import_item_id = v_item.import_item_id;

        v_results := v_results || jsonb_build_array(jsonb_build_object(
          'import_item_id', v_item.import_item_id,
          'item_index', v_item.item_index,
          'status', 'CONCURRENT_CONFLICT',
          'validation_status', v_status,
          'matched_question_id', v_matched_question_id,
          'matched_draft_id', v_matched_draft_id
        ));
        v_skipped_count := v_skipped_count + 1;
      when others then
        update public.import_batch_items
        set validation_status = 'INVALID',
            errors = errors || jsonb_build_array(jsonb_build_object(
              'code', 'DRAFT_INSERT_FAILED',
              'message', 'The controlled draft insert failed. Review this record and the server logs.'
            )),
            resolution_action = 'BLOCKED',
            resolution_notes = 'Draft creation failed during the controlled Phase 3C import.',
            resolved_by = v_admin,
            resolved_at = now()
        where import_item_id = v_item.import_item_id;

        v_results := v_results || jsonb_build_array(jsonb_build_object(
          'import_item_id', v_item.import_item_id,
          'item_index', v_item.item_index,
          'status', 'FAILED'
        ));
        v_failed_count := v_failed_count + 1;
    end;
  end loop;

  -- Reconciled exact duplicates that cannot represent a new source occurrence are skipped explicitly.
  update public.import_batch_items
  set resolution_action = 'SKIP_DUPLICATE',
      resolution_notes = coalesce(
        resolution_notes,
        'Exact duplicate retained in the reconciliation report; no duplicate draft was created.'
      ),
      resolved_by = coalesce(resolved_by, v_admin),
      resolved_at = coalesce(resolved_at, now())
  where import_batch_id = p_import_batch_id
    and validation_status = 'EXACT_DUPLICATE'
    and resolution_action = 'NONE'
    and (matched_question_id is null or occurrence_key is null);

  perform public.refresh_import_batch_action_totals(p_import_batch_id);

  insert into public.admin_audit_logs (
    admin_user_id,
    action,
    entity_type,
    entity_id,
    details
  ) values (
    v_admin,
    'IMPORT_VALID_TO_DRAFTS',
    'IMPORT_BATCH',
    p_import_batch_id::text,
    jsonb_build_object(
      'requested', v_requested_count,
      'revalidated', v_revalidated_count,
      'imported', v_imported_count,
      'skipped', v_skipped_count,
      'failed', v_failed_count,
      'selected_item_ids', to_jsonb(p_import_item_ids)
    )
  );

  return public.get_import_batch_report(p_import_batch_id)
    || jsonb_build_object(
      'draft_import_result', jsonb_build_object(
        'requested', v_requested_count,
        'revalidated', v_revalidated_count,
        'imported', v_imported_count,
        'skipped', v_skipped_count,
        'failed', v_failed_count,
        'items', v_results
      )
    );
end;
$$;

create or replace function public.link_import_batch_occurrences(
  p_import_batch_id uuid,
  p_import_item_ids uuid[]
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
  v_link_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_linked_count integer := 0;
  v_skipped_count integer := 0;
  v_failed_count integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if p_import_item_ids is null or cardinality(p_import_item_ids) = 0 then
    raise exception 'Select at least one exact duplicate PYQ occurrence.' using errcode = 'P0001';
  end if;

  select * into v_batch
  from public.import_batches
  where import_batch_id = p_import_batch_id
  for update;

  if not found then
    raise exception 'Import batch not found.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_import_batch_id::text));

  if exists (
    select 1
    from unnest(p_import_item_ids) requested(import_item_id)
    where not exists (
      select 1
      from public.import_batch_items i
      where i.import_item_id = requested.import_item_id
        and i.import_batch_id = p_import_batch_id
    )
  ) then
    raise exception 'One or more selected records do not belong to this import batch.' using errcode = 'P0001';
  end if;

  for v_item in
    select *
    from public.import_batch_items i
    where i.import_batch_id = p_import_batch_id
      and i.import_item_id = any(p_import_item_ids)
    order by i.item_index
    for update
  loop
    if v_item.validation_status = 'LINKED_TO_EXISTING' then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'import_item_id', v_item.import_item_id,
        'item_index', v_item.item_index,
        'status', 'ALREADY_LINKED',
        'question_id', v_item.matched_question_id
      ));
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    if v_item.validation_status <> 'EXACT_DUPLICATE'
       or v_item.matched_question_id is null
       or v_item.occurrence_key is null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'import_item_id', v_item.import_item_id,
        'item_index', v_item.item_index,
        'status', 'NOT_ACTIONABLE',
        'validation_status', v_item.validation_status
      ));
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    begin
      v_link_result := public.link_question_occurrence(
        v_item.matched_question_id,
        v_item.normalized_payload || jsonb_build_object(
          'source_record_id', v_item.source_record_id,
          'external_question_id', v_item.proposed_question_id,
          'strict_fingerprint', v_item.strict_fingerprint
        ),
        p_import_batch_id,
        v_batch.source_file_id,
        v_item.import_item_id
      );

      update public.import_batch_items
      set resolution_action = 'LINK_OCCURRENCE',
          resolution_notes = case
            when coalesce((v_link_result ->> 'already_linked')::boolean, false)
              then 'The source occurrence was already linked to the matching master question.'
            else 'The confirmed duplicate source occurrence was linked to the existing master question.'
          end,
          resolved_by = v_admin,
          resolved_at = now()
      where import_item_id = v_item.import_item_id;

      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'import_item_id', v_item.import_item_id,
        'item_index', v_item.item_index,
        'status', 'LINKED_TO_EXISTING',
        'question_id', v_item.matched_question_id,
        'occurrence_id', v_link_result ->> 'occurrence_id',
        'already_linked', coalesce((v_link_result ->> 'already_linked')::boolean, false)
      ));
      v_linked_count := v_linked_count + 1;
    exception
      when others then
        update public.import_batch_items
        set resolution_action = 'BLOCKED',
            resolution_notes = 'Occurrence linking failed. Review the source metadata and reconciliation report.',
            resolved_by = v_admin,
            resolved_at = now()
        where import_item_id = v_item.import_item_id;

        v_results := v_results || jsonb_build_array(jsonb_build_object(
          'import_item_id', v_item.import_item_id,
          'item_index', v_item.item_index,
          'status', 'FAILED'
        ));
        v_failed_count := v_failed_count + 1;
    end;
  end loop;

  perform public.refresh_import_batch_action_totals(p_import_batch_id);

  insert into public.admin_audit_logs (
    admin_user_id,
    action,
    entity_type,
    entity_id,
    details
  ) values (
    v_admin,
    'LINK_IMPORT_OCCURRENCES',
    'IMPORT_BATCH',
    p_import_batch_id::text,
    jsonb_build_object(
      'linked', v_linked_count,
      'skipped', v_skipped_count,
      'failed', v_failed_count,
      'selected_item_ids', to_jsonb(p_import_item_ids)
    )
  );

  return public.get_import_batch_report(p_import_batch_id)
    || jsonb_build_object(
      'occurrence_link_result', jsonb_build_object(
        'linked', v_linked_count,
        'skipped', v_skipped_count,
        'failed', v_failed_count,
        'items', v_results
      )
    );
end;
$$;

-- Internal accounting helper is not a browser API.
revoke all on function public.refresh_import_batch_action_totals(uuid) from public, anon, authenticated;

-- Admin-facing RPCs are authenticated but retain database-owned is_admin() checks.
revoke all on function public.import_valid_batch_items_to_drafts(uuid, uuid[]) from public, anon, authenticated;
revoke all on function public.link_import_batch_occurrences(uuid, uuid[]) from public, anon, authenticated;
revoke all on function public.get_import_batch_report(uuid) from public, anon, authenticated;

grant execute on function public.import_valid_batch_items_to_drafts(uuid, uuid[]) to authenticated;
grant execute on function public.link_import_batch_occurrences(uuid, uuid[]) to authenticated;
grant execute on function public.get_import_batch_report(uuid) to authenticated;

comment on function public.import_valid_batch_items_to_drafts(uuid, uuid[]) is
  'Phase 3C admin-only idempotent import. Revalidates selected VALID records and creates draft_questions only.';

comment on function public.link_import_batch_occurrences(uuid, uuid[]) is
  'Phase 3C admin-only explicit link of exact duplicate PYQ occurrences to existing master questions.';

comment on column public.import_batches.draft_import_status is
  'Controlled draft-import progress. Does not replace the persistent dry-run status.';

comment on column public.import_batch_items.resolution_action is
  'Authoritative Phase 3C action taken for this reconciled import item.';

commit;
