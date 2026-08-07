# ScoreMore Phase 4A — Dynamic Multi-Filter Test Builder

**Status:** implementation patch ready for deployment  
**Architecture:** additive Supabase migration + dedicated admin page  
**Import Package ID source:** `import_batches.package_id`  
**Test storage:** fixed references in `test_question_links`; master questions are never copied

## Purpose

Phase 4A lets an administrator build a fixed ScoreMore test from the published master-question catalogue by filtering one or more import packages, subjects, topics and other database-driven values.

The builder does not treat the monetization table `packages` as a source-paper catalogue. In this phase, “Package ID” means the immutable HTML import package identity stored in `import_batches.package_id`, for example:

- `GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2`
- `GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1`

## Locked behavior

### Dynamic filters

The server generates available values and counts from currently published questions. The interface supports:

- Import Package IDs
- Boards and exams
- Years and shifts
- Sections
- Subjects and topics
- Languages and difficulty
- Question types
- Package membership types

Selections inside one filter group use **OR**. Different filter groups use **AND**.

Example:

```text
Package = Shift 1 V2 OR Shift 3 V1
AND Subject = Reasoning OR English
AND Topic = Number Series OR Coding-Decoding
```

### Multi-select and selection persistence

- Package, subject and topic filters accept more than one value where the selected mode permits it.
- Manually selected questions remain selected while filters or pages change.
- “Select all filtered” is resolved by PostgreSQL, not only from the visible browser page.
- A maximum of 5,000 questions may be selected in one server-side select-all operation.

### Builder modes

| Mode | Package requirement | Questions resolved | Saved ScoreMore test type |
|---|---:|---|---|
| Custom selected | Optional | Only manually selected published master questions | Administrator-selected type |
| Original full PYQ | Exactly one active import package | Genuine `SOURCE_PYQ` memberships only; supplements excluded | `PYQ_FULL` |
| Completed PYQ practice | Exactly one active import package | Every published package question, including labelled supplemental/package NORMAL questions | `FULL_MOCK` |
| Sectional test | One or more active packages and one or more subjects | Filtered source/supplemental questions across selected packages | `PYQ_SECTIONAL` when source-only, otherwise `SECTIONAL_MOCK` |

Subject/topic filters may be used to inspect a full-paper package, but Original and Completed full modes authoritatively resolve the complete selected package. The preview warns when section filters were ignored for full-paper resolution.

### Package-version safety

A package is active when no newer import batch declares it in `supersedes_package_id`.

- Active versions appear by default.
- Superseded versions are hidden by default.
- Original and Completed full modes require an active package even when the diagnostic “Show superseded” option is enabled.

### Source and supplement accuracy

- `SOURCE_PYQ` comes from `question_occurrences` or a published PYQ directly traced to its import batch.
- `SUPPLEMENTAL_NORMAL` is a published question with `is_supplemental = true`.
- `PACKAGE_NORMAL` is another published NORMAL question traced to the package.
- Original full PYQ never includes supplemental or NORMAL questions.
- Completed practice includes all published memberships from the selected package and is not labelled as an exact original PYQ.

### Duplicate policy

ScoreMore’s existing test link and attempt schema permits a master question only once per test. Phase 4A therefore uses **UNIQUE_MASTER** handling:

- the same master question appearing in two selected packages is linked once;
- repeated package memberships are counted in preview warnings;
- no duplicate master row is created;
- original/source ordering is retained for the chosen representative membership.

### Save and publish safety

1. The browser asks PostgreSQL for an authoritative preview.
2. The save RPC resolves the same filters again.
3. Only published master questions are eligible.
4. All questions must belong to exactly one board and one exam.
5. The existing locked `save_fixed_question_test()` RPC remains the structural writer.
6. The test stores a fixed ordered list in `test_question_links`.
7. Phase 4A provenance is stored in `tests.question_filter`.
8. Tests with existing attempts remain structurally locked by the existing writer.
9. Publication uses the existing test catalogue and attempt engine.

## Database objects

### View

`phase4a_question_package_catalogue`

Maps published master questions to import-package memberships without copying question content.

### Admin-only RPCs

- `get_phase4a_test_builder_facets(jsonb)`
- `search_phase4a_test_builder_questions(jsonb,text,text,integer,integer)`
- `select_all_phase4a_test_builder_question_ids(jsonb,text,text)`
- `preview_phase4a_dynamic_test(text,jsonb,text[],text,test_type)`
- `save_phase4a_dynamic_test(text,text,text,jsonb,text[],text,test_type,integer,numeric,numeric,integer,boolean)`

All exposed Phase 4A RPCs recheck `public.is_admin()`. Internal helpers and the catalogue view are not directly granted to browser roles.

## Frontend files

- `test-builder.html`
- `assets/js/testBuilder4A.js`
- `assets/css/testBuilder4A.css`

The new page is dedicated to Phase 4A so the existing Review, Publish and Catalogue interfaces remain stable. It uses `assets/js/api.js` as the only browser data layer.

## API patch

Add the methods supplied in:

```text
patches/api.js_phase4a_methods.txt
```

Recommended insertion point: immediately before the existing `async listDrafts(...)` method inside the exported `api` object.

## Audit trail

Every successful Phase 4A save writes:

```text
admin_audit_logs.action = SAVE_PHASE4A_DYNAMIC_TEST
```

The audit details include builder mode, test type, question count, selected import package IDs, publication state and duplicate policy.

## Acceptance examples

After every question in the respective packages is human-reviewed and published:

- Shift 1 V2 Original full PYQ should resolve 100 source questions and 0 supplements.
- Shift 3 V1 Original full PYQ should resolve 99 source questions and show a partial-package warning.
- Shift 3 V1 Completed practice should resolve 100 questions: 99 source + 1 supplemental NORMAL.
- Shift 1 V2 + Shift 3 V1 with Reasoning should resolve the unique published Reasoning masters across both packages.
- Selecting Reasoning + English should apply OR between those subjects while the package filter remains an AND condition.

Actual counts remain dependent on how many drafts have reached `questions.question_status = 'PUBLISHED'`.
