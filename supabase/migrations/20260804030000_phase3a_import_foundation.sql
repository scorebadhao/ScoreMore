-- ScoreMore Phase 3A: accurate HTML import foundation
-- Date: 2026-08-04
-- Scope: import identity, fingerprints, duplicate protection, source occurrences,
--        authoritative validation RPCs and publication traceability.
-- No frontend import UI is introduced by this migration.

begin;

create type public.content_origin as enum (
  'SOURCE_EXTRACTED',
  'OCR_EXTRACTED',
  'AI_TRANSCRIBED',
  'MANUAL_ENTRY',
  'RECONSTRUCTED',
  'AI_GENERATED'
);

create type public.import_item_status as enum (
  'PENDING',
  'VALID',
  'VALID_WITH_WARNINGS',
  'INVALID',
  'EXACT_DUPLICATE',
  'POSSIBLE_DUPLICATE',
  'ID_CONFLICT',
  'ANSWER_CONFLICT',
  'SOURCE_CONFLICT',
  'IMPORTED_TO_DRAFT',
  'LINKED_TO_EXISTING',
  'SKIPPED'
);

create type public.import_duplicate_kind as enum (
  'NONE',
  'EXACT_ID',
  'EXACT_CONTENT',
  'POSSIBLE_CONTENT',
  'SOURCE_OCCURRENCE',
  'ID_CONFLICT',
  'SOURCE_CONFLICT'
);

-- Internal parsing helpers. These return NULL instead of throwing on malformed input.
create or replace function public.try_parse_integer(p_value text)
returns integer
language plpgsql
immutable
set search_path = public
as $$
begin
  if nullif(btrim(p_value), '') is null then
    return null;
  end if;

  return btrim(p_value)::integer;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return null;
end;
$$;

create or replace function public.try_parse_date(p_value text)
returns date
language plpgsql
immutable
set search_path = public
as $$
begin
  if nullif(btrim(p_value), '') is null then
    return null;
  end if;

  return btrim(p_value)::date;
exception
  when invalid_datetime_format or datetime_field_overflow then
    return null;
end;
$$;

