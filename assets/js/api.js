import { APP_CONFIG } from './config.js';
import { requireSupabase } from './supabaseClient.js';

function normalizeError(error, fallback = 'Something went wrong.') {
  if (!error) return new Error(fallback);
  const message = error.message || error.error_description || error.details || fallback;
  const normalized = new Error(message);
  normalized.code = error.code || 'UNKNOWN_ERROR';
  normalized.details = error.details || '';
  return normalized;
}

async function withTimeout(operation, timeoutMs = APP_CONFIG.requestTimeoutMs) {
  let timer;
  try {
    return await Promise.race([
      operation,
      new Promise((_, reject) => {
        timer = window.setTimeout(() => {
          const timeoutError = new Error('Request timed out. The server may still be processing this operation.');
          timeoutError.code = 'REQUEST_TIMEOUT';
          timeoutError.mayStillComplete = true;
          reject(timeoutError);
        }, timeoutMs);
      }),
    ]);
  } finally {
    window.clearTimeout(timer);
  }
}

function unwrap(response, fallback) {
  if (response?.error) throw normalizeError(response.error, fallback);
  return response?.data;
}

function clean(value) {
  return typeof value === 'string' ? value.trim() : value;
}

const STUDENT_IMAGE_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp']);
const STUDENT_IMAGE_MAX_BYTES = 5 * 1024 * 1024;

async function sha256File(file) {
  const digest = await window.crypto.subtle.digest('SHA-256', await file.arrayBuffer());
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function inspectImageFile(file) {
  if (!(file instanceof File) || !file.size) throw new Error('Choose a diagram-only image crop.');
  if (!STUDENT_IMAGE_TYPES.has(file.type)) throw new Error('Use a PNG, JPEG or WebP image crop.');
  if (file.size > STUDENT_IMAGE_MAX_BYTES) throw new Error('Student image crops must be 5 MB or smaller.');

  let bitmap;
  try {
    if (typeof window.createImageBitmap === 'function') {
      bitmap = await window.createImageBitmap(file);
      const width = Number(bitmap.width);
      const height = Number(bitmap.height);
      if (!width || !height || width > 8000 || height > 8000) throw new Error('Image dimensions must be between 1 and 8000 pixels.');
      return { width, height };
    }

    const objectUrl = URL.createObjectURL(file);
    try {
      const dimensions = await new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve({ width: image.naturalWidth, height: image.naturalHeight });
        image.onerror = () => reject(new Error('The selected file is not a readable image.'));
        image.src = objectUrl;
      });
      if (!dimensions.width || !dimensions.height || dimensions.width > 8000 || dimensions.height > 8000) {
        throw new Error('Image dimensions must be between 1 and 8000 pixels.');
      }
      return dimensions;
    } finally {
      URL.revokeObjectURL(objectUrl);
    }
  } finally {
    bitmap?.close?.();
  }
}

async function resolveStorageImageRefs(client, imageRefs, { blockedOnFailure = false } = {}) {
  const refs = Array.isArray(imageRefs) ? imageRefs : [];
  return Promise.all(refs.map(async (item) => {
    if (!item || typeof item !== 'object' || item.blocked) return item;
    const bucket = clean(item.bucket || item.storage_bucket);
    const path = clean(item.path || item.storage_path);
    if (!bucket || !path) return item;

    const response = await withTimeout(client.storage.from(bucket).createSignedUrl(path, 3600));
    if (response?.error || !response?.data?.signedUrl) {
      return blockedOnFailure ? { blocked: true } : { ...item, preview_error: response?.error?.message || 'Preview unavailable.' };
    }
    return { ...item, url: response.data.signedUrl };
  }));
}

async function removeStudentImageObject(client, storagePath) {
  if (!storagePath) return null;
  const response = await withTimeout(
    client.storage.from(APP_CONFIG.studentImageBucket).remove([storagePath]),
  );
  return response?.error ? response.error.message || 'Storage cleanup failed.' : null;
}

function normalizeIndianMobile(value) {
  const digits = String(clean(value) || '').replace(/\D/g, '');
  const nationalNumber = digits.length === 12 && digits.startsWith('91')
    ? digits.slice(2)
    : digits;

  if (!/^[6-9][0-9]{9}$/.test(nationalNumber)) {
    throw new Error('Enter a valid 10-digit Indian mobile number.');
  }

  return `+91${nationalNumber}`;
}

async function getUser() {
  const client = requireSupabase();
  const sessionData = unwrap(
    await withTimeout(client.auth.getSession()),
    'Unable to read your session.',
  );

  if (!sessionData?.session) return null;

  const data = unwrap(
    await withTimeout(client.auth.getUser()),
    'Unable to verify your session.',
  );
  return data.user || null;
}

