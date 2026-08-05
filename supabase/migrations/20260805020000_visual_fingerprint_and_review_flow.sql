-- ScoreMore visual fingerprint and fast human-review patch
-- Date: 2026-08-05
-- Scope:
-- 1. Stop false duplicates for diagram/image questions by including visual identity.
-- 2. Recheck old blocked import items with the new fingerprint version.
-- 3. Treat true exact duplicates as reuse/link actions instead of draft-import errors.
-- 4. Auto-link deferred PYQ occurrences after the reused canonical draft is published.

begin;

alter table public.questions
  add column if not exists fingerprint_version smallint not null default 2;

alter table public.draft_questions
  add column if not exists fingerprint_version smallint not null default 2;

alter table public.import_batch_items
  add column if not exists fingerprint_version smallint not null default 1;

alter table public.import_batch_items
  alter column fingerprint_version set default 2;

alter table public.questions
  drop constraint if exists questions_fingerprint_version_check;
alter table public.questions
  add constraint questions_fingerprint_version_check
  check (fingerprint_version in (1, 2));

alter table public.draft_questions
  drop constraint if exists draft_questions_fingerprint_version_check;
alter table public.draft_questions
  add constraint draft_questions_fingerprint_version_check
  check (fingerprint_version in (1, 2));

alter table public.import_batch_items
  drop constraint if exists import_batch_items_fingerprint_version_check;
alter table public.import_batch_items
  add constraint import_batch_items_fingerprint_version_check
  check (fingerprint_version in (1, 2));

-- Version 2 adds a digest of image_refs plus content/group identity. This prevents
-- generic diagram wording and placeholder option labels from collapsing unrelated
-- visual questions into one content fingerprint.
create or replace function public.build_question_fingerprints_v2(
  p_language text,
  p_question_text text,
  p_options jsonb,
  p_image_refs jsonb default '[]'::jsonb,
  p_content_id text default null,
  p_group_text text default null
)
returns jsonb
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  v_strict_payload text;
  v_loose_payload text;
  v_loose_options text[];
  v_visual_digest text;
