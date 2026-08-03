# ScoreBadhao → ScoreMore Metadata Mapping

This document is a compatibility reference only. It does not authorize live synchronization or migration.

## SCOREBADHAO_DB mapping

| ScoreBadhao sheet | ScoreMore PostgreSQL target | Notes |
|---|---|---|
| STUDENTS | `auth.users` + `profiles` | Password hashes are managed only by Supabase Auth. Do not import plaintext passwords. |
| ADMINS | `profiles.role = 'ADMIN'` | Admin authorization remains database controlled. |
| BOARDS | `boards` | Preserve `Board_ID`. |
| EXAMS | `exams` | Preserve `Exam_ID` and `Board_ID`. |
| SUBJECTS | `subjects` | Preserve `Subject_ID`. |
| TOPICS | `topics` | Preserve `Topic_ID`. |
| TESTS | `tests` + `test_question_links` | Convert `Question_Filter_JSON` keys to lowercase snake_case. |
| TEST_PACKAGES | `packages` | Preserve package business IDs. |
| PACKAGE_ACCESS | `package_access` | Map active/expired/revoked status and dates. |
| TEST_RESULTS | `attempts` | A submitted attempt is the normalized result row. |
| STUDENT_ANSWERS | `attempt_answers` | Unique by attempt and question. |
| MISTAKE_BOOK | `mistake_book` | Supports repeat count and resolved state. |
| BOOKMARKS | `bookmarks` | Unique per user and question. |
| PAYMENTS | `payments` | Provider metadata is JSONB. |
| PDF_UPLOAD_LOGS | `source_files` + `import_batches` | Store actual files in private Supabase Storage. |
| AI_IMPORT_LOGS | `import_batches` | AI content still enters drafts. |
| SETTINGS | `app_settings` | Public and private settings are separated by `is_public`. |
| SMART_RANK_ENGINE | `rank_snapshots` | Store time-based snapshots rather than one mutable row only. |

## SCOREBADHAO_QUESTIONS mapping

| ScoreBadhao sheet | ScoreMore PostgreSQL target | Notes |
|---|---|---|
| QUESTIONS | `questions` | `question_type = 'NORMAL'`. |
| PYQ_QUESTIONS | `questions` | `question_type = 'PYQ'`; store date, shift, paper and source metadata. |
| DRAFT_QUESTIONS | `draft_questions` | Mandatory staging table before publication. |
| QUESTION_IMPORT_LOGS | `import_batches` | Preserve totals, method, source and metadata version. |
| CONTENT_MASTER | `question_content` | One-to-one optional learning content. |

## Question field mapping

| Existing metadata | ScoreMore column |
|---|---|
| Question_ID / Published_Question_ID | `questions.question_id` |
| Draft_ID | `draft_questions.draft_id` |
| Board_ID | `board_id` |
| Exam_ID | `exam_id` |
| Year / Exam_Year | `exam_year` |
| Exam_Date | `exam_date` |
| Shift_No | `shift_no` |
| Paper_Code | `paper_code` |
| Question_Number / Original_Question_No | `original_question_no` |
| Subject_ID | `subject_id` |
| Topic_ID | `topic_id` |
| Section_Code | `section_code` |
| Question_Text | `question_text` |
| Option_A..Option_D | `options` JSONB keys A..D |
| Correct_Answer | `correct_answer` |
| Explanation | `explanation` |
| Language | `language` |
| Difficulty | `difficulty` |
| Image_Ref / Image_Refs_JSON | `image_refs` JSONB array |
| Content_ID | `content_id` |
| Source_File_ID | `source_file_id` |
| Source_Page | `source_page` |
| Source_Question_ID | `source_question_id` |
| Group_ID | `group_id` |
| Group_Type | `group_type` |
| Group_Text | `group_text` |
| Answer_Source | `answer_source` |
| Verification_Status | `verification_status` |
| Question_Status | `question_status` |
| Tags | `tags` text array |
| Import_ID / Import_Batch_ID | `import_batch_id` |

## Test filter conversion

ScoreBadhao example:

```json
{
  "Board_ID": "GSSSB",
  "Exam_ID": "CCE",
  "Year": 2024,
  "Exam_Date": "2024-04-01",
  "Shift_No": 1,
  "Paper_Code": "0401S1",
  "Section_Code": "REASONING",
  "Subject_ID": "REASONING"
}
```

ScoreMore equivalent:

```json
{
  "question_type": "PYQ",
  "board_id": "GSSSB",
  "exam_id": "CCE",
  "exam_year": 2024,
  "exam_date": "2024-04-01",
  "shift_no": 1,
  "paper_code": "0401S1",
  "section_code": "REASONING",
  "subject_id": "REASONING"
}
```

## Migration safety requirements

A future real migration must include:

1. Read-only export from ScoreBadhao
2. Field validation
3. Question ID duplicate detection
4. Foreign-key validation
5. Draft versus published separation
6. Dry-run import into a non-production Supabase branch/project
7. Row-count and checksum reconciliation
8. User approval
9. Production import
10. Rollback plan