-- Fingerprint normalization preserves source content in storage; it is used only for comparison.
-- Strict mode keeps meaningful punctuation and symbols while normalizing Unicode and whitespace.
-- Loose mode removes whitespace/punctuation and is used only to raise a possible-duplicate warning.
create or replace function public.normalize_import_text(
  p_value text,
  p_loose boolean default false
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_loose then
      regexp_replace(
        lower(normalize(coalesce(p_value, ''), NFC)),
        '[[:space:][:punct:]]+',
        '',
        'g'
      )
    else
      btrim(
        regexp_replace(
          lower(
            normalize(
              replace(replace(coalesce(p_value, ''), E'\r\n', E'\n'), E'\r', E'\n'),
              NFC
            )
          ),
          '[[:space:]]+',
          ' ',
          'g'
        )
      )
  end;
$$;

create or replace function public.build_question_fingerprints(
  p_language text,
  p_question_text text,
  p_options jsonb
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
begin
  v_strict_payload := concat_ws(
    E'\u001f',
    public.normalize_import_text(p_language, false),
    public.normalize_import_text(p_question_text, false),
    public.normalize_import_text(p_options ->> 'A', false),
    public.normalize_import_text(p_options ->> 'B', false),
    public.normalize_import_text(p_options ->> 'C', false),
    public.normalize_import_text(p_options ->> 'D', false)
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
    array_to_string(coalesce(v_loose_options, array[]::text[]), E'\u001e')
  );

  return jsonb_build_object(
    'strict', encode(extensions.digest(convert_to(v_strict_payload, 'UTF8'), 'sha256'), 'hex'),
    'loose', encode(extensions.digest(convert_to(v_loose_payload, 'UTF8'), 'sha256'), 'hex')
  );
end;
$$;

create or replace function public.build_question_occurrence_key(
  p_board_id text,
  p_exam_id text,
  p_exam_year integer,
  p_exam_date date,
  p_shift_no integer,
  p_paper_code text,
  p_original_question_no integer,
  p_source_page integer,
  p_source_question_id text
)
returns text
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  v_payload text;
begin
  if nullif(btrim(p_board_id), '') is null
     or nullif(btrim(p_exam_id), '') is null then
    return null;
  end if;

  if p_exam_year is null
     and p_exam_date is null
     and p_shift_no is null
     and nullif(btrim(p_paper_code), '') is null then
    return null;
  end if;

  if p_original_question_no is null
     and nullif(btrim(p_source_question_id), '') is null then
    return null;
  end if;

  v_payload := concat(
    'board=', upper(btrim(p_board_id)),
    '|exam=', upper(btrim(p_exam_id)),
    '|year=', coalesce(p_exam_year::text, ''),
    '|date=', coalesce(p_exam_date::text, ''),
    '|shift=', coalesce(p_shift_no::text, ''),
    '|paper=', upper(coalesce(btrim(p_paper_code), '')),
    '|qno=', coalesce(p_original_question_no::text, ''),
    '|page=', coalesce(p_source_page::text, ''),
    '|source_qid=', upper(coalesce(btrim(p_source_question_id), ''))
  );

  return encode(extensions.digest(convert_to(v_payload, 'UTF8'), 'sha256'), 'hex');
end;
$$;

-- Raw-file identity. Exact same file bytes must not be stored more than once.
update public.source_files
set checksum_sha256 = lower(btrim(checksum_sha256))
where checksum_sha256 is not null;

alter table public.source_files
  add constraint source_files_checksum_sha256_format
  check (checksum_sha256 is null or checksum_sha256 ~ '^[0-9a-f]{64}$');

create unique index source_files_checksum_sha256_uidx
  on public.source_files (checksum_sha256)
  where checksum_sha256 is not null;

-- Import-package identity and persistent reconciliation counters.
alter table public.import_batches
  add column package_id text,
  add column package_checksum_sha256 text,
  add column source_checksum_sha256 text,
  add column schema_name text,
  add column schema_version text,
  add column package_manifest jsonb not null default '{}'::jsonb,
  add column total_valid integer not null default 0,
  add column total_warning integer not null default 0,
  add column total_error integer not null default 0,
  add column total_duplicate integer not null default 0,
  add column updated_at timestamptz not null default now();

update public.import_batches
set package_checksum_sha256 = lower(btrim(package_checksum_sha256)),
    source_checksum_sha256 = lower(btrim(source_checksum_sha256))
where package_checksum_sha256 is not null
   or source_checksum_sha256 is not null;

alter table public.import_batches
  add constraint import_batches_package_id_format
    check (package_id is null or package_id ~ '^[A-Z0-9][A-Z0-9._-]{5,119}$'),
  add constraint import_batches_package_checksum_format
    check (package_checksum_sha256 is null or package_checksum_sha256 ~ '^[0-9a-f]{64}$'),
  add constraint import_batches_source_checksum_format
    check (source_checksum_sha256 is null or source_checksum_sha256 ~ '^[0-9a-f]{64}$'),
  add constraint import_batches_manifest_object
    check (jsonb_typeof(package_manifest) = 'object'),
  add constraint import_batches_phase3_counts_nonnegative
    check (
      total_valid >= 0
      and total_warning >= 0
      and total_error >= 0
      and total_duplicate >= 0
    );

create unique index import_batches_package_id_uidx
  on public.import_batches (package_id)
  where package_id is not null;

create unique index import_batches_package_checksum_uidx
  on public.import_batches (package_checksum_sha256)
  where package_checksum_sha256 is not null;

create trigger import_batches_set_updated_at
before update on public.import_batches
for each row execute function public.set_updated_at();

-- One immutable reconciliation row for every question record encountered in a package.
create table public.import_batch_items (
  import_item_id uuid primary key default gen_random_uuid(),
  import_batch_id uuid not null references public.import_batches(import_batch_id) on delete cascade,
  item_index integer not null check (item_index > 0),
  source_record_id text,
  proposed_question_id text,
  raw_payload jsonb not null,
  normalized_payload jsonb not null default '{}'::jsonb,
  strict_fingerprint text,
  loose_fingerprint text,
  occurrence_key text,
  validation_status public.import_item_status not null default 'PENDING',
  errors jsonb not null default '[]'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  duplicate_kind public.import_duplicate_kind not null default 'NONE',
  matched_question_id text references public.questions(question_id),
  matched_draft_id uuid references public.draft_questions(draft_id),
  created_draft_id uuid references public.draft_questions(draft_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (import_batch_id, item_index),
  constraint import_batch_items_normalized_object
    check (jsonb_typeof(normalized_payload) = 'object'),
  constraint import_batch_items_errors_array
    check (jsonb_typeof(errors) = 'array'),
  constraint import_batch_items_warnings_array
    check (jsonb_typeof(warnings) = 'array'),
  constraint import_batch_items_strict_fingerprint_format
    check (strict_fingerprint is null or strict_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint import_batch_items_loose_fingerprint_format
    check (loose_fingerprint is null or loose_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint import_batch_items_occurrence_key_format
    check (occurrence_key is null or occurrence_key ~ '^[0-9a-f]{64}$'),
  constraint import_batch_items_proposed_id_format
    check (proposed_question_id is null or proposed_question_id ~ '^[A-Z0-9]+(?:-[A-Z0-9]+)+$')
);

create unique index import_batch_items_source_record_uidx
  on public.import_batch_items (import_batch_id, source_record_id)
  where source_record_id is not null;

create unique index import_batch_items_created_draft_uidx
  on public.import_batch_items (created_draft_id)
  where created_draft_id is not null;

create index import_batch_items_batch_status_idx
  on public.import_batch_items (import_batch_id, validation_status, item_index);

create index import_batch_items_strict_fingerprint_idx
  on public.import_batch_items (strict_fingerprint)
  where strict_fingerprint is not null;

create index import_batch_items_loose_fingerprint_idx
  on public.import_batch_items (loose_fingerprint)
  where loose_fingerprint is not null;

create trigger import_batch_items_set_updated_at
before update on public.import_batch_items
for each row execute function public.set_updated_at();

-- Trace imported drafts and published questions back to the exact package item.
alter table public.questions
  add column content_origin public.content_origin not null default 'MANUAL_ENTRY',
  add column content_fingerprint text,
  add column loose_fingerprint text,
  add column import_item_id uuid references public.import_batch_items(import_item_id);

alter table public.draft_questions
  add column sort_order integer,
  add column content_origin public.content_origin not null default 'MANUAL_ENTRY',
  add column content_fingerprint text,
  add column loose_fingerprint text,
  add column import_item_id uuid references public.import_batch_items(import_item_id);

create unique index questions_import_item_uidx
  on public.questions (import_item_id)
  where import_item_id is not null;

create unique index draft_questions_import_item_uidx
  on public.draft_questions (import_item_id)
  where import_item_id is not null;

create or replace function public.set_question_fingerprints()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_fingerprints jsonb;
begin
  v_fingerprints := public.build_question_fingerprints(
    new.language,
    new.question_text,
    new.options
  );

  new.content_fingerprint := v_fingerprints ->> 'strict';
  new.loose_fingerprint := v_fingerprints ->> 'loose';
  return new;
end;
$$;

create trigger questions_set_fingerprints
before insert or update of language, question_text, options
on public.questions
for each row execute function public.set_question_fingerprints();

create trigger draft_questions_set_fingerprints
before insert or update of language, question_text, options
on public.draft_questions
for each row execute function public.set_question_fingerprints();

-- Backfill current records through the authoritative trigger.
update public.questions
set question_text = question_text;

update public.draft_questions
set question_text = question_text;

alter table public.questions
  alter column content_fingerprint set not null,
  alter column loose_fingerprint set not null;

alter table public.draft_questions
  alter column content_fingerprint set not null,
  alter column loose_fingerprint set not null;

alter table public.questions
  add constraint questions_content_fingerprint_format
    check (content_fingerprint ~ '^[0-9a-f]{64}$'),
  add constraint questions_loose_fingerprint_format
    check (loose_fingerprint ~ '^[0-9a-f]{64}$');

alter table public.draft_questions
  add constraint draft_questions_content_fingerprint_format
    check (content_fingerprint ~ '^[0-9a-f]{64}$'),
  add constraint draft_questions_loose_fingerprint_format
    check (loose_fingerprint ~ '^[0-9a-f]{64}$');

-- Master content can exist only once, regardless of Question ID or source paper.
create unique index questions_content_fingerprint_uidx
  on public.questions (content_fingerprint);

-- Prevent two active drafts for the same master content or inherited Question ID.
create unique index draft_questions_active_content_fingerprint_uidx
  on public.draft_questions (content_fingerprint)
  where review_status <> 'REJECTED';

create unique index draft_questions_active_proposed_id_uidx
  on public.draft_questions (proposed_question_id)
  where proposed_question_id is not null and review_status <> 'REJECTED';

create index questions_loose_fingerprint_idx
  on public.questions (loose_fingerprint);

create index draft_questions_loose_fingerprint_idx
  on public.draft_questions (loose_fingerprint)
  where review_status <> 'REJECTED';

-- A master question is stored once; every authentic paper appearance is stored here.
create table public.question_occurrences (
  occurrence_id uuid primary key default gen_random_uuid(),
  occurrence_key text not null unique,
  question_id text not null references public.questions(question_id) on delete cascade,
  import_batch_id uuid references public.import_batches(import_batch_id),
  import_item_id uuid references public.import_batch_items(import_item_id),
  source_file_id uuid references public.source_files(source_file_id),
  source_record_id text,
  external_question_id text,
  board_id text not null references public.boards(board_id),
  exam_id text not null references public.exams(exam_id),
  exam_year integer,
  exam_date date,
  shift_no integer check (shift_no is null or shift_no > 0),
  paper_code text,
  original_question_no integer check (original_question_no is null or original_question_no > 0),
  subject_id text not null references public.subjects(subject_id),
  topic_id text references public.topics(topic_id),
  section_code text,
  source_page integer check (source_page is null or source_page > 0),
  source_question_id text,
  created_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  constraint question_occurrences_key_format
    check (occurrence_key ~ '^[0-9a-f]{64}$')
);

create unique index question_occurrences_import_item_uidx
  on public.question_occurrences (import_item_id)
  where import_item_id is not null;

create index question_occurrences_question_idx
  on public.question_occurrences (question_id, exam_date, shift_no, original_question_no);

create index question_occurrences_paper_idx
  on public.question_occurrences (board_id, exam_id, exam_year, exam_date, shift_no, paper_code);

create or replace function public.enforce_question_occurrence_integrity()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_expected_key text;
begin
  if not exists (
    select 1 from public.exams e
    where e.exam_id = new.exam_id
      and e.board_id = new.board_id
  ) then
    raise exception 'Occurrence exam does not belong to occurrence board.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.subjects s
    where s.subject_id = new.subject_id
      and s.exam_id = new.exam_id
  ) then
    raise exception 'Occurrence subject does not belong to occurrence exam.' using errcode = 'P0001';
  end if;

  if new.topic_id is not null and not exists (
    select 1 from public.topics t
    where t.topic_id = new.topic_id
      and t.subject_id = new.subject_id
  ) then
    raise exception 'Occurrence topic does not belong to occurrence subject.' using errcode = 'P0001';
  end if;

  v_expected_key := public.build_question_occurrence_key(
    new.board_id,
    new.exam_id,
    new.exam_year,
    new.exam_date,
    new.shift_no,
    new.paper_code,
    new.original_question_no,
    new.source_page,
    new.source_question_id
  );

  if v_expected_key is null then
    raise exception 'Insufficient source metadata to identify the question occurrence.' using errcode = 'P0001';
  end if;

  if new.occurrence_key is not null
     and lower(new.occurrence_key) <> v_expected_key then
    raise exception 'Occurrence key does not match its source metadata.' using errcode = 'P0001';
  end if;

  new.occurrence_key := v_expected_key;
  return new;
end;
$$;

create trigger question_occurrences_enforce_integrity
before insert or update of
  occurrence_key,
  board_id,
  exam_id,
  exam_year,
  exam_date,
  shift_no,
  paper_code,
  original_question_no,
  subject_id,
  topic_id,
  source_page,
  source_question_id
on public.question_occurrences
for each row execute function public.enforce_question_occurrence_integrity();

-- Backfill any PYQ records that existed before Phase 3A.
insert into public.question_occurrences (
  occurrence_key,
  question_id,
  import_batch_id,
  import_item_id,
  source_file_id,
  external_question_id,
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
  source_page,
  source_question_id,
  created_by
)
select
  public.build_question_occurrence_key(
    q.board_id,
    q.exam_id,
    q.exam_year,
    q.exam_date,
    q.shift_no,
    q.paper_code,
    q.original_question_no,
    q.source_page,
    q.source_question_id
  ),
  q.question_id,
  q.import_batch_id,
  q.import_item_id,
  q.source_file_id,
  q.question_id,
  q.board_id,
  q.exam_id,
  q.exam_year,
  q.exam_date,
  q.shift_no,
  q.paper_code,
  q.original_question_no,
  q.subject_id,
  q.topic_id,
  q.section_code,
  q.source_page,
  q.source_question_id,
  q.created_by
from public.questions q
where q.question_type = 'PYQ'
  and q.exam_id is not null
  and public.build_question_occurrence_key(
    q.board_id,
    q.exam_id,
    q.exam_year,
    q.exam_date,
    q.shift_no,
    q.paper_code,
    q.original_question_no,
    q.source_page,
    q.source_question_id
  ) is not null
;

-- Package-level dry validation. It performs no writes.
create or replace function public.validate_import_package(
  p_manifest jsonb,
  p_package_checksum_sha256 text default null,
  p_source_checksum_sha256 text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_schema_name text;
  v_schema_version text;
  v_package_id text;
  v_question_count integer := 0;
  v_package_checksum text := lower(nullif(btrim(p_package_checksum_sha256), ''));
  v_source_checksum text := lower(nullif(btrim(p_source_checksum_sha256), ''));
  v_existing_by_id public.import_batches%rowtype;
  v_existing_by_checksum public.import_batches%rowtype;
  v_existing_source_file_id uuid;
  v_status text := 'VALID';
  v_duplicate_kind text := 'NONE';
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if p_manifest is null or jsonb_typeof(p_manifest) <> 'object' then
    return jsonb_build_object(
      'status', 'INVALID',
      'errors', jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_PACKAGE_OBJECT',
        'message', 'The import payload must be a JSON object.'
      )),
      'warnings', '[]'::jsonb,
      'duplicate_kind', 'NONE'
    );
  end if;

  v_schema_name := nullif(btrim(p_manifest ->> 'schema'), '');
  v_schema_version := nullif(btrim(p_manifest ->> 'schema_version'), '');
  v_package_id := upper(nullif(btrim(p_manifest ->> 'package_id'), ''));

  if v_schema_name is distinct from 'scoremore.question-import' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'UNSUPPORTED_SCHEMA',
      'message', 'schema must equal scoremore.question-import.'
    ));
  end if;

  if v_schema_version is distinct from '1.0.0' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'UNSUPPORTED_SCHEMA_VERSION',
      'message', 'Only schema_version 1.0.0 is supported in Phase 3.'
    ));
  end if;

  if v_package_id is null or v_package_id !~ '^[A-Z0-9][A-Z0-9._-]{5,119}$' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_PACKAGE_ID',
      'message', 'package_id must be 6-120 uppercase letters, numbers, dots, underscores or hyphens.'
    ));
  end if;

  if jsonb_typeof(p_manifest -> 'source') is distinct from 'object' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_SOURCE_OBJECT',
      'message', 'source must be a JSON object.'
    ));
  end if;

  if jsonb_typeof(p_manifest -> 'defaults') is distinct from 'object' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_DEFAULTS_OBJECT',
      'message', 'defaults must be a JSON object.'
    ));
  end if;

  if jsonb_typeof(p_manifest -> 'questions') is distinct from 'array' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_QUESTIONS_ARRAY',
      'message', 'questions must be a JSON array.'
    ));
  else
    v_question_count := jsonb_array_length(p_manifest -> 'questions');

    if v_question_count = 0 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'EMPTY_QUESTIONS_ARRAY',
        'message', 'The import package contains no question records.'
      ));
    elsif v_question_count > 2000 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'PACKAGE_TOO_LARGE',
        'message', 'A single Phase 3 package may contain at most 2000 records.'
      ));
    end if;
  end if;

  if nullif(btrim(p_manifest ->> 'generated_at'), '') is null then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'MISSING_GENERATED_AT',
      'message', 'generated_at is recommended for package audit history.'
    ));
  end if;

  if v_package_checksum is not null and v_package_checksum !~ '^[0-9a-f]{64}$' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_PACKAGE_CHECKSUM',
      'message', 'The canonical package checksum must be a lowercase SHA-256 hex value.'
    ));
  end if;

  if v_source_checksum is not null and v_source_checksum !~ '^[0-9a-f]{64}$' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_SOURCE_CHECKSUM',
      'message', 'The source checksum must be a lowercase SHA-256 hex value.'
    ));
  end if;

  if v_package_id is not null then
    select * into v_existing_by_id
    from public.import_batches
    where package_id = v_package_id
    limit 1;
  end if;

  if v_package_checksum is not null then
    select * into v_existing_by_checksum
    from public.import_batches
    where package_checksum_sha256 = v_package_checksum
    limit 1;
  end if;

  if v_source_checksum is not null then
    select source_file_id into v_existing_source_file_id
    from public.source_files
    where checksum_sha256 = v_source_checksum
    limit 1;
  end if;

  if v_existing_by_id.import_batch_id is not null then
    if v_package_checksum is not null
       and v_existing_by_id.package_checksum_sha256 = v_package_checksum then
      v_status := 'EXACT_DUPLICATE';
      v_duplicate_kind := 'EXACT_PACKAGE';
    elsif v_package_checksum is null
       and v_existing_by_id.package_checksum_sha256 is null then
      v_status := 'EXACT_DUPLICATE';
      v_duplicate_kind := 'EXACT_PACKAGE_ID';
    else
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'PACKAGE_ID_CONFLICT',
        'message', 'This package_id already exists with different package content.'
      ));
      v_status := 'PACKAGE_ID_CONFLICT';
      v_duplicate_kind := 'PACKAGE_ID_CONFLICT';
    end if;
  elsif v_existing_by_checksum.import_batch_id is not null then
    v_status := 'EXACT_DUPLICATE';
    v_duplicate_kind := 'EXACT_PACKAGE_CONTENT';
  end if;

  if jsonb_array_length(v_errors) > 0 and v_status <> 'PACKAGE_ID_CONFLICT' then
    v_status := 'INVALID';
  elsif v_status = 'VALID' and jsonb_array_length(v_warnings) > 0 then
    v_status := 'VALID_WITH_WARNINGS';
  end if;

  return jsonb_build_object(
    'status', v_status,
    'schema', v_schema_name,
    'schema_version', v_schema_version,
    'package_id', v_package_id,
    'question_count', v_question_count,
    'errors', v_errors,
    'warnings', v_warnings,
    'duplicate_kind', v_duplicate_kind,
    'existing_import_batch_id', coalesce(v_existing_by_id.import_batch_id, v_existing_by_checksum.import_batch_id),
    'existing_source_file_id', v_existing_source_file_id
  );
