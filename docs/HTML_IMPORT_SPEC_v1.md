# ScoreMore HTML Question Import Package Specification v1.0.0

**Status:** APPROVED AND LOCKED — Phase 3A  
**Schema name:** `scoremore.question-import`  
**Schema version:** `1.0.0`  
**Initial scope:** GSSSB CCE  
**Machine-readable schema:** `docs/scoremore-question-import.schema.v1.json`

## 1. Purpose

The ScoreMore HTML import package is a portable, human-readable container for accurately importing question records into the mandatory draft-review-publish workflow.

The HTML file is not a trusted application and is never rendered inside the ScoreMore admin page. ScoreMore reads only one structured JSON payload from the file.

```html
<script type="application/json" id="scoremore-import-data">
{
  "schema": "scoremore.question-import",
  "schema_version": "1.0.0",
  "package_id": "GSSSB-CCE-2024-0401-S1-V1",
  "source": {},
  "defaults": {},
  "questions": []
}
</script>
```

No JavaScript from the imported HTML is executed. Visible HTML may present a readable preview, but the JSON payload is authoritative.

## 2. Locked import workflow

```text
Choose HTML package
→ calculate raw-file and canonical-payload checksums
→ parse only #scoremore-import-data
→ validate package structure
→ merge package defaults into each item
→ validate every record against PostgreSQL catalogue data
→ compute strict and loose fingerprints
→ detect exact duplicates, possible duplicates and conflicts
→ persist dry-run reconciliation rows
→ admin confirms import actions
→ valid new records enter draft_questions
→ human review and correction
→ publish_draft_question()
→ questions
```

No HTML, CSV, PDF, OCR or AI import route may insert directly into `questions`.

## 3. Accuracy rules

1. Raw imported payloads are preserved in `import_batch_items.raw_payload`.
2. Normalized payloads are stored separately in `normalized_payload`.
3. Normalization is used only for validation and duplicate comparison; it does not rewrite stored source text.
4. Question text, options, mathematical symbols, Gujarati text, punctuation, source page and original question number must be preserved.
5. Missing answers may enter drafts with a warning, but publication remains blocked until verified.
6. Explanations may be added during human review.
7. AI must not silently invent a correct answer, source page, original question number or official metadata.
8. `RECONSTRUCTED` and `AI_GENERATED` content cannot be published as an original PYQ.

## 4. Duplicate identity

ScoreMore uses independent identity layers.

### Raw HTML checksum

`source_files.checksum_sha256` is SHA-256 over the exact uploaded HTML file bytes.

An exact file re-upload must reuse the previous source record and import report instead of creating another source file.

### Canonical package checksum

`import_batches.package_checksum_sha256` is SHA-256 over canonical JSON for the payload inside `#scoremore-import-data`.

Canonical JSON rules for Phase 3B:

- parse the JSON payload;
- recursively sort object keys;
- preserve array order;
- encode as UTF-8;
- remove insignificant JSON whitespace;
- hash the resulting bytes with SHA-256.

This detects the same package even when surrounding HTML formatting changes.

### Source checksum

`import_batches.source_checksum_sha256` stores the checksum of the original PDF/image source when available. It is different from the HTML package checksum.

### Strict question fingerprint

The server generates a strict SHA-256 fingerprint from:

```text
language
question_text
Option A
Option B
Option C
Option D
```

The correct answer, explanation, Question ID, board, exam and paper metadata are intentionally excluded. Therefore, identical question content cannot become another master question merely by changing its ID or source paper.

Strict normalization performs Unicode NFC normalization, lower-casing and whitespace normalization while preserving meaningful punctuation and symbols.

### Loose question fingerprint

The server also generates a warning-only fingerprint that removes punctuation/whitespace and sorts normalized option text. It may detect option reordering or minor OCR variation.

A loose match is never merged automatically. It becomes `POSSIBLE_DUPLICATE` and requires human review.

### Source occurrence key

A source occurrence key identifies one question position in one authentic paper using:

```text
board_id
exam_id
exam_year
exam_date
shift_no
paper_code
original_question_no
source_page
source_question_id
```

The same occurrence cannot be linked to different master content.

## 5. Content origin

Allowed `content_origin` values:

