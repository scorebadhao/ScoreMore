const IMPORT_SCHEMA = 'scoremore.question-import';
const IMPORT_SCHEMA_VERSION = '1.0.0';
const MAX_IMPORT_FILE_BYTES = 20 * 1024 * 1024;
const MAX_JSON_PAYLOAD_CHARS = 16 * 1024 * 1024;
const MAX_QUESTIONS = 2000;

const ENUMS = Object.freeze({
  question_type: ['NORMAL', 'PYQ'],
  difficulty: ['EASY', 'MEDIUM', 'HARD'],
  content_origin: [
    'SOURCE_EXTRACTED', 'OCR_EXTRACTED', 'AI_TRANSCRIBED',
    'MANUAL_ENTRY', 'RECONSTRUCTED', 'AI_GENERATED',
  ],
  verification_status: ['UNVERIFIED', 'NEEDS_CHECK', 'VERIFIED', 'DISPUTED'],
  answer_source: [
    'OFFICIAL_FINAL_KEY', 'OFFICIAL_PROVISIONAL_KEY', 'MANUALLY_VERIFIED',
    'SOURCE_BOOK', 'ADMIN_CORRECTED', 'AI_PROPOSED', null,
  ],
  correct_answer: ['A', 'B', 'C', 'D', null],
  confidence: ['HIGH', 'MEDIUM', 'LOW', null],
  source_quality: ['CLEAR', 'LOW_RESOLUTION', 'CROPPED', 'DIAGRAM_REVIEW', 'UNREADABLE', null],
  source_option_anomaly: ['NONE', 'DUPLICATE_OPTIONS_PRINTED', null],
  completeness_status: ['COMPLETE', 'PARTIAL', 'PARTIAL_WITH_SUPPLEMENTS', 'REJECTED'],
});

const TOP_LEVEL_KEYS = new Set([
  'schema', 'schema_version', 'package_id', 'generated_at', 'generator',
  'source', 'defaults', 'questions', 'package_version', 'supersedes_package_id', 'paper',
]);
const SOURCE_KEYS = new Set([
  'source_type', 'original_file_name', 'board_id', 'exam_id', 'exam_year',
  'exam_date', 'shift_no', 'paper_code', 'language',
  'source_checksum_sha256', 'notes',
]);
const DEFAULT_KEYS = new Set([
  'question_type', 'board_id', 'exam_id', 'exam_year', 'exam_date', 'shift_no',
  'paper_code', 'section_code', 'language', 'difficulty', 'content_origin',
  'verification_status', 'answer_source', 'transcription_confidence',
  'answer_confidence', 'topic_confidence', 'source_quality', 'source_option_anomaly',
  'source_option_anomaly_note', 'tags',
]);
const QUESTION_KEYS = new Set([
  'source_record_id', 'proposed_question_id', 'question_type', 'board_id',
  'exam_id', 'exam_year', 'exam_date', 'shift_no', 'paper_code',
  'original_question_no', 'sort_order', 'subject_id', 'topic_id',
  'section_code', 'language', 'difficulty', 'source_page',
  'source_question_id', 'content_origin', 'verification_status',
  'question_text', 'options', 'correct_answer', 'answer_source',
  'explanation', 'image_refs', 'content_id', 'group_id', 'group_type',
  'group_text', 'tags', 'suggested_topic_code', 'suggested_topic_name',
  'topic_confidence', 'transcription_confidence', 'answer_confidence',
  'answer_review_note', 'source_quality', 'source_option_anomaly',
  'source_option_anomaly_note', 'is_supplemental', 'supplement_reason',
]);
const IMAGE_REF_KEYS = new Set(['ref', 'alt', 'source_page']);
const PAPER_KEYS = new Set([
  'declared_total_questions', 'extracted_source_questions', 'missing_question_count',
  'missing_question_numbers', 'generated_supplement_count', 'completeness_status',
  'rejection_reason', 'section_plan',
]);
const SECTION_PLAN_KEYS = new Set([
  'section_code', 'subject_id', 'start_question_no', 'end_question_no',
  'expected_count', 'extracted_count', 'supplemental_count',
]);
const REQUIRED_TOP = ['schema', 'schema_version', 'package_id', 'source', 'defaults', 'questions'];
const REQUIRED_SOURCE = ['source_type', 'original_file_name', 'board_id', 'exam_id'];
const REQUIRED_RAW_QUESTION = [
  'source_record_id', 'proposed_question_id', 'subject_id',
  'sort_order', 'question_text', 'options',
];
const REQUIRED_EFFECTIVE_QUESTION = [
  'source_record_id', 'proposed_question_id', 'question_type', 'board_id',
  'exam_id', 'subject_id', 'language', 'difficulty', 'sort_order',
  'content_origin', 'verification_status', 'question_text', 'options',
];

function isPlainObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function issue(code, message, path = '$') {
  return { code, message, path };
}

function checkAdditionalKeys(object, allowed, path, errors) {
  if (!isPlainObject(object)) return;
  Object.keys(object).forEach((key) => {
    if (!allowed.has(key)) errors.push(issue('UNSUPPORTED_FIELD', `Unsupported field: ${key}`, `${path}.${key}`));
  });
}

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function isNullableString(value) {
  return value === null || typeof value === 'string';
}