end;
$$;

-- Question-level authoritative validation and duplicate inspection. It performs no writes.
create or replace function public.validate_import_question(p_question jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_question_type text;
  v_question_id text;
  v_board_id text;
  v_exam_id text;
  v_subject_id text;
  v_topic_id text;
  v_language text;
  v_difficulty text;
  v_question_text text;
  v_options jsonb;
  v_correct_answer text;
  v_answer_source text;
  v_explanation text;
  v_content_origin text;
  v_exam_year integer;
  v_exam_date date;
  v_shift_no integer;
  v_paper_code text;
  v_original_question_no integer;
  v_source_page integer;
  v_source_question_id text;
  v_section_code text;
  v_fingerprints jsonb;
  v_strict_fingerprint text;
  v_loose_fingerprint text;
  v_occurrence_key text;
  v_status public.import_item_status := 'PENDING';
  v_duplicate_kind public.import_duplicate_kind := 'NONE';
  v_matched_question_id text;
  v_matched_draft_id uuid;
  v_possible_question_ids text[] := array[]::text[];
  v_possible_draft_ids uuid[] := array[]::uuid[];
  v_existing_question_answer text;
  v_existing_draft_answer text;
  v_occurrence_question_id text;
  v_occurrence_fingerprint text;
  v_occurrence_answer text;
  v_verification_status text;
  v_source_record_id text;
  v_sort_order integer;
  v_id_conflict boolean := false;
  v_answer_conflict boolean := false;
  v_source_conflict boolean := false;
  v_exact_duplicate boolean := false;
  v_possible_duplicate boolean := false;
  v_distinct_options integer;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  if p_question is null or jsonb_typeof(p_question) <> 'object' then
    return jsonb_build_object(
      'status', 'INVALID',
      'errors', jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_QUESTION_OBJECT',
        'message', 'Each questions[] entry must be a JSON object.'
      )),
      'warnings', '[]'::jsonb,
      'duplicate', jsonb_build_object('kind', 'NONE')
    );
  end if;

  v_question_type := upper(nullif(btrim(p_question ->> 'question_type'), ''));
  v_question_id := upper(nullif(btrim(p_question ->> 'proposed_question_id'), ''));
  v_board_id := upper(nullif(btrim(p_question ->> 'board_id'), ''));
  v_exam_id := upper(nullif(btrim(p_question ->> 'exam_id'), ''));
  v_subject_id := upper(nullif(btrim(p_question ->> 'subject_id'), ''));
  v_topic_id := upper(nullif(btrim(p_question ->> 'topic_id'), ''));
  v_language := upper(nullif(btrim(p_question ->> 'language'), ''));
  v_difficulty := upper(coalesce(nullif(btrim(p_question ->> 'difficulty'), ''), 'MEDIUM'));
  v_question_text := nullif(btrim(p_question ->> 'question_text'), '');
  v_options := p_question -> 'options';
  v_correct_answer := upper(nullif(btrim(p_question ->> 'correct_answer'), ''));
  v_answer_source := upper(nullif(btrim(p_question ->> 'answer_source'), ''));
  v_explanation := nullif(btrim(p_question ->> 'explanation'), '');
  v_content_origin := upper(coalesce(nullif(btrim(p_question ->> 'content_origin'), ''), 'SOURCE_EXTRACTED'));
  v_exam_year := public.try_parse_integer(p_question ->> 'exam_year');
  v_exam_date := public.try_parse_date(p_question ->> 'exam_date');
  v_shift_no := public.try_parse_integer(p_question ->> 'shift_no');
  v_paper_code := upper(nullif(btrim(p_question ->> 'paper_code'), ''));
  v_original_question_no := public.try_parse_integer(p_question ->> 'original_question_no');
  v_source_page := public.try_parse_integer(p_question ->> 'source_page');
  v_source_question_id := nullif(btrim(p_question ->> 'source_question_id'), '');
  v_section_code := upper(nullif(btrim(p_question ->> 'section_code'), ''));
  v_verification_status := upper(coalesce(nullif(btrim(p_question ->> 'verification_status'), ''), 'NEEDS_CHECK'));
  v_source_record_id := nullif(btrim(p_question ->> 'source_record_id'), '');
  v_sort_order := public.try_parse_integer(p_question ->> 'sort_order');

  if v_source_record_id is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'MISSING_SOURCE_RECORD_ID',
      'message', 'source_record_id is required for item-level reconciliation.'
    ));
  end if;

  if v_sort_order is null or v_sort_order <= 0 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_SORT_ORDER',
      'message', 'sort_order must be a positive integer that preserves source chronology.'
    ));
  end if;

  if v_question_type not in ('NORMAL', 'PYQ') or v_question_type is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_QUESTION_TYPE',
      'message', 'question_type must be NORMAL or PYQ.'
    ));
  end if;

  if v_question_id is null or v_question_id !~ '^[A-Z0-9]+(?:-[A-Z0-9]+)+$' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_QUESTION_ID',
      'message', 'proposed_question_id must preserve the inherited uppercase hyphenated ID format.'
    ));
  end if;

  if v_board_id is null or not exists (
    select 1 from public.boards where board_id = v_board_id and status = 'ACTIVE'
  ) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'UNKNOWN_BOARD',
      'message', 'board_id does not reference an active board.'
    ));
  end if;

  if v_exam_id is null or not exists (
    select 1 from public.exams
    where exam_id = v_exam_id and board_id = v_board_id and status = 'ACTIVE'
  ) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'UNKNOWN_EXAM',
      'message', 'exam_id does not reference an active exam under the selected board.'
    ));
  end if;

  if v_subject_id is null or not exists (
    select 1 from public.subjects
    where subject_id = v_subject_id and exam_id = v_exam_id and status = 'ACTIVE'
  ) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'UNKNOWN_SUBJECT',
      'message', 'subject_id does not reference an active subject under the selected exam.'
    ));
  end if;

  if v_topic_id is not null and not exists (
    select 1 from public.topics
    where topic_id = v_topic_id and subject_id = v_subject_id and status = 'ACTIVE'
  ) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'UNKNOWN_TOPIC',
      'message', 'topic_id does not reference an active topic under the selected subject.'
    ));
  end if;

  if v_language is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'MISSING_LANGUAGE',
      'message', 'language is required.'
    ));
  end if;

  if v_difficulty not in ('EASY', 'MEDIUM', 'HARD') then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_DIFFICULTY',
      'message', 'difficulty must be EASY, MEDIUM or HARD.'
    ));
  end if;

  if v_question_text is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'MISSING_QUESTION_TEXT',
      'message', 'question_text is required.'
    ));
  end if;

  if v_options is null or jsonb_typeof(v_options) <> 'object' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_OPTIONS_OBJECT',
      'message', 'options must be a JSON object with exactly A, B, C and D.'
    ));
  else
    if not (v_options ?& array['A', 'B', 'C', 'D'])
       or exists (
         select 1
         from jsonb_object_keys(v_options) as option_keys(option_key)
         where option_key not in ('A', 'B', 'C', 'D')
       ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'INVALID_OPTION_KEYS',
        'message', 'options must contain exactly the keys A, B, C and D.'
      ));
    end if;

    if exists (
      select 1
      from jsonb_each(v_options) as option_entry(option_key, option_value)
      where option_key in ('A', 'B', 'C', 'D')
        and jsonb_typeof(option_value) <> 'string'
    ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'NON_TEXT_OPTION',
        'message', 'Every option value must be text.'
      ));
    end if;

    if coalesce(nullif(btrim(v_options ->> 'A'), ''), '') = ''
       or coalesce(nullif(btrim(v_options ->> 'B'), ''), '') = ''
       or coalesce(nullif(btrim(v_options ->> 'C'), ''), '') = ''
       or coalesce(nullif(btrim(v_options ->> 'D'), ''), '') = '' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'EMPTY_OPTION',
        'message', 'All four options must contain text.'
      ));
    end if;

    select count(distinct public.normalize_import_text(option_text, false))
    into v_distinct_options
    from (
      values
        (v_options ->> 'A'),
        (v_options ->> 'B'),
        (v_options ->> 'C'),
        (v_options ->> 'D')
    ) as option_values(option_text);

    if v_distinct_options < 4 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'DUPLICATE_OPTIONS',
        'message', 'Two or more options are identical after safe normalization.'
      ));
    end if;
  end if;

  if v_correct_answer is not null and v_correct_answer not in ('A', 'B', 'C', 'D') then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_CORRECT_ANSWER',
      'message', 'correct_answer must be A, B, C, D or null.'
    ));
  elsif v_correct_answer is null then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'MISSING_ANSWER',
      'message', 'The question may enter drafts but cannot be published until the answer is verified.'
    ));
  end if;

  if v_correct_answer is not null and v_answer_source is null then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'MISSING_ANSWER_SOURCE',
      'message', 'A verified answer source should be recorded.'
    ));
  elsif v_answer_source is not null and v_answer_source not in (
    'OFFICIAL_FINAL_KEY',
    'OFFICIAL_PROVISIONAL_KEY',
    'MANUALLY_VERIFIED',
    'SOURCE_BOOK',
    'ADMIN_CORRECTED'
  ) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_ANSWER_SOURCE',
      'message', 'answer_source is not supported by the ScoreMore database.'
    ));
  end if;

  if v_explanation is null then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'MISSING_EXPLANATION',
      'message', 'Explanation is recommended and may be added during human review.'
    ));
  end if;

  if v_content_origin not in (
    'SOURCE_EXTRACTED',
    'OCR_EXTRACTED',
    'AI_TRANSCRIBED',
    'MANUAL_ENTRY',
    'RECONSTRUCTED',
    'AI_GENERATED'
  ) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_CONTENT_ORIGIN',
      'message', 'content_origin is not supported.'
    ));
  end if;

  if v_verification_status not in ('UNVERIFIED', 'NEEDS_CHECK', 'VERIFIED', 'DISPUTED') then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_VERIFICATION_STATUS',
      'message', 'verification_status is not supported by the ScoreMore database.'
    ));
  end if;

  if p_question ? 'image_refs'
     and jsonb_typeof(p_question -> 'image_refs') is distinct from 'array' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_IMAGE_REFS',
      'message', 'image_refs must be a JSON array.'
    ));
  end if;

  if p_question ? 'tags'
     and jsonb_typeof(p_question -> 'tags') is distinct from 'array' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_TAGS',
      'message', 'tags must be a JSON array.'
    ));
  end if;

  if nullif(btrim(p_question ->> 'group_id'), '') is not null
     and nullif(btrim(p_question ->> 'group_type'), '') is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'MISSING_GROUP_TYPE',
      'message', 'group_type is required when group_id is present.'
    ));
  end if;

  if nullif(btrim(p_question ->> 'group_id'), '') is not null
     and nullif(btrim(p_question ->> 'group_text'), '') is null then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'MISSING_GROUP_TEXT',
      'message', 'group_text is recommended for passage or grouped questions.'
    ));
  end if;

  if v_exam_year is not null and (v_exam_year < 1900 or v_exam_year > 2200) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'EXAM_YEAR_OUT_OF_RANGE',
      'message', 'exam_year must be between 1900 and 2200.'
    ));
  end if;

  if v_shift_no is not null and v_shift_no <= 0 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_SHIFT_NO_RANGE',
      'message', 'shift_no must be positive.'
    ));
  end if;

  if v_original_question_no is not null and v_original_question_no <= 0 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_ORIGINAL_QUESTION_NO_RANGE',
      'message', 'original_question_no must be positive.'
    ));
  end if;

  if v_source_page is not null and v_source_page <= 0 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_SOURCE_PAGE_RANGE',
      'message', 'source_page must be positive.'
    ));
  end if;

  if v_question_type = 'PYQ' then
    if v_content_origin in ('RECONSTRUCTED', 'AI_GENERATED') then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'PYQ_ORIGIN_NOT_ALLOWED',
        'message', 'Reconstructed or AI-generated content cannot be represented as an original PYQ.'
      ));
    end if;

    if v_exam_year is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_EXAM_YEAR',
        'message', 'exam_year is required for imported PYQs.'
      ));
    end if;

    if v_exam_date is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_EXAM_DATE',
        'message', 'exam_date is required for imported PYQs.'
      ));
    end if;

    if v_shift_no is null or v_shift_no <= 0 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_SHIFT_NO',
        'message', 'A positive shift_no is required for imported PYQs.'
      ));
    end if;

    if v_paper_code is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_PAPER_CODE',
        'message', 'paper_code is required for imported PYQs.'
      ));
    end if;

    if v_original_question_no is null or v_original_question_no <= 0 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_ORIGINAL_QUESTION_NO',
        'message', 'A positive original_question_no is required for imported PYQs.'
      ));
    end if;

    if v_source_page is null or v_source_page <= 0 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_SOURCE_PAGE',
        'message', 'A positive source_page is required for imported PYQs.'
      ));
    end if;

    if v_section_code is null then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_SECTION_CODE',
        'message', 'section_code is recommended for sectional test reuse.'
      ));
    end if;

    if v_source_question_id is null then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
        'code', 'MISSING_SOURCE_QUESTION_ID',
        'message', 'source_question_id is recommended for source reconciliation.'
      ));
    end if;
  end if;

  if nullif(btrim(p_question ->> 'exam_year'), '') is not null and v_exam_year is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_EXAM_YEAR',
      'message', 'exam_year must be an integer.'
    ));
  end if;

  if nullif(btrim(p_question ->> 'exam_date'), '') is not null and v_exam_date is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_EXAM_DATE',
      'message', 'exam_date must use YYYY-MM-DD.'
    ));
  end if;

  if nullif(btrim(p_question ->> 'shift_no'), '') is not null and v_shift_no is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_SHIFT_NO',
      'message', 'shift_no must be an integer.'
    ));
  end if;

  if nullif(btrim(p_question ->> 'original_question_no'), '') is not null
     and v_original_question_no is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_ORIGINAL_QUESTION_NO',
      'message', 'original_question_no must be an integer.'
    ));
  end if;

  if nullif(btrim(p_question ->> 'source_page'), '') is not null and v_source_page is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_SOURCE_PAGE',
      'message', 'source_page must be an integer.'
    ));
  end if;

  if nullif(btrim(p_question ->> 'sort_order'), '') is not null and v_sort_order is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'code', 'INVALID_SORT_ORDER_TYPE',
      'message', 'sort_order must be an integer.'
    ));
  end if;

  if v_question_text is not null
     and v_options is not null
     and jsonb_typeof(v_options) = 'object'
     and (v_options ?& array['A', 'B', 'C', 'D']) then
    v_fingerprints := public.build_question_fingerprints(v_language, v_question_text, v_options);
    v_strict_fingerprint := v_fingerprints ->> 'strict';
    v_loose_fingerprint := v_fingerprints ->> 'loose';
  end if;

  if v_question_type = 'PYQ' then
    v_occurrence_key := public.build_question_occurrence_key(
      v_board_id,
      v_exam_id,
      v_exam_year,
      v_exam_date,
      v_shift_no,
      v_paper_code,
      v_original_question_no,
      v_source_page,
      v_source_question_id
    );
  end if;

  if v_question_id is not null and v_strict_fingerprint is not null then
    select q.question_id, q.correct_answer
    into v_matched_question_id, v_existing_question_answer
    from public.questions q
    where q.question_id = v_question_id
    limit 1;

    if v_matched_question_id is not null then
      if exists (
        select 1 from public.questions q
        where q.question_id = v_matched_question_id
          and q.content_fingerprint = v_strict_fingerprint
      ) then
        v_exact_duplicate := true;
        v_duplicate_kind := 'EXACT_ID';
        if v_correct_answer is not null
           and v_existing_question_answer is not null
           and v_correct_answer <> v_existing_question_answer then
          v_answer_conflict := true;
        end if;
      else
        v_id_conflict := true;
        v_duplicate_kind := 'ID_CONFLICT';
      end if;
    end if;

    if v_matched_question_id is null then
      select d.draft_id, d.correct_answer
      into v_matched_draft_id, v_existing_draft_answer
      from public.draft_questions d
      where d.proposed_question_id = v_question_id
        and d.review_status <> 'REJECTED'
      limit 1;

      if v_matched_draft_id is not null then
        if exists (
          select 1 from public.draft_questions d
          where d.draft_id = v_matched_draft_id
            and d.content_fingerprint = v_strict_fingerprint
        ) then
          v_exact_duplicate := true;
          v_duplicate_kind := 'EXACT_ID';
          if v_correct_answer is not null
             and v_existing_draft_answer is not null
             and v_correct_answer <> v_existing_draft_answer then
            v_answer_conflict := true;
          end if;
        else
          v_id_conflict := true;
          v_duplicate_kind := 'ID_CONFLICT';
        end if;
      end if;
    end if;
  end if;

  if not v_id_conflict and not v_exact_duplicate and v_strict_fingerprint is not null then
    select q.question_id, q.correct_answer
    into v_matched_question_id, v_existing_question_answer
    from public.questions q
    where q.content_fingerprint = v_strict_fingerprint
    limit 1;

    if v_matched_question_id is not null then
      v_exact_duplicate := true;
      v_duplicate_kind := 'EXACT_CONTENT';
      if v_correct_answer is not null
         and v_existing_question_answer is not null
         and v_correct_answer <> v_existing_question_answer then
        v_answer_conflict := true;
      end if;
    else
      select d.draft_id, d.correct_answer
      into v_matched_draft_id, v_existing_draft_answer
      from public.draft_questions d
      where d.content_fingerprint = v_strict_fingerprint
        and d.review_status <> 'REJECTED'
      limit 1;

      if v_matched_draft_id is not null then
        v_exact_duplicate := true;
        v_duplicate_kind := 'EXACT_CONTENT';
        if v_correct_answer is not null
           and v_existing_draft_answer is not null
           and v_correct_answer <> v_existing_draft_answer then
          v_answer_conflict := true;
        end if;
      end if;
    end if;
  end if;

  if v_occurrence_key is not null and not v_id_conflict then
    select qo.question_id, q.content_fingerprint, q.correct_answer
    into v_occurrence_question_id, v_occurrence_fingerprint, v_occurrence_answer
    from public.question_occurrences qo
    join public.questions q on q.question_id = qo.question_id
    where qo.occurrence_key = v_occurrence_key
    limit 1;

    if found then
      v_matched_question_id := v_occurrence_question_id;
      if v_fingerprints ->> 'strict' = v_occurrence_fingerprint then
        v_exact_duplicate := true;
        v_duplicate_kind := 'SOURCE_OCCURRENCE';
        if v_correct_answer is not null
           and v_occurrence_answer is not null
           and v_correct_answer <> v_occurrence_answer then
          v_answer_conflict := true;
        end if;
      else
        v_source_conflict := true;
        v_duplicate_kind := 'SOURCE_CONFLICT';
      end if;
    end if;
  end if;

  if not v_id_conflict
     and not v_source_conflict
     and not v_exact_duplicate
     and v_loose_fingerprint is not null then
    select coalesce(array_agg(q.question_id order by q.question_id), array[]::text[])
    into v_possible_question_ids
    from public.questions q
    where q.loose_fingerprint = v_loose_fingerprint;

    select coalesce(array_agg(d.draft_id order by d.created_at), array[]::uuid[])
    into v_possible_draft_ids
    from public.draft_questions d
    where d.loose_fingerprint = v_loose_fingerprint
      and d.review_status <> 'REJECTED';

    if cardinality(v_possible_question_ids) > 0
       or cardinality(v_possible_draft_ids) > 0 then
      v_possible_duplicate := true;
      v_duplicate_kind := 'POSSIBLE_CONTENT';
    end if;
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
      'message', 'Matching question content exists with a different correct answer.'
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
    'fingerprints', jsonb_build_object(
      'strict', v_fingerprints ->> 'strict',
      'loose', v_fingerprints ->> 'loose'
    ),
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