| Value | Meaning | PYQ publication |
|---|---|---|
| `SOURCE_EXTRACTED` | Transcribed directly from a reliable source | Allowed after review |
| `OCR_EXTRACTED` | Produced by OCR from a source image/PDF | Allowed after source comparison |
| `AI_TRANSCRIBED` | AI-assisted transcription of visible source content | Allowed after source comparison |
| `MANUAL_ENTRY` | Entered manually by an administrator | Allowed according to question type |
| `RECONSTRUCTED` | Missing source wording was reconstructed | Not allowed as original PYQ |
| `AI_GENERATED` | Newly generated content | Not allowed as original PYQ |

Content origin is independent from answer verification.

## 6. Answer source

Allowed `answer_source` values match the PostgreSQL enum:

- `OFFICIAL_FINAL_KEY`
- `OFFICIAL_PROVISIONAL_KEY`
- `MANUALLY_VERIFIED`
- `SOURCE_BOOK`
- `ADMIN_CORRECTED`

When an imported answer conflicts with matching master content, the item becomes `ANSWER_CONFLICT`. ScoreMore never overwrites the existing answer automatically.

## 7. Package object

Required top-level fields:

```json
{
  "schema": "scoremore.question-import",
  "schema_version": "1.0.0",
  "package_id": "GSSSB-CCE-2024-0401-S1-V1",
  "generated_at": "2026-08-04T12:00:00Z",
  "source": {},
  "defaults": {},
  "questions": []
}
```

`package_id` must be unique and stable. Do not reuse the same package ID for changed content. A corrected package must increment its version suffix, for example `...-V2`.

## 8. Source object

Recommended GSSSB CCE PYQ source object:

```json
{
  "source_type": "OFFICIAL_PDF",
  "original_file_name": "01-04-2024-CCE-Shift-1.pdf",
  "board_id": "GSSSB",
  "exam_id": "CCE",
  "exam_year": 2024,
  "exam_date": "2024-04-01",
  "shift_no": 1,
  "paper_code": "0401S1",
  "language": "GUJARATI"
}
```

The import engine must validate catalogue IDs against `boards`, `exams`, `subjects` and `topics`. Unknown catalogue records are errors; the importer does not create catalogue records silently.

## 9. Defaults object

Defaults reduce repeated metadata but do not override explicit item values.

```json
{
  "question_type": "PYQ",
  "language": "GUJARATI",
  "difficulty": "MEDIUM",
  "content_origin": "SOURCE_EXTRACTED",
  "verification_status": "NEEDS_CHECK",
  "board_id": "GSSSB",
  "exam_id": "CCE",
  "exam_year": 2024,
  "exam_date": "2024-04-01",
  "shift_no": 1,
  "paper_code": "0401S1"
}
```

Phase 3B merges in this order:

```text
source metadata
→ defaults
→ individual question values
```

The individual question value has highest priority.

## 10. Question object

Minimum valid four-option record:

```json
{
  "source_record_id": "Q001",
  "proposed_question_id": "GSSSB-CCE-2024-REASONING-0401S1-0001",
  "question_type": "PYQ",
  "board_id": "GSSSB",
  "exam_id": "CCE",
  "exam_year": 2024,
  "exam_date": "2024-04-01",
  "shift_no": 1,
  "paper_code": "0401S1",
  "original_question_no": 1,
  "sort_order": 1,
  "subject_id": "REASONING",
  "topic_id": null,
  "section_code": "REASONING",
  "language": "GUJARATI",
  "difficulty": "MEDIUM",
  "source_page": 1,
  "source_question_id": "Q1",
  "content_origin": "SOURCE_EXTRACTED",
  "verification_status": "NEEDS_CHECK",
  "question_text": "Question text",
  "options": {
    "A": "Option A",
    "B": "Option B",
    "C": "Option C",
    "D": "Option D"
  },
  "correct_answer": null,
  "answer_source": null,
  "explanation": null,
  "image_refs": [],
  "tags": []
}
```

### Required for every imported question

- `source_record_id`
- `proposed_question_id`
- `question_type`
- `board_id`
- `exam_id`
- `subject_id`
- `language`
- `difficulty`
- `sort_order`
- `content_origin`
- `verification_status`
- `question_text`
- exactly four text options: `A`, `B`, `C`, `D`