function isPositiveInteger(value) {
  return Number.isInteger(value) && value > 0;
}

function isDate(value) {
  return typeof value === 'string'
    && /^\d{4}-\d{2}-\d{2}$/.test(value)
    && !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
}

function isDateTime(value) {
  return typeof value === 'string' && !Number.isNaN(Date.parse(value));
}

function isSha256(value) {
  return typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
}

function validateNullableInteger(value, path, errors, { min = null, max = null } = {}) {
  if (value === null || value === undefined) return;
  if (!Number.isInteger(value)) {
    errors.push(issue('INVALID_INTEGER', 'Expected an integer or null.', path));
    return;
  }
  if (min !== null && value < min) errors.push(issue('INTEGER_TOO_SMALL', `Must be at least ${min}.`, path));
  if (max !== null && value > max) errors.push(issue('INTEGER_TOO_LARGE', `Must be at most ${max}.`, path));
}

function validateTags(tags, path, errors) {
  if (tags === undefined) return;
  if (!Array.isArray(tags)) {
    errors.push(issue('INVALID_TAGS', 'tags must be an array of strings.', path));
    return;
  }
  const seen = new Set();
  tags.forEach((tag, index) => {
    if (typeof tag !== 'string') errors.push(issue('INVALID_TAG', 'Every tag must be a string.', `${path}[${index}]`));
    const key = String(tag).trim();
    if (seen.has(key)) errors.push(issue('DUPLICATE_TAG', 'tags must contain unique values.', `${path}[${index}]`));
    seen.add(key);
  });
}

function validateOptions(options, path, errors) {
  if (!isPlainObject(options)) {
    errors.push(issue('INVALID_OPTIONS', 'options must be an object with exactly A, B, C and D.', path));
    return;
  }
  checkAdditionalKeys(options, new Set(['A', 'B', 'C', 'D']), path, errors);
  ['A', 'B', 'C', 'D'].forEach((key) => {
    if (!isNonEmptyString(options[key])) errors.push(issue('INVALID_OPTION', `Option ${key} must be non-empty text.`, `${path}.${key}`));
  });
}

function validateImageRefs(imageRefs, path, errors) {
  if (imageRefs === undefined) return;
  if (!Array.isArray(imageRefs)) {
    errors.push(issue('INVALID_IMAGE_REFS', 'image_refs must be an array.', path));
    return;
  }
  imageRefs.forEach((item, index) => {
    const itemPath = `${path}[${index}]`;
    if (typeof item === 'string') {
      if (!item.trim()) errors.push(issue('INVALID_IMAGE_REF', 'Image reference text cannot be empty.', itemPath));
      return;
    }
    if (!isPlainObject(item)) {
      errors.push(issue('INVALID_IMAGE_REF', 'Each image reference must be text or an object.', itemPath));
      return;
    }
    checkAdditionalKeys(item, IMAGE_REF_KEYS, itemPath, errors);
    if (!isNonEmptyString(item.ref)) errors.push(issue('INVALID_IMAGE_REF', 'Image object requires a non-empty ref.', `${itemPath}.ref`));
    if (item.alt !== undefined && !isNullableString(item.alt)) errors.push(issue('INVALID_IMAGE_ALT', 'alt must be text or null.', `${itemPath}.alt`));
    validateNullableInteger(item.source_page, `${itemPath}.source_page`, errors, { min: 1 });
  });
}

function validateSource(source, errors) {
  if (!isPlainObject(source)) {
    errors.push(issue('INVALID_SOURCE_OBJECT', 'source must be an object.', '$.source'));
    return;
  }
  checkAdditionalKeys(source, SOURCE_KEYS, '$.source', errors);
  REQUIRED_SOURCE.forEach((key) => {
    if (!isNonEmptyString(source[key])) errors.push(issue('MISSING_SOURCE_FIELD', `${key} is required.`, `$.source.${key}`));
  });
  validateNullableInteger(source.exam_year, '$.source.exam_year', errors, { min: 1900, max: 2200 });
  if (source.exam_date !== undefined && source.exam_date !== null && !isDate(source.exam_date)) {
    errors.push(issue('INVALID_DATE', 'exam_date must use YYYY-MM-DD.', '$.source.exam_date'));
  }
  validateNullableInteger(source.shift_no, '$.source.shift_no', errors, { min: 1 });
  if (source.paper_code !== undefined && !isNullableString(source.paper_code)) errors.push(issue('INVALID_TEXT', 'paper_code must be text or null.', '$.source.paper_code'));
  if (source.language !== undefined && !isNullableString(source.language)) errors.push(issue('INVALID_TEXT', 'language must be text or null.', '$.source.language'));
  if (source.source_checksum_sha256 !== undefined && source.source_checksum_sha256 !== null && !isSha256(source.source_checksum_sha256)) {
    errors.push(issue('INVALID_SOURCE_CHECKSUM', 'source_checksum_sha256 must be lowercase SHA-256 hex.', '$.source.source_checksum_sha256'));
  }
}

