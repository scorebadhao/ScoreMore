# ScoreMore Supabase migrations

Apply migrations in timestamp order through the controlled GitHub Actions database workflow.

```text
20260804000000_initial_scoremore_schema.sql
20260804010000_store_signup_mobile.sql
20260804020000_admin_fixed_test_manager.sql
20260804030000_phase3a_import_foundation.sql
20260804040000_phase3b_import_dry_run.sql
20260804050000_allow_html_import_mime_types.sql
20260804060000_phase3c_controlled_draft_import.sql
20260805000000_add_ai_proposed_answer_source.sql
20260805000100_phase3e_compatibility.sql
20260805010000_import_recovery_fast_drafts.sql
```

Do not edit an already-applied migration. Add a new timestamped migration for every production schema change.

The Phase 3A migration adds import identities, item reconciliation, fingerprints, source occurrences, validation RPCs and revised publication safeguards.

The Phase 3B migration adds persistent HTML dry-run batches, item reconciliation, intra-package duplicate/conflict checks and report RPCs. It creates no drafts or published questions.

The HTML MIME hotfix preserves existing PDF/image uploads and permits private ScoreMore HTML packages in the source bucket.

- `20260804060000_phase3c_controlled_draft_import.sql` — admin-only revalidated batch-to-draft import and exact duplicate PYQ occurrence linking.


## Phase 3E compatibility

AI-proposed answers, canonical topic mapping, dynamic paper completeness, confidence/source-quality metadata and safely labelled supplemental NORMAL questions are supported. AI-proposed answers and unresolved PYQ topics remain blocked from publication until human review.

### `20260805010000_import_recovery_fast_drafts.sql`

Repairs the Phase 3E AI_PROPOSED false-invalid status, adds compact mobile reports, timeout reconciliation, resumable mobile-safe draft chunks, import-state synchronization and protected reset of untouched unpublished drafts.

- `20260805020000_visual_fingerprint_and_review_flow.sql` upgrades duplicate identity to visual-aware fingerprint Version 2, repairs old blocked visual records, reuses true duplicates and supports deferred occurrence linking.
