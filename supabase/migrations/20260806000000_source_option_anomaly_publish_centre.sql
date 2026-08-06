-- ScoreMore: genuine printed-option anomaly recovery + separate publish centre
-- Date: 2026-08-06
-- Scope:
-- 1. Preserve a genuine PYQ when the printed source itself contains duplicate options.
-- 2. Repair Shift 1 V2 Q55 in place without re-uploading or deleting the batch.
-- 3. Add an admin-only, compact publish queue and safe batch publication RPC.
-- No unreviewed question is published automatically.

begin;

-- ---------------------------------------------------------------------------
-- Source option anomaly metadata
-- ---------------------------------------------------------------------------

alter table public.import_batch_items
  add column if not exists source_option_anomaly text not null default 'NONE',
  add column if not exists source_option_anomaly_note text;

alter table public.draft_questions
  add column if not exists source_option_anomaly text not null default 'NONE',
  add column if not exists source_option_anomaly_note text;

alter table public.questions
  add column if not exists source_option_anomaly text not null default 'NONE',
  add column if not exists source_option_anomaly_note text;

alter table public.import_batch_items
  drop constraint if exists import_batch_items_source_option_anomaly_check;
alter table public.import_batch_items
  add constraint import_batch_items_source_option_anomaly_check
  check (source_option_anomaly in ('NONE', 'DUPLICATE_OPTIONS_PRINTED'));

alter table public.draft_questions
  drop constraint if exists draft_questions_source_option_anomaly_check;
alter table public.draft_questions
  add constraint draft_questions_source_option_anomaly_check
  check (source_option_anomaly in ('NONE', 'DUPLICATE_OPTIONS_PRINTED'));

alter table public.questions
  drop constraint if exists questions_source_option_anomaly_check;
alter table public.questions
  add constraint questions_source_option_anomaly_check
  check (source_option_anomaly in ('NONE', 'DUPLICATE_OPTIONS_PRINTED'));

-- Imported drafts inherit the administrator-confirmed source anomaly from the
-- reconciled import item. Raw payload remains immutable; normalized payload records
-- the controlled interpretation.
create or replace function public.set_draft_source_option_anomaly()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_anomaly text;
  v_note text;
begin
  if new.import_item_id is not null then
    select
      coalesce(nullif(upper(btrim(i.normalized_payload ->> 'source_option_anomaly')), ''), i.source_option_anomaly, 'NONE'),
      coalesce(nullif(btrim(i.normalized_payload ->> 'source_option_anomaly_note'), ''), i.source_option_anomaly_note)
    into v_anomaly, v_note
    from public.import_batch_items i
    where i.import_item_id = new.import_item_id;

    if found then
      new.source_option_anomaly := coalesce(v_anomaly, 'NONE');
      new.source_option_anomaly_note := v_note;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists draft_questions_source_option_anomaly on public.draft_questions;
create trigger draft_questions_source_option_anomaly
before insert or update of import_item_id on public.draft_questions
for each row execute function public.set_draft_source_option_anomaly();

-- Published master questions inherit the reviewed anomaly and cannot silently
-- carry it without a traceability note.
create or replace function public.set_question_source_option_anomaly()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_anomaly text := 'NONE';
  v_note text;
begin
  if new.import_item_id is not null then
    select d.source_option_anomaly, d.source_option_anomaly_note
    into v_anomaly, v_note
    from public.draft_questions d
    where d.import_item_id = new.import_item_id
    order by d.updated_at desc
    limit 1;
  end if;

  new.source_option_anomaly := coalesce(v_anomaly, 'NONE');
  new.source_option_anomaly_note := v_note;

  if new.source_option_anomaly = 'DUPLICATE_OPTIONS_PRINTED'
     and nullif(btrim(new.source_option_anomaly_note), '') is null then
    raise exception 'A source traceability note is required for printed duplicate options.' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists questions_source_option_anomaly on public.questions;
create trigger questions_source_option_anomaly
before insert on public.questions
for each row execute function public.set_question_source_option_anomaly();

-- ---------------------------------------------------------------------------
-- Validator wrapper: duplicate options remain blocking by default. They become a
-- warning only when an administrator explicitly records that the genuine PYQ source
-- itself printed the duplicate values.
-- ---------------------------------------------------------------------------

alter function public.validate_import_question(jsonb)
  rename to validate_import_question_before_source_option_anomaly;