function validateDefaults(defaults, errors) {
  if (!isPlainObject(defaults)) {
    errors.push(issue('INVALID_DEFAULTS_OBJECT', 'defaults must be an object.', '$.defaults'));
    return;
  }
  checkAdditionalKeys(defaults, DEFAULT_KEYS, '$.defaults', errors);
  ['question_type', 'difficulty', 'content_origin', 'verification_status'].forEach((key) => {
    if (defaults[key] !== undefined && !ENUMS[key]?.includes(defaults[key])) {
      errors.push(issue('INVALID_ENUM', `${key} has an unsupported value.`, `$.defaults.${key}`));
    }
  });
  if (defaults.answer_source !== undefined && !ENUMS.answer_source.includes(defaults.answer_source)) {
    errors.push(issue('INVALID_ENUM', 'answer_source has an unsupported value.', '$.defaults.answer_source'));
  }
  validateNullableInteger(defaults.exam_year, '$.defaults.exam_year', errors, { min: 1900, max: 2200 });
  validateNullableInteger(defaults.shift_no, '$.defaults.shift_no', errors, { min: 1 });
  if (defaults.exam_date !== undefined && defaults.exam_date !== null && !isDate(defaults.exam_date)) {
    errors.push(issue('INVALID_DATE', 'exam_date must use YYYY-MM-DD.', '$.defaults.exam_date'));
  }
  ['transcription_confidence', 'answer_confidence', 'topic_confidence'].forEach((key) => {
    if (defaults[key] !== undefined && !ENUMS.confidence.includes(defaults[key])) {
      errors.push(issue('INVALID_CONFIDENCE', `${key} must be HIGH, MEDIUM or LOW.`, `$.defaults.${key}`));
    }
  });
  if (defaults.source_quality !== undefined && !ENUMS.source_quality.includes(defaults.source_quality)) {
    errors.push(issue('INVALID_SOURCE_QUALITY', 'source_quality has an unsupported value.', '$.defaults.source_quality'));
  }
  if (defaults.source_option_anomaly !== undefined && !ENUMS.source_option_anomaly.includes(defaults.source_option_anomaly)) {
    errors.push(issue('INVALID_SOURCE_OPTION_ANOMALY', 'source_option_anomaly has an unsupported value.', '$.defaults.source_option_anomaly'));
  }
  if (defaults.source_option_anomaly_note !== undefined && !isNullableString(defaults.source_option_anomaly_note)) {
    errors.push(issue('INVALID_TEXT', 'source_option_anomaly_note must be text or null.', '$.defaults.source_option_anomaly_note'));
  }
  validateTags(defaults.tags, '$.defaults.tags', errors);
}