begin
  v_visual_digest := encode(
    extensions.digest(
      convert_to(coalesce(p_image_refs, '[]'::jsonb)::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_strict_payload := concat_ws(
    E'\u001f',
    public.normalize_import_text(p_language, false),
    public.normalize_import_text(p_question_text, false),
    public.normalize_import_text(p_options ->> 'A', false),
    public.normalize_import_text(p_options ->> 'B', false),
    public.normalize_import_text(p_options ->> 'C', false),
    public.normalize_import_text(p_options ->> 'D', false),
    public.normalize_import_text(p_content_id, false),
    public.normalize_import_text(p_group_text, false),
    v_visual_digest
  );

  select array_agg(option_value order by option_value)
  into v_loose_options
  from (
    values
      (public.normalize_import_text(p_options ->> 'A', true)),
      (public.normalize_import_text(p_options ->> 'B', true)),
      (public.normalize_import_text(p_options ->> 'C', true)),
      (public.normalize_import_text(p_options ->> 'D', true))
  ) as normalized_options(option_value);

  v_loose_payload := concat_ws(
    E'\u001f',
    public.normalize_import_text(p_language, true),
    public.normalize_import_text(p_question_text, true),
    array_to_string(coalesce(v_loose_options, array[]::text[]), E'\u001e'),
    public.normalize_import_text(p_content_id, true),
    public.normalize_import_text(p_group_text, true),
    v_visual_digest
  );

  return jsonb_build_object(
    'version', 2,
    'strict', encode(extensions.digest(convert_to(v_strict_payload, 'UTF8'), 'sha256'), 'hex'),
    'loose', encode(extensions.digest(convert_to(v_loose_payload, 'UTF8'), 'sha256'), 'hex'),
    'visual_digest', v_visual_digest
  );
end;
$$;

create or replace function public.set_question_fingerprints()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_fingerprints jsonb;
begin
  v_fingerprints := public.build_question_fingerprints_v2(
    new.language,
    new.question_text,
    new.options,
    new.image_refs,
    new.content_id,
    new.group_text
  );

  new.content_fingerprint := v_fingerprints ->> 'strict';
  new.loose_fingerprint := v_fingerprints ->> 'loose';
  new.fingerprint_version := 2;
  return new;
end;
$$;

drop trigger if exists questions_set_fingerprints on public.questions;
create trigger questions_set_fingerprints
before insert or update of language, question_text, options, image_refs, content_id, group_text
on public.questions
for each row execute function public.set_question_fingerprints();

drop trigger if exists draft_questions_set_fingerprints on public.draft_questions;
create trigger draft_questions_set_fingerprints
before insert or update of language, question_text, options, image_refs, content_id, group_text
on public.draft_questions
for each row execute function public.set_question_fingerprints();

-- Rebuild unique indexes after the authoritative visual-aware backfill.
drop index if exists public.questions_content_fingerprint_uidx;
drop index if exists public.draft_questions_active_content_fingerprint_uidx;

update public.questions set question_text = question_text;
update public.draft_questions set question_text = question_text;

create unique index questions_content_fingerprint_uidx
  on public.questions (content_fingerprint);

create unique index draft_questions_active_content_fingerprint_uidx
  on public.draft_questions (content_fingerprint)
  where review_status <> 'REJECTED';

-- Existing successful import items inherit the recalculated draft/master identity.
update public.import_batch_items i
set strict_fingerprint = d.content_fingerprint,
    loose_fingerprint = d.loose_fingerprint,
    fingerprint_version = 2,
    matched_draft_id = coalesce(i.matched_draft_id, d.draft_id),
    created_draft_id = coalesce(i.created_draft_id, d.draft_id)
from public.draft_questions d
where d.import_item_id = i.import_item_id;

update public.import_batch_items i
set strict_fingerprint = q.content_fingerprint,
    loose_fingerprint = q.loose_fingerprint,
    fingerprint_version = 2,
    matched_question_id = coalesce(i.matched_question_id, q.question_id)
from public.questions q
where q.import_item_id = i.import_item_id;

-- Wrap the current validator and recompute every duplicate decision with Version 2.
alter function public.validate_import_question(jsonb)
  rename to validate_import_question_before_visual_fingerprint_v2;

create or replace function public.validate_import_question(p_question jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_fingerprints jsonb;
  v_status text := 'VALID';
  v_question_id text := upper(nullif(btrim(p_question ->> 'proposed_question_id'), ''));
  v_correct_answer text := upper(nullif(btrim(p_question ->> 'correct_answer'), ''));
  v_strict text;
  v_loose text;
  v_occurrence_key text;
  v_duplicate_kind text := 'NONE';
  v_matched_question_id text;
  v_matched_draft_id uuid;
  v_existing_answer text;
  v_id_conflict boolean := false;
  v_source_conflict boolean := false;
  v_answer_conflict boolean := false;
  v_exact_duplicate boolean := false;
  v_possible_duplicate boolean := false;
  v_possible_question_ids text[] := array[]::text[];
  v_possible_draft_ids uuid[] := array[]::uuid[];
  v_occurrence_question_id text;
  v_occurrence_fingerprint text;
  v_occurrence_answer text;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  v_base := public.validate_import_question_before_visual_fingerprint_v2(p_question);

  select coalesce(jsonb_agg(entry), '[]'::jsonb)
  into v_errors
  from jsonb_array_elements(coalesce(v_base -> 'errors', '[]'::jsonb)) as error_rows(entry)
  where coalesce(entry ->> 'code', '') not in (
    'QUESTION_ID_CONFLICT',
    'SOURCE_OCCURRENCE_CONFLICT',
    'ANSWER_CONFLICT'
  );

  v_warnings := coalesce(v_base -> 'warnings', '[]'::jsonb);
  v_occurrence_key := nullif(v_base ->> 'occurrence_key', '');

  if nullif(btrim(p_question ->> 'question_text'), '') is not null
     and jsonb_typeof(p_question -> 'options') = 'object' then
    v_fingerprints := public.build_question_fingerprints_v2(
      p_question ->> 'language',
      p_question ->> 'question_text',
      p_question -> 'options',
      coalesce(p_question -> 'image_refs', '[]'::jsonb),
      p_question ->> 'content_id',
      p_question ->> 'group_text'
    );
    v_strict := v_fingerprints ->> 'strict';
    v_loose := v_fingerprints ->> 'loose';
  else
    v_fingerprints := jsonb_build_object('version', 2, 'strict', null, 'loose', null);
  end if;

  -- Question ID identity.
  if v_question_id is not null and v_strict is not null then
    select q.question_id, q.correct_answer
    into v_matched_question_id, v_existing_answer
    from public.questions q
    where q.question_id = v_question_id
    limit 1;

    if v_matched_question_id is not null then
      if exists (
        select 1 from public.questions q
        where q.question_id = v_matched_question_id
          and q.content_fingerprint = v_strict
      ) then
        v_exact_duplicate := true;
        v_duplicate_kind := 'EXACT_ID';
        if v_correct_answer is not null and v_existing_answer is not null
           and v_correct_answer <> v_existing_answer then
          v_answer_conflict := true;
        end if;
      else
        v_id_conflict := true;
        v_duplicate_kind := 'ID_CONFLICT';
      end if;
    else
      select d.draft_id, d.correct_answer
      into v_matched_draft_id, v_existing_answer
      from public.draft_questions d
      where d.proposed_question_id = v_question_id
        and d.review_status <> 'REJECTED'
      order by d.created_at
      limit 1;

      if v_matched_draft_id is not null then
        if exists (
          select 1 from public.draft_questions d
          where d.draft_id = v_matched_draft_id
            and d.content_fingerprint = v_strict
        ) then
          v_exact_duplicate := true;
          v_duplicate_kind := 'EXACT_ID';
          if v_correct_answer is not null and v_existing_answer is not null
             and v_correct_answer <> v_existing_answer then
            v_answer_conflict := true;
          end if;
        else
          v_id_conflict := true;
          v_duplicate_kind := 'ID_CONFLICT';
        end if;
      end if;
    end if;
  end if;

  -- Content identity.
  if not v_id_conflict and not v_exact_duplicate and v_strict is not null then
    select q.question_id, q.correct_answer
    into v_matched_question_id, v_existing_answer
    from public.questions q
    where q.content_fingerprint = v_strict
    limit 1;

    if v_matched_question_id is not null then
      v_exact_duplicate := true;
      v_duplicate_kind := 'EXACT_CONTENT';
      if v_correct_answer is not null and v_existing_answer is not null
         and v_correct_answer <> v_existing_answer then
        v_answer_conflict := true;
      end if;
    else
      select d.draft_id, d.correct_answer
      into v_matched_draft_id, v_existing_answer
      from public.draft_questions d
      where d.content_fingerprint = v_strict
        and d.review_status <> 'REJECTED'
      order by d.created_at
      limit 1;

      if v_matched_draft_id is not null then
        v_exact_duplicate := true;
        v_duplicate_kind := 'EXACT_CONTENT';
        if v_correct_answer is not null and v_existing_answer is not null
           and v_correct_answer <> v_existing_answer then
          v_answer_conflict := true;
        end if;
      end if;
    end if;
  end if;

  -- Same source occurrence must never point to different visual/text content.
  if v_occurrence_key is not null and not v_id_conflict then
    select qo.question_id, q.content_fingerprint, q.correct_answer
    into v_occurrence_question_id, v_occurrence_fingerprint, v_occurrence_answer
    from public.question_occurrences qo
    join public.questions q on q.question_id = qo.question_id
    where qo.occurrence_key = v_occurrence_key
    limit 1;

    if found then
      v_matched_question_id := v_occurrence_question_id;
      if v_strict = v_occurrence_fingerprint then
        v_exact_duplicate := true;
        v_duplicate_kind := 'SOURCE_OCCURRENCE';
        if v_correct_answer is not null and v_occurrence_answer is not null
           and v_correct_answer <> v_occurrence_answer then
          v_answer_conflict := true;
        end if;
      else
        v_source_conflict := true;
        v_duplicate_kind := 'SOURCE_CONFLICT';
      end if;
    end if;
  end if;

  -- Warning-only possible duplicate. Visual digest is part of Version 2, so
  -- unrelated diagram questions no longer collide merely because labels are generic.
  if not v_id_conflict and not v_source_conflict and not v_exact_duplicate
     and v_loose is not null then
    select coalesce(array_agg(q.question_id order by q.question_id), array[]::text[])
    into v_possible_question_ids
    from public.questions q
    where q.loose_fingerprint = v_loose
      and q.content_fingerprint is distinct from v_strict;

    select coalesce(array_agg(d.draft_id order by d.created_at), array[]::uuid[])
    into v_possible_draft_ids
    from public.draft_questions d
    where d.loose_fingerprint = v_loose
      and d.content_fingerprint is distinct from v_strict
      and d.review_status <> 'REJECTED';

    v_possible_duplicate := cardinality(v_possible_question_ids) > 0
      or cardinality(v_possible_draft_ids) > 0;
    if v_possible_duplicate then v_duplicate_kind := 'POSSIBLE_CONTENT'; end if;
  end if;

  if v_id_conflict then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'QUESTION_ID_CONFLICT',
      'message', 'The proposed Question ID already exists with different content.'
    ));
    v_status := 'ID_CONFLICT';
  elsif v_source_conflict then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'SOURCE_OCCURRENCE_CONFLICT',
      'message', 'The same source occurrence is already linked to different question content.'
    ));
    v_status := 'SOURCE_CONFLICT';
  elsif v_answer_conflict then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'ANSWER_CONFLICT',
      'message', 'Matching question content exists with a different proposed correct answer.'
    ));
    v_status := 'ANSWER_CONFLICT';
  elsif jsonb_array_length(v_errors) > 0 then
    v_status := 'INVALID';
  elsif v_exact_duplicate then
    v_status := 'EXACT_DUPLICATE';
  elsif v_possible_duplicate then
    v_status := 'POSSIBLE_DUPLICATE';
  elsif jsonb_array_length(v_warnings) > 0 then
    v_status := 'VALID_WITH_WARNINGS';
  else
    v_status := 'VALID';
  end if;

  return jsonb_build_object(
    'status', v_status,
    'errors', v_errors,
    'warnings', v_warnings,
    'fingerprints', v_fingerprints,
    'occurrence_key', v_occurrence_key,
    'duplicate', jsonb_build_object(
      'kind', v_duplicate_kind,
      'matched_question_id', v_matched_question_id,
      'matched_draft_id', v_matched_draft_id,
      'possible_question_ids', to_jsonb(v_possible_question_ids),
      'possible_draft_ids', to_jsonb(v_possible_draft_ids)
    )
  );
