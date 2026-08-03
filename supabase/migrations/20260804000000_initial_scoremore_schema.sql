-- ScoreMore initial Supabase schema
-- Date: 2026-08-04
-- Purpose: GSSSB CCE vertical slice with mandatory draft-review-publish.

begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create type public.user_role as enum ('STUDENT', 'ADMIN');
create type public.entity_status as enum ('ACTIVE', 'INACTIVE', 'ARCHIVED');
create type public.question_type as enum ('NORMAL', 'PYQ');
create type public.question_status as enum ('DRAFT', 'REVIEWED', 'PUBLISHED', 'DISPUTED', 'CANCELLED', 'CORRECTED', 'ARCHIVED');
create type public.review_status as enum ('PENDING', 'IN_REVIEW', 'REJECTED', 'PUBLISHED');
create type public.verification_status as enum ('UNVERIFIED', 'NEEDS_CHECK', 'VERIFIED', 'DISPUTED');
create type public.answer_source as enum ('OFFICIAL_FINAL_KEY', 'OFFICIAL_PROVISIONAL_KEY', 'MANUALLY_VERIFIED', 'SOURCE_BOOK', 'ADMIN_CORRECTED');
create type public.test_status as enum ('DRAFT', 'PUBLISHED', 'ARCHIVED');
create type public.test_type as enum ('PYQ_FULL', 'PYQ_SECTIONAL', 'TOPIC_PRACTICE', 'FULL_MOCK', 'SECTIONAL_MOCK', 'DAILY_QUIZ', 'BOOKMARK_REVISION', 'MISTAKE_REVISION', 'PERSONALIZED_TEST');
create type public.selection_mode as enum ('FIXED_PAPER', 'FIXED_QUESTION_LIST', 'FILTERED', 'RULE_BASED', 'RANDOMIZED', 'PERSONALIZED');
create type public.attempt_status as enum ('IN_PROGRESS', 'SUBMITTED', 'AUTO_SUBMITTED', 'ABANDONED');
create type public.access_status as enum ('ACTIVE', 'EXPIRED', 'REVOKED');
create type public.payment_status as enum ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED');

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  mobile text,
  role public.user_role not null default 'STUDENT',
  target_board_id text,
  target_exam_id text,
  language text not null default 'GUJARATI',
  status public.entity_status not null default 'ACTIVE',
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.boards (
  board_id text primary key,
  board_name text not null,
  board_code text not null unique,
  description text,
  status public.entity_status not null default 'ACTIVE',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.exams (
  exam_id text primary key,
  board_id text not null references public.boards(board_id),
  exam_name text not null,
  exam_code text not null,
  description text,
  status public.entity_status not null default 'ACTIVE',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (board_id, exam_code)
);

alter table public.profiles
  add constraint profiles_target_board_fk foreign key (target_board_id) references public.boards(board_id),
  add constraint profiles_target_exam_fk foreign key (target_exam_id) references public.exams(exam_id);

create table public.subjects (
  subject_id text primary key,
  exam_id text not null references public.exams(exam_id),
  subject_name text not null,
  subject_code text not null,
  description text,
  status public.entity_status not null default 'ACTIVE',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (exam_id, subject_code)
);

create table public.topics (
  topic_id text primary key,
  subject_id text not null references public.subjects(subject_id),
  topic_name text not null,
  topic_code text not null,
  description text,
  status public.entity_status not null default 'ACTIVE',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (subject_id, topic_code)
);

create table public.app_settings (
  setting_key text primary key,
  setting_value text not null,
  description text,
  is_public boolean not null default false,
  updated_by uuid references public.profiles(user_id),
  updated_at timestamptz not null default now()
);

create table public.packages (
  package_id text primary key,
  exam_id text references public.exams(exam_id),
  package_name text not null,
  description text,
  price numeric(12,2) not null default 0 check (price >= 0),
  validity_days integer check (validity_days is null or validity_days > 0),
  status public.entity_status not null default 'ACTIVE',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.package_access (
  access_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  package_id text not null references public.packages(package_id),
  access_status public.access_status not null default 'ACTIVE',
  access_source text not null default 'ADMIN',
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  granted_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, package_id, starts_at)
);

create table public.payments (
  payment_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id),
  package_id text references public.packages(package_id),
  provider text,
  provider_payment_id text,
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'INR',
  status public.payment_status not null default 'PENDING',
  metadata jsonb not null default '{}'::jsonb,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.source_files (
  source_file_id uuid primary key default gen_random_uuid(),
  storage_bucket text not null,
  storage_path text not null unique,
  original_file_name text not null,
  mime_type text,
  file_size_bytes bigint check (file_size_bytes is null or file_size_bytes >= 0),
  checksum_sha256 text,
  uploaded_by uuid not null references public.profiles(user_id),
  created_at timestamptz not null default now()
);

create table public.import_batches (
  import_batch_id uuid primary key default gen_random_uuid(),
  import_method text not null,
  source_type text,
  source_file_id uuid references public.source_files(source_file_id),
  board_id text references public.boards(board_id),
  exam_id text references public.exams(exam_id),
  exam_year integer,
  exam_date date,
  shift_no integer,
  subject_id text references public.subjects(subject_id),
  section_code text,
  paper_code text,
  total_raw integer not null default 0,
  total_extracted integer not null default 0,
  total_draft integer not null default 0,
  total_published integer not null default 0,
  status text not null default 'CREATED',
  metadata_version text,
  remarks text,
  created_by uuid not null references public.profiles(user_id),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.questions (
  question_id text primary key,
  question_type public.question_type not null,
  board_id text not null references public.boards(board_id),
  exam_id text references public.exams(exam_id),
  exam_year integer,
  exam_date date,
  shift_no integer,
  paper_code text,
  original_question_no integer,
  subject_id text not null references public.subjects(subject_id),
  topic_id text references public.topics(topic_id),
  section_code text,
  language text not null,
  difficulty text not null default 'MEDIUM' check (difficulty in ('EASY', 'MEDIUM', 'HARD')),
  question_text text not null,
  options jsonb not null,
  correct_answer text not null check (correct_answer in ('A', 'B', 'C', 'D')),
  explanation text,
  image_refs jsonb not null default '[]'::jsonb,
  content_id text,
  source_file_id uuid references public.source_files(source_file_id),
  source_page integer,
  source_question_id text,
  group_id text,
  group_type text,
  group_text text,
  answer_source public.answer_source,
  verification_status public.verification_status not null default 'UNVERIFIED',
  question_status public.question_status not null default 'PUBLISHED',
  tags text[] not null default '{}',
  sort_order integer,
  import_batch_id uuid references public.import_batches(import_batch_id),
  created_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint questions_options_object check (jsonb_typeof(options) = 'object'),
  constraint questions_option_keys check (options ?& array['A','B','C','D']),
  constraint questions_id_format check (question_id ~ '^[A-Z0-9]+(?:-[A-Z0-9]+)+$')
);

create table public.question_content (
  content_id text primary key,
  question_id text not null unique references public.questions(question_id) on delete cascade,
  hint text,
  formula text,
  image_ref text,
  ai_explanation text,
  notes text,
  related_concept text,
  revision_tag text,
  created_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.draft_questions (
  draft_id uuid primary key default gen_random_uuid(),
  import_batch_id uuid references public.import_batches(import_batch_id),
  question_type public.question_type not null,
  proposed_question_id text,
  board_id text not null references public.boards(board_id),
  exam_id text references public.exams(exam_id),
  exam_year integer,
  exam_date date,
  shift_no integer,
  paper_code text,
  original_question_no integer,
  subject_id text not null references public.subjects(subject_id),
  topic_id text references public.topics(topic_id),
  section_code text,
  language text not null,
  difficulty text not null default 'MEDIUM' check (difficulty in ('EASY', 'MEDIUM', 'HARD')),
  question_text text not null,
  options jsonb not null,
  correct_answer text check (correct_answer is null or correct_answer in ('A', 'B', 'C', 'D')),
  explanation text,
  image_refs jsonb not null default '[]'::jsonb,
  content_id text,
  source_file_id uuid references public.source_files(source_file_id),
  source_page integer,
  source_question_id text,
  group_id text,
  group_type text,
  group_text text,
  answer_source public.answer_source,
  verification_status public.verification_status not null default 'UNVERIFIED',
  question_status public.question_status not null default 'DRAFT',
  review_status public.review_status not null default 'PENDING',
  admin_notes text,
  tags text[] not null default '{}',
  created_by uuid not null references public.profiles(user_id),
  reviewed_by uuid references public.profiles(user_id),
  published_question_id text references public.questions(question_id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint draft_options_object check (jsonb_typeof(options) = 'object'),
  constraint draft_option_keys check (options ?& array['A','B','C','D']),
  constraint draft_proposed_id_format check (proposed_question_id is null or proposed_question_id ~ '^[A-Z0-9]+(?:-[A-Z0-9]+)+$')
);

create table public.tests (
  test_id text primary key,
  board_id text not null references public.boards(board_id),
  exam_id text not null references public.exams(exam_id),
  subject_id text references public.subjects(subject_id),
  topic_id text references public.topics(topic_id),
  package_id text references public.packages(package_id),
  test_name text not null,
  test_type public.test_type not null,
  selection_mode public.selection_mode not null,
  question_count integer not null check (question_count > 0),
  duration_minutes integer not null default 0 check (duration_minutes >= 0),
  marks_per_question numeric(8,3) not null default 1,
  negative_marks numeric(8,3) not null default 0 check (negative_marks >= 0),
  status public.test_status not null default 'DRAFT',
  is_free boolean not null default true,
  sort_order integer not null default 0,
  exam_year integer,
  exam_date date,
  shift_no integer,
  paper_code text,
  section_code text,
  question_filter jsonb not null default '{}'::jsonb,
  source_file_id uuid references public.source_files(source_file_id),
  created_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.test_question_links (
  test_id text not null references public.tests(test_id) on delete cascade,
  question_id text not null references public.questions(question_id),
  position integer not null check (position > 0),
  primary key (test_id, question_id),
  unique (test_id, position)
);

create table public.attempts (
  attempt_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  test_id text not null references public.tests(test_id),
  status public.attempt_status not null default 'IN_PROGRESS',
  total_questions integer not null default 0,
  attempted integer not null default 0,
  correct integer not null default 0,
  wrong integer not null default 0,
  skipped integer not null default 0,
  score numeric(12,3) not null default 0,
  accuracy numeric(7,3) not null default 0,
  time_taken_seconds integer not null default 0,
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index attempts_one_in_progress_per_test
  on public.attempts(user_id, test_id)
  where status = 'IN_PROGRESS';

create table public.attempt_questions (
  attempt_id uuid not null references public.attempts(attempt_id) on delete cascade,
  question_id text not null references public.questions(question_id),
  position integer not null check (position > 0),
  primary key (attempt_id, question_id),
  unique (attempt_id, position)
);

create table public.attempt_answers (
  answer_id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.attempts(attempt_id) on delete cascade,
  question_id text not null references public.questions(question_id),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  selected_answer text check (selected_answer is null or selected_answer in ('A', 'B', 'C', 'D')),
  correct_answer text check (correct_answer is null or correct_answer in ('A', 'B', 'C', 'D')),
  is_correct boolean,
  time_taken_seconds integer not null default 0 check (time_taken_seconds >= 0),
  marked_review boolean not null default false,
  answered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (attempt_id, question_id)
);

create table public.bookmarks (
  bookmark_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  question_id text not null references public.questions(question_id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, question_id)
);

create table public.mistake_book (
  mistake_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  question_id text not null references public.questions(question_id) on delete cascade,
  latest_attempt_id uuid references public.attempts(attempt_id) on delete set null,
  mistake_count integer not null default 1 check (mistake_count > 0),
  resolved boolean not null default false,
  last_mistake_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, question_id)
);

create table public.rank_snapshots (
  rank_snapshot_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  exam_id text not null references public.exams(exam_id),
  total_attempts integer not null default 0,
  average_score numeric(12,3) not null default 0,
  average_accuracy numeric(7,3) not null default 0,
  average_time_per_question numeric(12,3) not null default 0,
  strong_subject_id text references public.subjects(subject_id),
  weak_subject_id text references public.subjects(subject_id),
  percentile numeric(7,3),
  predicted_rank integer,
  improvement_trend numeric(12,3),
  exam_readiness_score numeric(7,3),
  created_at timestamptz not null default now()
);

create table public.admin_audit_logs (
  audit_id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references public.profiles(user_id),
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Performance indexes
create index profiles_role_idx on public.profiles(role);
create index exams_board_idx on public.exams(board_id, status, sort_order);
create index subjects_exam_idx on public.subjects(exam_id, status, sort_order);
create index topics_subject_idx on public.topics(subject_id, status, sort_order);
create index questions_catalogue_idx on public.questions(board_id, exam_id, question_type, question_status);
create index questions_pyq_filter_idx on public.questions(exam_year, exam_date, shift_no, paper_code, section_code);
create index questions_subject_topic_idx on public.questions(subject_id, topic_id, difficulty);
create index questions_import_batch_idx on public.questions(import_batch_id);
create index draft_review_idx on public.draft_questions(review_status, created_at desc);
create index draft_import_idx on public.draft_questions(import_batch_id);
create index tests_catalogue_idx on public.tests(status, test_type, board_id, exam_id, sort_order);
create index attempts_user_status_idx on public.attempts(user_id, status, started_at desc);
create index attempt_questions_position_idx on public.attempt_questions(attempt_id, position);
create index attempt_answers_user_idx on public.attempt_answers(user_id, attempt_id);
create index package_access_user_idx on public.package_access(user_id, access_status, expires_at);
create index payments_user_idx on public.payments(user_id, created_at desc);
create index bookmarks_user_idx on public.bookmarks(user_id, created_at desc);
create index mistake_book_user_idx on public.mistake_book(user_id, resolved, last_mistake_at desc);
create index rank_snapshots_user_idx on public.rank_snapshots(user_id, exam_id, created_at desc);

-- Updated-at helper
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger boards_set_updated_at before update on public.boards for each row execute function public.set_updated_at();
create trigger exams_set_updated_at before update on public.exams for each row execute function public.set_updated_at();
create trigger subjects_set_updated_at before update on public.subjects for each row execute function public.set_updated_at();
create trigger topics_set_updated_at before update on public.topics for each row execute function public.set_updated_at();
create trigger packages_set_updated_at before update on public.packages for each row execute function public.set_updated_at();
create trigger package_access_set_updated_at before update on public.package_access for each row execute function public.set_updated_at();
create trigger payments_set_updated_at before update on public.payments for each row execute function public.set_updated_at();
create trigger questions_set_updated_at before update on public.questions for each row execute function public.set_updated_at();
create trigger question_content_set_updated_at before update on public.question_content for each row execute function public.set_updated_at();
create trigger drafts_set_updated_at before update on public.draft_questions for each row execute function public.set_updated_at();
create trigger tests_set_updated_at before update on public.tests for each row execute function public.set_updated_at();
create trigger attempts_set_updated_at before update on public.attempts for each row execute function public.set_updated_at();
create trigger attempt_answers_set_updated_at before update on public.attempt_answers for each row execute function public.set_updated_at();
create trigger mistake_book_set_updated_at before update on public.mistake_book for each row execute function public.set_updated_at();

-- Create a profile for every Auth user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'full_name', 'Student'))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Database-owned admin check. User-editable metadata is never used for authorization.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where user_id = (select auth.uid())
      and role = 'ADMIN'
      and status = 'ACTIVE'
  );
$$;

-- Dynamic public statistics.
create or replace function public.get_public_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'published_questions', (select count(*) from public.questions where question_status = 'PUBLISHED'),
    'pyq_papers', (select count(distinct concat_ws('|', exam_id, exam_year, exam_date, shift_no, paper_code)) from public.questions where question_type = 'PYQ' and question_status = 'PUBLISHED'),
    'published_tests', (select count(*) from public.tests where status = 'PUBLISHED'),
    'student_attempts', (select count(*) from public.attempts where status in ('SUBMITTED', 'AUTO_SUBMITTED'))
  );
$$;

-- Create or resume an attempt and materialize only references to master questions.
create or replace function public.create_test_attempt(p_test_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_test public.tests%rowtype;
  v_attempt_id uuid;
  v_filter jsonb;
  v_total integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = 'P0001';
  end if;

  select * into v_test
  from public.tests
  where test_id = p_test_id and status = 'PUBLISHED';

  if not found then
    raise exception 'Published test not found.' using errcode = 'P0001';
  end if;

  if not v_test.is_free then
    if v_test.package_id is null or not exists (
      select 1 from public.package_access pa
      where pa.user_id = v_user_id
        and pa.package_id = v_test.package_id
        and pa.access_status = 'ACTIVE'
        and pa.starts_at <= now()
        and (pa.expires_at is null or pa.expires_at > now())
    ) then
      raise exception 'This test requires active package access.' using errcode = 'P0001';
    end if;
  end if;

  select attempt_id into v_attempt_id
  from public.attempts
  where user_id = v_user_id
    and test_id = p_test_id
    and status = 'IN_PROGRESS'
  order by started_at desc
  limit 1;

  if v_attempt_id is not null then
    return jsonb_build_object('attempt_id', v_attempt_id, 'resumed', true);
  end if;

  insert into public.attempts (user_id, test_id)
  values (v_user_id, p_test_id)
  returning attempt_id into v_attempt_id;

  if v_test.selection_mode = 'FIXED_QUESTION_LIST' then
    insert into public.attempt_questions (attempt_id, question_id, position)
    select v_attempt_id, link.question_id, row_number() over (order by link.position)::integer
    from public.test_question_links link
    join public.questions q on q.question_id = link.question_id
    where link.test_id = p_test_id
      and q.question_status = 'PUBLISHED'
    order by link.position
    limit v_test.question_count;
  else
    v_filter := coalesce(v_test.question_filter, '{}'::jsonb);

    if v_test.selection_mode in ('RANDOMIZED', 'PERSONALIZED') then
      insert into public.attempt_questions (attempt_id, question_id, position)
      select v_attempt_id, selected.question_id, selected.position
      from (
        select q.question_id, row_number() over (order by random())::integer as position
        from public.questions q
        where q.question_status = 'PUBLISHED'
          and (v_filter ->> 'question_type' is null or q.question_type::text = v_filter ->> 'question_type')
          and (v_filter ->> 'board_id' is null or q.board_id = v_filter ->> 'board_id')
          and (v_filter ->> 'exam_id' is null or q.exam_id = v_filter ->> 'exam_id')
          and (v_filter ->> 'subject_id' is null or q.subject_id = v_filter ->> 'subject_id')
          and (v_filter ->> 'topic_id' is null or q.topic_id = v_filter ->> 'topic_id')
          and (v_filter ->> 'exam_year' is null or q.exam_year = (v_filter ->> 'exam_year')::integer)
          and (v_filter ->> 'exam_date' is null or q.exam_date = (v_filter ->> 'exam_date')::date)
          and (v_filter ->> 'shift_no' is null or q.shift_no = (v_filter ->> 'shift_no')::integer)
          and (v_filter ->> 'paper_code' is null or q.paper_code = v_filter ->> 'paper_code')
          and (v_filter ->> 'section_code' is null or q.section_code = v_filter ->> 'section_code')
          and (v_filter ->> 'difficulty' is null or q.difficulty = v_filter ->> 'difficulty')
        limit v_test.question_count
      ) selected;
    else
      insert into public.attempt_questions (attempt_id, question_id, position)
      select v_attempt_id, selected.question_id, selected.position
      from (
        select q.question_id,
               row_number() over (
                 order by coalesce(q.original_question_no, q.sort_order, 2147483647), q.question_id
               )::integer as position
        from public.questions q
        where q.question_status = 'PUBLISHED'
          and (v_filter ->> 'question_type' is null or q.question_type::text = v_filter ->> 'question_type')
          and (v_filter ->> 'board_id' is null or q.board_id = v_filter ->> 'board_id')
          and (v_filter ->> 'exam_id' is null or q.exam_id = v_filter ->> 'exam_id')
          and (v_filter ->> 'subject_id' is null or q.subject_id = v_filter ->> 'subject_id')
          and (v_filter ->> 'topic_id' is null or q.topic_id = v_filter ->> 'topic_id')
          and (v_filter ->> 'exam_year' is null or q.exam_year = (v_filter ->> 'exam_year')::integer)
          and (v_filter ->> 'exam_date' is null or q.exam_date = (v_filter ->> 'exam_date')::date)
          and (v_filter ->> 'shift_no' is null or q.shift_no = (v_filter ->> 'shift_no')::integer)
          and (v_filter ->> 'paper_code' is null or q.paper_code = v_filter ->> 'paper_code')
          and (v_filter ->> 'section_code' is null or q.section_code = v_filter ->> 'section_code')
          and (v_filter ->> 'difficulty' is null or q.difficulty = v_filter ->> 'difficulty')
        limit v_test.question_count
      ) selected;
    end if;
  end if;

  select count(*) into v_total from public.attempt_questions where attempt_id = v_attempt_id;
  if v_total = 0 then
    delete from public.attempts where attempt_id = v_attempt_id;
    raise exception 'No published questions match this test configuration.' using errcode = 'P0001';
  end if;

  update public.attempts set total_questions = v_total where attempt_id = v_attempt_id;
  return jsonb_build_object('attempt_id', v_attempt_id, 'resumed', false, 'total_questions', v_total);
end;
$$;

-- Protected batch loader: no correct answer or explanation is returned.
create or replace function public.get_attempt_questions(
  p_attempt_id uuid,
  p_offset integer default 0,
  p_limit integer default 10
)
returns table (
  position integer,
  question_id text,
  subject_id text,
  subject_name text,
  section_code text,
  difficulty text,
  question_text text,
  options jsonb,
  image_refs jsonb,
  selected_answer text,
  marked_review boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.attempts a
    where a.attempt_id = p_attempt_id
      and a.user_id = (select auth.uid())
  ) then
    raise exception 'Attempt not found or access denied.' using errcode = 'P0001';
  end if;

  return query
  select aq.position, q.question_id, q.subject_id, s.subject_name, q.section_code,
         q.difficulty, q.question_text, q.options, q.image_refs,
         aa.selected_answer, coalesce(aa.marked_review, false)
  from public.attempt_questions aq
  join public.questions q on q.question_id = aq.question_id
  join public.subjects s on s.subject_id = q.subject_id
  left join public.attempt_answers aa
    on aa.attempt_id = aq.attempt_id and aa.question_id = aq.question_id
  where aq.attempt_id = p_attempt_id
  order by aq.position
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 10), 1), 50);
end;
$$;