-- Admin-only trusted operation for linking a confirmed duplicate source occurrence
-- to an existing published master question. It never creates a duplicate question.
create or replace function public.link_question_occurrence(
  p_question_id text,
  p_occurrence jsonb,
  p_import_batch_id uuid default null,
  p_source_file_id uuid default null,
  p_import_item_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_question public.questions%rowtype;
  v_board_id text;
  v_exam_id text;
  v_subject_id text;
  v_topic_id text;
  v_exam_year integer;
  v_exam_date date;
  v_shift_no integer;
  v_paper_code text;
  v_original_question_no integer;
  v_source_page integer;
  v_source_question_id text;
  v_section_code text;
  v_source_record_id text;
  v_external_question_id text;
  v_supplied_fingerprint text;
  v_occurrence_key text;
  v_existing_question_id text;
  v_occurrence_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  select * into v_question
  from public.questions
  where question_id = upper(btrim(p_question_id))
    and question_status = 'PUBLISHED';

  if not found then
    raise exception 'Published master question not found.' using errcode = 'P0001';
  end if;

  if p_occurrence is null or jsonb_typeof(p_occurrence) <> 'object' then
    raise exception 'Occurrence data must be a JSON object.' using errcode = 'P0001';
  end if;

  v_board_id := upper(coalesce(nullif(btrim(p_occurrence ->> 'board_id'), ''), v_question.board_id));
  v_exam_id := upper(coalesce(nullif(btrim(p_occurrence ->> 'exam_id'), ''), v_question.exam_id));
  v_subject_id := upper(coalesce(nullif(btrim(p_occurrence ->> 'subject_id'), ''), v_question.subject_id));
  v_topic_id := upper(coalesce(nullif(btrim(p_occurrence ->> 'topic_id'), ''), v_question.topic_id));
  v_exam_year := coalesce(public.try_parse_integer(p_occurrence ->> 'exam_year'), v_question.exam_year);
  v_exam_date := coalesce(public.try_parse_date(p_occurrence ->> 'exam_date'), v_question.exam_date);
  v_shift_no := coalesce(public.try_parse_integer(p_occurrence ->> 'shift_no'), v_question.shift_no);
  v_paper_code := upper(coalesce(nullif(btrim(p_occurrence ->> 'paper_code'), ''), v_question.paper_code));
  v_original_question_no := coalesce(public.try_parse_integer(p_occurrence ->> 'original_question_no'), v_question.original_question_no);
  v_source_page := coalesce(public.try_parse_integer(p_occurrence ->> 'source_page'), v_question.source_page);
  v_source_question_id := coalesce(nullif(btrim(p_occurrence ->> 'source_question_id'), ''), v_question.source_question_id);
  v_section_code := upper(coalesce(nullif(btrim(p_occurrence ->> 'section_code'), ''), v_question.section_code));
  v_source_record_id := nullif(btrim(p_occurrence ->> 'source_record_id'), '');
  v_external_question_id := upper(nullif(btrim(p_occurrence ->> 'external_question_id'), ''));
  v_supplied_fingerprint := lower(nullif(btrim(p_occurrence ->> 'strict_fingerprint'), ''));

  if p_import_item_id is not null and not exists (
    select 1
    from public.import_batch_items ibi
    where ibi.import_item_id = p_import_item_id
      and (p_import_batch_id is null or ibi.import_batch_id = p_import_batch_id)
  ) then
    raise exception 'Import item does not belong to the supplied import batch.' using errcode = 'P0001';
  end if;

  if p_import_batch_id is not null and p_source_file_id is not null and not exists (
    select 1
    from public.import_batches ib
    where ib.import_batch_id = p_import_batch_id
      and (ib.source_file_id is null or ib.source_file_id = p_source_file_id)
  ) then
    raise exception 'Source file does not match the supplied import batch.' using errcode = 'P0001';
  end if;

  if v_supplied_fingerprint is not null
     and v_supplied_fingerprint <> v_question.content_fingerprint then
    raise exception 'Occurrence fingerprint does not match the selected master question.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.boards where board_id = v_board_id and status = 'ACTIVE'
  ) then
    raise exception 'Active occurrence board not found.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.exams
    where exam_id = v_exam_id and board_id = v_board_id and status = 'ACTIVE'
  ) then
    raise exception 'Occurrence exam does not belong to the selected board.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.subjects
    where subject_id = v_subject_id and exam_id = v_exam_id and status = 'ACTIVE'
  ) then
    raise exception 'Occurrence subject does not belong to the selected exam.' using errcode = 'P0001';
  end if;

  if v_topic_id is not null and not exists (
    select 1 from public.topics
    where topic_id = v_topic_id and subject_id = v_subject_id and status = 'ACTIVE'
  ) then
    raise exception 'Occurrence topic does not belong to the selected subject.' using errcode = 'P0001';
  end if;

  v_occurrence_key := public.build_question_occurrence_key(
    v_board_id,
    v_exam_id,
    v_exam_year,
    v_exam_date,
    v_shift_no,
    v_paper_code,
    v_original_question_no,
    v_source_page,
    v_source_question_id
  );

  if v_occurrence_key is null then
    raise exception 'Insufficient source metadata to create an occurrence key.' using errcode = 'P0001';
  end if;

  select question_id, occurrence_id
  into v_existing_question_id, v_occurrence_id
  from public.question_occurrences
  where occurrence_key = v_occurrence_key;

  if v_existing_question_id is not null then
    if v_existing_question_id <> v_question.question_id then
      raise exception 'This source occurrence is already linked to another master question.' using errcode = 'P0001';
    end if;

    if p_import_item_id is not null then
      update public.import_batch_items
      set matched_question_id = v_question.question_id,
          duplicate_kind = 'SOURCE_OCCURRENCE',
          validation_status = 'LINKED_TO_EXISTING'
      where import_item_id = p_import_item_id;
    end if;

    return jsonb_build_object(
      'occurrence_id', v_occurrence_id,
      'question_id', v_question.question_id,
      'already_linked', true
    );
  end if;

  insert into public.question_occurrences (
    occurrence_key,
    question_id,
    import_batch_id,
    import_item_id,
    source_file_id,
    source_record_id,
    external_question_id,
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
    source_page,
    source_question_id,
    created_by
  ) values (
    v_occurrence_key,
    v_question.question_id,
    p_import_batch_id,
    p_import_item_id,
    p_source_file_id,
    v_source_record_id,
    coalesce(v_external_question_id, v_question.question_id),
    v_board_id,
    v_exam_id,
    v_exam_year,
    v_exam_date,
    v_shift_no,
    v_paper_code,
    v_original_question_no,
    v_subject_id,
    v_topic_id,
    v_section_code,
    v_source_page,
    v_source_question_id,
    v_admin
  )
  on conflict (occurrence_key) do nothing;

  select occurrence_id, question_id
  into v_occurrence_id, v_existing_question_id
  from public.question_occurrences
  where occurrence_key = v_occurrence_key;

  if v_existing_question_id <> v_question.question_id then
    raise exception 'This source occurrence is already linked to another master question.' using errcode = 'P0001';
  end if;

  if p_import_item_id is not null then
    update public.import_batch_items
    set matched_question_id = v_question.question_id,
        duplicate_kind = 'EXACT_CONTENT',
        validation_status = 'LINKED_TO_EXISTING'
    where import_item_id = p_import_item_id;
  end if;

  insert into public.admin_audit_logs (
    admin_user_id,
    action,
    entity_type,
    entity_id,
    details
  ) values (
    v_admin,
    'LINK_QUESTION_OCCURRENCE',
    'QUESTION_OCCURRENCE',
    v_occurrence_id::text,
    jsonb_build_object(
      'question_id', v_question.question_id,
      'import_batch_id', p_import_batch_id,
      'import_item_id', p_import_item_id,
      'source_file_id', p_source_file_id
    )
  );

  return jsonb_build_object(
    'occurrence_id', v_occurrence_id,
    'question_id', v_question.question_id,
    'already_linked', false
  );