function validatePaper(paper, manifest, errors) {
  if (paper === undefined) return;
  if (!isPlainObject(paper)) {
    errors.push(issue('INVALID_PAPER_OBJECT', 'paper must be an object.', '$.paper'));
    return;
  }
  checkAdditionalKeys(paper, PAPER_KEYS, '$.paper', errors);
  const integerKeys = [
    'declared_total_questions', 'extracted_source_questions', 'missing_question_count',
    'generated_supplement_count',
  ];
  integerKeys.forEach((key) => validateNullableInteger(paper[key], `$.paper.${key}`, errors, { min: key === 'declared_total_questions' ? 1 : 0 }));
  if (!Array.isArray(paper.missing_question_numbers)) {
    errors.push(issue('INVALID_MISSING_NUMBERS', 'missing_question_numbers must be an array.', '$.paper.missing_question_numbers'));
  } else {
    const unique = new Set();
    paper.missing_question_numbers.forEach((value, index) => {
      if (!isPositiveInteger(value)) errors.push(issue('INVALID_MISSING_NUMBER', 'Every missing question number must be a positive integer.', `$.paper.missing_question_numbers[${index}]`));
      if (unique.has(value)) errors.push(issue('DUPLICATE_MISSING_NUMBER', 'Missing question numbers must be unique.', `$.paper.missing_question_numbers[${index}]`));
      unique.add(value);
    });
  }
  if (!ENUMS.completeness_status.includes(paper.completeness_status)) {
    errors.push(issue('INVALID_COMPLETENESS_STATUS', 'completeness_status is unsupported.', '$.paper.completeness_status'));
  }
  if (!Array.isArray(paper.section_plan)) {
    errors.push(issue('INVALID_SECTION_PLAN', 'section_plan must be an array.', '$.paper.section_plan'));
  } else {
    let previousEnd = 0;
    let totalExpected = 0;
    let totalExtracted = 0;
    let totalSupplemental = 0;
    paper.section_plan.forEach((row, index) => {
      const path = `$.paper.section_plan[${index}]`;
      if (!isPlainObject(row)) return errors.push(issue('INVALID_SECTION_PLAN_ROW', 'Each section row must be an object.', path));
      checkAdditionalKeys(row, SECTION_PLAN_KEYS, path, errors);
      ['section_code', 'subject_id'].forEach((key) => {
        if (!isNonEmptyString(row[key])) errors.push(issue('MISSING_SECTION_FIELD', `${key} is required.`, `${path}.${key}`));
      });
      ['start_question_no', 'end_question_no', 'expected_count', 'extracted_count', 'supplemental_count'].forEach((key) => {
        validateNullableInteger(row[key], `${path}.${key}`, errors, { min: key === 'supplemental_count' || key === 'extracted_count' ? 0 : 1 });
      });
      const start = Number(row.start_question_no);
      const end = Number(row.end_question_no);
      const expected = Number(row.expected_count);
      const extractedCount = Number(row.extracted_count);
      const supplementalCount = Number(row.supplemental_count);
      if ([start, end, expected, extractedCount, supplementalCount].every(Number.isInteger)) {
        if (end < start) errors.push(issue('INVALID_SECTION_BOUNDARY', 'end_question_no cannot be smaller than start_question_no.', `${path}.end_question_no`));
        if (expected !== end - start + 1) errors.push(issue('SECTION_EXPECTED_COUNT_MISMATCH', 'expected_count must equal the inclusive question-number range.', `${path}.expected_count`));
        if (index === 0 && start !== 1) errors.push(issue('SECTION_PLAN_MUST_START_AT_ONE', 'The first section must start at question 1.', `${path}.start_question_no`));
        if (index > 0 && start !== previousEnd + 1) errors.push(issue('SECTION_PLAN_NOT_CONTIGUOUS', 'Section ranges must be ordered and contiguous.', `${path}.start_question_no`));
        if (extractedCount + supplementalCount > expected) errors.push(issue('SECTION_RECORD_COUNT_EXCEEDED', 'Extracted plus supplemental records cannot exceed the section expected count.', path));
        previousEnd = end;
        totalExpected += expected;
        totalExtracted += extractedCount;
        totalSupplemental += supplementalCount;
      }
    });
    if (paper.section_plan.length && Number.isInteger(Number(paper.declared_total_questions))) {
      if (previousEnd !== Number(paper.declared_total_questions)) errors.push(issue('SECTION_PLAN_END_MISMATCH', 'The last section must end at declared_total_questions.', '$.paper.section_plan'));
      if (totalExpected !== Number(paper.declared_total_questions)) errors.push(issue('SECTION_EXPECTED_TOTAL_MISMATCH', 'Section expected counts must sum to declared_total_questions.', '$.paper.section_plan'));
      if (totalExtracted !== Number(paper.extracted_source_questions)) errors.push(issue('SECTION_EXTRACTED_TOTAL_MISMATCH', 'Section extracted counts must sum to extracted_source_questions.', '$.paper.section_plan'));
      if (totalSupplemental !== Number(paper.generated_supplement_count || 0)) errors.push(issue('SECTION_SUPPLEMENT_TOTAL_MISMATCH', 'Section supplemental counts must sum to generated_supplement_count.', '$.paper.section_plan'));
    }
  }

  const declared = Number(paper.declared_total_questions);
  const extracted = Number(paper.extracted_source_questions);
  const missing = Number(paper.missing_question_count || 0);
  const generated = Number(paper.generated_supplement_count || 0);
  const missingNumbers = Array.isArray(paper.missing_question_numbers) ? paper.missing_question_numbers : [];
  const questionCount = Array.isArray(manifest.questions) ? manifest.questions.length : 0;
  const actualSupplements = Array.isArray(manifest.questions)
    ? manifest.questions.filter((question) => question?.is_supplemental === true).length
    : 0;

  if (Number.isInteger(missing) && missing !== missingNumbers.length) errors.push(issue('MISSING_COUNT_MISMATCH', 'missing_question_count must equal missing_question_numbers length.', '$.paper.missing_question_count'));
  if (Number.isInteger(declared) && missingNumbers.some((value) => Number.isInteger(value) && value > declared)) errors.push(issue('MISSING_NUMBER_OUT_OF_RANGE', 'Missing question numbers cannot exceed declared_total_questions.', '$.paper.missing_question_numbers'));
  if (Number.isInteger(declared) && Number.isInteger(extracted) && declared !== extracted + missing) errors.push(issue('PAPER_TOTAL_MISMATCH', 'declared_total_questions must equal extracted_source_questions plus missing_question_count.', '$.paper'));
  if (missing > 10) errors.push(issue('MISSING_QUESTION_LIMIT_EXCEEDED', 'More than 10 missing source questions rejects the PYQ package.', '$.paper.missing_question_count'));
  if (actualSupplements !== generated) errors.push(issue('SUPPLEMENT_COUNT_MISMATCH', 'generated_supplement_count must equal supplemental records.', '$.paper.generated_supplement_count'));
  if (Number.isInteger(extracted) && questionCount !== extracted + generated) errors.push(issue('PACKAGE_RECORD_COUNT_MISMATCH', 'questions length must equal extracted_source_questions plus generated_supplement_count.', '$.questions'));
  if (generated > missing) errors.push(issue('TOO_MANY_SUPPLEMENTS', 'Supplemental questions cannot exceed missing source questions.', '$.paper.generated_supplement_count'));
  if (missing === 0 && (paper.completeness_status !== 'COMPLETE' || generated !== 0)) errors.push(issue('COMPLETENESS_STATUS_MISMATCH', 'Complete papers cannot contain missing or supplemental questions.', '$.paper.completeness_status'));
  if (missing >= 1 && missing <= 10 && generated === 0 && paper.completeness_status !== 'PARTIAL') errors.push(issue('COMPLETENESS_STATUS_MISMATCH', 'Missing questions without supplements requires PARTIAL status.', '$.paper.completeness_status'));
  if (missing >= 1 && missing <= 10 && generated === missing && paper.completeness_status !== 'PARTIAL_WITH_SUPPLEMENTS') errors.push(issue('COMPLETENESS_STATUS_MISMATCH', 'Fully supplemented incomplete papers require PARTIAL_WITH_SUPPLEMENTS.', '$.paper.completeness_status'));
  if (missing > 10 && paper.completeness_status !== 'REJECTED') errors.push(issue('COMPLETENESS_STATUS_MISMATCH', 'More than 10 missing questions requires REJECTED status.', '$.paper.completeness_status'));
  if (paper.completeness_status === 'REJECTED' && !isNonEmptyString(paper.rejection_reason)) errors.push(issue('REJECTION_REASON_REQUIRED', 'Rejected packages require a clear rejection_reason.', '$.paper.rejection_reason'));
}