-- Protected answer upsert. The browser cannot write scoring or ownership columns.
create or replace function public.save_attempt_answer(
  p_attempt_id uuid,
  p_question_id text,
  p_selected_answer text default null,
  p_marked_review boolean default false,
  p_time_taken_seconds integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_answer_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = 'P0001';
  end if;

  if p_selected_answer is not null and p_selected_answer not in ('A', 'B', 'C', 'D') then
    raise exception 'Selected answer must be A, B, C or D.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.attempts a
    join public.attempt_questions aq on aq.attempt_id = a.attempt_id
    where a.attempt_id = p_attempt_id
      and a.user_id = v_user_id
      and a.status = 'IN_PROGRESS'
      and aq.question_id = p_question_id
  ) then
    raise exception 'Attempt question not found or attempt is not editable.' using errcode = 'P0001';
  end if;

  insert into public.attempt_answers (
    attempt_id, question_id, user_id, selected_answer,
    time_taken_seconds, marked_review, answered_at
  ) values (
    p_attempt_id, p_question_id, v_user_id, p_selected_answer,
    greatest(coalesce(p_time_taken_seconds, 0), 0), coalesce(p_marked_review, false), now()
  )
  on conflict (attempt_id, question_id)
  do update set
    selected_answer = excluded.selected_answer,
    time_taken_seconds = greatest(public.attempt_answers.time_taken_seconds, excluded.time_taken_seconds),
    marked_review = excluded.marked_review,
    answered_at = now(),
    updated_at = now()
  returning answer_id into v_answer_id;

  return jsonb_build_object(
    'answer_id', v_answer_id,
    'selected_answer', p_selected_answer,
    'marked_review', coalesce(p_marked_review, false),
    'answered_at', now()
  );
