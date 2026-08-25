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
20260805000050_catalogue_parent_prerequisites.sql
20260805000100_phase3e_compatibility.sql
20260805010000_import_recovery_fast_drafts.sql
20260805020000_visual_fingerprint_and_review_flow.sql
20260806000000_source_option_anomaly_publish_centre.sql
20260806010000_simple_test_builder_catalogue.sql
20260807010000_phase4a_dynamic_multifilter_test_builder.sql
20260807020000_mobile_test_runner_sections.sql
20260808010000_student_safe_image_repair_centre.sql
20260808020000_compulsory_student_image_readiness.sql
20260810010000_student_hub_v1.sql
20260811020000_public_catalogue_baseline.sql
20260814010000_draft_first_image_content_repair_workflow.sql
20260816010000_phase4a_safety_efficiency_v1.sql
20260817010000_phase4a_facet_performance_fix.sql
20260825010000_content_repair_integrity_gate.sql
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

- `20260806000000_source_option_anomaly_publish_centre.sql` preserves explicitly confirmed printed duplicate options in genuine PYQs, repairs Shift 1 V2 Q55 in place, and adds the admin-only verified Publish Centre RPCs.

- `20260806010000_simple_test_builder_catalogue.sql` adds paper-aware fixed-test saving and an audited admin-only test status RPC for the simplified Test Builder and Catalogue Control.

- `20260807010000_phase4a_dynamic_multifilter_test_builder.sql` adds the Phase 4A dynamic multi-filter test builder and protected preview/save workflows.

- `20260807020000_mobile_test_runner_sections.sql` adds the protected complete attempt navigator, persisted visit state, authoritative server timer/auto-submit, dynamic section support and student-safe image boundary for the mobile test runner.

- `20260808010000_student_safe_image_repair_centre.sql` adds the private approved-crop bucket, audited image-repair lifecycle, admin-only repair queue/RPCs and attempt-owned signed-image access without exposing raw source captures.

- `20260808020000_compulsory_student_image_readiness.sql` makes an audited visual-safety decision compulsory, filters unresolved questions from builders, guards test publication and new attempts, and supports the audited `NO_STUDENT_IMAGE_REQUIRED` decision.

- `20260810010000_student_hub_v1.sql` adds protected Home, Tests, Saved, Results and Profile RPCs; server-side catalogue filters; active-attempt answer protection; submitted-result analytics/review; safe profile editing; and revokes direct browser writes to bookmarks, mistake records and profile fields.


- `20260805000050_catalogue_parent_prerequisites.sql` ensures the GSSSB/CCE parent catalogue exists before dependent topic/catalogue seed data.

- `20260811020000_public_catalogue_baseline.sql` normalizes the public GSSSB CCE catalogue baseline with idempotent upserts.

- `20260814010000_draft_first_image_content_repair_workflow.sql` moves student-safe image/content repair before Final Review, preserves imported audit content and invalidates review after later repair changes.

- `20260816010000_phase4a_safety_efficiency_v1.sql` adds the guarded Phase 4A v1.5 preview/save wrappers, mode-aware publish blockers, neutral multi-package sectional identity enforcement and explicit source-package provenance.

- `20260817010000_phase4a_facet_performance_fix.sql` keeps Phase 4A facet loading within the locked performance boundary.

- `20260825010000_content_repair_integrity_gate.sql` adds an independent content-repair state for visual and non-visual drafts, exact audited Final Review-to-Repair routing, optimistic repair revisions, mandatory source/presentation confirmation and a server-side publication gate.