function sourceDefaults(source = {}) {
  return {
    board_id: source.board_id,
    exam_id: source.exam_id,
    exam_year: source.exam_year,
    exam_date: source.exam_date,
    shift_no: source.shift_no,
    paper_code: source.paper_code,
    language: source.language,
  };
}

function mergeQuestion(manifest, question) {
  return {
    ...sourceDefaults(manifest.source),
    ...(manifest.defaults || {}),
    ...question,
  };
}

function validateRawQuestion(question, index, manifest, errors, warnings) {
  const base = `$.questions[${index}]`;
  if (!isPlainObject(question)) {
    errors.push(issue('INVALID_QUESTION_OBJECT', 'Question entry must be an object.', base));
    return null;
  }
  checkAdditionalKeys(question, QUESTION_KEYS, base, errors);
  REQUIRED_RAW_QUESTION.forEach((key) => {
    if (question[key] === undefined || question[key] === null || question[key] === '') {
      errors.push(issue('MISSING_QUESTION_FIELD', `${key} is required in every questions[] record.`, `${base}.${key}`));
    }
  });

  if (question.source_record_id !== undefined && !isNonEmptyString(question.source_record_id)) errors.push(issue('INVALID_SOURCE_RECORD_ID', 'source_record_id must be non-empty text.', `${base}.source_record_id`));
  if (question.proposed_question_id !== undefined && (typeof question.proposed_question_id !== 'string' || !/^[A-Z0-9]+(?:-[A-Z0-9]+)+$/.test(question.proposed_question_id))) {
    errors.push(issue('INVALID_QUESTION_ID', 'proposed_question_id does not match the locked format.', `${base}.proposed_question_id`));
  }
  if (question.subject_id !== undefined && !isNonEmptyString(question.subject_id)) errors.push(issue('INVALID_SUBJECT_ID', 'subject_id must be non-empty text.', `${base}.subject_id`));
  if (question.sort_order !== undefined && !isPositiveInteger(question.sort_order)) errors.push(issue('INVALID_SORT_ORDER', 'sort_order must be a positive integer.', `${base}.sort_order`));
  if (question.question_text !== undefined && !isNonEmptyString(question.question_text)) errors.push(issue('INVALID_QUESTION_TEXT', 'question_text must be non-empty source text.', `${base}.question_text`));
  validateOptions(question.options, `${base}.options`, errors);

  ['question_type', 'difficulty', 'content_origin', 'verification_status'].forEach((key) => {
    if (question[key] !== undefined && !ENUMS[key]?.includes(question[key])) errors.push(issue('INVALID_ENUM', `${key} has an unsupported value.`, `${base}.${key}`));
  });
  if (question.correct_answer !== undefined && !ENUMS.correct_answer.includes(question.correct_answer)) errors.push(issue('INVALID_CORRECT_ANSWER', 'correct_answer must be A, B, C, D or null.', `${base}.correct_answer`));
  if (question.answer_source !== undefined && !ENUMS.answer_source.includes(question.answer_source)) errors.push(issue('INVALID_ANSWER_SOURCE', 'answer_source has an unsupported value.', `${base}.answer_source`));
  ['topic_confidence', 'transcription_confidence', 'answer_confidence'].forEach((key) => {
    if (question[key] !== undefined && !ENUMS.confidence.includes(question[key])) errors.push(issue('INVALID_CONFIDENCE', `${key} must be HIGH, MEDIUM or LOW.`, `${base}.${key}`));
  });
  if (question.source_quality !== undefined && !ENUMS.source_quality.includes(question.source_quality)) errors.push(issue('INVALID_SOURCE_QUALITY', 'source_quality has an unsupported value.', `${base}.source_quality`));
  if (question.source_option_anomaly !== undefined && !ENUMS.source_option_anomaly.includes(question.source_option_anomaly)) errors.push(issue('INVALID_SOURCE_OPTION_ANOMALY', 'source_option_anomaly has an unsupported value.', `${base}.source_option_anomaly`));
  if (question.is_supplemental !== undefined && typeof question.is_supplemental !== 'boolean') errors.push(issue('INVALID_BOOLEAN', 'is_supplemental must be true or false.', `${base}.is_supplemental`));
  ['suggested_topic_code', 'suggested_topic_name', 'answer_review_note', 'source_option_anomaly_note', 'supplement_reason'].forEach((key) => {
    if (question[key] !== undefined && question[key] !== null && typeof question[key] !== 'string') errors.push(issue('INVALID_TEXT', `${key} must be text or null.`, `${base}.${key}`));
  });

  validateNullableInteger(question.exam_year, `${base}.exam_year`, errors, { min: 1900, max: 2200 });
  validateNullableInteger(question.shift_no, `${base}.shift_no`, errors, { min: 1 });
  validateNullableInteger(question.original_question_no, `${base}.original_question_no`, errors, { min: 1 });
  validateNullableInteger(question.source_page, `${base}.source_page`, errors, { min: 1 });
  if (question.exam_date !== undefined && question.exam_date !== null && !isDate(question.exam_date)) errors.push(issue('INVALID_DATE', 'exam_date must use YYYY-MM-DD.', `${base}.exam_date`));
  validateTags(question.tags, `${base}.tags`, errors);
  validateImageRefs(question.image_refs, `${base}.image_refs`, errors);

  const merged = mergeQuestion(manifest, question);
  REQUIRED_EFFECTIVE_QUESTION.forEach((key) => {
    const value = merged[key];
    if (value === undefined || value === null || value === '') {
      errors.push(issue('MISSING_EFFECTIVE_FIELD', `${key} is required after source/default merging.`, `${base}.${key}`));
    }
  });
  if (merged.question_type === 'PYQ') {
    [
      ['exam_year', merged.exam_year], ['exam_date', merged.exam_date],
      ['shift_no', merged.shift_no], ['paper_code', merged.paper_code],
      ['original_question_no', merged.original_question_no], ['source_page', merged.source_page],
    ].forEach(([key, value]) => {
      if (value === undefined || value === null || value === '') errors.push(issue('MISSING_PYQ_FIELD', `${key} is required for PYQ records.`, `${base}.${key}`));
    });
    if (!merged.section_code) warnings.push(issue('MISSING_SECTION_CODE', 'section_code is recommended for sectional reuse.', `${base}.section_code`));
    if (!merged.source_question_id) warnings.push(issue('MISSING_SOURCE_QUESTION_ID', 'source_question_id is recommended for source reconciliation.', `${base}.source_question_id`));
  }
  if (merged.correct_answer === null || merged.correct_answer === undefined || merged.correct_answer === '') {
    warnings.push(issue('MISSING_CORRECT_ANSWER', 'The record may enter a dry run, but publication will require a verified answer.', `${base}.correct_answer`));
  }
  if (!merged.explanation) warnings.push(issue('MISSING_EXPLANATION', 'Explanation can be added during human review.', `${base}.explanation`));
  if (merged.answer_source === 'AI_PROPOSED') {
    if (!merged.correct_answer) errors.push(issue('AI_ANSWER_MISSING', 'AI_PROPOSED requires a proposed correct_answer.', `${base}.correct_answer`));
    if (!['HIGH', 'MEDIUM', 'LOW'].includes(merged.answer_confidence)) errors.push(issue('AI_ANSWER_CONFIDENCE_REQUIRED', 'AI_PROPOSED requires answer_confidence.', `${base}.answer_confidence`));
    if (!merged.explanation) errors.push(issue('AI_EXPLANATION_REQUIRED', 'AI_PROPOSED requires an explanation.', `${base}.explanation`));
    if (merged.verification_status === 'VERIFIED') errors.push(issue('AI_ANSWER_CANNOT_BE_PREVERIFIED', 'AI_PROPOSED must remain NEEDS_CHECK until human review.', `${base}.verification_status`));
    warnings.push(issue('AI_PROPOSED_ANSWER_REQUIRES_REVIEW', 'Admin confirmation is required before publication.', `${base}.answer_source`));
  }
  if (merged.source_option_anomaly === 'DUPLICATE_OPTIONS_PRINTED') {
    if (merged.question_type !== 'PYQ') errors.push(issue('OPTION_ANOMALY_REQUIRES_PYQ', 'Printed duplicate-option confirmation is allowed only for genuine PYQs.', `${base}.source_option_anomaly`));
    if (!isNonEmptyString(merged.source_option_anomaly_note)) errors.push(issue('OPTION_ANOMALY_NOTE_REQUIRED', 'Add a source traceability note for printed duplicate options.', `${base}.source_option_anomaly_note`));
    const normalizedOptions = ['A', 'B', 'C', 'D'].map((key) => String(merged.options?.[key] || '').normalize('NFC').trim().replace(/\s+/g, ' '));
    if (new Set(normalizedOptions).size === 4) errors.push(issue('OPTION_ANOMALY_NOT_PRESENT', 'All four options are distinct; remove the duplicate-option anomaly flag.', `${base}.source_option_anomaly`));
    else warnings.push(issue('SOURCE_DUPLICATE_OPTIONS_PRINTED', 'The source prints repeated option values. Preserve them exactly and verify the answer during human review.', `${base}.options`));
  }
  if (merged.is_supplemental === true) {
    if (merged.question_type !== 'NORMAL' || merged.content_origin !== 'AI_GENERATED') errors.push(issue('INVALID_SUPPLEMENTAL_ORIGIN', 'Supplemental questions must be NORMAL and AI_GENERATED.', base));
    if (!merged.supplement_reason) errors.push(issue('MISSING_SUPPLEMENT_REASON', 'Supplemental questions require supplement_reason.', `${base}.supplement_reason`));
    if (merged.original_question_no || merged.source_question_id) errors.push(issue('SUPPLEMENT_CANNOT_IMPERSONATE_PYQ', 'Supplemental questions cannot carry original PYQ identity.', base));
  }
  return merged;
}

