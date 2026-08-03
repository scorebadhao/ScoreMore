-- ScoreMore initial dynamic configuration.
-- Safe to rerun after `supabase db reset`.

insert into public.boards (board_id, board_name, board_code, description, status, sort_order)
values ('GSSSB', 'Gujarat Subordinate Service Selection Board', 'GSSSB', 'Initial ScoreMore public board scope.', 'ACTIVE', 1)
on conflict (board_id) do update set
  board_name = excluded.board_name,
  description = excluded.description,
  status = excluded.status,
  sort_order = excluded.sort_order;

insert into public.exams (exam_id, board_id, exam_name, exam_code, description, status, sort_order)
values ('CCE', 'GSSSB', 'Combined Competitive Examination (CCE)', 'CCE', 'Initial ScoreMore public exam scope.', 'ACTIVE', 1)
on conflict (exam_id) do update set
  exam_name = excluded.exam_name,
  description = excluded.description,
  status = excluded.status,
  sort_order = excluded.sort_order;

insert into public.subjects (subject_id, exam_id, subject_name, subject_code, description, status, sort_order)
values
  ('REASONING', 'CCE', 'Reasoning', 'REASONING', 'Reasoning and logical ability.', 'ACTIVE', 1),
  ('QUANTITATIVE_APTITUDE', 'CCE', 'Quantitative Aptitude', 'QUANT', 'Mathematics and quantitative aptitude.', 'ACTIVE', 2),
  ('ENGLISH', 'CCE', 'English', 'ENGLISH', 'English language section.', 'ACTIVE', 3),
  ('GUJARATI', 'CCE', 'Gujarati', 'GUJARATI', 'Gujarati language section.', 'ACTIVE', 4)
on conflict (subject_id) do update set
  subject_name = excluded.subject_name,
  description = excluded.description,
  status = excluded.status,
  sort_order = excluded.sort_order;

insert into public.app_settings (setting_key, setting_value, description, is_public)
values
  ('app_name', 'ScoreMore', 'Public product name.', true),
  ('app_tagline', 'Prepare smarter', 'Short brand tagline.', true),
  ('scope_badge', 'GSSSB CCE', 'Current public exam scope.', true),
  ('hero_title', 'Prepare Smarter for GSSSB CCE', 'Landing page primary heading.', true),
  ('hero_subtitle', 'અસલ PYQ, વિભાગવાર પ્રેક્ટિસ, ફુલ ટેસ્ટ અને સ્માર્ટ એનાલિટિક્સ સાથે તૈયારી કરો.', 'Landing page Gujarati support line.', true)
on conflict (setting_key) do update set
  setting_value = excluded.setting_value,
  description = excluded.description,
  is_public = excluded.is_public,
  updated_at = now();