### Required for imported PYQs

- `exam_year`
- `exam_date`
- positive `shift_no`
- `paper_code`
- positive `original_question_no`
- positive `source_page`

`section_code` and `source_question_id` generate warnings when missing because they are important for reconciliation and sectional reuse.

### Correct answer

`correct_answer` may be `A`, `B`, `C`, `D` or `null`.

A null answer is allowed in the import dry run and drafts. `publish_draft_question()` still requires a verified answer.

## 11. Groups and passages

Grouped questions may use:

```json
{
  "group_id": "PASSAGE-0401S1-001",
  "group_type": "PASSAGE",
  "group_text": "Shared passage text"
}
```

Every item with the same `group_id` must use identical `group_type` and `group_text`. Phase 3B must report group inconsistencies.

## 12. Images

`image_refs` is always an array. A recommended item is:

```json
{
  "ref": "images/q001-diagram.png",
  "alt": "Diagram used in question 1",
  "source_page": 1
}
```

Image references do not grant public storage access. Source and import files remain private and admin-only.

## 13. Item validation statuses

Each `import_batch_items` row uses one of:

- `PENDING`
- `VALID`
- `VALID_WITH_WARNINGS`
- `INVALID`
- `EXACT_DUPLICATE`
- `POSSIBLE_DUPLICATE`
- `ID_CONFLICT`
- `ANSWER_CONFLICT`
- `SOURCE_CONFLICT`
- `IMPORTED_TO_DRAFT`
- `LINKED_TO_EXISTING`
- `SKIPPED`

## 14. Duplicate outcomes

| Condition | Result | Automatic write |
|---|---|---|
| Same raw HTML checksum | Return previous source/import report | None |
| Same package ID and checksum | `EXACT_DUPLICATE` | None |
| Same package ID, different checksum | `PACKAGE_ID_CONFLICT` | Block |
| Same Question ID, same strict content | `EXACT_DUPLICATE` | None |
| Same Question ID, different strict content | `ID_CONFLICT` | Block |
| Same strict content, different Question ID | `EXACT_DUPLICATE` | Link occurrence only after confirmation |
| Same content, different answer | `ANSWER_CONFLICT` | Block |
| Same occurrence, different content | `SOURCE_CONFLICT` | Block |
| Loose fingerprint match only | `POSSIBLE_DUPLICATE` | Human decision required |
| New valid content | `VALID` or `VALID_WITH_WARNINGS` | Draft only after confirmation |

## 15. Phase 3A and Phase 3B database RPCs

### `validate_import_package(manifest, package_checksum, source_checksum)`

Validates package identity and structure without writing records.

### `validate_import_question(question)`

Validates a fully merged question record against the live catalogue, computes fingerprints and reports duplicate/conflict matches without writing records.

### `link_question_occurrence(question_id, occurrence, import_batch_id, source_file_id, import_item_id)`

Admin-only trusted operation for linking a human-confirmed duplicate occurrence to an existing published master question. It never creates another master question.

### `stage_import_dry_run(manifest, raw_file_checksum, package_checksum, source_file_id)`

Phase 3B admin-only operation that persists one validated import batch and one reconciliation row per package question. It performs live catalogue checks, fingerprints, database duplicate checks, intra-package duplicate/conflict checks and group consistency checks. It creates no draft and no published question.

### `get_import_batch_report(import_batch_id)`

Returns the complete admin-only batch summary and ordered item-level reconciliation report.

## 16. Security

- All Phase 3 import tables use RLS.
- Only active admins may validate, stage, inspect or link imports.
- The browser uses only the publishable key.
- Source HTML/PDF/image files remain private.
- Imported HTML is never inserted into the DOM.
- Correct answers remain hidden from students during active attempts.
- `publish_draft_question()` remains the only question publication path.

## 17. Versioning

Changes that add, remove or reinterpret package fields require a new `schema_version` and a new machine-readable schema file.

Phase 3B rejects unsupported schema versions rather than guessing how to interpret them. The browser validator is an early safety gate; PostgreSQL remains authoritative for catalogue, duplicate and conflict outcomes.