function validateGroupConsistency(mergedQuestions, errors) {
  const groups = new Map();
  mergedQuestions.forEach((question, index) => {
    const groupId = typeof question?.group_id === 'string' ? question.group_id.trim() : '';
    if (!groupId) return;
    const signature = JSON.stringify({ group_type: question.group_type ?? null, group_text: question.group_text ?? null });
    const previous = groups.get(groupId);
    if (!previous) {
      groups.set(groupId, { signature, index });
      return;
    }
    if (previous.signature !== signature) {
      errors.push(issue(
        'GROUP_METADATA_CONFLICT',
        `group_id ${groupId} uses inconsistent group_type or group_text.`,
        `$.questions[${index}].group_id`,
      ));
    }
  });
}

function validateManifestSchema(manifest) {
  const errors = [];
  const warnings = [];
  const itemErrors = [];
  const itemWarnings = [];

  if (!isPlainObject(manifest)) {
    return { valid: false, errors: [issue('INVALID_PACKAGE_OBJECT', 'The JSON payload must be an object.')], warnings, itemErrors, itemWarnings };
  }
  checkAdditionalKeys(manifest, TOP_LEVEL_KEYS, '$', errors);
  REQUIRED_TOP.forEach((key) => {
    if (!(key in manifest)) errors.push(issue('MISSING_TOP_LEVEL_FIELD', `${key} is required.`, `$.${key}`));
  });
  if (manifest.schema !== IMPORT_SCHEMA) errors.push(issue('UNSUPPORTED_SCHEMA', `schema must equal ${IMPORT_SCHEMA}.`, '$.schema'));
  if (manifest.schema_version !== IMPORT_SCHEMA_VERSION) errors.push(issue('UNSUPPORTED_SCHEMA_VERSION', `Only ${IMPORT_SCHEMA_VERSION} is supported.`, '$.schema_version'));
  if (typeof manifest.package_id !== 'string' || !/^[A-Z0-9][A-Z0-9._-]{5,119}$/.test(manifest.package_id)) errors.push(issue('INVALID_PACKAGE_ID', 'package_id must use 6-120 uppercase letters, numbers, dots, underscores or hyphens.', '$.package_id'));
  if (manifest.generated_at !== undefined && !isDateTime(manifest.generated_at)) errors.push(issue('INVALID_GENERATED_AT', 'generated_at must be an ISO date-time.', '$.generated_at'));
  if (manifest.generated_at === undefined) warnings.push(issue('MISSING_GENERATED_AT', 'generated_at is recommended for audit history.', '$.generated_at'));
  if (manifest.generator !== undefined && (typeof manifest.generator !== 'string' || manifest.generator.length > 200)) errors.push(issue('INVALID_GENERATOR', 'generator must be text of at most 200 characters.', '$.generator'));
  if (manifest.package_version !== undefined && !isPositiveInteger(manifest.package_version)) errors.push(issue('INVALID_PACKAGE_VERSION', 'package_version must be a positive integer.', '$.package_version'));
  if (manifest.supersedes_package_id !== undefined && manifest.supersedes_package_id !== null && !isNonEmptyString(manifest.supersedes_package_id)) errors.push(issue('INVALID_SUPERSEDES_PACKAGE', 'supersedes_package_id must be text or null.', '$.supersedes_package_id'));

  validateSource(manifest.source, errors);
  validateDefaults(manifest.defaults, errors);
  validatePaper(manifest.paper, manifest, errors);

  if (!Array.isArray(manifest.questions)) {
    errors.push(issue('INVALID_QUESTIONS_ARRAY', 'questions must be an array.', '$.questions'));
  } else if (!manifest.questions.length || manifest.questions.length > MAX_QUESTIONS) {
    errors.push(issue('INVALID_QUESTION_COUNT', `questions must contain 1-${MAX_QUESTIONS} records.`, '$.questions'));
  }

  const mergedQuestions = [];
  if (Array.isArray(manifest.questions)) {
    manifest.questions.forEach((question, index) => {
      const questionErrors = [];
      const questionWarnings = [];
      const merged = validateRawQuestion(question, index, manifest, questionErrors, questionWarnings);
      itemErrors[index] = questionErrors;
      itemWarnings[index] = questionWarnings;
      if (merged) mergedQuestions[index] = merged;
    });
    validateGroupConsistency(mergedQuestions, errors);
  }

  return {
    valid: errors.length === 0 && itemErrors.every((rows) => !rows?.length),
    errors,
    warnings,
    itemErrors,
    itemWarnings,
    mergedQuestions,
  };
}

