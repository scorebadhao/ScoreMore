begin;

-- These five RankTiger catalogue entries are reconstructed/completed practice
-- tests, not untouched original papers. Keep their reviewed FULL_MOCK type and
-- remove the student-facing PYQ claim so homepage taxonomy remains truthful.
-- The exact-ID guard prevents this content correction from touching any other
-- test. ScoreMore DEV does not currently contain these production IDs, so the
-- migration is intentionally a safe no-op there while preserving one shared
-- forward-only migration history.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $$
declare
  v_unexpected text[];
  v_updated integer := 0;
begin
  select array_agg(t.test_id order by t.test_id)
  into v_unexpected
  from public.tests t
  where t.test_id = any (array[
    'GSSSB-CCE-2024-1705-S3-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
    'GSSSB-CCE-2024-2005-S1-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
    'GSSSB-CCE-2024-2005-S2-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
    'GSSSB-CCE-2024-2005-S3-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
    'GSSSB-CCE-2024-2005-S4-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST'
  ]::text[])
    and t.test_type <> 'FULL_MOCK';

  if coalesce(array_length(v_unexpected, 1), 0) > 0 then
    raise exception
      'Completed-practice taxonomy correction blocked: unexpected test type for %',
      array_to_string(v_unexpected, ', ')
      using errcode = 'P0001';
  end if;

  update public.tests t
  set
    test_name = v.corrected_name,
    updated_at = now()
  from (values
    ('GSSSB-CCE-2024-1705-S3-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST', 'CCE 2024 Completed Practice Test - 17 May Shift 3'),
    ('GSSSB-CCE-2024-2005-S1-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST', 'CCE 2024 Completed Practice Test - 20 May Shift 1'),
    ('GSSSB-CCE-2024-2005-S2-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST', 'CCE 2024 Completed Practice Test - 20 May Shift 2'),
    ('GSSSB-CCE-2024-2005-S3-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST', 'CCE 2024 Completed Practice Test - 20 May Shift 3'),
    ('GSSSB-CCE-2024-2005-S4-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST', 'CCE 2024 Completed Practice Test - 20 May Shift 4')
  ) as v(test_id, corrected_name)
  where t.test_id = v.test_id
    and t.test_type = 'FULL_MOCK'
    and t.test_name is distinct from v.corrected_name;

  get diagnostics v_updated = row_count;

  if exists (
    select 1
    from public.tests t
    where t.test_id = any (array[
      'GSSSB-CCE-2024-1705-S3-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
      'GSSSB-CCE-2024-2005-S1-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
      'GSSSB-CCE-2024-2005-S2-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
      'GSSSB-CCE-2024-2005-S3-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST',
      'GSSSB-CCE-2024-2005-S4-REAL-PYQ-V1-COMPLETED-PRACTICE-TEST'
    ]::text[])
      and (
        t.test_type <> 'FULL_MOCK'
        or upper(t.test_name) like '%PYQ%'
      )
  ) then
    raise exception 'Completed-practice taxonomy correction did not reach the approved final state.'
      using errcode = 'P0001';
  end if;

  raise notice 'Completed-practice taxonomy names updated: %', v_updated;
end;
$$;

commit;
