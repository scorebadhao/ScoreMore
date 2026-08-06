# ScoreMore — Printed Option Anomaly and Separate Publish Centre

## Problem confirmed from Shift 1 V2

`GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2` record Q55 was blocked by `DUPLICATE_OPTIONS`.
The source paper itself prints option `640` twice, as options B and D. ScoreMore must preserve the authentic paper instead of inventing a replacement option, but it must also record that the anomaly was explicitly checked.

## Locked rule

Duplicate option values remain a blocking error by default.

They may become a warning only when all conditions are true:

- The record is a genuine `PYQ`.
- The source page and source Question ID are present.
- An administrator explicitly confirms `DUPLICATE_OPTIONS_PRINTED`.
- A traceability note explains what was checked.
- Human answer and topic review still occurs before publication.

This exception never guesses or rewrites a source option.

## Shift 1 V2 recovery

Migration `20260806000000_source_option_anomaly_publish_centre.sql` repairs only:

```text
Package: GSSSB-CCE-2024-0401-S1-REAL-PYQ-V2
Question: GSSSB-CCE-2024-QUANT-0401S1-0055
```

The existing import batch and 99 drafts remain unchanged. Q55 becomes `VALID_WITH_WARNINGS`, and the normal resumable **Import remaining drafts** action creates the 100th draft.

Expected final state:

```text
Shift 1 V2 drafts: 100
Published automatically: 0
Printed option anomaly: 1
```

## Separate Publish Centre

Human review and publication are now distinct operations.

### Review Centre

- Shows unreviewed drafts.
- Loads one source preview at a time.
- Confirms answer, answer source, topic and explanation.
- **Verify & next** moves the draft to the Publish Centre.
- It does not publish.

### Publish Centre

- Shows only drafts satisfying every publication prerequisite.
- Supports compact preview.
- Supports individual publication.
- Supports selecting and publishing verified questions in safe chunks.
- Each selected draft is rechecked by `publish_draft_question()`.
- A failed item remains unpublished and returns an explicit error.

The server accepts at most 25 selected drafts per RPC, while the mobile frontend sends chunks of 10.

## Security

- ADMIN role is required.
- `AI_PROPOSED` answers cannot enter the publish queue.
- Unverified or topic-unresolved PYQs cannot enter the publish queue.
- `UNREADABLE` source records cannot enter the publish queue.
- Printed duplicate options require a stored traceability note.
- Every successful publication keeps the existing publication audit log.
- Batch publication failures also create an audit record.