create or replace function public.validate_import_question(p_question jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb := public.validate_import_question_before_source_option_anomaly(p_question);
  v_errors jsonb := coalesce(v_result -> 'errors', '[]'::jsonb);
  v_warnings jsonb := coalesce(v_result -> 'warnings', '[]'::jsonb);
  v_status text := coalesce(v_result ->> 'status', 'INVALID');
  v_kind text := coalesce(v_result #>> '{duplicate,kind}', 'NONE');
  v_anomaly text := upper(coalesce(nullif(btrim(p_question ->> 'source_option_anomaly'), ''), 'NONE'));
  v_note text := nullif(btrim(p_question ->> 'source_option_anomaly_note'), '');
  v_question_type text := upper(nullif(btrim(p_question ->> 'question_type'), ''));
  v_options jsonb := p_question -> 'options';
  v_distinct_options integer := 0;
  v_removed integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if v_anomaly not in ('NONE', 'DUPLICATE_OPTIONS_PRINTED') then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_SOURCE_OPTION_ANOMALY',
      'message', 'source_option_anomaly must be NONE or DUPLICATE_OPTIONS_PRINTED.'
    ));
  elsif v_anomaly = 'DUPLICATE_OPTIONS_PRINTED' then
    if v_question_type <> 'PYQ' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'OPTION_ANOMALY_REQUIRES_PYQ',
        'message', 'Printed duplicate-option confirmation is allowed only for a genuine PYQ source.'
      ));
    end if;

    if v_note is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'OPTION_ANOMALY_NOTE_REQUIRED',
        'message', 'A source traceability note is required for printed duplicate options.'
      ));
    end if;

    if public.try_parse_integer(p_question ->> 'source_page') is null
       or nullif(btrim(p_question ->> 'source_question_id'), '') is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'OPTION_ANOMALY_SOURCE_REQUIRED',
        'message', 'source_page and source_question_id are required before accepting a printed option anomaly.'
      ));
    end if;

    if jsonb_typeof(v_options) = 'object' then
      select count(distinct public.normalize_import_text(option_text, false))
      into v_distinct_options
      from (
        values
          (v_options ->> 'A'),
          (v_options ->> 'B'),
          (v_options ->> 'C'),
          (v_options ->> 'D')
      ) as option_values(option_text);
    end if;

    if v_distinct_options >= 4 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'OPTION_ANOMALY_NOT_PRESENT',
        'message', 'The package marks duplicate printed options, but all four normalized options are distinct.'
      ));
    else
      select count(*)
      into v_removed
      from jsonb_array_elements(v_errors) as error_rows(entry)
      where coalesce(entry ->> 'code', '') = 'DUPLICATE_OPTIONS';

      select coalesce(jsonb_agg(entry), '[]'::jsonb)
      into v_errors
      from jsonb_array_elements(v_errors) as error_rows(entry)
      where coalesce(entry ->> 'code', '') <> 'DUPLICATE_OPTIONS';

      if v_removed > 0 then
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code', 'SOURCE_DUPLICATE_OPTIONS_PRINTED',
          'message', 'The genuine PYQ source prints duplicate option values. Preserve them exactly and verify the answer during human review.'
        ));
      end if;
    end if;
  end if;

  if jsonb_array_length(v_errors) > 0 then
    v_status := case
      when v_status in ('ID_CONFLICT', 'ANSWER_CONFLICT', 'SOURCE_CONFLICT') then v_status
      else 'INVALID'
    end;
  elsif v_kind in ('EXACT_ID', 'EXACT_CONTENT', 'SOURCE_OCCURRENCE') then
    v_status := 'EXACT_DUPLICATE';
  elsif v_kind = 'POSSIBLE_CONTENT' then
    v_status := 'POSSIBLE_DUPLICATE';
  elsif jsonb_array_length(v_warnings) > 0 then
    v_status := 'VALID_WITH_WARNINGS';
  else
    v_status := 'VALID';
  end if;

  return jsonb_set(
    jsonb_set(
      jsonb_set(v_result, '{status}', to_jsonb(v_status), true),
      '{errors}', v_errors, true
    ),
    '{warnings}', v_warnings, true
  );
end;
$$;

