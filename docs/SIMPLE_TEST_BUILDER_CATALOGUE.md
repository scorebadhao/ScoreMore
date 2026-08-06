# ScoreMore Simple Test Builder and Catalogue Control

## Purpose

This patch replaces the long fixed-test form and passive catalogue list with a mobile-first three-step builder and an actionable catalogue.

## Test Builder

1. **Test details** — choose type, enter name and use the optional ID suggestion.
2. **Catalogue and paper** — choose board/exam/subject/topic. PYQ types also require year, shift and paper code so one exact paper is loaded.
3. **Published questions** — load matching questions, search locally, select visible questions or clear the selection.

Advanced duration, marking and sort settings remain available in one collapsed panel.

The selected question order follows the loaded fixed list. For PYQ paper filters, questions are ordered by `original_question_no` and then `sort_order`.

## Catalogue Control

The catalogue now provides:

- All, Draft, Published and Archived counts
- Search by test name, ID, type, subject or paper
- Status filter
- Edit action that loads the complete fixed question list into the builder
- Publish, Archive and Restore Draft actions through an admin-only RPC
- Student view shortcut for published tests

## Database rules

`save_fixed_question_test_v2()` delegates all existing question/link validation to the locked `save_fixed_question_test()` function and additionally stores:

- exam year
- exam date
- shift number
- paper code
- section code

`set_admin_test_status()` is admin-only, audited and verifies complete published question links before publication.

No master question is copied. Tests continue to reuse `questions` through `test_question_links`.