end;
$$;

-- Final server-side scoring.
create or replace function public.submit_test_attempt(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_attempt public.attempts%rowtype;
  v_test public.tests%rowtype;
  v_attempted integer;
  v_correct integer;
  v_wrong integer;
  v_skipped integer;
  v_score numeric(12,3);
  v_accuracy numeric(7,3);
  v_time integer;
begin
  select * into v_attempt
  from public.attempts
  where attempt_id = p_attempt_id and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Attempt not found or access denied.' using errcode = 'P0001';
  end if;

  if v_attempt.status <> 'IN_PROGRESS' then
    return jsonb_build_object(
      'attempt_id', v_attempt.attempt_id,
      'status', v_attempt.status,
      'score', v_attempt.score,
      'accuracy', v_attempt.accuracy,
      'correct', v_attempt.correct,
      'wrong', v_attempt.wrong,
      'skipped', v_attempt.skipped
    );
  end if;

  select * into v_test from public.tests where test_id = v_attempt.test_id;

  update public.attempt_answers aa
  set correct_answer = q.correct_answer,
      is_correct = (aa.selected_answer = q.correct_answer),
      updated_at = now()
  from public.questions q
  where aa.attempt_id = p_attempt_id
    and aa.question_id = q.question_id;

  select
    count(*) filter (where aa.selected_answer is not null),
    count(*) filter (where aa.selected_answer is not null and aa.is_correct is true),
    count(*) filter (where aa.selected_answer is not null and aa.is_correct is false),
    count(*) filter (where aa.selected_answer is null)
  into v_attempted, v_correct, v_wrong, v_skipped
  from public.attempt_questions aq
  left join public.attempt_answers aa
    on aa.attempt_id = aq.attempt_id and aa.question_id = aq.question_id
  where aq.attempt_id = p_attempt_id;

  v_score := (v_correct * v_test.marks_per_question) - (v_wrong * v_test.negative_marks);
  v_accuracy := case when v_attempted = 0 then 0 else round((v_correct::numeric / v_attempted::numeric) * 100, 3) end;
  v_time := greatest(0, extract(epoch from (now() - v_attempt.started_at))::integer);

  update public.attempts
  set status = 'SUBMITTED',
      attempted = v_attempted,
      correct = v_correct,
      wrong = v_wrong,
      skipped = v_skipped,
      score = v_score,
      accuracy = v_accuracy,
      time_taken_seconds = v_time,
      submitted_at = now()
  where attempt_id = p_attempt_id;

  insert into public.mistake_book (user_id, question_id, latest_attempt_id, mistake_count, resolved, last_mistake_at)
  select v_user_id, aa.question_id, p_attempt_id, 1, false, now()
  from public.attempt_answers aa
  where aa.attempt_id = p_attempt_id and aa.is_correct is false
  on conflict (user_id, question_id)
  do update set
    latest_attempt_id = excluded.latest_attempt_id,
    mistake_count = public.mistake_book.mistake_count + 1,
    resolved = false,
    last_mistake_at = now(),
    updated_at = now();

  return jsonb_build_object(
    'attempt_id', p_attempt_id,
    'status', 'SUBMITTED',
    'score', v_score,
    'accuracy', v_accuracy,
    'attempted', v_attempted,
    'correct', v_correct,
    'wrong', v_wrong,
    'skipped', v_skipped,
    'time_taken_seconds', v_time
  );
end;
$$;

-- Review data is available only after submission.
create or replace function public.get_attempt_review(
  p_attempt_id uuid,
  p_offset integer default 0,
  p_limit integer default 25
)
returns table (
  position integer,
  question_id text,
  question_text text,
  options jsonb,
  selected_answer text,
  correct_answer text,
  is_correct boolean,
  explanation text,
  subject_id text,
  topic_id text,
  difficulty text,
  time_taken_seconds integer,
  marked_review boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.attempts a
    where a.attempt_id = p_attempt_id
      and a.user_id = (select auth.uid())
      and a.status in ('SUBMITTED', 'AUTO_SUBMITTED')
  ) then
    raise exception 'Review is available only for your submitted attempt.' using errcode = 'P0001';
  end if;

  return query
  select aq.position, q.question_id, q.question_text, q.options,
         aa.selected_answer, q.correct_answer, aa.is_correct,
         q.explanation, q.subject_id, q.topic_id, q.difficulty,
         coalesce(aa.time_taken_seconds, 0), coalesce(aa.marked_review, false)
  from public.attempt_questions aq
  join public.questions q on q.question_id = aq.question_id
  left join public.attempt_answers aa
    on aa.attempt_id = aq.attempt_id and aa.question_id = aq.question_id
  where aq.attempt_id = p_attempt_id
  order by aq.position
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 25), 1), 100);
end;
$$;

