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
    'SOURCE_BOOK', 'ADMIN_CORRECTED', null,
  ],
  correct_answer: ['A', 'B', 'C', 'D', null],
});

const TOP_LEVEL_KEYS = new Set([
  'schema', 'schema_version', 'package_id', 'generated_at', 'generator',
  'source', 'defaults', 'questions',
]);
const SOURCE_KEYS = new Set([
  'source_type', 'original_file_name', 'board_id', 'exam_id', 'exam_year',
  'exam_date', 'shift_no', 'paper_code', 'language',
  'source_checksum_sha256', 'notes',
]);
const DEFAULT_KEYS = new Set([
  'question_type', 'board_id', 'exam_id', 'exam_year', 'exam_date', 'shift_no',
  'paper_code', 'section_code', 'language', 'difficulty', 'content_origin',
  'verification_status', 'answer_source', 'tags',
]);
const QUESTION_KEYS = new Set([
  'source_record_id', 'proposed_question_id', 'question_type', 'board_id',
  'exam_id', 'exam_year', 'exam_date', 'shift_no', 'paper_code',
  'original_question_no', 'sort_order', 'subject_id', 'topic_id',
  'section_code', 'language', 'difficulty', 'source_page',
  'source_question_id', 'content_origin', 'verification_status',
  'question_text', 'options', 'correct_answer', 'answer_source',
  'explanation', 'image_refs', 'content_id', 'group_id', 'group_type',
  'group_text', 'tags',
]);
const IMAGE_REF_KEYS = new Set(['ref', 'alt', 'source_page']);
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
  validateTags(defaults.tags, '$.defaults.tags', errors);
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

  validateSource(manifest.source, errors);
  validateDefaults(manifest.defaults, errors);

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
  if (!extensionOkay && !mimeOkay) throw new Error('Choose an .html, .htm or .xhtml ScoreMore import package.');
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
