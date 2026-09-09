# Sectional Test Identity Safety and Batch Drafts

## Incident cause

The Phase 4A builder previously suggested this identity for every single-package sectional test:

```text
<PACKAGE_ID>-SECTIONAL-TEST
```

The subject was absent. Creating Gujarati and English sectional tests from the same package therefore sent the same primary key to the fixed-list writer. That writer intentionally supports edits through `ON CONFLICT (test_id) DO UPDATE`, so the later English save replaced the earlier Gujarati test metadata and question links.

Master questions were not deleted. The lost Gujarati fixed-list test can be reconstructed from the package membership.

## New identity contract

- One package and one subject: `<PACKAGE_ID>-<SUBJECT_ID>-SECTIONAL-TEST`
- Topic-narrowed sectional: includes a stable topic token.
- Multiple subjects: includes `MULTI-SUBJECT` and a stable scope token.
- Multiple packages: retains the neutral multi-package identity rule.
- The database rejects any existing Test ID whose saved package, subject or topic scope differs from the requested scope.

An exact same-scope save remains an edit. A different-scope save fails before the fixed-list writer can update anything.

## Batch workflow

In **Dynamic Test Builder → Sectional test**:

1. Select one or more active Paper / Package values.
2. Choose whether supplemental NORMAL questions are included.
3. In **Create every package subject**, set marks, negative marks and starting catalogue order.
4. Select **Preview all subjects**.
5. Review every row:
   - `Create draft` creates a missing subject test.
   - `Keep existing` leaves a legacy or current test unchanged.
   - `Review duplicates` or `ID conflict` blocks the whole batch.
6. Select **Create missing drafts** and confirm.
7. Review each draft's subject, language, question count, duration and marks before publishing it individually.

The database runs creation as one transaction. It creates all missing drafts or none. Batch creation never publishes and never overwrites an existing test.

## Educator-facing rules

- Every subject test uses the complete published package-by-subject set under the selected supplement setting.
- Suggested duration is approximately 36 seconds per question, rounded up to a five-minute boundary.
- All-source tests are typed and named as PYQ sectional tests.
- A set containing supplemental or other NORMAL content is typed and named as completed-practice sectional content, not an exact PYQ.
- Source-aware names are preferred over unstable `Test 1`, `Test 2` numbering.

## Recovery for 17 May 2024 Shift 3

The current package contains English, Gujarati, Quantitative Aptitude and Reasoning. Batch preview should keep the existing English test and offer new drafts for the missing Gujarati, Quantitative Aptitude and Reasoning tests. The Reasoning set includes supplemental content and must remain clearly labelled as completed practice.

## Acceptance checks

- Creating a Gujarati sectional and then an English sectional from one package produces different IDs and preserves both tests.
- Reusing an existing ID for another subject is rejected with no metadata or link change.
- Batch preview recognizes legacy package-only IDs by package plus stored subject.
- Repeating the same batch is idempotent: all rows become `Keep existing` and no new write is offered.
- One conflict blocks the complete batch.
- Anonymous and student accounts cannot execute preview or save RPCs.
- Newly generated items are Draft only.
- Mobile layout remains readable at 320–390 px without horizontal overflow.