end;
$$;

-- Replace publication RPC so Phase 3 metadata and chronology are preserved.
create or replace function public.publish_draft_question(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_draft public.draft_questions%rowtype;
  v_admin uuid := (select auth.uid());
  v_answer_source public.answer_source;
  v_existing_question_id text;
  v_occurrence_key text;
  v_existing_occurrence_question_id text;
  v_import_source_record_id text;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  select * into v_draft
  from public.draft_questions
  where draft_id = p_draft_id
  for update;

  if not found then
    raise exception 'Draft not found.' using errcode = 'P0001';
  end if;

  if v_draft.review_status = 'PUBLISHED' then
    return jsonb_build_object(
      'question_id', v_draft.published_question_id,
      'already_published', true
    );
  end if;

  if v_draft.proposed_question_id is null
     or v_draft.proposed_question_id !~ '^[A-Z0-9]+(?:-[A-Z0-9]+)+$' then
    raise exception 'A valid inherited Question ID is required before publication.' using errcode = 'P0001';
  end if;

  if v_draft.correct_answer is null then
    raise exception 'Correct answer must be verified before publication.' using errcode = 'P0001';
  end if;

  if coalesce(v_draft.options ->> 'A', '') = ''
     or coalesce(v_draft.options ->> 'B', '') = ''
     or coalesce(v_draft.options ->> 'C', '') = ''
     or coalesce(v_draft.options ->> 'D', '') = '' then
    raise exception 'All four options are required before publication.' using errcode = 'P0001';
  end if;

  if v_draft.question_type = 'PYQ'
     and v_draft.content_origin in ('RECONSTRUCTED', 'AI_GENERATED') then
    raise exception 'Reconstructed or AI-generated content cannot be published as an original PYQ.' using errcode = 'P0001';
  end if;

  if v_draft.import_item_id is not null and v_draft.question_type = 'PYQ' then
    if v_draft.exam_id is null
       or v_draft.exam_year is null
       or v_draft.exam_date is null
       or v_draft.shift_no is null
       or nullif(btrim(v_draft.paper_code), '') is null
       or v_draft.original_question_no is null
       or v_draft.source_page is null then
      raise exception 'Imported PYQ source metadata is incomplete. Publication stopped.' using errcode = 'P0001';
    end if;
  end if;

  select q.question_id into v_existing_question_id
  from public.questions q
  where q.question_id = v_draft.proposed_question_id
  limit 1;

  if v_existing_question_id is not null then
    raise exception 'Question ID already exists. Publication stopped to protect the ID system.' using errcode = 'P0001';
  end if;

  select q.question_id into v_existing_question_id
  from public.questions q
  where q.content_fingerprint = v_draft.content_fingerprint
  limit 1;

  if v_existing_question_id is not null then
    raise exception 'Matching master question already exists as %. Link the source occurrence instead of publishing a duplicate.', v_existing_question_id using errcode = 'P0001';
  end if;

  v_answer_source := coalesce(v_draft.answer_source, 'MANUALLY_VERIFIED'::public.answer_source);

  insert into public.questions (
    question_id,
    question_type,
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
    tags,
    sort_order,
    import_batch_id,
    import_item_id,
    content_origin,
    created_by
  ) values (
    v_draft.proposed_question_id,
    v_draft.question_type,
    v_draft.board_id,
    v_draft.exam_id,
    v_draft.exam_year,
    v_draft.exam_date,
    v_draft.shift_no,
    v_draft.paper_code,
    v_draft.original_question_no,
    v_draft.subject_id,
    v_draft.topic_id,
    v_draft.section_code,
    v_draft.language,
    v_draft.difficulty,
    v_draft.question_text,
    v_draft.options,
    v_draft.correct_answer,
    v_draft.explanation,
    v_draft.image_refs,
    v_draft.content_id,
    v_draft.source_file_id,
    v_draft.source_page,
    v_draft.source_question_id,
    v_draft.group_id,
    v_draft.group_type,
    v_draft.group_text,
    v_answer_source,
    'VERIFIED',
    'PUBLISHED',
    v_draft.tags,
    v_draft.sort_order,
    v_draft.import_batch_id,
    v_draft.import_item_id,
    v_draft.content_origin,
    v_admin
  );

  if v_draft.import_item_id is not null then
    select source_record_id into v_import_source_record_id
    from public.import_batch_items
    where import_item_id = v_draft.import_item_id;
  end if;

  if v_draft.question_type = 'PYQ'
     or v_draft.source_file_id is not null
     or v_draft.import_batch_id is not null then
    v_occurrence_key := public.build_question_occurrence_key(
      v_draft.board_id,
      v_draft.exam_id,
      v_draft.exam_year,
      v_draft.exam_date,
      v_draft.shift_no,
      v_draft.paper_code,
      v_draft.original_question_no,
      v_draft.source_page,
      v_draft.source_question_id
    );

    if v_occurrence_key is not null then
      select question_id into v_existing_occurrence_question_id
      from public.question_occurrences
      where occurrence_key = v_occurrence_key;

      if v_existing_occurrence_question_id is not null
         and v_existing_occurrence_question_id <> v_draft.proposed_question_id then
        raise exception 'Source occurrence is already linked to another master question.' using errcode = 'P0001';
      end if;

      insert into public.question_occurrences (
        occurrence_key,
        question_id,
        import_batch_id,
        import_item_id,
        source_file_id,
        source_record_id,
        external_question_id,
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
        source_page,
        source_question_id,
        created_by
      ) values (
        v_occurrence_key,
        v_draft.proposed_question_id,
        v_draft.import_batch_id,
        v_draft.import_item_id,
        v_draft.source_file_id,
        v_import_source_record_id,
        v_draft.proposed_question_id,
        v_draft.board_id,
        v_draft.exam_id,
        v_draft.exam_year,
        v_draft.exam_date,
        v_draft.shift_no,
        v_draft.paper_code,
        v_draft.original_question_no,
        v_draft.subject_id,
        v_draft.topic_id,
        v_draft.section_code,
        v_draft.source_page,
        v_draft.source_question_id,
        v_admin
      )
      on conflict (occurrence_key) do nothing;

      select question_id into v_existing_occurrence_question_id
      from public.question_occurrences
      where occurrence_key = v_occurrence_key;

      if v_existing_occurrence_question_id <> v_draft.proposed_question_id then
        raise exception 'Source occurrence is already linked to another master question.' using errcode = 'P0001';
      end if;
    end if;
  end if;

  update public.draft_questions
  set review_status = 'PUBLISHED',
      question_status = 'PUBLISHED',
      verification_status = 'VERIFIED',
      answer_source = v_answer_source,
      reviewed_by = v_admin,
      reviewed_at = now(),
      published_question_id = v_draft.proposed_question_id
  where draft_id = p_draft_id;

  if v_draft.import_item_id is not null then
    update public.import_batch_items
    set matched_question_id = v_draft.proposed_question_id,
        matched_draft_id = p_draft_id,
        created_draft_id = coalesce(created_draft_id, p_draft_id)
    where import_item_id = v_draft.import_item_id;
  end if;

  if v_draft.import_batch_id is not null then
    update public.import_batches
    set total_published = total_published + 1
    where import_batch_id = v_draft.import_batch_id;
  end if;

  insert into public.admin_audit_logs (
    admin_user_id,
    action,
    entity_type,
    entity_id,
    details
  ) values (
    v_admin,
    'PUBLISH_DRAFT',
    'QUESTION',
    v_draft.proposed_question_id,
    jsonb_build_object(
      'draft_id', p_draft_id,
      'import_item_id', v_draft.import_item_id,
      'content_fingerprint', v_draft.content_fingerprint,
      'occurrence_key', v_occurrence_key
    )
  );

  return jsonb_build_object(
    'question_id', v_draft.proposed_question_id,
    'already_published', false,
    'content_fingerprint', v_draft.content_fingerprint,
    'occurrence_key', v_occurrence_key
  );
exception
  when unique_violation then
    raise exception 'Duplicate Question ID, content fingerprint, import item or source occurrence detected. Publication stopped.' using errcode = 'P0001';
end;
$$;

-- RLS for new reconciliation tables.
alter table public.import_batch_items enable row level security;
alter table public.question_occurrences enable row level security;

create policy import_batch_items_admin_all
on public.import_batch_items
for all to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()));

