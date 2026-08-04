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
        timer = window.setTimeout(() => reject(new Error('Request timed out. Please retry.')), timeoutMs);
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
    return unwrap(await withTimeout(
      client.rpc('get_attempt_questions', {
        p_attempt_id: attemptId,
        p_offset: offset,
        p_limit: limit,
      }),
    ), 'Unable to load questions.') || [];
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
    return unwrap(await withTimeout(
      client.rpc('get_attempt_review', {
        p_attempt_id: attemptId,
        p_offset: offset,
        p_limit: limit,
      }),
    ), 'Unable to load review data.') || [];
  },

  async getAdminReferenceData() {
    const client = requireSupabase();
    const [boards, exams, subjects, topics] = await Promise.all([
      withTimeout(client.from('boards').select('board_id, board_name, status, sort_order').order('sort_order')),
      withTimeout(client.from('exams').select('exam_id, board_id, exam_name, status, sort_order').order('sort_order')),
      withTimeout(client.from('subjects').select('subject_id, exam_id, subject_name, status, sort_order').order('sort_order')),
      withTimeout(client.from('topics').select('topic_id, subject_id, topic_name, status, sort_order').order('sort_order')),
    ]);
    return {
      boards: unwrap(boards, 'Unable to load boards.') || [],
      exams: unwrap(exams, 'Unable to load exams.') || [],
      subjects: unwrap(subjects, 'Unable to load subjects.') || [],
      topics: unwrap(topics, 'Unable to load topics.') || [],
    };
  },

  async listPublishedQuestions({ boardId = '', examId = '', subjectId = '', topicId = '', pageSize = 100 } = {}) {
    const client = requireSupabase();
    let query = client
      .from('questions')
      .select('question_id, question_type, board_id, exam_id, subject_id, topic_id, language, difficulty, question_text')
      .eq('question_status', 'PUBLISHED')
      .order('question_id', { ascending: true })
      .limit(Math.min(Math.max(Number(pageSize) || 100, 1), 200));

    if (boardId) query = query.eq('board_id', clean(boardId).toUpperCase());
    if (examId) query = query.eq('exam_id', clean(examId).toUpperCase());
    if (subjectId) query = query.eq('subject_id', clean(subjectId).toUpperCase());
    if (topicId) query = query.eq('topic_id', clean(topicId).toUpperCase());

    return unwrap(await withTimeout(query), 'Unable to load published questions.') || [];
  },

  async listAdminTests({ status = '', pageSize = 50 } = {}) {
    const client = requireSupabase();
    let query = client
      .from('tests')
      .select(`
        test_id, test_name, test_type, selection_mode, question_count,
        duration_minutes, marks_per_question, negative_marks, status,
        is_free, sort_order, created_at, updated_at,
        boards (board_id, board_name),
        exams (exam_id, exam_name),
        subjects (subject_id, subject_name),
        topics (topic_id, topic_name)
      `)
      .order('created_at', { ascending: false })
      .limit(Math.min(Math.max(Number(pageSize) || 50, 1), 100));

    if (status) query = query.eq('status', clean(status).toUpperCase());
    return unwrap(await withTimeout(query), 'Unable to load configured tests.') || [];
  },

  async saveFixedQuestionTest(input) {
    const client = requireSupabase();
    const questionIds = Array.isArray(input.questionIds)
      ? input.questionIds.map((value) => clean(value).toUpperCase()).filter(Boolean)
      : [];

    return unwrap(await withTimeout(
      client.rpc('save_fixed_question_test', {
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
      }),
    ), 'Unable to save the test configuration.');
  },

  async listDrafts({ status = 'PENDING', page = 0, pageSize = 30 } = {}) {
    const client = requireSupabase();
    const from = page * pageSize;
    const to = from + pageSize - 1;
    let query = client
      .from('draft_questions')
      .select('*')
      .order('created_at', { ascending: false })
      .range(from, to);
    if (status) query = query.eq('review_status', status);
    return unwrap(await withTimeout(query), 'Unable to load draft questions.') || [];
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
      verification_status: 'UNVERIFIED',
      question_status: 'DRAFT',
      created_by: user.id,
    };

    return unwrap(await withTimeout(
      client.from('draft_questions').insert(payload).select('*').single(),
    ), 'Unable to save the draft.');
  },

  async publishDraft(draftId) {
    const client = requireSupabase();
    return unwrap(await withTimeout(
      client.rpc('publish_draft_question', { p_draft_id: draftId }),
    ), 'Unable to publish the draft.');
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