end;
$$;

-- General Version-2 recheck. Existing old items that were falsely blocked can be
-- repaired without deleting their batch or re-uploading the HTML file.
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

  if not exists (
    select 1 from public.import_batches where import_batch_id = p_import_batch_id
  ) then
    raise exception 'Import batch not found.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_import_batch_id::text));

  for v_item in
    select *
    from public.import_batch_items i
    where i.import_batch_id = p_import_batch_id
      and i.created_draft_id is null
      and not exists (
        select 1 from public.draft_questions d where d.import_item_id = i.import_item_id
      )
      and (
        i.fingerprint_version < 2
        or i.errors @> '[{"code":"DRAFT_INSERT_FAILED"}]'::jsonb
        or (i.matched_draft_id is not null and not exists (
          select 1 from public.draft_questions stale where stale.draft_id = i.matched_draft_id
        ))
      )
    order by i.item_index
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
        fingerprint_version = 2,
        occurrence_key = nullif(v_validation ->> 'occurrence_key', ''),
        resolution_action = case
          when v_status in ('VALID','VALID_WITH_WARNINGS','EXACT_DUPLICATE') then 'NONE'
          else 'BLOCKED'
        end,
        resolution_notes = case
          when v_status in ('VALID','VALID_WITH_WARNINGS')
            then 'Revalidated with visual-aware fingerprint Version 2.'
          when v_status = 'EXACT_DUPLICATE'
            then 'True exact duplicate confirmed with visual-aware fingerprint Version 2.'
          else 'Version-2 revalidation kept a genuine blocking status.'
        end,
        resolved_by = v_admin,
        resolved_at = now()
    where import_item_id = v_item.import_item_id;

    if v_status in ('VALID','VALID_WITH_WARNINGS','EXACT_DUPLICATE') then
      v_repaired := v_repaired + 1;
    end if;
  end loop;

  select count(*)
  into v_remaining
  from public.import_batch_items i
  where i.import_batch_id = p_import_batch_id
    and i.created_draft_id is null
    and (
      i.fingerprint_version < 2
      or i.errors @> '[{"code":"DRAFT_INSERT_FAILED"}]'::jsonb
      or (i.matched_draft_id is not null and not exists (
        select 1 from public.draft_questions stale where stale.draft_id = i.matched_draft_id
      ))
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

-- Preserve the small resumable draft creator and extend it so exact duplicates are
-- resolved in the same primary action instead of appearing as import errors.
alter function public.import_next_valid_batch_chunk(uuid, integer)
  rename to import_next_valid_batch_chunk_before_visual_v2;

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
  v_base jsonb;
  v_item public.import_batch_items%rowtype;
  v_link jsonb;
  v_budget integer := least(greatest(coalesce(p_limit, 10), 1), 25);
  v_processed integer := 0;
  v_imported integer := 0;
  v_linked integer := 0;
  v_skipped integer := 0;
  v_failed integer := 0;
  v_remaining integer := 0;
  v_draft_ids jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  select * into v_batch
  from public.import_batches
  where import_batch_id = p_import_batch_id;
  if not found then raise exception 'Import batch not found.' using errcode = 'P0001'; end if;

  v_base := public.import_next_valid_batch_chunk_before_visual_v2(
    p_import_batch_id,
    v_budget
  );

  v_processed := coalesce((v_base ->> 'processed')::integer, 0);
  v_imported := coalesce((v_base ->> 'imported')::integer, 0);
  v_skipped := coalesce((v_base ->> 'skipped')::integer, 0);
  v_failed := coalesce((v_base ->> 'failed')::integer, 0);
  v_draft_ids := coalesce(v_base -> 'draft_ids', '[]'::jsonb);

  v_budget := greatest(v_budget - v_processed, 0);

  if v_budget > 0 then
    for v_item in
      select *
      from public.import_batch_items i
      where i.import_batch_id = p_import_batch_id
        and i.validation_status = 'EXACT_DUPLICATE'
        and i.resolution_action in ('NONE','BLOCKED')
      order by i.item_index
      limit v_budget
      for update
    loop
      v_processed := v_processed + 1;

      begin
        if v_item.matched_question_id is not null
           and v_item.occurrence_key is not null
           and upper(coalesce(v_item.normalized_payload ->> 'question_type', '')) = 'PYQ' then
          v_link := public.link_question_occurrence(
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
          set validation_status = 'LINKED_TO_EXISTING',
              resolution_action = 'LINK_OCCURRENCE',
              resolution_notes = 'Exact duplicate reused the published master question and linked this paper occurrence.',
              resolved_by = v_admin,
              resolved_at = now()
          where import_item_id = v_item.import_item_id;
          v_linked := v_linked + 1;

        elsif v_item.matched_draft_id is not null then
          update public.import_batch_items
          set resolution_action = 'SKIP_DUPLICATE',
              resolution_notes = 'Exact duplicate reuses an existing draft. Its PYQ occurrence will auto-link when that canonical draft is published.',
              resolved_by = v_admin,
              resolved_at = now()
          where import_item_id = v_item.import_item_id;
          v_skipped := v_skipped + 1;

        else
          update public.import_batch_items
          set resolution_action = 'SKIP_DUPLICATE',
              resolution_notes = 'Exact duplicate requires no additional draft.',
              resolved_by = v_admin,
              resolved_at = now()
          where import_item_id = v_item.import_item_id;
          v_skipped := v_skipped + 1;
        end if;
      exception when others then
        update public.import_batch_items
        set resolution_action = 'BLOCKED',
            resolution_notes = 'Exact duplicate reuse/linking failed and needs review.',
            resolved_by = v_admin,
            resolved_at = now()
        where import_item_id = v_item.import_item_id;
        v_failed := v_failed + 1;
      end;
    end loop;
  end if;

  select count(*)
  into v_remaining
  from public.import_batch_items i
  where i.import_batch_id = p_import_batch_id
    and (
      i.validation_status in ('VALID','VALID_WITH_WARNINGS')
      or (
        i.validation_status = 'EXACT_DUPLICATE'
        and i.resolution_action in ('NONE','BLOCKED')
      )
    );

  perform public.refresh_import_batch_action_totals(p_import_batch_id);

  return jsonb_build_object(
    'import_batch_id', p_import_batch_id,
    'processed', v_processed,
    'imported', v_imported,
    'linked', v_linked,
    'skipped', v_skipped,
    'failed', v_failed,
    'remaining', v_remaining,
    'draft_ids', v_draft_ids
  );
end;
$$;

-- When a canonical draft is published, automatically link any true duplicate PYQ
-- items that previously reused that draft while it was still unpublished.
create or replace function public.materialize_deferred_duplicate_occurrences()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft_id uuid;
  v_item public.import_batch_items%rowtype;
  v_batch_source_file_id uuid;
  v_link jsonb;
begin
  select d.draft_id
  into v_draft_id
  from public.draft_questions d
  where d.import_item_id = new.import_item_id
     or d.proposed_question_id = new.question_id
  order by case when d.import_item_id = new.import_item_id then 0 else 1 end, d.created_at
  limit 1;

  if v_draft_id is null then return new; end if;

  for v_item in
    select *
    from public.import_batch_items i
    where i.matched_draft_id = v_draft_id
      and i.validation_status = 'EXACT_DUPLICATE'
      and i.resolution_action = 'SKIP_DUPLICATE'
      and i.occurrence_key is not null
    order by i.item_index
    for update
  loop
    begin
      select ib.source_file_id
      into v_batch_source_file_id
      from public.import_batches ib
      where ib.import_batch_id = v_item.import_batch_id;

      v_link := public.link_question_occurrence(
        new.question_id,
        v_item.normalized_payload || jsonb_build_object(
          'source_record_id', v_item.source_record_id,
          'external_question_id', v_item.proposed_question_id,
          'strict_fingerprint', new.content_fingerprint
        ),
        v_item.import_batch_id,
        v_batch_source_file_id,
        v_item.import_item_id
      );

      update public.import_batch_items
      set validation_status = 'LINKED_TO_EXISTING',
          matched_question_id = new.question_id,
          resolution_action = 'LINK_OCCURRENCE',
          resolution_notes = 'Deferred duplicate occurrence linked automatically when the canonical draft was published.',
          resolved_by = v_admin,
          resolved_at = now()
      where import_item_id = v_item.import_item_id;

      perform public.refresh_import_batch_action_totals(v_item.import_batch_id);
    exception when others then
      update public.import_batch_items
      set resolution_action = 'BLOCKED',
          resolution_notes = 'Canonical question published, but the deferred occurrence could not be linked.',
          resolved_by = v_admin,
          resolved_at = now()
      where import_item_id = v_item.import_item_id;

      perform public.refresh_import_batch_action_totals(v_item.import_batch_id);
    end;
  end loop;

  return new;
end;
$$;

drop trigger if exists questions_materialize_deferred_duplicates on public.questions;
create trigger questions_materialize_deferred_duplicates
after insert on public.questions
for each row execute function public.materialize_deferred_duplicate_occurrences();

-- Lightweight report now exposes fingerprint version and considers old Version-1
-- unresolved items repairable.
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

  if v_batch is null then raise exception 'Import batch not found.' using errcode = 'P0001'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'import_item_id', i.import_item_id,
    'item_index', i.item_index,
    'source_record_id', i.source_record_id,
    'proposed_question_id', i.proposed_question_id,
    'normalized_payload', (i.normalized_payload - 'image_refs' - 'group_text'),
    'strict_fingerprint', i.strict_fingerprint,
    'loose_fingerprint', i.loose_fingerprint,
    'fingerprint_version', i.fingerprint_version,
    'occurrence_key', i.occurrence_key,
    'validation_status', i.validation_status,
    'errors', i.errors,
    'warnings', i.warnings,
    'duplicate_kind', i.duplicate_kind,
    'matched_question_id', i.matched_question_id,
    'matched_draft_id', i.matched_draft_id,
    'created_draft_id', i.created_draft_id,
    'resolution_action', i.resolution_action,
    'resolution_notes', i.resolution_notes,
    'resolved_by', i.resolved_by,
    'resolved_at', i.resolved_at,
    'created_at', i.created_at,
    'updated_at', i.updated_at
  ) order by i.item_index), '[]'::jsonb)
  into v_items
  from public.import_batch_items i
  where i.import_batch_id = p_import_batch_id;

  return jsonb_build_object(
    'batch', v_batch,
    'summary', jsonb_build_object(
      'total', coalesce((v_batch ->> 'total_raw')::integer, 0),
      'valid', coalesce((v_batch ->> 'total_valid')::integer, 0),
      'warnings', coalesce((v_batch ->> 'total_warning')::integer, 0),
      'errors', coalesce((v_batch ->> 'total_error')::integer, 0),
      'duplicates', coalesce((v_batch ->> 'total_duplicate')::integer, 0),
      'ready_for_draft', (select count(*) from public.import_batch_items i where i.import_batch_id = p_import_batch_id and i.validation_status in ('VALID','VALID_WITH_WARNINGS')),
      'imported_to_draft', (select count(*) from public.import_batch_items i where i.import_batch_id = p_import_batch_id and i.validation_status = 'IMPORTED_TO_DRAFT'),
      'linked_to_existing', (select count(*) from public.import_batch_items i where i.import_batch_id = p_import_batch_id and i.validation_status = 'LINKED_TO_EXISTING'),
      'skipped_duplicates', (select count(*) from public.import_batch_items i where i.import_batch_id = p_import_batch_id and i.resolution_action = 'SKIP_DUPLICATE'),
      'actionable_occurrences', (select count(*) from public.import_batch_items i where i.import_batch_id = p_import_batch_id and i.validation_status = 'EXACT_DUPLICATE' and i.matched_question_id is not null and i.occurrence_key is not null and i.resolution_action = 'NONE'),
      'reusable_duplicates', (select count(*) from public.import_batch_items i where i.import_batch_id = p_import_batch_id and i.validation_status = 'EXACT_DUPLICATE' and i.resolution_action in ('NONE','BLOCKED')),
      'repairable_items', (
        select count(*) from public.import_batch_items i
        where i.import_batch_id = p_import_batch_id
          and i.created_draft_id is null
          and (
            i.fingerprint_version < 2
            or i.errors @> '[{"code":"DRAFT_INSERT_FAILED"}]'::jsonb
            or (i.matched_draft_id is not null and not exists (select 1 from public.draft_questions d where d.draft_id = i.matched_draft_id))
          )
      )
    ),
    'items', v_items,
    'report_mode', 'COMPACT_MOBILE_V2'
  );