-- Admin action for future genuine papers with a printed duplicate option.
create or replace function public.confirm_import_source_option_anomaly(
  p_import_item_id uuid,
  p_note text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_item public.import_batch_items%rowtype;
  v_payload jsonb;
  v_result jsonb;
  v_status public.import_item_status;
  v_other_errors integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if nullif(btrim(p_note), '') is null then
    raise exception 'Add a source traceability note before confirming duplicate printed options.' using errcode = 'P0001';
  end if;

  select * into v_item
  from public.import_batch_items
  where import_item_id = p_import_item_id
  for update;

  if not found then
    raise exception 'Import item not found.' using errcode = 'P0001';
  end if;

  if v_item.created_draft_id is not null
     or exists (select 1 from public.draft_questions d where d.import_item_id = p_import_item_id) then
    raise exception 'A draft already exists for this import item.' using errcode = 'P0001';
  end if;

  if upper(coalesce(v_item.normalized_payload ->> 'question_type', '')) <> 'PYQ' then
    raise exception 'Only a genuine PYQ may use the printed duplicate-option exception.' using errcode = 'P0001';
  end if;

  if not (v_item.errors @> '[{"code":"DUPLICATE_OPTIONS"}]'::jsonb) then
    raise exception 'This item is not blocked by DUPLICATE_OPTIONS.' using errcode = 'P0001';
  end if;

  select count(*) into v_other_errors
  from jsonb_array_elements(v_item.errors) as error_rows(entry)
  where coalesce(entry ->> 'code', '') <> 'DUPLICATE_OPTIONS';

  if v_other_errors > 0 then
    raise exception 'Resolve the other blocking validation errors before confirming this source anomaly.' using errcode = 'P0001';
  end if;

  v_payload := v_item.normalized_payload || jsonb_build_object(
    'source_option_anomaly', 'DUPLICATE_OPTIONS_PRINTED',
    'source_option_anomaly_note', btrim(p_note)
  );

  v_result := public.validate_import_question(v_payload);
  v_status := (v_result ->> 'status')::public.import_item_status;

  update public.import_batch_items
  set normalized_payload = v_payload,
      source_option_anomaly = 'DUPLICATE_OPTIONS_PRINTED',
      source_option_anomaly_note = btrim(p_note),
      validation_status = v_status,
      errors = coalesce(v_result -> 'errors', '[]'::jsonb),
      warnings = coalesce(v_result -> 'warnings', '[]'::jsonb),
      duplicate_kind = coalesce(nullif(v_result #>> '{duplicate,kind}', ''), 'NONE')::public.import_duplicate_kind,
      matched_question_id = nullif(v_result #>> '{duplicate,matched_question_id}', ''),
      matched_draft_id = nullif(v_result #>> '{duplicate,matched_draft_id}', '')::uuid,
      strict_fingerprint = nullif(v_result #>> '{fingerprints,strict}', ''),
      loose_fingerprint = nullif(v_result #>> '{fingerprints,loose}', ''),
      occurrence_key = nullif(v_result ->> 'occurrence_key', ''),
      resolution_action = case when v_status in ('VALID', 'VALID_WITH_WARNINGS') then 'NONE' else 'BLOCKED' end,
      resolution_notes = 'Administrator confirmed that duplicate option values are printed in the genuine PYQ source.',
      resolved_by = v_admin,
      resolved_at = now(),
      updated_at = now()
  where import_item_id = p_import_item_id;

  perform public.refresh_import_batch_action_totals(v_item.import_batch_id);

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (
    v_admin,
    'CONFIRM_SOURCE_OPTION_ANOMALY',
    'IMPORT_ITEM',
    p_import_item_id::text,
    jsonb_build_object(
      'import_batch_id', v_item.import_batch_id,
      'proposed_question_id', v_item.proposed_question_id,
      'source_option_anomaly', 'DUPLICATE_OPTIONS_PRINTED',
      'note', btrim(p_note),
      'new_status', v_status
    )
  );

  return jsonb_build_object(
    'import_item_id', p_import_item_id,
    'status', v_status,
    'source_option_anomaly', 'DUPLICATE_OPTIONS_PRINTED'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- One-time, narrowly-scoped repair for the recorded Shift 1 V2 source anomaly.
-- The uploaded source page prints option 640 twice (B and D) for Q55. Preserve the
-- paper exactly; do not invent or silently rewrite an option.
-- ---------------------------------------------------------------------------

do $$
declare
  v_item_id uuid;
  v_batch_id uuid;
  v_admin uuid;
  v_note text := 'Verified against GSSSB CCE 01-04-2024 Shift 1 source page 29: options B and D are both printed as 640.';
  v_errors jsonb;
  v_warnings jsonb;
begin
  select i.import_item_id, i.import_batch_id
  into v_item_id, v_batch_id
  from public.import_batch_items i
  join public.import_batches b on b.import_batch_id = i.import_batch_id
  where b.package_id = 'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2'
    and i.proposed_question_id = 'GSSSB-CCE-2024-QUANT-0401S1-0055'
    and i.created_draft_id is null
    and not exists (select 1 from public.draft_questions d where d.import_item_id = i.import_item_id)
    and i.errors @> '[{"code":"DUPLICATE_OPTIONS"}]'::jsonb
    and not exists (
      select 1
      from jsonb_array_elements(i.errors) as error_rows(entry)
      where coalesce(entry ->> 'code', '') <> 'DUPLICATE_OPTIONS'
    )
  limit 1
  for update of i;

  if v_item_id is not null then
    select coalesce(jsonb_agg(entry), '[]'::jsonb)
    into v_errors
    from jsonb_array_elements((select errors from public.import_batch_items where import_item_id = v_item_id)) as error_rows(entry)
    where coalesce(entry ->> 'code', '') <> 'DUPLICATE_OPTIONS';

    select coalesce(jsonb_agg(entry), '[]'::jsonb)
    into v_warnings
    from (
      select entry
      from jsonb_array_elements((select warnings from public.import_batch_items where import_item_id = v_item_id)) as warning_rows(entry)
      where coalesce(entry ->> 'code', '') <> 'SOURCE_DUPLICATE_OPTIONS_PRINTED'
      union all
      select jsonb_build_object(
        'code', 'SOURCE_DUPLICATE_OPTIONS_PRINTED',
        'message', 'The genuine PYQ source prints duplicate option values. Preserve them exactly and verify the answer during human review.'
      )
    ) merged(entry);

    select user_id into v_admin
    from public.profiles
    where role = 'ADMIN'
    order by created_at
    limit 1;

    update public.import_batch_items
    set normalized_payload = normalized_payload || jsonb_build_object(
          'source_option_anomaly', 'DUPLICATE_OPTIONS_PRINTED',
          'source_option_anomaly_note', v_note
        ),
        source_option_anomaly = 'DUPLICATE_OPTIONS_PRINTED',
        source_option_anomaly_note = v_note,
        fingerprint_version = greatest(coalesce(fingerprint_version, 1), 2),
        validation_status = 'VALID_WITH_WARNINGS',
        errors = v_errors,
        warnings = v_warnings,
        resolution_action = 'NONE',
        resolution_notes = 'Migration confirmed the printed Shift 1 V2 Q55 duplicate-option anomaly from the source PDF.',
        resolved_by = v_admin,
        resolved_at = now(),
        updated_at = now()
    where import_item_id = v_item_id;

    perform public.refresh_import_batch_action_totals(v_batch_id);

    if v_admin is not null then
      insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
      values (
        v_admin,
        'REPAIR_PRINTED_DUPLICATE_OPTIONS',
        'IMPORT_ITEM',
        v_item_id::text,
        jsonb_build_object(
          'package_id', 'GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2',
          'proposed_question_id', 'GSSSB-CCE-2024-QUANT-0401S1-0055',
          'note', v_note
        )
      );
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Separate, authoritative publish queue
-- ---------------------------------------------------------------------------

create or replace function public.list_publish_queue(
  p_limit integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  select count(*)
  into v_total
  from public.draft_questions d
  where d.review_status = 'IN_REVIEW'
    and d.question_status = 'DRAFT'
    and d.published_question_id is null
    and d.verification_status = 'VERIFIED'
    and d.correct_answer is not null
    and d.answer_source is not null
    and d.answer_source <> 'AI_PROPOSED'
    and nullif(btrim(d.explanation), '') is not null
    and coalesce(d.source_quality::text, 'CLEAR') <> 'UNREADABLE'
    and (
      d.source_option_anomaly <> 'DUPLICATE_OPTIONS_PRINTED'
      or nullif(btrim(d.source_option_anomaly_note), '') is not null
    )
    and (
      d.question_type <> 'PYQ'
      or (
        d.topic_id is not null
        and d.topic_resolution_status in ('MATCHED', 'ADMIN_CONFIRMED')
      )
    );

  select coalesce(jsonb_agg(row_data order by reviewed_at nulls last, created_at, draft_id), '[]'::jsonb)
  into v_items
  from (
    select jsonb_build_object(
      'draft_id', d.draft_id,
      'proposed_question_id', d.proposed_question_id,
      'question_type', d.question_type,
      'subject_id', d.subject_id,
      'topic_id', d.topic_id,
      'question_text', d.question_text,
      'correct_answer', d.correct_answer,
      'answer_source', d.answer_source,
      'verification_status', d.verification_status,
      'review_status', d.review_status,
      'source_quality', d.source_quality,
      'source_option_anomaly', d.source_option_anomaly,
      'source_option_anomaly_note', d.source_option_anomaly_note,
      'is_supplemental', d.is_supplemental,
      'reviewed_at', d.reviewed_at,
      'created_at', d.created_at
    ) as row_data,
    d.reviewed_at,
    d.created_at,
    d.draft_id
    from public.draft_questions d
    where d.review_status = 'IN_REVIEW'
      and d.question_status = 'DRAFT'
      and d.published_question_id is null
      and d.verification_status = 'VERIFIED'
      and d.correct_answer is not null
      and d.answer_source is not null
      and d.answer_source <> 'AI_PROPOSED'
      and nullif(btrim(d.explanation), '') is not null
      and coalesce(d.source_quality::text, 'CLEAR') <> 'UNREADABLE'
      and (
        d.source_option_anomaly <> 'DUPLICATE_OPTIONS_PRINTED'
        or nullif(btrim(d.source_option_anomaly_note), '') is not null
      )
      and (
        d.question_type <> 'PYQ'
        or (
          d.topic_id is not null
          and d.topic_resolution_status in ('MATCHED', 'ADMIN_CONFIRMED')
        )
      )
    order by d.reviewed_at nulls last, d.created_at, d.draft_id
    limit v_limit offset v_offset
  ) queue_rows;

  return jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'items', v_items
  );
end;
$$;

create or replace function public.publish_verified_drafts(p_draft_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_id uuid;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_published integer := 0;
  v_already integer := 0;
  v_failed integer := 0;
  v_input_count integer := coalesce(cardinality(p_draft_ids), 0);
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if v_input_count = 0 then
    raise exception 'Select at least one verified draft.' using errcode = 'P0001';
  end if;

  if v_input_count > 25 then
    raise exception 'Publish at most 25 verified drafts per request.' using errcode = 'P0001';
  end if;

  for v_id in
    select distinct selected_id
    from unnest(p_draft_ids) as selected(selected_id)
    where selected_id is not null
  loop
    begin
      v_result := public.publish_draft_question(v_id);
      if coalesce((v_result ->> 'already_published')::boolean, false) then
        v_already := v_already + 1;
        v_results := v_results || jsonb_build_array(jsonb_build_object(
          'draft_id', v_id,
          'status', 'ALREADY_PUBLISHED',
          'question_id', v_result ->> 'question_id'
        ));
      else
        v_published := v_published + 1;
        v_results := v_results || jsonb_build_array(jsonb_build_object(
          'draft_id', v_id,
          'status', 'PUBLISHED',
          'question_id', v_result ->> 'question_id'
        ));
      end if;
    exception
      when others then
        v_failed := v_failed + 1;
        v_results := v_results || jsonb_build_array(jsonb_build_object(
          'draft_id', v_id,
          'status', 'FAILED',
          'error', sqlerrm
        ));

        insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
        values (
          v_admin,
          'PUBLISH_DRAFT_FAILED',
          'DRAFT_QUESTION',
          v_id::text,
          jsonb_build_object('error', sqlerrm)
        );
    end;
  end loop;

  return jsonb_build_object(
    'requested', v_input_count,
    'published', v_published,
    'already_published', v_already,
    'failed', v_failed,
    'items', v_results
  );
end;
$$;

-- Privilege hardening.
revoke all on function public.validate_import_question_before_source_option_anomaly(jsonb) from public, anon, authenticated;
revoke all on function public.validate_import_question(jsonb) from public, anon;
revoke all on function public.confirm_import_source_option_anomaly(uuid, text) from public, anon;
revoke all on function public.list_publish_queue(integer, integer) from public, anon;
revoke all on function public.publish_verified_drafts(uuid[]) from public, anon;

grant execute on function public.validate_import_question(jsonb) to authenticated;
grant execute on function public.confirm_import_source_option_anomaly(uuid, text) to authenticated;
grant execute on function public.list_publish_queue(integer, integer) to authenticated;
grant execute on function public.publish_verified_drafts(uuid[]) to authenticated;

comment on column public.import_batch_items.source_option_anomaly is
  'Controlled source anomaly. DUPLICATE_OPTIONS_PRINTED means the genuine PYQ source itself contains repeated option values.';
comment on column public.draft_questions.source_option_anomaly is
  'Source anomaly preserved into human review; it never bypasses answer verification.';
comment on column public.questions.source_option_anomaly is
  'Published traceability for a reviewed source anomaly.';
comment on function public.confirm_import_source_option_anomaly(uuid, text) is
  'Admin-only confirmation that duplicate option values are genuinely printed in the source. Revalidates the item; creates no draft and publishes nothing.';
comment on function public.list_publish_queue(integer, integer) is
  'Admin-only compact list of human-verified drafts that satisfy all publication prerequisites.';
comment on function public.publish_verified_drafts(uuid[]) is
  'Admin-only safe publication of up to 25 already-verified drafts. Each item is isolated and returns an explicit result.';

commit;
