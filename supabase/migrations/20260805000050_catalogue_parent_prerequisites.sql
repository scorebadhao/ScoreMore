-- ScoreMore / RankTiger catalogue parent prerequisites
-- Patch 5.2
-- Purpose: make fresh environment migration replay self-contained before
-- 20260805000100_phase3e_compatibility.sql inserts canonical topics.
-- This is an idempotent versioned migration, not seed data.

begin;

insert into public.boards (board_id, board_name, board_code, description, status, sort_order)
values ('GSSSB', 'Gujarat Subordinate Service Selection Board', 'GSSSB', 'Initial public board scope.', 'ACTIVE', 1)
on conflict (board_id) do update set
  board_name = excluded.board_name,
  board_code = excluded.board_code,
  description = excluded.description,
  status = excluded.status,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.exams (exam_id, board_id, exam_name, exam_code, description, status, sort_order)
values ('CCE', 'GSSSB', 'Combined Competitive Examination (CCE)', 'CCE', 'Initial public exam scope.', 'ACTIVE', 1)
on conflict (exam_id) do update set
  board_id = excluded.board_id,
  exam_name = excluded.exam_name,
  exam_code = excluded.exam_code,
  description = excluded.description,
  status = excluded.status,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.subjects (subject_id, exam_id, subject_name, subject_code, description, status, sort_order)
values
  ('REASONING', 'CCE', 'Reasoning', 'REASONING', 'Reasoning and logical ability.', 'ACTIVE', 1),
  ('QUANTITATIVE_APTITUDE', 'CCE', 'Quantitative Aptitude', 'QUANT', 'Mathematics and quantitative aptitude.', 'ACTIVE', 2),
  ('ENGLISH', 'CCE', 'English', 'ENGLISH', 'English language section.', 'ACTIVE', 3),
  ('GUJARATI', 'CCE', 'Gujarati', 'GUJARATI', 'Gujarati language section.', 'ACTIVE', 4)
on conflict (subject_id) do update set
  exam_id = excluded.exam_id,
  subject_name = excluded.subject_name,
  subject_code = excluded.subject_code,
  description = excluded.description,
  status = excluded.status,
  sort_order = excluded.sort_order,
  updated_at = now();

commit;