export const api = Object.freeze({
  async signUp({ fullName, mobile, email, password }) {
    const client = requireSupabase();
    const normalizedMobile = normalizeIndianMobile(mobile);
    const data = unwrap(await withTimeout(client.auth.signUp({
      email: clean(email),
      password,
      options: {
        emailRedirectTo: new URL('./student.html', window.location.href).href,
        data: {
          full_name: clean(fullName),
          mobile: normalizedMobile,
        },
      },
    })), 'Unable to create account.');
    return data;
  },

  async signIn({ email, password }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(client.auth.signInWithPassword({
      email: clean(email),
      password,
    })), 'Unable to sign in.');
  },

  async signOut() {
    const client = requireSupabase();
    unwrap(await withTimeout(client.auth.signOut()), 'Unable to sign out.');
  },

  async changePassword({ currentPassword, newPassword }) {
    const client = requireSupabase();
    const current = typeof currentPassword === 'string' ? currentPassword : '';
    const next = typeof newPassword === 'string' ? newPassword : '';

    if (!current) throw new Error('Enter your current password.');
    if (next.length < 12) throw new Error('Use at least 12 characters for the new password.');
    if (next === current) throw new Error('Choose a new password different from your current password.');

    const user = await getUser();
    const email = user?.email;
    if (!email) throw new Error('Unable to verify the current account email.');

    // Explicitly verify the current password before any password update.
    // Do not rely on the optional Supabase project-level
    // "Require current password when changing password" setting.
    unwrap(await withTimeout(client.auth.signInWithPassword({
      email,
      password: current,
    })), 'Current password is incorrect.');

    return unwrap(await withTimeout(client.auth.updateUser({
      password: next,
    })), 'Unable to change password.');
  },

  getUser,

  onAuthStateChange(callback) {
    const client = requireSupabase();
    return client.auth.onAuthStateChange((event, session) => callback(event, session));
  },

  async getProfile() {
    const client = requireSupabase();
    const user = await getUser();
    if (!user) return null;
    const data = unwrap(await withTimeout(
      client.from('profiles').select('*').eq('user_id', user.id).single(),
    ), 'Unable to load profile.');
    return data;
  },

  async getStudentHome() {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('get_student_home'),
    ), 'Unable to load your student dashboard.') || {};
  },

  async getStudentTestFacets() {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('get_student_test_facets'),
    ), 'Unable to load test filters.') || {};
  },

  async listStudentTests({
    testType = '',
    search = '',
    subjectId = '',
    topicId = '',
    examYear = '',
    examDate = '',
    shiftNo = '',
    access = 'ALL',
    progress = 'ALL',
    sort = 'RECOMMENDED',
    page = 0,
    pageSize = 12,
  } = {}) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('list_student_tests', {
        p_test_type: clean(testType) || null,
        p_search: clean(search) || null,
        p_subject_id: clean(subjectId) || null,
        p_topic_id: clean(topicId) || null,
        p_exam_year: examYear === '' || examYear === null ? null : Number(examYear),
        p_exam_date: clean(examDate) || null,
        p_shift_no: shiftNo === '' || shiftNo === null ? null : Number(shiftNo),
        p_access: clean(access) || 'ALL',
        p_progress: clean(progress) || 'ALL',
        p_sort: clean(sort) || 'RECOMMENDED',
        p_page: Math.max(0, Number(page) || 0),
        p_page_size: Math.min(Math.max(Number(pageSize) || 12, 1), 50),
      }),
    ), 'Unable to load tests.') || { items: [], total: 0, page: 0, has_more: false };
  },

  async getAttemptBookmarks(attemptId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('get_attempt_bookmarks', { p_attempt_id: attemptId }),
    ), 'Unable to load saved-question state.') || [];
  },

  async setStudentBookmark({ questionId, attemptId = null, saved = true }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('set_student_bookmark', {
        p_question_id: questionId,
        p_attempt_id: attemptId,
        p_saved: Boolean(saved),
      }),
    ), saved ? 'Unable to save this question.' : 'Unable to remove this bookmark.');
  },

  async listStudentSaved({
    kind = 'BOOKMARKS',
    search = '',
    subjectId = '',
    topicId = '',
    status = 'ALL',
    offset = 0,
    limit = 20,
  } = {}) {
    const client = requireSupabase();
    const result = unwrap(await withTimeout(
      client.rpc('list_student_saved', {
        p_kind: clean(kind) || 'BOOKMARKS',
        p_search: clean(search) || null,
        p_subject_id: clean(subjectId) || null,
        p_topic_id: clean(topicId) || null,
        p_status: clean(status) || 'ALL',
        p_offset: Math.max(0, Number(offset) || 0),
        p_limit: Math.min(Math.max(Number(limit) || 20, 1), 50),
      }),
    ), 'Unable to load saved questions.') || { items: [], total: 0, has_more: false };

    result.items = await Promise.all((result.items || []).map(async (item) => ({
      ...item,
      image_refs: await resolveStorageImageRefs(client, item.image_refs, { blockedOnFailure: true }),
    })));
    return result;
  },

  async setMistakeResolved(questionId, resolved = true) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('set_student_mistake_resolved', {
        p_question_id: questionId,
        p_resolved: Boolean(resolved),
      }),
    ), 'Unable to update this mistake.');
  },

  async listStudentResults({ search = '', sort = 'NEWEST', page = 0, pageSize = 12 } = {}) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('list_student_results', {
        p_search: clean(search) || null,
        p_sort: clean(sort) || 'NEWEST',
        p_page: Math.max(0, Number(page) || 0),
        p_page_size: Math.min(Math.max(Number(pageSize) || 12, 1), 50),
      }),
    ), 'Unable to load result history.') || { items: [], total: 0, page: 0, has_more: false };
  },

  async getStudentResultDetail(attemptId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('get_student_result_detail', { p_attempt_id: attemptId }),
    ), 'Unable to load result analytics.') || {};
  },

  async getStudentProfile() {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('get_student_profile'),
    ), 'Unable to load your profile.') || {};
  },

  async updateStudentProfile({ fullName, language, targetBoardId = '', targetExamId = '' }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('update_student_profile', {
        p_full_name: clean(fullName),
        p_language: clean(language),
        p_target_board_id: clean(targetBoardId) || null,
        p_target_exam_id: clean(targetExamId) || null,
      }),
    ), 'Unable to update your profile.');
  },

  async getPublicConfiguration() {
    const client = requireSupabase();
    const [settingsResponse, boardsResponse, examsResponse, statsResponse] = await Promise.all([
      withTimeout(client.from('app_settings').select('setting_key, setting_value').eq('is_public', true)),
      withTimeout(client.from('boards').select('board_id, board_name, board_code, sort_order').eq('status', 'ACTIVE').order('sort_order')),
      withTimeout(client.from('exams').select('exam_id, board_id, exam_name, exam_code, sort_order').eq('status', 'ACTIVE').order('sort_order')),
      withTimeout(client.rpc('get_public_stats')),
    ]);

    const settingsRows = unwrap(settingsResponse, 'Unable to load public settings.') || [];
    const settings = Object.fromEntries(settingsRows.map((row) => [row.setting_key, row.setting_value]));
    return {
      settings,
      boards: unwrap(boardsResponse, 'Unable to load boards.') || [],
      exams: unwrap(examsResponse, 'Unable to load exams.') || [],
      stats: unwrap(statsResponse, 'Unable to load statistics.') || {},
    };
  },

  async listTests({ testType = '', page = 0, pageSize = 12 } = {}) {
    const client = requireSupabase();
    const from = page * pageSize;
    const to = from + pageSize - 1;
    let query = client
      .from('tests')
      .select(`
        test_id, test_name, test_type, question_count, duration_minutes,
        marks_per_question, negative_marks, is_free, status, exam_year,
        exam_date, shift_no, paper_code, section_code, selection_mode,
        boards (board_id, board_name),
        exams (exam_id, exam_name),
        subjects (subject_id, subject_name),
        packages (package_id, package_name)
      `)
      .eq('status', 'PUBLISHED')
      .order('sort_order', { ascending: true })
      .order('created_at', { ascending: false })
      .range(from, to);

    if (testType) query = query.eq('test_type', testType);
    return unwrap(await withTimeout(query), 'Unable to load tests.') || [];
  },

  async createOrResumeAttempt(testId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('create_test_attempt', { p_test_id: testId }),
    ), 'Unable to start this test.');
  },

  async getAttempt(attemptId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.from('attempts')
        .select('attempt_id, test_id, status, started_at, submitted_at, total_questions, attempted, correct, wrong, skipped, score, accuracy, time_taken_seconds, tests(test_name, test_type, duration_minutes, marks_per_question, negative_marks)')
        .eq('attempt_id', attemptId)
        .single(),
    ), 'Unable to load attempt.');
  },

  async getInProgressAttempt() {
    const client = requireSupabase();
    const user = await getUser();
    if (!user) return null;
    const response = await withTimeout(
      client.from('attempts')
        .select('attempt_id, test_id, started_at, tests(test_name)')
        .eq('user_id', user.id)
        .eq('status', 'IN_PROGRESS')
        .order('started_at', { ascending: false })
        .limit(1)
        .maybeSingle(),
    );
    return unwrap(response, 'Unable to load the active attempt.');
  },

  async loadQuestionBatch(attemptId, offset = 0, limit = APP_CONFIG.questionBatchSize) {
    const client = requireSupabase();
    const rows = unwrap(await withTimeout(
      client.rpc('get_attempt_questions', {
        p_attempt_id: attemptId,
        p_offset: offset,
        p_limit: limit,
      }),
    ), 'Unable to load questions.') || [];

    return Promise.all(rows.map(async (row) => ({
      ...row,
      image_refs: await resolveStorageImageRefs(client, row.image_refs, { blockedOnFailure: true }),
    })));
  },

  async getAttemptNavigation(attemptId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('get_attempt_navigation', { p_attempt_id: attemptId }),
    ), 'Unable to load test navigation.');
  },

  async visitAttemptQuestion(attemptId, questionId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('visit_attempt_question', {
        p_attempt_id: attemptId,
        p_question_id: questionId,
      }),
    ), 'Unable to save the current question position.');
  },

  async saveAnswer({ attemptId, questionId, selectedAnswer, markedReview = false, timeTakenSeconds = 0 }) {
    const client = requireSupabase();
    const user = await getUser();
    if (!user) throw new Error('Your session has expired. Please sign in again.');

    return unwrap(await withTimeout(
      client.rpc('save_attempt_answer', {
        p_attempt_id: attemptId,
        p_question_id: questionId,
        p_selected_answer: selectedAnswer || null,
        p_marked_review: Boolean(markedReview),
        p_time_taken_seconds: Math.max(0, Math.round(Number(timeTakenSeconds) || 0)),
      }),
    ), 'Unable to synchronize answer.');
  },

  async submitAttempt(attemptId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('submit_test_attempt', { p_attempt_id: attemptId }),
    ), 'Unable to submit this test.');
  },

  async getAttemptReview(attemptId, offset = 0, limit = 25) {
    const client = requireSupabase();
    const rows = unwrap(await withTimeout(
      client.rpc('get_attempt_review', {
        p_attempt_id: attemptId,
        p_offset: offset,
        p_limit: limit,
      }),
    ), 'Unable to load review data.') || [];
    return Promise.all(rows.map(async (row) => ({
      ...row,
      image_refs: await resolveStorageImageRefs(client, row.image_refs, { blockedOnFailure: true }),
    })));
  },

  async getAdminReferenceData() {
    const client = requireSupabase();
    const [boards, exams, subjects, topics] = await Promise.all([
      withTimeout(client.from('boards').select('board_id, board_name, status, sort_order').order('sort_order')),
      withTimeout(client.from('exams').select('exam_id, board_id, exam_name, status, sort_order').order('sort_order')),
      withTimeout(client.from('subjects').select('subject_id, exam_id, subject_name, status, sort_order').order('sort_order')),
      withTimeout(client.from('topics').select('topic_id, subject_id, topic_name, topic_code, status, sort_order').order('sort_order')),
    ]);
    return {
      boards: unwrap(boards, 'Unable to load boards.') || [],
      exams: unwrap(exams, 'Unable to load exams.') || [],
      subjects: unwrap(subjects, 'Unable to load subjects.') || [],
      topics: unwrap(topics, 'Unable to load topics.') || [],
    };
  },

  async listPublishedQuestions({
    boardId = '',
    examId = '',
    subjectId = '',
    topicId = '',
    questionType = '',
    examYear = '',
    examDate = '',
    shiftNo = '',
    paperCode = '',
    sectionCode = '',
    pageSize = 100,
  } = {}) {
    const client = requireSupabase();
    let query = client
      .from('questions')
      .select(`
        question_id, question_type, board_id, exam_id, exam_year, exam_date,
        shift_no, paper_code, original_question_no, section_code,
        subject_id, topic_id, language, difficulty, question_text, sort_order
      `)
      .eq('question_status', 'PUBLISHED')
      .in('student_image_review_status', [
        'NOT_APPLICABLE',
        'SAFE_CROP_APPROVED',
        'NO_STUDENT_IMAGE_REQUIRED',
      ])
      .limit(Math.min(Math.max(Number(pageSize) || 100, 1), 500));

    if (boardId) query = query.eq('board_id', clean(boardId).toUpperCase());
    if (examId) query = query.eq('exam_id', clean(examId).toUpperCase());
    if (subjectId) query = query.eq('subject_id', clean(subjectId).toUpperCase());
    if (topicId) query = query.eq('topic_id', clean(topicId).toUpperCase());
    if (questionType) query = query.eq('question_type', clean(questionType).toUpperCase());
    if (examYear) query = query.eq('exam_year', Number(examYear));
    if (examDate) query = query.eq('exam_date', clean(examDate));
    if (shiftNo) query = query.eq('shift_no', Number(shiftNo));
    if (paperCode) query = query.eq('paper_code', clean(paperCode).toUpperCase());
    if (sectionCode) query = query.eq('section_code', clean(sectionCode).toUpperCase());

    return unwrap(await withTimeout(query), 'Unable to load published questions.') || [];
  },

  async listAdminTests({ status = '', pageSize = 200 } = {}) {
    const client = requireSupabase();
    let query = client
      .from('tests')
      .select(`
        test_id, board_id, exam_id, subject_id, topic_id,
        test_name, test_type, selection_mode, question_count,
        duration_minutes, marks_per_question, negative_marks, status,
        is_free, sort_order, exam_year, exam_date, shift_no, paper_code,
        section_code, created_at, updated_at,
        boards (board_id, board_name),
        exams (exam_id, exam_name),
        subjects (subject_id, subject_name),
        topics (topic_id, topic_name)
      `)
      .order('sort_order', { ascending: true })
      .order('updated_at', { ascending: false })
      .limit(Math.min(Math.max(Number(pageSize) || 200, 1), 500));

    if (status) query = query.eq('status', clean(status).toUpperCase());
    return unwrap(await withTimeout(query), 'Unable to load configured tests.') || [];
  },

  async getAdminTestDetail(testId) {
    const client = requireSupabase();
    const normalizedTestId = clean(testId).toUpperCase();
    const test = unwrap(await withTimeout(
      client
        .from('tests')
        .select(`
          test_id, board_id, exam_id, subject_id, topic_id,
          test_name, test_type, selection_mode, question_count,
          duration_minutes, marks_per_question, negative_marks, status,
          is_free, sort_order, exam_year, exam_date, shift_no, paper_code,
          section_code, created_at, updated_at
        `)
        .eq('test_id', normalizedTestId)
        .single(),
    ), 'Unable to load the test configuration.');

    const links = unwrap(await withTimeout(
      client
        .from('test_question_links')
        .select(`
          position,
          question_id,
          questions (
            question_id, question_type, board_id, exam_id, exam_year, exam_date,
            shift_no, paper_code, original_question_no, section_code,
            subject_id, topic_id, language, difficulty, question_text, sort_order
          )
        `)
        .eq('test_id', normalizedTestId)
        .order('position', { ascending: true }),
    ), 'Unable to load the test question list.') || [];

    return {
      test,
      questions: links.map((link) => link.questions).filter(Boolean),
    };
  },

  async saveFixedQuestionTest(input) {
    const client = requireSupabase();
    const questionIds = Array.isArray(input.questionIds)
      ? input.questionIds.map((value) => clean(value).toUpperCase()).filter(Boolean)
      : [];

    return unwrap(await withTimeout(
      client.rpc('save_fixed_question_test_v2', {
        p_test_id: clean(input.testId).toUpperCase(),
        p_test_name: clean(input.testName),
        p_board_id: clean(input.boardId).toUpperCase(),
        p_exam_id: clean(input.examId).toUpperCase(),
        p_subject_id: clean(input.subjectId)?.toUpperCase() || null,
        p_topic_id: clean(input.topicId)?.toUpperCase() || null,
        p_test_type: clean(input.testType).toUpperCase(),
        p_duration_minutes: Math.max(0, Math.round(Number(input.durationMinutes) || 0)),
        p_marks_per_question: Number(input.marksPerQuestion) || 1,
        p_negative_marks: Math.max(0, Number(input.negativeMarks) || 0),
        p_sort_order: Math.round(Number(input.sortOrder) || 0),
        p_question_ids: questionIds,
        p_publish: Boolean(input.publish),
        p_exam_year: input.examYear ? Math.round(Number(input.examYear)) : null,
        p_exam_date: clean(input.examDate) || null,
        p_shift_no: input.shiftNo ? Math.round(Number(input.shiftNo)) : null,
        p_paper_code: clean(input.paperCode)?.toUpperCase() || null,
        p_section_code: clean(input.sectionCode)?.toUpperCase() || null,
      }),
    ), 'Unable to save the test configuration.');
  },

  async setAdminTestStatus(testId, status) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('set_admin_test_status', {
        p_test_id: clean(testId).toUpperCase(),
        p_status: clean(status).toUpperCase(),
      }),
    ), 'Unable to change the test status.');
  },

  async listStudentImageRepairQueue({
    status = 'NEEDS_REPAIR',
    search = '',
    paperCode = '',
    shiftNo = '',
    sectionCode = '',
    originalQuestionNo = '',
    page = 0,
    pageSize = 20,
  } = {}) {
    const client = requireSupabase();
    const limit = Math.min(Math.max(Math.round(Number(pageSize) || 20), 1), 100);
    const offset = Math.max(Math.round(Number(page) || 0), 0) * limit;
    return unwrap(await withTimeout(
      client.rpc('list_student_image_repair_queue', {
        p_status: clean(status)?.toUpperCase() || 'NEEDS_REPAIR',
        p_search: clean(search) || null,
        p_paper_code: clean(paperCode)?.toUpperCase() || null,
        p_shift_no: shiftNo === '' || shiftNo === null ? null : Math.max(1, Math.round(Number(shiftNo))),
        p_section_code: clean(sectionCode)?.toUpperCase() || null,
        p_original_question_no: originalQuestionNo === '' || originalQuestionNo === null
          ? null
          : Math.max(1, Math.round(Number(originalQuestionNo))),
        p_limit: limit,
        p_offset: offset,
      }),
    ), 'Unable to load the student-safe image repair queue.');
  },

  async getStudentImageRepairDetail(questionId) {
    const client = requireSupabase();
    const detail = unwrap(await withTimeout(
      client.rpc('get_student_image_repair_detail', {
        p_question_id: clean(questionId)?.toUpperCase(),
      }),
    ), 'Unable to load this image-repair record.');

    const sourceImages = await resolveStorageImageRefs(client, detail?.question?.image_refs || []);
    const repairs = await Promise.all((detail?.repairs || []).map(async (repair) => {
      if (!['PENDING', 'APPROVED'].includes(repair.status)) return { ...repair, preview_url: '', preview_error: '' };
      const [preview] = await resolveStorageImageRefs(client, [{
        bucket: repair.storage_bucket,
        path: repair.storage_path,
      }]);
      return { ...repair, preview_url: preview?.url || '', preview_error: preview?.preview_error || '' };
    }));

    return {
      ...detail,
      question: { ...detail.question, source_image_refs: sourceImages },
      repairs,
    };
  },

  async uploadStudentImageRepair({ questionId, file, altText, adminNote = '' }) {
    const client = requireSupabase();
    const user = await getUser();
    if (!user) throw new Error('Your session has expired.');

    const normalizedQuestionId = clean(questionId)?.toUpperCase();
    if (!normalizedQuestionId) throw new Error('Question ID is required.');
    const normalizedAlt = clean(altText);
    if (!normalizedAlt) throw new Error('Describe the diagram for students.');

    const dimensions = await inspectImageFile(file);
    const checksum = await sha256File(file);
    const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
    const storagePath = `${user.id}/${normalizedQuestionId}/${Date.now()}-${checksum.slice(0, 12)}-${safeName}`;

    unwrap(await withTimeout(
      client.storage.from(APP_CONFIG.studentImageBucket).upload(storagePath, file, {
        cacheControl: '3600',
        upsert: false,
        contentType: file.type,
      }),
    ), 'Unable to upload the student-safe crop.');

    try {
      const result = unwrap(await withTimeout(
        client.rpc('register_student_image_upload', {
          p_question_id: normalizedQuestionId,
          p_storage_path: storagePath,
          p_original_file_name: file.name,
          p_mime_type: file.type,
          p_file_size_bytes: file.size,
          p_checksum_sha256: checksum,
          p_pixel_width: dimensions.width,
          p_pixel_height: dimensions.height,
          p_alt_text: normalizedAlt,
          p_admin_note: clean(adminNote) || null,
        }),
      ), 'The crop uploaded, but its pending repair record could not be saved.');

      const cleanupWarning = await removeStudentImageObject(client, result?.superseded_storage_path);
      return { ...result, cleanup_warning: cleanupWarning };
    } catch (error) {
      await removeStudentImageObject(client, storagePath);
      throw error;
    }
  },

  async approveStudentImageRepair({ repairId, altText, adminNote = '' }) {
    const client = requireSupabase();
    const result = unwrap(await withTimeout(
      client.rpc('approve_student_image_repair', {
        p_repair_id: repairId,
        p_alt_text: clean(altText),
        p_admin_note: clean(adminNote) || null,
        p_confirmation: 'APPROVE_STUDENT_IMAGE',
      }),
    ), 'Unable to approve the student-safe image.');
    const cleanupWarning = await removeStudentImageObject(client, result?.replaced_storage_path);
    return { ...result, cleanup_warning: cleanupWarning };
  },

  async discardStudentImageUpload({ repairId, adminNote = '' }) {
    const client = requireSupabase();
    const result = unwrap(await withTimeout(
      client.rpc('discard_student_image_upload', {
        p_repair_id: repairId,
        p_admin_note: clean(adminNote) || null,
        p_confirmation: 'DISCARD_STUDENT_IMAGE',
      }),
    ), 'Unable to discard the pending crop.');
    const cleanupWarning = await removeStudentImageObject(client, result?.storage_path);
    return { ...result, cleanup_warning: cleanupWarning };
  },

  async removeApprovedStudentImage({ questionId, adminNote = '' }) {
    const client = requireSupabase();
    const result = unwrap(await withTimeout(
      client.rpc('remove_approved_student_image', {
        p_question_id: clean(questionId)?.toUpperCase(),
        p_admin_note: clean(adminNote) || null,
        p_confirmation: 'REMOVE_STUDENT_IMAGE',
      }),
    ), 'Unable to remove the approved student image.');
    const cleanupWarning = await removeStudentImageObject(client, result?.storage_path);
    return { ...result, cleanup_warning: cleanupWarning };
  },

  async markStudentImageNotRequired({ questionId, adminNote = '' }) {
    const client = requireSupabase();
    const result = unwrap(await withTimeout(
      client.rpc('mark_student_image_not_required', {
        p_question_id: clean(questionId)?.toUpperCase(),
        p_admin_note: clean(adminNote),
        p_confirmation: 'NO_STUDENT_IMAGE_REQUIRED',
      }),
    ), 'Unable to confirm that no student image is required.');
    const cleanupWarning = await removeStudentImageObject(client, result?.storage_path);
    return { ...result, cleanup_warning: cleanupWarning };
  },

  async reopenStudentImageReview({ questionId, adminNote = '' }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('reopen_student_image_review', {
        p_question_id: clean(questionId)?.toUpperCase(),
        p_admin_note: clean(adminNote),
        p_confirmation: 'REOPEN_STUDENT_IMAGE_REVIEW',
      }),
    ), 'Unable to reopen student-image review.');
  },

  async getPhase4ATestBuilderFacets(filters = {}) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('get_phase4a_test_builder_facets', {
        p_filters: filters && typeof filters === 'object' ? filters : {},
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 60000),
    ), 'Unable to load the dynamic test-builder filters.');
  },

  async searchPhase4ATestBuilderQuestions({
    filters = {},
    search = '',
    order = 'PACKAGE_ORIGINAL',
    offset = 0,
    limit = 40,
  } = {}) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('search_phase4a_test_builder_questions', {
        p_filters: filters && typeof filters === 'object' ? filters : {},
        p_search: clean(search) || null,
        p_order: clean(order)?.toUpperCase() || 'PACKAGE_ORIGINAL',
        p_offset: Math.max(Math.round(Number(offset) || 0), 0),
        p_limit: Math.min(Math.max(Math.round(Number(limit) || 40), 1), 200),
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 60000),
    ), 'Unable to load the filtered question stack.');
  },

  async selectAllPhase4ATestBuilderQuestionIds({
    filters = {},
    search = '',
    order = 'PACKAGE_ORIGINAL',
  } = {}) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('select_all_phase4a_test_builder_question_ids', {
        p_filters: filters && typeof filters === 'object' ? filters : {},
        p_search: clean(search) || null,
        p_order: clean(order)?.toUpperCase() || 'PACKAGE_ORIGINAL',
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 90000),
    ), 'Unable to select every filtered question.');
  },

  async previewPhase4ADynamicTest(input = {}) {
    const client = requireSupabase();
    const questionIds = [...new Set(
      (Array.isArray(input.questionIds) ? input.questionIds : [])
        .map((value) => clean(value)?.toUpperCase())
        .filter(Boolean),
    )];

    return unwrap(await withTimeout(
      client.rpc('preview_phase4a_dynamic_test', {
        p_builder_mode: clean(input.builderMode)?.toUpperCase() || 'CUSTOM',
        p_filters: input.filters && typeof input.filters === 'object' ? input.filters : {},
        p_question_ids: questionIds,
        p_order: clean(input.order)?.toUpperCase() || 'PACKAGE_ORIGINAL',
        p_custom_test_type: clean(input.customTestType)?.toUpperCase() || null,
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 90000),
    ), 'Unable to preview the resolved test.');
  },

  async savePhase4ADynamicTest(input = {}) {
    const client = requireSupabase();
    const questionIds = [...new Set(
      (Array.isArray(input.questionIds) ? input.questionIds : [])
        .map((value) => clean(value)?.toUpperCase())
        .filter(Boolean),
    )];

    return unwrap(await withTimeout(
      client.rpc('save_phase4a_dynamic_test', {
        p_test_id: clean(input.testId)?.toUpperCase(),
        p_test_name: clean(input.testName),
        p_builder_mode: clean(input.builderMode)?.toUpperCase() || 'CUSTOM',
        p_filters: input.filters && typeof input.filters === 'object' ? input.filters : {},
        p_question_ids: questionIds,
        p_order: clean(input.order)?.toUpperCase() || 'PACKAGE_ORIGINAL',
        p_custom_test_type: clean(input.customTestType)?.toUpperCase() || null,
        p_duration_minutes: Math.max(0, Math.round(Number(input.durationMinutes) || 0)),
        p_marks_per_question: Number(input.marksPerQuestion) || 1,
        p_negative_marks: Math.max(0, Number(input.negativeMarks) || 0),
        p_sort_order: Math.round(Number(input.sortOrder) || 0),
        p_publish: Boolean(input.publish),
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 120000),
    ), 'Unable to save the dynamic multi-filter test.');
  },

  async listDrafts({ status = 'PENDING', page = 0, pageSize = 24 } = {}) {
    const client = requireSupabase();
    const from = page * pageSize;
    const to = from + pageSize - 1;
    const summaryFields = [
      'draft_id',
      'proposed_question_id',
      'review_status',
      'question_type',
      'subject_id',
      'question_text',
      'correct_answer',
      'answer_source',
      'verification_status',
      'topic_id',
      'suggested_topic_code',
      'suggested_topic_name',
      'answer_confidence',
      'transcription_confidence',
      'source_quality',
      'source_option_anomaly',
      'source_option_anomaly_note',
      'is_supplemental',
      'explanation',
      'created_at',
      'updated_at',
    ].join(',');
    let query = client
      .from('draft_questions')
      .select(summaryFields)
      .order('created_at', { ascending: false })
      .range(from, to);
    if (status) query = query.eq('review_status', status);
    return unwrap(await withTimeout(query), 'Unable to load draft questions.') || [];
  },

  async getDraftReview(draftId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client
        .from('draft_questions')
        .select('*')
        .eq('draft_id', draftId)
        .single(),
    ), 'Unable to load this draft for review.');
  },

  async createDraft(input) {
    const client = requireSupabase();
    const user = await getUser();
    if (!user) throw new Error('Your session has expired.');

    const payload = {
      question_type: input.questionType,
      proposed_question_id: clean(input.proposedQuestionId).toUpperCase(),
      board_id: clean(input.boardId).toUpperCase(),
      exam_id: clean(input.examId)?.toUpperCase() || null,
      subject_id: clean(input.subjectId).toUpperCase(),
      topic_id: clean(input.topicId)?.toUpperCase() || null,
      question_text: clean(input.questionText),
      options: {
        A: clean(input.optionA),
        B: clean(input.optionB),
        C: clean(input.optionC),
        D: clean(input.optionD),
      },
      correct_answer: clean(input.correctAnswer).toUpperCase(),
      explanation: clean(input.explanation) || null,
      language: clean(input.language).toUpperCase(),
      difficulty: clean(input.difficulty).toUpperCase(),
      source_file_id: input.sourceFileId || null,
      review_status: 'PENDING',
      answer_source: 'MANUALLY_VERIFIED',
      verification_status: 'NEEDS_CHECK',
      topic_resolution_status: input.topicId ? 'ADMIN_CONFIRMED' : 'UNRESOLVED',
      question_status: 'DRAFT',
      created_by: user.id,
    };

    return unwrap(await withTimeout(
      client.from('draft_questions').insert(payload).select('*').single(),
    ), 'Unable to save the draft.');
  },

  async reviewDraftAnswerTopic({ draftId, correctAnswer, answerSource, explanation, topicId, answerReviewNote, adminNotes }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('review_draft_answer_topic', {
        p_draft_id: draftId,
        p_correct_answer: clean(correctAnswer)?.toUpperCase(),
        p_answer_source: clean(answerSource)?.toUpperCase(),
        p_explanation: clean(explanation),
        p_topic_id: clean(topicId)?.toUpperCase() || null,
        p_answer_review_note: clean(answerReviewNote) || null,
        p_admin_notes: clean(adminNotes) || null,
      }),
    ), 'Unable to save the human answer and topic review.');
  },

  async publishDraft(draftId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('publish_draft_question', { p_draft_id: draftId }),
    ), 'Unable to publish the draft.');
  },

  async listPublishQueue({ page = 0, pageSize = 25 } = {}) {
    const client = requireSupabase();
    const limit = Math.min(Math.max(Math.round(Number(pageSize) || 25), 1), 100);
    const offset = Math.max(Math.round(Number(page) || 0), 0) * limit;
    return unwrap(await withTimeout(
      client.rpc('list_publish_queue', {
        p_limit: limit,
        p_offset: offset,
      }),
    ), 'Unable to load the verified publish queue.');
  },

  async publishVerifiedDrafts(draftIds) {
    const client = requireSupabase();
    const ids = [...new Set((Array.isArray(draftIds) ? draftIds : []).filter(Boolean))];
    if (!ids.length) throw new Error('Select at least one verified draft.');
    if (ids.length > 25) throw new Error('Publish at most 25 verified drafts per request.');
    return unwrap(await withTimeout(
      client.rpc('publish_verified_drafts', { p_draft_ids: ids }),
      Math.max(APP_CONFIG.requestTimeoutMs, 90000),
    ), 'Unable to publish the selected verified drafts.');
  },

  async confirmImportSourceOptionAnomaly({ importItemId, note }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('confirm_import_source_option_anomaly', {
        p_import_item_id: importItemId,
        p_note: clean(note),
      }),
    ), 'Unable to confirm the printed source option anomaly.');
  },

  async rejectDraft(draftId, notes) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('reject_draft_question', {
        p_draft_id: draftId,
        p_notes: clean(notes) || 'Rejected during human review.',
      }),
    ), 'Unable to reject the draft.');
  },

  async validateImportPackage({ manifest, packageChecksum, rawFileChecksum }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('validate_import_package', {
        p_manifest: manifest,
        p_package_checksum_sha256: clean(packageChecksum)?.toLowerCase() || null,
        p_source_checksum_sha256: clean(rawFileChecksum)?.toLowerCase() || null,
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 90000),
    ), 'Unable to validate the import package.');
  },

  async uploadImportHtml(file, rawFileChecksum) {
    const client = requireSupabase();
    const user = await getUser();
    if (!user) throw new Error('Your session has expired.');

    const checksum = clean(rawFileChecksum)?.toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(checksum || '')) {
      throw new Error('A valid HTML SHA-256 checksum is required.');
    }

    const existingResponse = await withTimeout(
      client.from('source_files')
        .select('*')
        .eq('checksum_sha256', checksum)
        .maybeSingle(),
    );
    const existing = unwrap(existingResponse, 'Unable to inspect existing source files.');
    if (existing) return { ...existing, reused: true };

    const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
    const storagePath = `${user.id}/html-imports/${checksum}-${safeName}`;
    const uploadResponse = await withTimeout(
      client.storage.from(APP_CONFIG.sourceBucket).upload(storagePath, file, {
        cacheControl: '3600',
        upsert: false,
        contentType: file.type || 'text/html',
      }),
    );

    let upload;
    if (uploadResponse?.error) {
      const duplicateStorage = String(uploadResponse.error.message || '').toLowerCase().includes('already exists');
      if (!duplicateStorage) throw normalizeError(uploadResponse.error, 'Unable to upload the HTML package privately.');
      upload = { path: storagePath };
    } else {
      upload = uploadResponse.data;
    }

    const insertResponse = await withTimeout(
      client.from('source_files').insert({
        storage_bucket: APP_CONFIG.sourceBucket,
        storage_path: upload.path,
        original_file_name: file.name,
        mime_type: file.type || 'text/html',
        file_size_bytes: file.size,
        checksum_sha256: checksum,
        uploaded_by: user.id,
      }).select('*').single(),
    );

    if (!insertResponse?.error) return { ...insertResponse.data, reused: false };

    if (insertResponse.error.code === '23505') {
      const duplicate = unwrap(await withTimeout(
        client.from('source_files').select('*').eq('checksum_sha256', checksum).single(),
      ), 'Unable to load the existing HTML source record.');
      return { ...duplicate, reused: true };
    }

    throw normalizeError(insertResponse.error, 'HTML uploaded, but its source record could not be saved.');
  },

  async stageImportDryRun({ manifest, rawFileChecksum, packageChecksum, sourceFileId }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('stage_import_dry_run', {
        p_manifest: manifest,
        p_raw_file_checksum_sha256: clean(rawFileChecksum)?.toLowerCase(),
        p_package_checksum_sha256: clean(packageChecksum)?.toLowerCase(),
        p_source_file_id: sourceFileId,
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 300000),
    ), 'Unable to complete the authoritative import dry run.');
  },

  async getImportBatchReport(importBatchId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('get_import_batch_report', { p_import_batch_id: importBatchId }),
      Math.max(APP_CONFIG.requestTimeoutMs, 60000),
    ), 'Unable to load the import reconciliation report.');
  },


  async findImportBatchByIdentity({ packageId, packageChecksum }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('find_import_batch_by_identity', {
        p_package_id: clean(packageId)?.toUpperCase() || null,
        p_package_checksum_sha256: clean(packageChecksum)?.toLowerCase() || null,
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 30000),
    ), 'Unable to check the server import state.');
  },

  async reconcileImportBatchState(importBatchId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('reconcile_import_batch_state', { p_import_batch_id: importBatchId }),
      Math.max(APP_CONFIG.requestTimeoutMs, 90000),
    ), 'Unable to synchronize the actual draft state.');
  },

  async repairAiProposedImportChunk({ importBatchId, limit = 20 }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('repair_ai_proposed_import_chunk', {
        p_import_batch_id: importBatchId,
        p_limit: Math.min(Math.max(Number(limit) || 20, 1), 50),
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 90000),
    ), 'Unable to recheck this import batch.');
  },

  async importNextValidDraftChunk({ importBatchId, limit = 10 }) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('import_next_valid_batch_chunk', {
        p_import_batch_id: importBatchId,
        p_limit: Math.min(Math.max(Number(limit) || 10, 1), 25),
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 90000),
    ), 'Unable to create the next draft chunk.');
  },

  async resetUnreviewedImportDrafts(importBatchId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('reset_unreviewed_import_batch_drafts', {
        p_import_batch_id: importBatchId,
        p_confirmation: 'RESET_UNREVIEWED_DRAFTS',
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 120000),
    ), 'Unable to reset unreviewed drafts.');
  },

  async importBatchItemsToDrafts({ importBatchId, importItemIds }) {
    const ids = [...new Set((importItemIds || []).filter(Boolean))];
    if (!importBatchId) throw new Error('Import batch ID is required.');
    if (!ids.length) throw new Error('Select at least one valid record.');
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('import_valid_batch_items_to_drafts', {
        p_import_batch_id: importBatchId,
        p_import_item_ids: ids,
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 120000),
    ), 'Unable to create controlled question drafts.');
  },

  async linkImportBatchOccurrences({ importBatchId, importItemIds }) {
    const ids = [...new Set((importItemIds || []).filter(Boolean))];
    if (!importBatchId) throw new Error('Import batch ID is required.');
    if (!ids.length) throw new Error('Select at least one exact duplicate PYQ occurrence.');
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('link_import_batch_occurrences', {
        p_import_batch_id: importBatchId,
        p_import_item_ids: ids,
      }),
      Math.max(APP_CONFIG.requestTimeoutMs, 120000),
    ), 'Unable to link the selected source occurrences.');
  },

  async listImportBatches({ pageSize = 20 } = {}) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.from('import_batches')
        .select('import_batch_id, package_id, package_version, supersedes_package_id, schema_version, status, draft_import_status, total_raw, total_valid, total_warning, total_error, total_duplicate, total_draft, total_linked, total_skipped, declared_total_questions, extracted_source_questions, missing_question_count, generated_supplement_count, paper_completeness_status, paper_rejection_reason, created_at, completed_at, draft_import_completed_at, source_files(original_file_name, checksum_sha256)')
        .eq('import_method', 'HTML_PACKAGE')
        .order('created_at', { ascending: false })
        .limit(Math.min(Math.max(Number(pageSize) || 20, 1), 50)),
    ), 'Unable to load recent import dry runs.') || [];
  },

  async uploadSourceFile(file) {
    const client = requireSupabase();
    const user = await getUser();
    if (!user) throw new Error('Your session has expired.');
    const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
    const storagePath = `${user.id}/${Date.now()}-${safeName}`;
    const upload = unwrap(await withTimeout(
      client.storage.from(APP_CONFIG.sourceBucket).upload(storagePath, file, {
        cacheControl: '3600',
        upsert: false,
        contentType: file.type || undefined,
      }),
    ), 'Unable to upload source file.');

    const sourceRecord = unwrap(await withTimeout(
      client.from('source_files').insert({
        storage_bucket: APP_CONFIG.sourceBucket,
        storage_path: upload.path,
        original_file_name: file.name,
        mime_type: file.type || null,
        file_size_bytes: file.size,
        uploaded_by: user.id,
      }).select('*').single(),
    ), 'File uploaded, but its database record could not be saved.');

    return sourceRecord;
  },
});

export { normalizeError };
