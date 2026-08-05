-- ScoreMore Phase 3E compatibility: add AI-proposed answer provenance.
-- PostgreSQL enum values must be committed before they are referenced by later migrations.

alter type public.answer_source add value if not exists 'AI_PROPOSED';