-- Human-reviewed publication only.
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
    return jsonb_build_object('question_id', v_draft.published_question_id, 'already_published', true);
  end if;

  if v_draft.proposed_question_id is null or v_draft.proposed_question_id !~ '^[A-Z0-9]+(?:-[A-Z0-9]+)+$' then
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

  v_answer_source := coalesce(v_draft.answer_source, 'MANUALLY_VERIFIED'::public.answer_source);

  insert into public.questions (
    question_id, question_type, board_id, exam_id, exam_year, exam_date, shift_no,
    paper_code, original_question_no, subject_id, topic_id, section_code, language,
    difficulty, question_text, options, correct_answer, explanation, image_refs,
    content_id, source_file_id, source_page, source_question_id, group_id, group_type,
    group_text, answer_source, verification_status, question_status, tags,
    import_batch_id, created_by
  ) values (
    v_draft.proposed_question_id, v_draft.question_type, v_draft.board_id, v_draft.exam_id,
    v_draft.exam_year, v_draft.exam_date, v_draft.shift_no, v_draft.paper_code,
    v_draft.original_question_no, v_draft.subject_id, v_draft.topic_id, v_draft.section_code,
    v_draft.language, v_draft.difficulty, v_draft.question_text, v_draft.options,
    v_draft.correct_answer, v_draft.explanation, v_draft.image_refs, v_draft.content_id,
    v_draft.source_file_id, v_draft.source_page, v_draft.source_question_id, v_draft.group_id,
    v_draft.group_type, v_draft.group_text, v_answer_source, 'VERIFIED', 'PUBLISHED',
    v_draft.tags, v_draft.import_batch_id, v_admin
  );

  update public.draft_questions
  set review_status = 'PUBLISHED',
      question_status = 'PUBLISHED',
      verification_status = 'VERIFIED',
      answer_source = v_answer_source,
      reviewed_by = v_admin,
      reviewed_at = now(),
      published_question_id = v_draft.proposed_question_id
  where draft_id = p_draft_id;

  if v_draft.import_batch_id is not null then
    update public.import_batches
    set total_published = total_published + 1
    where import_batch_id = v_draft.import_batch_id;
  end if;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (v_admin, 'PUBLISH_DRAFT', 'QUESTION', v_draft.proposed_question_id, jsonb_build_object('draft_id', p_draft_id));

  return jsonb_build_object('question_id', v_draft.proposed_question_id, 'already_published', false);
