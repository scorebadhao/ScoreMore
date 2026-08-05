-- ScoreMore Phase 3E compatibility foundation
-- Date: 2026-08-05
-- Scope: AI-proposed answer review, canonical topic mapping, confidence/source quality,
--        dynamic paper completeness and safely labelled supplemental questions.

begin;

do $$ begin
  create type public.confidence_level as enum ('HIGH', 'MEDIUM', 'LOW');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.source_quality as enum ('CLEAR', 'LOW_RESOLUTION', 'CROPPED', 'DIAGRAM_REVIEW', 'UNREADABLE');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.topic_resolution_status as enum ('MATCHED', 'SUGGESTED', 'UNRESOLVED', 'ADMIN_CONFIRMED', 'IGNORED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.paper_completeness_status as enum ('COMPLETE', 'PARTIAL', 'PARTIAL_WITH_SUPPLEMENTS', 'REJECTED');
exception when duplicate_object then null; end $$;

alter table public.questions
  add column if not exists transcription_confidence public.confidence_level,
  add column if not exists answer_confidence public.confidence_level,
  add column if not exists topic_confidence public.confidence_level,
  add column if not exists source_quality public.source_quality,
  add column if not exists answer_review_note text,
  add column if not exists suggested_topic_code text,
  add column if not exists suggested_topic_name text,
  add column if not exists topic_resolution_status public.topic_resolution_status not null default 'UNRESOLVED',
  add column if not exists is_supplemental boolean not null default false,
  add column if not exists supplement_reason text;

alter table public.draft_questions
  add column if not exists transcription_confidence public.confidence_level,
  add column if not exists answer_confidence public.confidence_level,
  add column if not exists topic_confidence public.confidence_level,
  add column if not exists source_quality public.source_quality,
  add column if not exists answer_review_note text,
  add column if not exists suggested_topic_code text,
  add column if not exists suggested_topic_name text,
  add column if not exists topic_resolution_status public.topic_resolution_status not null default 'UNRESOLVED',
  add column if not exists is_supplemental boolean not null default false,
  add column if not exists supplement_reason text;

alter table public.import_batches
  add column if not exists package_version integer not null default 1,
  add column if not exists supersedes_package_id text,
  add column if not exists declared_total_questions integer,
  add column if not exists extracted_source_questions integer,
  add column if not exists missing_question_count integer not null default 0,
  add column if not exists missing_question_numbers integer[] not null default '{}',
  add column if not exists generated_supplement_count integer not null default 0,
  add column if not exists paper_completeness_status public.paper_completeness_status,
  add column if not exists paper_rejection_reason text,
  add column if not exists section_plan jsonb not null default '[]'::jsonb;

alter table public.import_batches
  drop constraint if exists import_batches_phase3e_counts,
  add constraint import_batches_phase3e_counts check (
    package_version >= 1
    and (declared_total_questions is null or declared_total_questions >= 1)
    and (extracted_source_questions is null or extracted_source_questions >= 0)
    and missing_question_count >= 0
    and generated_supplement_count >= 0
    and jsonb_typeof(section_plan) = 'array'
  );

alter table public.questions
  drop constraint if exists questions_supplemental_integrity,
  add constraint questions_supplemental_integrity check (
    (not is_supplemental)
    or (question_type = 'NORMAL' and content_origin = 'AI_GENERATED' and nullif(btrim(supplement_reason), '') is not null)
  );

alter table public.draft_questions
  drop constraint if exists draft_questions_supplemental_integrity,
  add constraint draft_questions_supplemental_integrity check (
    (not is_supplemental)
    or (question_type = 'NORMAL' and content_origin = 'AI_GENERATED' and nullif(btrim(supplement_reason), '') is not null)
  );

create table if not exists public.topic_aliases (
  topic_alias_id uuid primary key default gen_random_uuid(),
  subject_id text not null references public.subjects(subject_id) on delete cascade,
  alias_code text,
  alias_name text not null,
  normalized_alias text generated always as (upper(regexp_replace(btrim(alias_name), '[[:space:][:punct:]]+', '', 'g'))) stored,
  topic_id text not null references public.topics(topic_id) on delete cascade,
  status public.entity_status not null default 'ACTIVE',
  created_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  unique (subject_id, normalized_alias)
);

create table if not exists public.topic_suggestions (
  topic_suggestion_id uuid primary key default gen_random_uuid(),
  import_batch_id uuid not null references public.import_batches(import_batch_id) on delete cascade,
  import_item_id uuid not null unique references public.import_batch_items(import_item_id) on delete cascade,
  subject_id text not null references public.subjects(subject_id),
  suggested_topic_code text,
  suggested_topic_name text,
  topic_confidence public.confidence_level,
  resolution_status public.topic_resolution_status not null default 'UNRESOLVED',
  matched_topic_id text references public.topics(topic_id),
  resolved_by uuid references public.profiles(user_id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.topic_aliases enable row level security;
alter table public.topic_suggestions enable row level security;

drop policy if exists topic_aliases_admin_all on public.topic_aliases;
create policy topic_aliases_admin_all on public.topic_aliases
for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists topic_suggestions_admin_all on public.topic_suggestions;
create policy topic_suggestions_admin_all on public.topic_suggestions
for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

grant select, insert, update, delete on public.topic_aliases, public.topic_suggestions to authenticated;

-- Canonical GSSSB CCE topics. The IDs are stable; display names remain editable catalogue data.
insert into public.topics (topic_id, subject_id, topic_name, topic_code, description, sort_order)
values
  ('REASONING-NUMBER-SERIES', 'REASONING', 'Number Series', 'NUMBER_SERIES', 'Number patterns, missing terms and sequence logic.', 10),
  ('REASONING-ALPHABET-SERIES', 'REASONING', 'Alphabet Series', 'ALPHABET_SERIES', 'Alphabet and alphanumeric sequence questions.', 20),
  ('REASONING-FIGURE-SERIES', 'REASONING', 'Figure Series', 'FIGURE_SERIES', 'Non-verbal figure sequence and next-figure questions.', 30),
  ('REASONING-FIGURE-ANALOGY', 'REASONING', 'Figure Analogy', 'FIGURE_ANALOGY', 'Analogy relationships represented with figures.', 40),
  ('REASONING-FIGURE-CLASSIFICATION', 'REASONING', 'Figure Classification', 'FIGURE_CLASSIFICATION', 'Odd figure and figure classification questions.', 50),
  ('REASONING-CODING-DECODING', 'REASONING', 'Coding and Decoding', 'CODING_DECODING', 'Letter, number and symbol coding-decoding.', 60),
  ('REASONING-BLOOD-RELATION', 'REASONING', 'Blood Relation', 'BLOOD_RELATION', 'Family and blood-relation reasoning.', 70),
  ('REASONING-DIRECTION-SENSE', 'REASONING', 'Direction Sense', 'DIRECTION_SENSE', 'Direction, distance and movement reasoning.', 80),
  ('REASONING-RANKING-ORDER', 'REASONING', 'Ranking and Order', 'RANKING_ORDER', 'Position, rank and order based reasoning.', 90),
  ('REASONING-SEATING-ARRANGEMENT', 'REASONING', 'Seating Arrangement', 'SEATING_ARRANGEMENT', 'Linear and circular arrangement problems.', 100),
  ('REASONING-PUZZLE', 'REASONING', 'Logical Puzzle', 'PUZZLE', 'Multi-condition logical puzzle questions.', 110),
  ('REASONING-ANALOGY', 'REASONING', 'Analogy', 'ANALOGY', 'Word, number and logical analogy.', 120),
  ('REASONING-CLASSIFICATION', 'REASONING', 'Classification', 'CLASSIFICATION', 'Classification and odd-one-out reasoning.', 130),
  ('REASONING-MATHEMATICAL-OPERATIONS', 'REASONING', 'Mathematical Operations', 'MATHEMATICAL_OPERATIONS', 'Symbol substitution and operator based reasoning.', 140),
  ('REASONING-MISSING-NUMBER', 'REASONING', 'Missing Number', 'MISSING_NUMBER', 'Missing value in diagrams or numeric patterns.', 150),
  ('REASONING-SYLLOGISM', 'REASONING', 'Syllogism', 'SYLLOGISM', 'Logical conclusions from statements.', 160),
  ('REASONING-STATEMENT-CONCLUSION', 'REASONING', 'Statement and Conclusion', 'STATEMENT_CONCLUSION', 'Conclusion, inference and statement logic.', 170),
  ('REASONING-DATA-SUFFICIENCY', 'REASONING', 'Data Sufficiency', 'DATA_SUFFICIENCY', 'Determine whether the supplied statements are sufficient.', 180),
  ('REASONING-VENN-DIAGRAM', 'REASONING', 'Venn Diagram', 'VENN_DIAGRAM', 'Set relationships and Venn-diagram reasoning.', 190),
  ('REASONING-DATA-INTERPRETATION', 'REASONING', 'Data Interpretation', 'DATA_INTERPRETATION', 'Tables, line graphs and chart interpretation.', 200),
  ('REASONING-FIGURE-COUNTING', 'REASONING', 'Figure Counting', 'FIGURE_COUNTING', 'Count shapes or components in complex figures.', 210),
  ('REASONING-EMBEDDED-FIGURE', 'REASONING', 'Embedded Figure', 'EMBEDDED_FIGURE', 'Find a simple figure hidden in a complex figure.', 220),
  ('REASONING-PAPER-FOLDING-CUTTING', 'REASONING', 'Paper Folding and Cutting', 'PAPER_FOLDING_CUTTING', 'Paper folding, cutting and hole-punch patterns.', 230),
  ('REASONING-MIRROR-WATER-IMAGE', 'REASONING', 'Mirror and Water Image', 'MIRROR_WATER_IMAGE', 'Mirror-image and water-image reasoning.', 240),
  ('REASONING-CUBE-DICE', 'REASONING', 'Cube and Dice', 'CUBE_DICE', 'Cube, dice and spatial-face relationships.', 250),
  ('REASONING-NON-VERBAL', 'REASONING', 'Non-Verbal Reasoning', 'NON_VERBAL_REASONING', 'Other diagrammatic and spatial reasoning.', 260),
  ('QUANT-NUMBER-SYSTEM', 'QUANTITATIVE_APTITUDE', 'Number System', 'NUMBER_SYSTEM', 'Properties and operations involving numbers.', 10),
  ('QUANT-SIMPLIFICATION', 'QUANTITATIVE_APTITUDE', 'Simplification', 'SIMPLIFICATION', 'Arithmetic simplification and approximation.', 20),
  ('QUANT-HCF-LCM', 'QUANTITATIVE_APTITUDE', 'HCF and LCM', 'HCF_LCM', 'Highest common factor and least common multiple.', 30),
  ('QUANT-RATIO-PROPORTION', 'QUANTITATIVE_APTITUDE', 'Ratio and Proportion', 'RATIO_PROPORTION', 'Ratio, proportion and variation.', 40),
  ('QUANT-PERCENTAGE', 'QUANTITATIVE_APTITUDE', 'Percentage', 'PERCENTAGE', 'Percentage calculations and applications.', 50),
  ('QUANT-PROFIT-LOSS-DISCOUNT', 'QUANTITATIVE_APTITUDE', 'Profit, Loss and Discount', 'PROFIT_LOSS_DISCOUNT', 'Commercial arithmetic involving profit, loss and discount.', 60),
  ('QUANT-SIMPLE-INTEREST', 'QUANTITATIVE_APTITUDE', 'Simple Interest', 'SIMPLE_INTEREST', 'Simple-interest calculations.', 70),
  ('QUANT-COMPOUND-INTEREST', 'QUANTITATIVE_APTITUDE', 'Compound Interest', 'COMPOUND_INTEREST', 'Compound-interest and growth calculations.', 80),
  ('QUANT-AVERAGE', 'QUANTITATIVE_APTITUDE', 'Average', 'AVERAGE', 'Arithmetic mean and weighted average.', 90),
  ('QUANT-AGE-PROBLEMS', 'QUANTITATIVE_APTITUDE', 'Age Problems', 'AGE_PROBLEMS', 'Present, past and future age relationships.', 100),
  ('QUANT-TIME-WORK', 'QUANTITATIVE_APTITUDE', 'Time and Work', 'TIME_WORK', 'Work rates and combined work.', 110),
  ('QUANT-PIPES-CISTERNS', 'QUANTITATIVE_APTITUDE', 'Pipes and Cisterns', 'PIPES_CISTERNS', 'Filling and emptying rate problems.', 120),
  ('QUANT-TIME-SPEED-DISTANCE', 'QUANTITATIVE_APTITUDE', 'Time, Speed and Distance', 'TIME_SPEED_DISTANCE', 'Motion, distance and relative speed.', 130),
  ('QUANT-TRAINS', 'QUANTITATIVE_APTITUDE', 'Trains', 'TRAINS', 'Train speed and crossing problems.', 140),
  ('QUANT-BOATS-STREAMS', 'QUANTITATIVE_APTITUDE', 'Boats and Streams', 'BOATS_STREAMS', 'Upstream and downstream motion.', 150),
  ('QUANT-MENSURATION', 'QUANTITATIVE_APTITUDE', 'Mensuration', 'MENSURATION', 'Perimeter, area, surface area and volume.', 160),
  ('QUANT-ALGEBRA', 'QUANTITATIVE_APTITUDE', 'Algebra', 'ALGEBRA', 'Algebraic expressions and equations.', 170),
  ('QUANT-GEOMETRY', 'QUANTITATIVE_APTITUDE', 'Geometry', 'GEOMETRY', 'Plane geometry and geometric properties.', 180),
  ('QUANT-DATA-INTERPRETATION', 'QUANTITATIVE_APTITUDE', 'Data Interpretation', 'DATA_INTERPRETATION', 'Tables, charts and graphs for quantitative analysis.', 190),
  ('QUANT-MIXTURE-ALLIGATION', 'QUANTITATIVE_APTITUDE', 'Mixture and Alligation', 'MIXTURE_ALLIGATION', 'Mixture, concentration and alligation.', 200),
  ('QUANT-PARTNERSHIP', 'QUANTITATIVE_APTITUDE', 'Partnership', 'PARTNERSHIP', 'Investment ratio and partnership profit.', 210),
  ('QUANT-CALENDAR', 'QUANTITATIVE_APTITUDE', 'Calendar', 'CALENDAR', 'Date, day and calendar arithmetic.', 220),
  ('QUANT-CLOCK', 'QUANTITATIVE_APTITUDE', 'Clock', 'CLOCK', 'Clock angle and time relationships.', 230),
  ('QUANT-PROBABILITY', 'QUANTITATIVE_APTITUDE', 'Probability', 'PROBABILITY', 'Elementary probability.', 240),
  ('QUANT-PERMUTATION-COMBINATION', 'QUANTITATIVE_APTITUDE', 'Permutation and Combination', 'PERMUTATION_COMBINATION', 'Counting arrangements and selections.', 250),
  ('QUANT-SERIES', 'QUANTITATIVE_APTITUDE', 'Arithmetic and Number Series', 'SERIES', 'Series sums and quantitative sequence questions.', 260),
  ('ENGLISH-SYNONYMS', 'ENGLISH', 'Synonyms', 'SYNONYMS', 'Words with similar meanings.', 10),
  ('ENGLISH-ANTONYMS', 'ENGLISH', 'Antonyms', 'ANTONYMS', 'Words with opposite meanings.', 20),
  ('ENGLISH-ONE-WORD-SUBSTITUTION', 'ENGLISH', 'One Word Substitution', 'ONE_WORD_SUBSTITUTION', 'Single-word substitutions for phrases.', 30),
  ('ENGLISH-IDIOMS-PHRASES', 'ENGLISH', 'Idioms and Phrases', 'IDIOMS_PHRASES', 'Meaning and usage of idiomatic expressions.', 40),
  ('ENGLISH-PREPOSITIONS', 'ENGLISH', 'Prepositions', 'PREPOSITIONS', 'Correct use of prepositions.', 50),
  ('ENGLISH-ARTICLES', 'ENGLISH', 'Articles', 'ARTICLES', 'Use of a, an and the.', 60),
  ('ENGLISH-TENSES', 'ENGLISH', 'Tenses', 'TENSES', 'Verb tense usage.', 70),
  ('ENGLISH-VERB-FORMS', 'ENGLISH', 'Verb Forms', 'VERB_FORMS', 'Inflection and correct verb forms.', 80),
  ('ENGLISH-SUBJECT-VERB-AGREEMENT', 'ENGLISH', 'Subject–Verb Agreement', 'SUBJECT_VERB_AGREEMENT', 'Agreement between subject and verb.', 90),
  ('ENGLISH-FILL-BLANKS', 'ENGLISH', 'Fill in the Blanks', 'FILL_IN_THE_BLANKS', 'Contextual grammar and vocabulary blanks.', 100),
  ('ENGLISH-SENTENCE-ARRANGEMENT', 'ENGLISH', 'Sentence Arrangement', 'SENTENCE_ARRANGEMENT', 'Rearrangement of sentences or clauses.', 110),
  ('ENGLISH-ERROR-DETECTION', 'ENGLISH', 'Error Detection', 'ERROR_DETECTION', 'Identify grammatical or usage errors.', 120),
  ('ENGLISH-READING-COMPREHENSION', 'ENGLISH', 'Reading Comprehension', 'READING_COMPREHENSION', 'Passage-based comprehension questions.', 130),
  ('ENGLISH-TRANSLATION', 'ENGLISH', 'Translation', 'TRANSLATION', 'English–Gujarati translation questions.', 140),
  ('ENGLISH-SPELLING', 'ENGLISH', 'Spelling', 'SPELLING', 'Correct spelling and orthography.', 150),
  ('ENGLISH-ACTIVE-PASSIVE', 'ENGLISH', 'Active and Passive Voice', 'ACTIVE_PASSIVE', 'Voice transformation and usage.', 160),
  ('ENGLISH-DIRECT-INDIRECT', 'ENGLISH', 'Direct and Indirect Speech', 'DIRECT_INDIRECT', 'Reported speech transformation.', 170),
  ('ENGLISH-VOCABULARY', 'ENGLISH', 'Vocabulary', 'VOCABULARY', 'General vocabulary questions.', 180),
  ('GUJARATI-SPELLING', 'GUJARATI', 'ગુજરાતી જોડણી', 'GUJARATI_SPELLING', 'ગુજરાતી શબ્દોની સાચી જોડણી.', 10),
  ('GUJARATI-SYNONYMS', 'GUJARATI', 'સમાનાર્થી શબ્દો', 'GUJARATI_SYNONYMS', 'ગુજરાતી સમાનાર્થી શબ્દો.', 20),
  ('GUJARATI-ANTONYMS', 'GUJARATI', 'વિરુદ્ધાર્થી શબ્દો', 'GUJARATI_ANTONYMS', 'ગુજરાતી વિરુદ્ધાર્થી શબ્દો.', 30),
  ('GUJARATI-IDIOMS', 'GUJARATI', 'રૂઢિપ્રયોગ', 'GUJARATI_IDIOMS', 'ગુજરાતી રૂઢિપ્રયોગ અને અર્થ.', 40),
  ('GUJARATI-PROVERBS', 'GUJARATI', 'કહેવતો', 'GUJARATI_PROVERBS', 'ગુજરાતી કહેવતો અને અર્થ.', 50),
  ('GUJARATI-GRAMMAR', 'GUJARATI', 'ગુજરાતી વ્યાકરણ', 'GUJARATI_GRAMMAR', 'સામાન્ય ગુજરાતી વ્યાકરણ.', 60),
  ('GUJARATI-SANDHI', 'GUJARATI', 'સંધિ', 'GUJARATI_SANDHI', 'સંધિ અને સંધિવિચ્છેદ.', 70),
  ('GUJARATI-SAMAS', 'GUJARATI', 'સમાસ', 'GUJARATI_SAMAS', 'સમાસ અને સમાસવિગ્રહ.', 80),
  ('GUJARATI-ALANKAR', 'GUJARATI', 'અલંકાર', 'GUJARATI_ALANKAR', 'ગુજરાતી અલંકાર.', 90),
  ('GUJARATI-CHHAND', 'GUJARATI', 'છંદ', 'GUJARATI_CHHAND', 'ગુજરાતી છંદ.', 100),
  ('GUJARATI-VOCABULARY', 'GUJARATI', 'શબ્દભંડોળ', 'GUJARATI_VOCABULARY', 'ગુજરાતી શબ્દભંડોળ અને અર્થ.', 110),
  ('GUJARATI-SENTENCE-CORRECTION', 'GUJARATI', 'વાક્યશુદ્ધિ', 'GUJARATI_SENTENCE_CORRECTION', 'ગુજરાતી વાક્યમાં ભાષાશુદ્ધિ.', 120),
  ('GUJARATI-TRANSLATION', 'GUJARATI', 'અનુવાદ', 'GUJARATI_TRANSLATION', 'ગુજરાતી અનુવાદ આધારિત પ્રશ્નો.', 130)
on conflict (topic_id) do update set
  subject_id = excluded.subject_id,
  topic_name = excluded.topic_name,
  topic_code = excluded.topic_code,
  description = excluded.description,
  status = 'ACTIVE',
  sort_order = excluded.sort_order,
  updated_at = now();

-- Selected aliases retained from the ScoreBadhao-style topic-review vocabulary.
insert into public.topic_aliases (subject_id, alias_code, alias_name, topic_id)
values
  ('REASONING', 'DI', 'DATA INTERPRETATION', 'REASONING-DATA-INTERPRETATION'),
  ('REASONING', 'FIGURE_COUNT', 'FIGURE COUNTING', 'REASONING-FIGURE-COUNTING'),
  ('REASONING', 'BLOOD_RELATIONS', 'BLOOD RELATIONS', 'REASONING-BLOOD-RELATION'),
  ('QUANTITATIVE_APTITUDE', 'DI', 'DATA INTERPRETATION', 'QUANT-DATA-INTERPRETATION'),
  ('QUANTITATIVE_APTITUDE', 'TIME_AND_WORK', 'TIME AND WORK', 'QUANT-TIME-WORK'),
  ('ENGLISH', 'RC', 'READING COMPREHENSION', 'ENGLISH-READING-COMPREHENSION'),
  ('GUJARATI', 'SPELLING', 'ગુજરાતી જોડણી', 'GUJARATI-SPELLING')
on conflict (subject_id, normalized_alias) do update set
  alias_code = excluded.alias_code,
  topic_id = excluded.topic_id,
  status = 'ACTIVE';

create or replace function public.resolve_import_topic(
  p_subject_id text,
  p_topic_id text default null,
  p_suggested_topic_code text default null,
  p_suggested_topic_name text default null
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_subject_id text := upper(nullif(btrim(p_subject_id), ''));
  v_topic_id text := upper(nullif(btrim(p_topic_id), ''));
  v_code text := upper(nullif(btrim(p_suggested_topic_code), ''));
  v_name text := nullif(btrim(p_suggested_topic_name), '');
  v_normalized_name text := upper(regexp_replace(coalesce(v_name, ''), '[^[:alnum:]]+', '', 'g'));
  v_match public.topics%rowtype;
begin
  if v_subject_id is null then
    return jsonb_build_object('status', 'UNRESOLVED', 'topic_id', null, 'reason', 'MISSING_SUBJECT');
  end if;

  if v_topic_id is not null then
    select * into v_match from public.topics
    where topic_id = v_topic_id and subject_id = v_subject_id and status = 'ACTIVE';
    if found then
      return jsonb_build_object('status', 'MATCHED', 'topic_id', v_match.topic_id, 'topic_code', v_match.topic_code, 'topic_name', v_match.topic_name, 'match_type', 'TOPIC_ID');
    end if;
  end if;

  if v_code is not null then
    select * into v_match from public.topics
    where subject_id = v_subject_id and upper(topic_code) = v_code and status = 'ACTIVE'
    order by sort_order, topic_id limit 1;
    if found then
      return jsonb_build_object('status', 'MATCHED', 'topic_id', v_match.topic_id, 'topic_code', v_match.topic_code, 'topic_name', v_match.topic_name, 'match_type', 'TOPIC_CODE');
    end if;

    select t.* into v_match
    from public.topic_aliases a join public.topics t on t.topic_id = a.topic_id
    where a.subject_id = v_subject_id and upper(coalesce(a.alias_code, '')) = v_code
      and a.status = 'ACTIVE' and t.status = 'ACTIVE'
    order by t.sort_order, t.topic_id limit 1;
    if found then
      return jsonb_build_object('status', 'MATCHED', 'topic_id', v_match.topic_id, 'topic_code', v_match.topic_code, 'topic_name', v_match.topic_name, 'match_type', 'ALIAS_CODE');
    end if;
  end if;

  if v_normalized_name <> '' then
    select * into v_match from public.topics
    where subject_id = v_subject_id
      and upper(regexp_replace(topic_name, '[^[:alnum:]]+', '', 'g')) = v_normalized_name
      and status = 'ACTIVE'
    order by sort_order, topic_id limit 1;
    if found then
      return jsonb_build_object('status', 'MATCHED', 'topic_id', v_match.topic_id, 'topic_code', v_match.topic_code, 'topic_name', v_match.topic_name, 'match_type', 'TOPIC_NAME');
    end if;

    select t.* into v_match
    from public.topic_aliases a join public.topics t on t.topic_id = a.topic_id
    where a.subject_id = v_subject_id and a.normalized_alias = v_normalized_name
      and a.status = 'ACTIVE' and t.status = 'ACTIVE'
    order by t.sort_order, t.topic_id limit 1;
    if found then
      return jsonb_build_object('status', 'MATCHED', 'topic_id', v_match.topic_id, 'topic_code', v_match.topic_code, 'topic_name', v_match.topic_name, 'match_type', 'ALIAS_NAME');
    end if;
  end if;

  return jsonb_build_object(
    'status', case when v_code is not null or v_name is not null then 'SUGGESTED' else 'UNRESOLVED' end,
    'topic_id', null,
    'topic_code', v_code,
    'topic_name', v_name,
    'match_type', 'NONE'
  );
end;
$$;

-- Preserve Phase 3D function implementations under explicit names, then expose compatibility wrappers.
alter function public.normalize_import_question_payload(jsonb) rename to normalize_import_question_payload_phase3d;
alter function public.validate_import_manifest_shape(jsonb) rename to validate_import_manifest_shape_phase3d;
alter function public.validate_import_raw_item_shape(jsonb) rename to validate_import_raw_item_shape_phase3d;
alter function public.validate_import_question(jsonb) rename to validate_import_question_phase3d;

create or replace function public.normalize_import_question_payload(p_question jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_base jsonb := public.normalize_import_question_payload_phase3d(p_question);
  v_is_supplemental boolean := case
    when jsonb_typeof(p_question -> 'is_supplemental') = 'boolean' then (p_question ->> 'is_supplemental')::boolean
    else false
  end;
begin
  return v_base || jsonb_build_object(
    'suggested_topic_code', upper(nullif(btrim(p_question ->> 'suggested_topic_code'), '')),
    'suggested_topic_name', nullif(btrim(p_question ->> 'suggested_topic_name'), ''),
    'topic_confidence', upper(nullif(btrim(p_question ->> 'topic_confidence'), '')),
    'transcription_confidence', upper(nullif(btrim(p_question ->> 'transcription_confidence'), '')),
    'answer_confidence', upper(nullif(btrim(p_question ->> 'answer_confidence'), '')),
    'answer_review_note', nullif(btrim(p_question ->> 'answer_review_note'), ''),
    'source_quality', upper(nullif(btrim(p_question ->> 'source_quality'), '')),
    'is_supplemental', v_is_supplemental,
    'supplement_reason', upper(nullif(btrim(p_question ->> 'supplement_reason'), ''))
  );
end;
$$;

create or replace function public.validate_import_manifest_shape(p_manifest jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_errors jsonb;
  v_paper jsonb;
  v_key text;
  v_section jsonb;
  v_section_index integer;
  v_declared integer;
  v_extracted integer;
  v_missing integer;
  v_generated integer;
  v_question_count integer;
  v_actual_supplements integer := 0;
  v_missing_array_count integer := 0;
  v_missing_distinct_count integer := 0;
  v_status text;
  v_start integer;
  v_end integer;
  v_expected integer;
  v_section_extracted integer;
  v_section_supplemental integer;
  v_previous_end integer := 0;
  v_total_expected integer := 0;
  v_total_extracted integer := 0;
  v_total_supplemental integer := 0;
begin
  select coalesce(jsonb_agg(entry), '[]'::jsonb) into v_errors
  from jsonb_array_elements(public.validate_import_manifest_shape_phase3d(p_manifest)) entry
  where not (
    entry ->> 'code' = 'UNSUPPORTED_FIELD'
    and entry ->> 'path' in (
      '$.package_version', '$.supersedes_package_id', '$.paper',
      '$.defaults.transcription_confidence', '$.defaults.answer_confidence',
      '$.defaults.topic_confidence', '$.defaults.source_quality'
    )
  );

  if p_manifest ? 'package_version' and (
    jsonb_typeof(p_manifest -> 'package_version') <> 'number'
    or public.try_parse_integer(p_manifest ->> 'package_version') is null
    or public.try_parse_integer(p_manifest ->> 'package_version') < 1
  ) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_PACKAGE_VERSION','message','package_version must be a positive integer.','path','$.package_version'));
  end if;

  if p_manifest ? 'supersedes_package_id' and p_manifest -> 'supersedes_package_id' <> 'null'::jsonb
     and jsonb_typeof(p_manifest -> 'supersedes_package_id') <> 'string' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_SUPERSEDES_PACKAGE','message','supersedes_package_id must be text or null.','path','$.supersedes_package_id'));
  end if;

  v_paper := p_manifest -> 'paper';
  if v_paper is null or v_paper = 'null'::jsonb then
    return v_errors;
  end if;
  if jsonb_typeof(v_paper) <> 'object' then
    return v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_PAPER_OBJECT','message','paper must be an object.','path','$.paper'));
  end if;

  for v_key in select jsonb_object_keys(v_paper) loop
    if v_key not in ('declared_total_questions','extracted_source_questions','missing_question_count','missing_question_numbers','generated_supplement_count','completeness_status','rejection_reason','section_plan') then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','UNSUPPORTED_FIELD','message',format('Unsupported paper field: %s',v_key),'path',format('$.paper.%s',v_key)));
    end if;
  end loop;

  v_declared := public.try_parse_integer(v_paper ->> 'declared_total_questions');
  v_extracted := public.try_parse_integer(v_paper ->> 'extracted_source_questions');
  v_missing := coalesce(public.try_parse_integer(v_paper ->> 'missing_question_count'), 0);
  v_generated := coalesce(public.try_parse_integer(v_paper ->> 'generated_supplement_count'), 0);
  v_status := upper(nullif(btrim(v_paper ->> 'completeness_status'), ''));
  v_question_count := case when jsonb_typeof(p_manifest -> 'questions') = 'array' then jsonb_array_length(p_manifest -> 'questions') else 0 end;

  if v_declared is null or v_declared < 1 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_DECLARED_TOTAL','message','declared_total_questions must be a positive integer.','path','$.paper.declared_total_questions'));
  end if;
  if v_extracted is null or v_extracted < 0 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_EXTRACTED_TOTAL','message','extracted_source_questions must be a non-negative integer.','path','$.paper.extracted_source_questions'));
  end if;
  if v_missing < 0 or v_generated < 0 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_COMPLETENESS_COUNT','message','Missing and supplemental counts cannot be negative.','path','$.paper'));
  end if;

  if jsonb_typeof(v_paper -> 'missing_question_numbers') <> 'array' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_MISSING_NUMBERS','message','missing_question_numbers must be an array of unique positive integers.','path','$.paper.missing_question_numbers'));
  else
    select count(*), count(distinct value::text) into v_missing_array_count, v_missing_distinct_count
    from jsonb_array_elements(v_paper -> 'missing_question_numbers');
    if v_missing_array_count <> v_missing_distinct_count or exists (
      select 1 from jsonb_array_elements(v_paper -> 'missing_question_numbers') e
      where jsonb_typeof(e) <> 'number' or public.try_parse_integer(e #>> '{}') is null or public.try_parse_integer(e #>> '{}') < 1
    ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_MISSING_NUMBERS','message','missing_question_numbers must contain unique positive integers.','path','$.paper.missing_question_numbers'));
    end if;
    if v_missing_array_count <> v_missing then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','MISSING_COUNT_MISMATCH','message','missing_question_count must equal the number of missing_question_numbers.','path','$.paper.missing_question_count'));
    end if;
    if v_declared is not null and exists (
      select 1 from jsonb_array_elements(v_paper -> 'missing_question_numbers') e
      where public.try_parse_integer(e #>> '{}') > v_declared
    ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','MISSING_NUMBER_OUT_OF_RANGE','message','Missing question numbers cannot exceed declared_total_questions.','path','$.paper.missing_question_numbers'));
    end if;
  end if;

  if v_declared is not null and v_extracted is not null and v_declared <> v_extracted + v_missing then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','PAPER_TOTAL_MISMATCH','message','declared_total_questions must equal extracted_source_questions plus missing_question_count.','path','$.paper'));
  end if;

  if v_missing > 10 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','MISSING_QUESTION_LIMIT_EXCEEDED','message','More than 10 missing source questions rejects the PYQ package.','path','$.paper.missing_question_count'));
  end if;

  if jsonb_typeof(p_manifest -> 'questions') = 'array' then
    select count(*) into v_actual_supplements
    from jsonb_array_elements(p_manifest -> 'questions') q
    where case when jsonb_typeof(q -> 'is_supplemental') = 'boolean' then (q ->> 'is_supplemental')::boolean else false end;
  else
    v_actual_supplements := 0;
  end if;

  if v_actual_supplements <> v_generated then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SUPPLEMENT_COUNT_MISMATCH','message','generated_supplement_count must equal the number of supplemental question records.','path','$.paper.generated_supplement_count'));
  end if;
  if v_extracted is not null and v_question_count <> v_extracted + v_generated then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','PACKAGE_RECORD_COUNT_MISMATCH','message','questions length must equal extracted_source_questions plus generated_supplement_count.','path','$.questions'));
  end if;
  if v_generated > v_missing then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','TOO_MANY_SUPPLEMENTS','message','Supplemental questions cannot exceed the number of missing source questions.','path','$.paper.generated_supplement_count'));
  end if;

  if v_status not in ('COMPLETE','PARTIAL','PARTIAL_WITH_SUPPLEMENTS','REJECTED') then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_COMPLETENESS_STATUS','message','completeness_status is unsupported.','path','$.paper.completeness_status'));
  elsif v_missing = 0 and (v_status <> 'COMPLETE' or v_generated <> 0) then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','COMPLETENESS_STATUS_MISMATCH','message','A complete paper must have no missing or supplemental questions.','path','$.paper.completeness_status'));
  elsif v_missing between 1 and 10 and v_generated = 0 and v_status <> 'PARTIAL' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','COMPLETENESS_STATUS_MISMATCH','message','A paper with missing questions and no supplements must be PARTIAL.','path','$.paper.completeness_status'));
  elsif v_missing between 1 and 10 and v_generated = v_missing and v_status <> 'PARTIAL_WITH_SUPPLEMENTS' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','COMPLETENESS_STATUS_MISMATCH','message','A fully supplemented partial paper must be PARTIAL_WITH_SUPPLEMENTS.','path','$.paper.completeness_status'));
  elsif v_missing > 10 and v_status <> 'REJECTED' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','COMPLETENESS_STATUS_MISMATCH','message','A paper missing more than 10 questions must be REJECTED.','path','$.paper.completeness_status'));
  end if;

  if v_status = 'REJECTED' and nullif(btrim(v_paper ->> 'rejection_reason'), '') is null then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','REJECTION_REASON_REQUIRED','message','Rejected packages require a clear rejection_reason.','path','$.paper.rejection_reason'));
  end if;

  if jsonb_typeof(v_paper -> 'section_plan') <> 'array' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_SECTION_PLAN','message','section_plan must be an array.','path','$.paper.section_plan'));
  else
    for v_section, v_section_index in select value, ordinality::integer from jsonb_array_elements(v_paper -> 'section_plan') with ordinality loop
      if jsonb_typeof(v_section) <> 'object' or not (v_section ?& array['section_code','subject_id','start_question_no','end_question_no','expected_count','extracted_count','supplemental_count']) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_SECTION_PLAN_ROW','message','Each section row requires section_code, subject_id, boundaries and counts.','path',format('$.paper.section_plan[%s]',v_section_index-1)));
      else
        v_start := public.try_parse_integer(v_section ->> 'start_question_no');
        v_end := public.try_parse_integer(v_section ->> 'end_question_no');
        v_expected := public.try_parse_integer(v_section ->> 'expected_count');
        v_section_extracted := public.try_parse_integer(v_section ->> 'extracted_count');
        v_section_supplemental := public.try_parse_integer(v_section ->> 'supplemental_count');

        if v_start is null or v_start < 1 or v_end is null or v_end < 1 or v_expected is null or v_expected < 1
           or v_section_extracted is null or v_section_extracted < 0 or v_section_supplemental is null or v_section_supplemental < 0 then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_SECTION_PLAN_ROW','message','Section boundaries and counts must be valid integers.','path',format('$.paper.section_plan[%s]',v_section_index-1)));
        else
          if v_end < v_start then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_SECTION_BOUNDARY','message','end_question_no cannot be smaller than start_question_no.','path',format('$.paper.section_plan[%s].end_question_no',v_section_index-1)));
          end if;
          if v_expected <> v_end - v_start + 1 then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SECTION_EXPECTED_COUNT_MISMATCH','message','expected_count must equal the inclusive question-number range.','path',format('$.paper.section_plan[%s].expected_count',v_section_index-1)));
          end if;
          if v_section_index = 1 and v_start <> 1 then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SECTION_PLAN_MUST_START_AT_ONE','message','The first section must start at question 1.','path','$.paper.section_plan[0].start_question_no'));
          elsif v_section_index > 1 and v_start <> v_previous_end + 1 then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SECTION_PLAN_NOT_CONTIGUOUS','message','Section ranges must be ordered and contiguous.','path',format('$.paper.section_plan[%s].start_question_no',v_section_index-1)));
          end if;
          if v_section_extracted + v_section_supplemental > v_expected then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SECTION_RECORD_COUNT_EXCEEDED','message','Extracted plus supplemental records cannot exceed the section expected count.','path',format('$.paper.section_plan[%s]',v_section_index-1)));
          end if;
          v_previous_end := v_end;
          v_total_expected := v_total_expected + v_expected;
          v_total_extracted := v_total_extracted + v_section_extracted;
          v_total_supplemental := v_total_supplemental + v_section_supplemental;
        end if;
      end if;
    end loop;

    if jsonb_array_length(v_paper -> 'section_plan') > 0 and v_declared is not null then
      if v_previous_end <> v_declared then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SECTION_PLAN_END_MISMATCH','message','The last section must end at declared_total_questions.','path','$.paper.section_plan'));
      end if;
      if v_total_expected <> v_declared then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SECTION_EXPECTED_TOTAL_MISMATCH','message','Section expected counts must sum to declared_total_questions.','path','$.paper.section_plan'));
      end if;
      if v_extracted is not null and v_total_extracted <> v_extracted then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SECTION_EXTRACTED_TOTAL_MISMATCH','message','Section extracted counts must sum to extracted_source_questions.','path','$.paper.section_plan'));
      end if;
      if v_total_supplemental <> v_generated then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SECTION_SUPPLEMENT_TOTAL_MISMATCH','message','Section supplemental counts must sum to generated_supplement_count.','path','$.paper.section_plan'));
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
  v_errors jsonb;
  v_key text;
  v_value text;
begin
  select coalesce(jsonb_agg(entry), '[]'::jsonb) into v_errors
  from jsonb_array_elements(public.validate_import_raw_item_shape_phase3d(p_item)) entry
  where not (
    entry ->> 'code' = 'UNSUPPORTED_FIELD'
    and entry ->> 'path' in (
      '$.suggested_topic_code', '$.suggested_topic_name', '$.topic_confidence',
      '$.transcription_confidence', '$.answer_confidence', '$.answer_review_note',
      '$.source_quality', '$.is_supplemental', '$.supplement_reason'
    )
  );

  foreach v_key in array array['suggested_topic_code','suggested_topic_name','topic_confidence','transcription_confidence','answer_confidence','answer_review_note','source_quality','supplement_reason'] loop
    if p_item ? v_key and p_item -> v_key <> 'null'::jsonb and jsonb_typeof(p_item -> v_key) <> 'string' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_JSON_TYPE','message',format('%s must be JSON text or null.',v_key),'path',format('$.%s',v_key)));
    end if;
  end loop;

  if p_item ? 'is_supplemental' and jsonb_typeof(p_item -> 'is_supplemental') <> 'boolean' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_BOOLEAN','message','is_supplemental must be a JSON boolean.','path','$.is_supplemental'));
  end if;

  foreach v_key in array array['topic_confidence','transcription_confidence','answer_confidence'] loop
    v_value := upper(nullif(btrim(p_item ->> v_key), ''));
    if v_value is not null and v_value not in ('HIGH','MEDIUM','LOW') then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_CONFIDENCE','message',format('%s must be HIGH, MEDIUM or LOW.',v_key),'path',format('$.%s',v_key)));
    end if;
  end loop;

  v_value := upper(nullif(btrim(p_item ->> 'source_quality'), ''));
  if v_value is not null and v_value not in ('CLEAR','LOW_RESOLUTION','CROPPED','DIAGRAM_REVIEW','UNREADABLE') then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_SOURCE_QUALITY','message','source_quality is unsupported.','path','$.source_quality'));
  end if;

  return v_errors;
end;
$$;

create or replace function public.validate_import_question(p_question jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base jsonb := public.validate_import_question_phase3d(p_question);
  v_errors jsonb;
  v_warnings jsonb;
  v_status text;
  v_answer_source text := upper(nullif(btrim(p_question ->> 'answer_source'), ''));
  v_answer_confidence text := upper(nullif(btrim(p_question ->> 'answer_confidence'), ''));
  v_transcription_confidence text := upper(nullif(btrim(p_question ->> 'transcription_confidence'), ''));
  v_topic_confidence text := upper(nullif(btrim(p_question ->> 'topic_confidence'), ''));
  v_source_quality text := upper(nullif(btrim(p_question ->> 'source_quality'), ''));
  v_topic jsonb;
  v_is_supplemental boolean := case
    when jsonb_typeof(p_question -> 'is_supplemental') = 'boolean' then (p_question ->> 'is_supplemental')::boolean
    else false
  end;
  v_question_type text := upper(nullif(btrim(p_question ->> 'question_type'), ''));
  v_content_origin text := upper(nullif(btrim(p_question ->> 'content_origin'), ''));
  v_original_question_no integer := public.try_parse_integer(p_question ->> 'original_question_no');
  v_source_question_id text := nullif(btrim(p_question ->> 'source_question_id'), '');
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required.' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(entry), '[]'::jsonb) into v_errors
  from jsonb_array_elements(coalesce(v_base -> 'errors','[]'::jsonb)) entry
  where not (entry ->> 'code' = 'INVALID_ANSWER_SOURCE' and v_answer_source = 'AI_PROPOSED');
  v_warnings := coalesce(v_base -> 'warnings', '[]'::jsonb);
  v_status := v_base ->> 'status';

  v_topic := public.resolve_import_topic(
    p_question ->> 'subject_id', p_question ->> 'topic_id',
    p_question ->> 'suggested_topic_code', p_question ->> 'suggested_topic_name'
  );

  if v_answer_source = 'AI_PROPOSED' then
    if nullif(btrim(p_question ->> 'correct_answer'), '') is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','AI_ANSWER_MISSING','message','AI_PROPOSED requires a proposed correct_answer.'));
    end if;
    if v_answer_confidence not in ('HIGH','MEDIUM','LOW') then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','AI_ANSWER_CONFIDENCE_REQUIRED','message','AI_PROPOSED requires answer_confidence HIGH, MEDIUM or LOW.'));
    end if;
    if nullif(btrim(p_question ->> 'explanation'), '') is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','AI_EXPLANATION_REQUIRED','message','AI_PROPOSED requires an explanation for human review.'));
    end if;
    if upper(coalesce(nullif(btrim(p_question ->> 'verification_status'), ''),'NEEDS_CHECK')) = 'VERIFIED' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','AI_ANSWER_CANNOT_BE_PREVERIFIED','message','AI_PROPOSED answers must remain NEEDS_CHECK until an administrator confirms or corrects them.'));
    end if;
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code','AI_PROPOSED_ANSWER_REQUIRES_REVIEW','message','The proposed answer is not publishable until an administrator records a verified answer source.'));
  end if;

  if v_transcription_confidence is null then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code','MISSING_TRANSCRIPTION_CONFIDENCE','message','transcription_confidence is recommended for source-derived imports.'));
  end if;
  if v_source_quality is null then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code','MISSING_SOURCE_QUALITY','message','source_quality is recommended for source-derived imports.'));
  elsif v_source_quality = 'UNREADABLE' then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','UNREADABLE_SOURCE','message','An unreadable source record cannot create a publishable PYQ draft.'));
  end if;

  if v_topic ->> 'status' = 'MATCHED' then
    if nullif(btrim(p_question ->> 'topic_id'), '') is null then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code','TOPIC_AUTO_MATCHED','message',format('Suggested topic matched %s.',v_topic ->> 'topic_id')));
    end if;
  elsif nullif(btrim(p_question ->> 'suggested_topic_code'), '') is not null or nullif(btrim(p_question ->> 'suggested_topic_name'), '') is not null then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code','UNRESOLVED_TOPIC_SUGGESTION','message','The suggested topic requires admin mapping before PYQ publication.'));
  elsif v_question_type = 'PYQ' and nullif(btrim(p_question ->> 'topic_id'), '') is null then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code','MISSING_TOPIC','message','A primary topic must be selected before PYQ publication.'));
  end if;

  if v_topic_confidence is null and (nullif(btrim(p_question ->> 'topic_id'), '') is not null or nullif(btrim(p_question ->> 'suggested_topic_code'), '') is not null) then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code','MISSING_TOPIC_CONFIDENCE','message','topic_confidence is recommended when a topic is assigned or suggested.'));
  end if;

  if v_is_supplemental then
    if v_question_type <> 'NORMAL' or v_content_origin <> 'AI_GENERATED' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_SUPPLEMENTAL_ORIGIN','message','Supplemental records must be NORMAL questions with AI_GENERATED origin.'));
    end if;
    if nullif(btrim(p_question ->> 'supplement_reason'), '') is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','MISSING_SUPPLEMENT_REASON','message','Supplemental records require supplement_reason.'));
    end if;
    if v_original_question_no is not null or v_source_question_id is not null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','SUPPLEMENT_CANNOT_IMPERSONATE_PYQ','message','Supplemental questions cannot inherit original_question_no or source_question_id.'));
    end if;
  end if;

  if jsonb_array_length(v_errors) > 0 then
    v_status := 'INVALID';
  elsif v_status in ('VALID','VALID_WITH_WARNINGS') and jsonb_array_length(v_warnings) > 0 then
    v_status := 'VALID_WITH_WARNINGS';
  end if;

  return v_base
    || jsonb_build_object(
      'status', v_status,
      'errors', v_errors,
      'warnings', v_warnings,
      'topic_resolution', v_topic,
      'publication_review', jsonb_build_object(
        'answer_requires_admin_confirmation', v_answer_source = 'AI_PROPOSED',
        'topic_requires_admin_confirmation', v_question_type = 'PYQ' and v_topic ->> 'status' <> 'MATCHED',
        'source_quality', v_source_quality,
        'answer_confidence', v_answer_confidence,
        'transcription_confidence', v_transcription_confidence,
        'topic_confidence', v_topic_confidence
      )
    );
end;
$$;

create or replace function public.set_import_batch_phase3e_fields()
returns trigger language plpgsql set search_path = public as $$
declare
  v_paper jsonb := coalesce(new.package_manifest -> 'paper', '{}'::jsonb);
begin
  new.package_version := coalesce(public.try_parse_integer(new.package_manifest ->> 'package_version'), 1);
  new.supersedes_package_id := nullif(btrim(new.package_manifest ->> 'supersedes_package_id'), '');
  new.declared_total_questions := public.try_parse_integer(v_paper ->> 'declared_total_questions');
  new.extracted_source_questions := public.try_parse_integer(v_paper ->> 'extracted_source_questions');
  new.missing_question_count := coalesce(public.try_parse_integer(v_paper ->> 'missing_question_count'), 0);
  new.generated_supplement_count := coalesce(public.try_parse_integer(v_paper ->> 'generated_supplement_count'), 0);
  new.paper_completeness_status := case when nullif(btrim(v_paper ->> 'completeness_status'), '') is null then null else (upper(v_paper ->> 'completeness_status'))::public.paper_completeness_status end;
  new.paper_rejection_reason := nullif(btrim(v_paper ->> 'rejection_reason'), '');
  new.section_plan := case when jsonb_typeof(v_paper -> 'section_plan') = 'array' then v_paper -> 'section_plan' else '[]'::jsonb end;
  select coalesce(array_agg(public.try_parse_integer(value #>> '{}') order by ordinality), '{}'::integer[])
  into new.missing_question_numbers
  from jsonb_array_elements(coalesce(v_paper -> 'missing_question_numbers','[]'::jsonb)) with ordinality;
  return new;
end;
$$;

drop trigger if exists import_batches_phase3e_fields on public.import_batches;
create trigger import_batches_phase3e_fields before insert or update of package_manifest on public.import_batches
for each row execute function public.set_import_batch_phase3e_fields();

create or replace function public.sync_topic_suggestion_from_import_item()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_payload jsonb := new.normalized_payload;
  v_topic jsonb;
  v_code text := upper(nullif(btrim(v_payload ->> 'suggested_topic_code'), ''));
  v_name text := nullif(btrim(v_payload ->> 'suggested_topic_name'), '');
  v_conf public.confidence_level := case when upper(nullif(btrim(v_payload ->> 'topic_confidence'), '')) in ('HIGH','MEDIUM','LOW') then (upper(v_payload ->> 'topic_confidence'))::public.confidence_level else null end;
begin
  if v_code is null and v_name is null and nullif(btrim(v_payload ->> 'topic_id'), '') is null then
    return new;
  end if;
  v_topic := public.resolve_import_topic(v_payload ->> 'subject_id', v_payload ->> 'topic_id', v_code, v_name);
  insert into public.topic_suggestions (
    import_batch_id, import_item_id, subject_id, suggested_topic_code, suggested_topic_name,
    topic_confidence, resolution_status, matched_topic_id
  ) values (
    new.import_batch_id, new.import_item_id, v_payload ->> 'subject_id', v_code, v_name, v_conf,
    case when v_topic ->> 'status' = 'MATCHED' then 'MATCHED'::public.topic_resolution_status
         when v_code is not null or v_name is not null then 'SUGGESTED'::public.topic_resolution_status
         else 'UNRESOLVED'::public.topic_resolution_status end,
    nullif(v_topic ->> 'topic_id','')
  ) on conflict (import_item_id) do update set
    suggested_topic_code = excluded.suggested_topic_code,
    suggested_topic_name = excluded.suggested_topic_name,
    topic_confidence = excluded.topic_confidence,
    resolution_status = excluded.resolution_status,
    matched_topic_id = excluded.matched_topic_id,
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists import_item_topic_suggestion_sync on public.import_batch_items;
create trigger import_item_topic_suggestion_sync after insert or update of normalized_payload on public.import_batch_items
for each row execute function public.sync_topic_suggestion_from_import_item();

create or replace function public.set_draft_phase3e_fields()
returns trigger language plpgsql set search_path = public as $$
declare
  v_payload jsonb;
  v_topic jsonb;
begin
  if new.import_item_id is not null then
    select normalized_payload into v_payload from public.import_batch_items where import_item_id = new.import_item_id;
    if v_payload is not null then
      v_topic := public.resolve_import_topic(v_payload ->> 'subject_id', v_payload ->> 'topic_id', v_payload ->> 'suggested_topic_code', v_payload ->> 'suggested_topic_name');
      new.topic_id := coalesce(new.topic_id, nullif(v_topic ->> 'topic_id',''));
      new.suggested_topic_code := nullif(v_payload ->> 'suggested_topic_code','');
      new.suggested_topic_name := nullif(v_payload ->> 'suggested_topic_name','');
      new.topic_confidence := case when upper(nullif(v_payload ->> 'topic_confidence','')) in ('HIGH','MEDIUM','LOW') then upper(v_payload ->> 'topic_confidence')::public.confidence_level else null end;
      new.transcription_confidence := case when upper(nullif(v_payload ->> 'transcription_confidence','')) in ('HIGH','MEDIUM','LOW') then upper(v_payload ->> 'transcription_confidence')::public.confidence_level else null end;
      new.answer_confidence := case when upper(nullif(v_payload ->> 'answer_confidence','')) in ('HIGH','MEDIUM','LOW') then upper(v_payload ->> 'answer_confidence')::public.confidence_level else null end;
      new.answer_review_note := nullif(v_payload ->> 'answer_review_note','');
      new.source_quality := case when upper(nullif(v_payload ->> 'source_quality','')) in ('CLEAR','LOW_RESOLUTION','CROPPED','DIAGRAM_REVIEW','UNREADABLE') then upper(v_payload ->> 'source_quality')::public.source_quality else null end;
      new.is_supplemental := coalesce((v_payload ->> 'is_supplemental')::boolean, false);
      new.supplement_reason := nullif(v_payload ->> 'supplement_reason','');
      new.topic_resolution_status := case
        when new.topic_resolution_status = 'ADMIN_CONFIRMED' then 'ADMIN_CONFIRMED'::public.topic_resolution_status
        when new.topic_id is not null then 'MATCHED'::public.topic_resolution_status
        when new.suggested_topic_code is not null or new.suggested_topic_name is not null then 'SUGGESTED'::public.topic_resolution_status
        else 'UNRESOLVED'::public.topic_resolution_status end;
    end if;
  elsif new.topic_id is not null then
    new.topic_resolution_status := 'ADMIN_CONFIRMED';
  end if;
  return new;
end;
$$;

drop trigger if exists draft_questions_phase3e_fields on public.draft_questions;
create trigger draft_questions_phase3e_fields before insert or update on public.draft_questions
for each row execute function public.set_draft_phase3e_fields();

create or replace function public.review_draft_answer_topic(
  p_draft_id uuid,
  p_correct_answer text,
  p_answer_source text,
  p_explanation text,
  p_topic_id text,
  p_answer_review_note text default null,
  p_admin_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid := (select auth.uid());
  v_draft public.draft_questions%rowtype;
  v_answer text := upper(nullif(btrim(p_correct_answer), ''));
  v_source text := upper(nullif(btrim(p_answer_source), ''));
  v_topic text := upper(nullif(btrim(p_topic_id), ''));
begin
  if not public.is_admin() then raise exception 'Admin authorization required.' using errcode = 'P0001'; end if;
  select * into v_draft from public.draft_questions where draft_id = p_draft_id for update;
  if not found then raise exception 'Draft not found.' using errcode = 'P0001'; end if;
  if v_draft.review_status = 'PUBLISHED' then raise exception 'Published drafts cannot be edited.' using errcode = 'P0001'; end if;
  if v_answer not in ('A','B','C','D') then raise exception 'Choose a verified answer A, B, C or D.' using errcode = 'P0001'; end if;
  if v_source is null or v_source = 'AI_PROPOSED' or v_source not in ('OFFICIAL_FINAL_KEY','OFFICIAL_PROVISIONAL_KEY','MANUALLY_VERIFIED','SOURCE_BOOK','ADMIN_CORRECTED') then
    raise exception 'Choose a human-verifiable answer source before saving review.' using errcode = 'P0001';
  end if;
  if nullif(btrim(p_explanation), '') is null then raise exception 'A reviewed explanation is required.' using errcode = 'P0001'; end if;
  if v_draft.question_type = 'PYQ' and v_topic is null then raise exception 'Select an approved primary topic before PYQ publication.' using errcode = 'P0001'; end if;
  if v_topic is not null and not exists (select 1 from public.topics where topic_id = v_topic and subject_id = v_draft.subject_id and status = 'ACTIVE') then
    raise exception 'The selected topic does not belong to this subject.' using errcode = 'P0001';
  end if;
  if v_draft.source_quality = 'UNREADABLE' then raise exception 'An unreadable source must be corrected before verification.' using errcode = 'P0001'; end if;

  update public.draft_questions set
    correct_answer = v_answer,
    answer_source = v_source::public.answer_source,
    explanation = btrim(p_explanation),
    topic_id = v_topic,
    topic_resolution_status = case when v_topic is null then 'UNRESOLVED'::public.topic_resolution_status else 'ADMIN_CONFIRMED'::public.topic_resolution_status end,
    verification_status = 'VERIFIED',
    review_status = 'IN_REVIEW',
    answer_review_note = nullif(btrim(p_answer_review_note), ''),
    admin_notes = nullif(btrim(p_admin_notes), ''),
    reviewed_by = v_admin,
    reviewed_at = now(),
    updated_at = now()
  where draft_id = p_draft_id;

  if v_draft.import_item_id is not null then
    update public.topic_suggestions set
      matched_topic_id = v_topic,
      resolution_status = case when v_topic is null then 'UNRESOLVED'::public.topic_resolution_status else 'ADMIN_CONFIRMED'::public.topic_resolution_status end,
      resolved_by = v_admin,
      resolved_at = now(),
      updated_at = now()
    where import_item_id = v_draft.import_item_id;
  end if;

  insert into public.admin_audit_logs (admin_user_id, action, entity_type, entity_id, details)
  values (v_admin, 'VERIFY_DRAFT_ANSWER_TOPIC', 'DRAFT_QUESTION', p_draft_id::text,
    jsonb_build_object('correct_answer',v_answer,'answer_source',v_source,'topic_id',v_topic,'previous_answer_source',v_draft.answer_source));

  return (select to_jsonb(d) from public.draft_questions d where d.draft_id = p_draft_id);
end;
$$;

create or replace function public.guard_question_publication_phase3e()
returns trigger language plpgsql set search_path = public as $$
declare
  v_draft public.draft_questions%rowtype;
begin
  select * into v_draft from public.draft_questions
  where proposed_question_id = new.question_id and review_status <> 'PUBLISHED'
  order by updated_at desc limit 1;
  if not found then raise exception 'Published questions must originate from a reviewed draft.' using errcode = 'P0001'; end if;
  if v_draft.answer_source is null or v_draft.answer_source = 'AI_PROPOSED' then raise exception 'AI-proposed or missing answers must be human-confirmed before publication.' using errcode = 'P0001'; end if;
  if v_draft.verification_status <> 'VERIFIED' then raise exception 'Save the human answer/topic review before publication.' using errcode = 'P0001'; end if;
  if nullif(btrim(v_draft.explanation), '') is null then raise exception 'A reviewed explanation is required before publication.' using errcode = 'P0001'; end if;
  if v_draft.question_type = 'PYQ' and (v_draft.topic_id is null or v_draft.topic_resolution_status not in ('MATCHED','ADMIN_CONFIRMED')) then
    raise exception 'An approved primary topic is required before PYQ publication.' using errcode = 'P0001';
  end if;
  if v_draft.source_quality = 'UNREADABLE' then raise exception 'Unreadable source content cannot be published.' using errcode = 'P0001'; end if;
  if v_draft.is_supplemental and v_draft.question_type <> 'NORMAL' then raise exception 'Supplemental generated questions cannot be published as PYQ.' using errcode = 'P0001'; end if;

  new.transcription_confidence := v_draft.transcription_confidence;
  new.answer_confidence := v_draft.answer_confidence;
  new.topic_confidence := v_draft.topic_confidence;
  new.source_quality := v_draft.source_quality;
  new.answer_review_note := v_draft.answer_review_note;
  new.suggested_topic_code := v_draft.suggested_topic_code;
  new.suggested_topic_name := v_draft.suggested_topic_name;
  new.topic_resolution_status := v_draft.topic_resolution_status;
  new.is_supplemental := v_draft.is_supplemental;
  new.supplement_reason := v_draft.supplement_reason;
  return new;
end;
$$;

drop trigger if exists questions_phase3e_publication_guard on public.questions;
create trigger questions_phase3e_publication_guard before insert on public.questions
for each row execute function public.guard_question_publication_phase3e();

revoke all on function public.normalize_import_question_payload(jsonb) from public, anon, authenticated;
revoke all on function public.validate_import_manifest_shape(jsonb) from public, anon, authenticated;
revoke all on function public.validate_import_raw_item_shape(jsonb) from public, anon, authenticated;
revoke all on function public.resolve_import_topic(text,text,text,text) from public, anon;
revoke all on function public.validate_import_question(jsonb) from public, anon;
revoke all on function public.review_draft_answer_topic(uuid,text,text,text,text,text,text) from public, anon;
grant execute on function public.resolve_import_topic(text,text,text,text) to authenticated;
grant execute on function public.validate_import_question(jsonb) to authenticated;
grant execute on function public.review_draft_answer_topic(uuid,text,text,text,text,text,text) to authenticated;

commit;
