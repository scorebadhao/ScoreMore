# ScoreMore Visual Fingerprint V2 and Simple Review Flow

## Problem confirmed from the admin recording

The Shift 3 batch showed 98 real drafts and two blocked records. Records 10 and 37 were unrelated diagram questions, but their transcribed text and placeholder options were generic. Fingerprint Version 1 compared only language, question text and options, so both collided with another visual draft even though their source images were different.

The batch therefore displayed two false duplicate/answer-conflict records and the main import action could not create the two remaining drafts.

## Fingerprint Version 2

Version 2 includes:

- language
- question text
- ordered options A-D
- content ID
- group/passage text
- SHA-256 digest of `image_refs`

The source image itself is not exposed in the compact import report. Only its digest participates in duplicate identity.

This keeps exact text questions deduplicated while separating unrelated diagram, table and figure questions that use generic wording.

## Recovery behavior

Opening an old batch and tapping **Import remaining drafts** now performs:

1. synchronize actual drafts;
2. recheck Version-1 unresolved items with Version 2;
3. create genuinely new drafts in small chunks;
4. link exact duplicates to an existing published master question;
5. reuse an existing draft without creating a copy;
6. publish nothing automatically.

For the recorded Shift 3 batch, the expected recovery is:

- existing drafts: 98
- Version-1 records rechecked: 2
- new drafts created: 2
- final drafts: 100

## True duplicate reuse

A genuine exact duplicate never creates a second master question.

- If the master question is already published, the new paper occurrence is linked immediately.
- If only a canonical draft exists, the duplicate is marked as reused. When that canonical draft is later published, the deferred PYQ occurrence is linked automatically.

## Human review UI

The draft list now loads lightweight summary columns only. Large `image_refs` are fetched for one draft only when the administrator opens it.

The simplified review screen shows:

1. source preview;
2. question and options;
3. proposed answer selection;
4. answer source;
5. primary topic;
6. collapsed explanation and optional notes;
7. **Verify & next** as the main action.

This preserves human verification while reducing scrolling and mobile payload size.