exception
  when unique_violation then
    raise exception 'Question ID already exists. Publication stopped to protect the ID system.' using errcode = 'P0001';
end;
$$;

create or replace function public.reject_draft_question(p_draft_id uuid, p_notes text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  update public.draft_questions
  set review_status = 'REJECTED',
      question_status = 'DRAFT',
      admin_notes = nullif(trim(p_notes), ''),
      reviewed_by = v_admin,
      reviewed_at = now()
  where draft_id = p_draft_id and review_status <> 'PUBLISHED';

  if not found then
    raise exception 'Draft not found or already published.' using errcode = 'P0001';
  end if;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (v_admin, 'REJECT_DRAFT', 'DRAFT_QUESTION', p_draft_id::text, jsonb_build_object('notes', p_notes));

  return jsonb_build_object('draft_id', p_draft_id, 'review_status', 'REJECTED');
end;
$$;

-- Storage bucket for source PDFs/images. Private by default.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'source-documents',
  'source-documents',
  false,
  52428800,
  array['application/pdf','image/png','image/jpeg','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Enable RLS on every exposed table.
alter table public.profiles enable row level security;
alter table public.boards enable row level security;
alter table public.exams enable row level security;
alter table public.subjects enable row level security;
alter table public.topics enable row level security;
alter table public.app_settings enable row level security;
alter table public.packages enable row level security;
alter table public.package_access enable row level security;
alter table public.payments enable row level security;
alter table public.source_files enable row level security;
alter table public.import_batches enable row level security;
alter table public.questions enable row level security;
alter table public.question_content enable row level security;
alter table public.draft_questions enable row level security;
alter table public.tests enable row level security;
alter table public.test_question_links enable row level security;
alter table public.attempts enable row level security;
alter table public.attempt_questions enable row level security;
alter table public.attempt_answers enable row level security;
alter table public.bookmarks enable row level security;
alter table public.mistake_book enable row level security;
alter table public.rank_snapshots enable row level security;
alter table public.admin_audit_logs enable row level security;

-- Public read policies.
create policy app_settings_public_read on public.app_settings for select to anon, authenticated using (is_public = true);
create policy boards_public_read on public.boards for select to anon, authenticated using (status = 'ACTIVE');
create policy exams_public_read on public.exams for select to anon, authenticated using (status = 'ACTIVE');
create policy subjects_public_read on public.subjects for select to anon, authenticated using (status = 'ACTIVE');
create policy topics_public_read on public.topics for select to anon, authenticated using (status = 'ACTIVE');
create policy tests_public_read on public.tests for select to anon, authenticated using (status = 'PUBLISHED');
create policy packages_public_read on public.packages for select to anon, authenticated using (status = 'ACTIVE');

-- Profile policies.
create policy profiles_own_read on public.profiles for select to authenticated using ((select auth.uid()) = user_id);
create policy profiles_own_update on public.profiles for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy profiles_admin_all on public.profiles for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Student-owned data.
create policy package_access_own_read on public.package_access for select to authenticated using ((select auth.uid()) = user_id);
create policy payments_own_read on public.payments for select to authenticated using ((select auth.uid()) = user_id);
create policy attempts_own_read on public.attempts for select to authenticated using ((select auth.uid()) = user_id);
create policy answers_own_read on public.attempt_answers for select to authenticated using ((select auth.uid()) = user_id);
create policy answers_own_insert on public.attempt_answers for insert to authenticated with check (
  (select auth.uid()) = user_id
  and exists (select 1 from public.attempts a where a.attempt_id = attempt_id and a.user_id = (select auth.uid()) and a.status = 'IN_PROGRESS')
);
create policy answers_own_update on public.attempt_answers for update to authenticated using (
  (select auth.uid()) = user_id
  and exists (select 1 from public.attempts a where a.attempt_id = attempt_id and a.user_id = (select auth.uid()) and a.status = 'IN_PROGRESS')
) with check (
  (select auth.uid()) = user_id
  and exists (select 1 from public.attempts a where a.attempt_id = attempt_id and a.user_id = (select auth.uid()) and a.status = 'IN_PROGRESS')
);
create policy bookmarks_own_all on public.bookmarks for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy mistakes_own_all on public.mistake_book for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy ranks_own_read on public.rank_snapshots for select to authenticated using ((select auth.uid()) = user_id);

-- Admin-only content and management policies.
create policy app_settings_admin_all on public.app_settings for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy boards_admin_all on public.boards for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy exams_admin_all on public.exams for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy subjects_admin_all on public.subjects for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy topics_admin_all on public.topics for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy packages_admin_all on public.packages for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy package_access_admin_all on public.package_access for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy payments_admin_all on public.payments for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy source_files_admin_all on public.source_files for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy import_batches_admin_all on public.import_batches for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy questions_admin_all on public.questions for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy question_content_admin_all on public.question_content for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy drafts_admin_all on public.draft_questions for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy tests_admin_all on public.tests for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy test_links_admin_all on public.test_question_links for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy attempts_admin_all on public.attempts for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy attempt_questions_admin_all on public.attempt_questions for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy answers_admin_all on public.attempt_answers for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy bookmarks_admin_all on public.bookmarks for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy mistakes_admin_all on public.mistake_book for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy ranks_admin_all on public.rank_snapshots for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy audit_admin_read on public.admin_audit_logs for select to authenticated using ((select public.is_admin()));
create policy audit_admin_insert on public.admin_audit_logs for insert to authenticated with check ((select public.is_admin()));

-- Private storage: admin access only. SELECT mirrors INSERT so uploads can return metadata.
create policy source_documents_admin_select on storage.objects for select to authenticated using (
  bucket_id = 'source-documents' and (select public.is_admin())
);
create policy source_documents_admin_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'source-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (select public.is_admin())
);
create policy source_documents_admin_update on storage.objects for update to authenticated using (
  bucket_id = 'source-documents' and (select public.is_admin())
) with check (
  bucket_id = 'source-documents' and (select public.is_admin())
);
create policy source_documents_admin_delete on storage.objects for delete to authenticated using (
  bucket_id = 'source-documents' and (select public.is_admin())
);

-- Explicit table privileges. RLS remains the final authorization layer.
revoke all on all tables in schema public from anon, authenticated;

grant select on public.app_settings, public.boards, public.exams, public.subjects, public.topics, public.tests, public.packages to anon, authenticated;
grant select on public.profiles, public.package_access, public.payments, public.attempts, public.attempt_answers, public.bookmarks, public.mistake_book, public.rank_snapshots to authenticated;
grant update (full_name, mobile, target_board_id, target_exam_id, language, last_login_at) on public.profiles to authenticated;
grant insert, update on public.attempt_answers to authenticated;
grant insert, update, delete on public.bookmarks, public.mistake_book to authenticated;

grant select, insert, update, delete on public.app_settings, public.boards, public.exams, public.subjects, public.topics,
  public.packages, public.package_access, public.payments, public.source_files, public.import_batches,
  public.questions, public.question_content, public.draft_questions, public.tests, public.test_question_links,
  public.attempts, public.attempt_questions, public.attempt_answers, public.bookmarks, public.mistake_book,
  public.rank_snapshots, public.admin_audit_logs to authenticated;

-- Students save answers only through save_attempt_answer(); direct answer writes remain unavailable.
revoke insert, update, delete on public.attempt_answers from authenticated;

-- Revoke broad profile update again, then restore only safe student-editable columns.
revoke update on public.profiles from authenticated;
grant update (full_name, mobile, target_board_id, target_exam_id, language, last_login_at) on public.profiles to authenticated;

revoke all on function public.set_updated_at() from public;
revoke all on function public.handle_new_user() from public;
revoke all on function public.is_admin() from public;
revoke all on function public.get_public_stats() from public;
revoke all on function public.create_test_attempt(text) from public;
revoke all on function public.get_attempt_questions(uuid, integer, integer) from public;
revoke all on function public.save_attempt_answer(uuid, text, text, boolean, integer) from public;
revoke all on function public.submit_test_attempt(uuid) from public;
revoke all on function public.get_attempt_review(uuid, integer, integer) from public;
revoke all on function public.publish_draft_question(uuid) from public;
revoke all on function public.reject_draft_question(uuid, text) from public;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.get_public_stats() to anon, authenticated;
grant execute on function public.create_test_attempt(text) to authenticated;
grant execute on function public.get_attempt_questions(uuid, integer, integer) to authenticated;
grant execute on function public.save_attempt_answer(uuid, text, text, boolean, integer) to authenticated;
grant execute on function public.submit_test_attempt(uuid) to authenticated;
grant execute on function public.get_attempt_review(uuid, integer, integer) to authenticated;
grant execute on function public.publish_draft_question(uuid) to authenticated;
grant execute on function public.reject_draft_question(uuid, text) to authenticated;

commit;