create policy question_occurrences_admin_all
on public.question_occurrences
for all to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()));

-- Explicit privileges. RLS remains the final authorization layer.
revoke all on public.import_batch_items, public.question_occurrences from anon, authenticated;

grant select, insert, update, delete
on public.import_batch_items, public.question_occurrences
to authenticated;

-- Internal helpers are not browser APIs.
revoke all on function public.try_parse_integer(text) from public, anon, authenticated;
revoke all on function public.try_parse_date(text) from public, anon, authenticated;
revoke all on function public.normalize_import_text(text, boolean) from public, anon, authenticated;
revoke all on function public.build_question_fingerprints(text, text, jsonb) from public, anon, authenticated;
revoke all on function public.build_question_occurrence_key(text, text, integer, date, integer, text, integer, integer, text) from public, anon, authenticated;
revoke all on function public.set_question_fingerprints() from public, anon, authenticated;
revoke all on function public.enforce_question_occurrence_integrity() from public, anon, authenticated;

-- Admin-facing RPCs are granted to authenticated users but enforce is_admin() internally.
revoke all on function public.validate_import_package(jsonb, text, text) from public, anon, authenticated;
revoke all on function public.validate_import_question(jsonb) from public, anon, authenticated;
revoke all on function public.link_question_occurrence(text, jsonb, uuid, uuid, uuid) from public, anon, authenticated;

grant execute on function public.validate_import_package(jsonb, text, text) to authenticated;
grant execute on function public.validate_import_question(jsonb) to authenticated;
grant execute on function public.link_question_occurrence(text, jsonb, uuid, uuid, uuid) to authenticated;

-- Keep the revised publication RPC available only to authenticated users; it checks admin role.
revoke all on function public.publish_draft_question(uuid) from public, anon, authenticated;
grant execute on function public.publish_draft_question(uuid) to authenticated;

comment on table public.import_batch_items is
  'Persistent item-level validation, duplicate and reconciliation record for every HTML import question.';

comment on table public.question_occurrences is
  'Authentic source appearances of one deduplicated master question across papers and shifts.';

comment on column public.questions.content_fingerprint is
  'Server-generated strict SHA-256 fingerprint over language, question text and ordered options A-D.';

comment on column public.questions.loose_fingerprint is
  'Server-generated warning-only fingerprint that tolerates punctuation and option-order differences.';

comment on column public.draft_questions.sort_order is
  'Original source chronology preserved through draft review and publication.';

commit;