function canonicalJson(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
}

async function sha256Hex(input) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes < 0) return '—';
  if (bytes < 1024) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB'];
  let value = bytes / 1024;
  let unit = units[0];
  for (let index = 1; index < units.length && value >= 1024; index += 1) {
    value /= 1024;
    unit = units[index];
  }
  return `${value.toFixed(value >= 10 ? 1 : 2)} ${unit}`;
}

function parseTagAttributes(openingTag) {
  const attributes = {};
  const body = openingTag.replace(/^<script\b/i, '').replace(/>$/, '');
  const pattern = /([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/g;
  let match;
  while ((match = pattern.exec(body))) {
    attributes[match[1].toLowerCase()] = match[2] ?? match[3] ?? match[4] ?? '';
  }
  return attributes;
}

function extractImportPayloadText(htmlText) {
  const lowerHtml = htmlText.toLowerCase();
  const scriptOpenPattern = /<script\b[^>]*>/gi;
  const payloads = [];
  let match;
  while ((match = scriptOpenPattern.exec(htmlText))) {
    const attributes = parseTagAttributes(match[0]);
    const closeStart = lowerHtml.indexOf('</script>', scriptOpenPattern.lastIndex);
    if (closeStart < 0) throw new Error('The HTML contains an unclosed script element.');
    const closeEnd = closeStart + '</script>'.length;
    if (attributes.id === 'scoremore-import-data' && String(attributes.type || '').toLowerCase() === 'application/json') {
      payloads.push(htmlText.slice(scriptOpenPattern.lastIndex, closeStart));
    }
    scriptOpenPattern.lastIndex = closeEnd;
  }
  if (payloads.length !== 1) {
    throw new Error('The HTML package must contain exactly one application/json script with id="scoremore-import-data".');
  }
  return payloads[0];
}

async function parseImportHtml(file) {
  if (!(file instanceof File) || !file.size) throw new Error('Choose a non-empty HTML import package.');
  if (file.size > MAX_IMPORT_FILE_BYTES) throw new Error('The HTML package exceeds the 20 MB Phase 3B limit.');
  const extensionOkay = /\.(html?|xhtml)$/i.test(file.name);
  const mimeOkay = ['text/html', 'application/xhtml+xml', ''].includes((file.type || '').toLowerCase());
  if (!extensionOkay && !mimeOkay) throw new Error('Choose an .html, .htm or .xhtml question import package.');
  if (!globalThis.crypto?.subtle) throw new Error('Secure SHA-256 hashing is not available in this browser.');

  const bytes = await file.arrayBuffer();
  const rawChecksum = await sha256Hex(bytes);
  let htmlText;
  try {
    htmlText = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw new Error('The import package must be valid UTF-8 HTML.');
  }

  // Parse the fixed script envelope directly from text. No DOM is created, so
  // imported resources, markup and scripts cannot execute or load.
  const payloadText = extractImportPayloadText(htmlText);
  if (!payloadText.trim()) throw new Error('The scoremore-import-data JSON payload is empty.');
  if (payloadText.length > MAX_JSON_PAYLOAD_CHARS) throw new Error('The embedded JSON payload exceeds the 16 MB limit.');

  let manifest;
  try {
    manifest = JSON.parse(payloadText);
  } catch (error) {
    throw new Error(`The embedded JSON is invalid: ${error.message}`);
  }

  const canonicalPayload = canonicalJson(manifest);
  const packageChecksum = await sha256Hex(canonicalPayload);
  const schemaValidation = validateManifestSchema(manifest);

  return {
    file,
    manifest,
    canonicalPayload,
    rawChecksum,
    packageChecksum,
    schemaValidation,
    metadata: {
      fileName: file.name,
      fileSize: file.size,
      fileSizeLabel: formatBytes(file.size),
      mimeType: file.type || 'text/html',
      packageId: manifest?.package_id || '—',
      schemaVersion: manifest?.schema_version || '—',
      questionCount: Array.isArray(manifest?.questions) ? manifest.questions.length : 0,
      packageVersion: manifest?.package_version || 1,
      paper: manifest?.paper || null,
    },
  };
}

function downloadJson(filename, value) {
  const blob = new Blob([JSON.stringify(value, null, 2)], { type: 'application/json;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

export {
  IMPORT_SCHEMA,
  IMPORT_SCHEMA_VERSION,
  canonicalJson,
  downloadJson,
  formatBytes,
  mergeQuestion,
  parseImportHtml,
  sha256Hex,
  validateManifestSchema,
};