end;
$$;

-- Refresh every batch whose successful items were backfilled. Unresolved Version-1
-- items remain PARTIAL until the main Import action rechecks them.
do $$
declare v_batch_id uuid;
begin
  for v_batch_id in select import_batch_id from public.import_batches loop
    perform public.refresh_import_batch_action_totals(v_batch_id);
  end loop;
end;
$$;

revoke all on function public.build_question_fingerprints_v2(text,text,jsonb,jsonb,text,text) from public, anon, authenticated;
revoke all on function public.set_question_fingerprints() from public, anon, authenticated;
revoke all on function public.materialize_deferred_duplicate_occurrences() from public, anon, authenticated;
revoke all on function public.validate_import_question_before_visual_fingerprint_v2(jsonb) from public, anon, authenticated;
revoke all on function public.import_next_valid_batch_chunk_before_visual_v2(uuid,integer) from public, anon, authenticated;
revoke all on function public.validate_import_question(jsonb) from public, anon;
revoke all on function public.repair_ai_proposed_import_chunk(uuid,integer) from public, anon;
revoke all on function public.import_next_valid_batch_chunk(uuid,integer) from public, anon;
revoke all on function public.get_import_batch_report(uuid) from public, anon;

grant execute on function public.validate_import_question(jsonb) to authenticated;
grant execute on function public.repair_ai_proposed_import_chunk(uuid,integer) to authenticated;
grant execute on function public.import_next_valid_batch_chunk(uuid,integer) to authenticated;
grant execute on function public.get_import_batch_report(uuid) to authenticated;

comment on function public.build_question_fingerprints_v2(text,text,jsonb,jsonb,text,text) is
  'Visual-aware Version-2 SHA-256 fingerprint over language, question, ordered options, content/group identity and image_refs digest.';

comment on column public.questions.fingerprint_version is 'Question fingerprint algorithm version. Version 2 includes visual identity.';
comment on column public.draft_questions.fingerprint_version is 'Draft fingerprint algorithm version. Version 2 includes visual identity.';
comment on column public.import_batch_items.fingerprint_version is 'Reconciliation fingerprint algorithm version used for the import item.';

commit;
