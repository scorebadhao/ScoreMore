# ScoreMore Supabase migrations

Apply migrations in timestamp order through the controlled GitHub Actions database workflow.

```text
20260804000000_initial_scoremore_schema.sql
20260804010000_store_signup_mobile.sql
20260804020000_admin_fixed_test_manager.sql
20260804030000_phase3a_import_foundation.sql
```

Do not edit an already-applied migration. Add a new timestamped migration for every production schema change.

The Phase 3A migration adds import identities, item reconciliation, fingerprints, source occurrences, validation RPCs and the revised publication safeguards. It does not add the Phase 3B admin import UI.
