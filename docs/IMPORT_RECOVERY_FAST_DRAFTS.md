# ScoreMore Import Recovery and Resumable Drafts

## Failures confirmed from the Android recording

The recording shows three independent symptoms:

1. **False browser timeout.** A large validation request exceeded the previous generic client timeout. A browser timeout did not prove that PostgreSQL had rolled back; the server could still commit afterward.
2. **False `INVALID` status for AI-proposed answers.** Phase 3E correctly removed the inherited `INVALID_ANSWER_SOURCE` error for `AI_PROPOSED`, but the wrapper did not recalculate the inherited `INVALID` status. The Shift 1 package consequently displayed 100 invalid items even though the remaining item errors were empty.
3. **Heavy mobile response and all-at-once draft creation.** The reconciliation RPC returned both raw and normalized payloads, including embedded source previews. Draft creation also attempted a large batch in one request.

## Locked correction

- Recalculate a false inherited `INVALID` item to `VALID_WITH_WARNINGS` or `VALID` when no blocking error remains.
- Preserve genuine `INVALID`, duplicate and conflict statuses.
- Use operation-specific validation and staging timeouts.
- Recover timed-out dry runs through persistent package identity.
- Reconcile the item ledger against the actual `draft_questions` table before resuming.
- Import eligible records in idempotent chunks of 10.
- Revalidate every record immediately before its draft insert.
- Return a compact mobile report without duplicate raw payloads or embedded base64 source previews. The original payload and previews remain stored in PostgreSQL/Storage and flow into draft review.
- Render only the first 20 report cards initially; load more on demand.
- Allow a protected reset of only untouched `PENDING`, unreviewed, unpublished drafts.
- Protect reviewed/published drafts and preserve source, batch, item and audit history.

## Simplified primary workflow

The Admin import centre now has two primary steps:

1. **Validate package**
2. **Import eligible drafts**

Step 2 automatically performs safe preparation first:

```text
synchronize actual draft state
→ repair known false-invalid/stale records
→ show the current eligible count
→ request confirmation
→ create drafts in resumable chunks
→ synchronize again
```

The recovery controls remain under a collapsed advanced section.

## Existing batch recovery

### Shift 3 V1

`GSSSB-CCE-2024-0401-S3-REAL-PYQ-V1` should be opened and processed with the main Step 2 button. It will repair the old false-invalid items before asking to create drafts. The expected content is 99 source PYQs plus one clearly labelled supplemental NORMAL question.

### Shift 1 V1

`GSSSB-CCE-2024-0401-S1-REAL-PYQ-V1` is superseded by V2 and should not be imported. Open the report and use **Sync actual draft state**. If a timed-out operation actually created untouched drafts, use **Reset unreviewed drafts**; then import V2.

### Shift 1 V2

Validate and import `GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2`. It contains 100 original PYQs, no missing question and no supplement.

## Safety guarantees

- No recovery function writes to published `questions`.
- Import creates `draft_questions` only.
- Exact duplicates do not create another draft or master question.
- A repeated request recovers/reuses the existing draft by `import_item_id`.
- A timeout is followed by an authoritative database reconciliation.
- Reset cannot delete reviewed or published content.
- Cross-package draft references are revalidated if an untouched draft is reset.

## Read-only verification

After recovery, run `docs/IMPORT_RECOVERY_VERIFICATION.sql` in Supabase SQL Editor. It checks batch/item status, ledger-to-draft agreement, duplicate draft protection and confirms that recovery created no published master question automatically.
