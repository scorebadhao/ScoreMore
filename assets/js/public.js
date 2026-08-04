import { APP_CONFIG, isConfigured } from './config.js';
import { api } from './api.js';
import { bindAuthTabs, bindStudentAuth } from './auth.js';
import { toast } from './toast.js';

const PENDING_TEST_KEY = 'scoremore:pending-test-id';

const elements = {
  setupNotice: document.getElementById('setupNotice'),
  publicLoading: document.getElementById('publicLoading'),
  publicView: document.getElementById('publicView'),
  publicTestList: document.getElementById('publicTestList'),
  publicFeaturedTests: document.getElementById('publicFeaturedTests'),
  publicTestTypes: document.getElementById('publicTestTypes'),
  publicScopes: document.getElementById('publicScopes'),
};

let redirecting = false;
let publicTests = [];
let publicConfig = { boards: [], exams: [], settings: {}, stats: {} };

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function renderSkeletons(container, count = 3, compact = false) {
  if (!container) return;
  container.innerHTML = Array.from(
    { length: count },
    () => `<div class="skeleton ${compact ? 'skeleton-compact' : ''}" aria-hidden="true"></div>`,
  ).join('');
}

function testTypeLabel(type) {
  return ({
    PYQ_FULL: 'Previous Paper',
    PYQ_SECTIONAL: 'Sectional PYQ',
    TOPIC_PRACTICE: 'Topic Practice',
    FULL_MOCK: 'Full Mock',
    SECTIONAL_MOCK: 'Sectional Mock',
    DAILY_QUIZ: 'Daily Quiz',
    BOOKMARK_REVISION: 'Bookmark Revision',
    MISTAKE_REVISION: 'Mistake Revision',
    PERSONALIZED_TEST: 'Personalized Test',
  })[type] || type;
}

function typeIcon(type) {
  if (type === 'PYQ_FULL') return 'i-file';
  if (type === 'FULL_MOCK') return 'i-target';
  return 'i-layers';
}

function revealPublicView() {
  elements.publicLoading?.classList.add('hidden');
  elements.publicView?.classList.remove('hidden');
}

function redirectToStudent() {
  if (redirecting) return;
  redirecting = true;
  window.location.replace('./student.html');
}

function bindStartButtons(container) {
  container?.querySelectorAll('[data-start-test]').forEach((button) => {
    button.addEventListener('click', () => {
      sessionStorage.setItem(PENDING_TEST_KEY, button.dataset.startTest);
      document.getElementById('authCard')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      toast.info('Sign in to start this test.');
    });
  });
}

function testCardMarkup(test, { compact = false } = {}) {
  const dateShift = [test.exam_date, test.shift_no ? `Shift ${test.shift_no}` : ''].filter(Boolean).join(' · ');
  const type = testTypeLabel(test.test_type);
  if (compact) {
    return `
      <article class="mini-test-row">
        <span class="mini-test-icon"><svg class="icon"><use href="#${typeIcon(test.test_type)}"></use></svg></span>
        <span class="mini-test-copy"><strong>${escapeHtml(test.test_name)}</strong><small>${escapeHtml(type)} · ${escapeHtml(test.question_count)} questions</small></span>
        <button class="icon-button mini-test-action" data-start-test="${escapeHtml(test.test_id)}" type="button" aria-label="Sign in to start ${escapeHtml(test.test_name)}"><svg class="icon"><use href="#i-arrow"></use></svg></button>
      </article>
    `;
  }

  return `
    <article class="catalogue-test-card test-card">
      <div class="test-card-topline">
        <span class="eyebrow">${escapeHtml(type)}</span>
        <span class="access-badge ${test.is_free ? 'free' : 'premium'}">${test.is_free ? 'Free' : 'Premium'}</span>
      </div>
      <div class="test-card-heading">
        <span class="test-type-icon"><svg class="icon"><use href="#${typeIcon(test.test_type)}"></use></svg></span>
        <div>
          <h3>${escapeHtml(test.test_name)}</h3>
          <p>${escapeHtml(test.boards?.board_name || 'ScoreMore')} ${test.exams?.exam_name ? `· ${escapeHtml(test.exams.exam_name)}` : ''}</p>
        </div>
      </div>
      <div class="test-meta">
        ${test.subjects?.subject_name ? `<span class="chip">${escapeHtml(test.subjects.subject_name)}</span>` : ''}
        ${dateShift ? `<span class="chip">${escapeHtml(dateShift)}</span>` : ''}
        <span class="chip">${escapeHtml(test.question_count)} questions</span>
        <span class="chip">${escapeHtml(test.duration_minutes || 0)} min</span>
      </div>
      <div class="test-card-facts">
        <span><b>${escapeHtml(test.marks_per_question ?? 1)}</b> mark/question</span>
        <span><b>${escapeHtml(test.negative_marks ?? 0)}</b> negative</span>
      </div>
      <button class="button button-primary test-card-action" data-start-test="${escapeHtml(test.test_id)}" type="button">
        <span>Sign in to start</span><svg class="icon"><use href="#i-arrow"></use></svg>
      </button>
    </article>
  `;
}

function renderTests(tests) {
  if (!tests.length) {
    elements.publicTestList.innerHTML = `
      <div class="empty-state catalogue-empty">
        <span class="empty-icon"><svg class="icon"><use href="#i-grid"></use></svg></span>
        <h3>No published tests yet</h3>
        <p>Reviewed tests will appear here as soon as the ScoreMore administrator publishes them.</p>
      </div>
    `;
    return;
  }

  elements.publicTestList.innerHTML = tests.map((test) => testCardMarkup(test)).join('');
  bindStartButtons(elements.publicTestList);
}

function renderFeaturedTests(tests) {
  if (!elements.publicFeaturedTests) return;
  const featured = tests.slice(0, 3);
  if (!featured.length) {
    elements.publicFeaturedTests.innerHTML = '<div class="empty-inline">No featured tests yet.</div>';
    return;
  }
  elements.publicFeaturedTests.innerHTML = featured.map((test) => testCardMarkup(test, { compact: true })).join('');
  bindStartButtons(elements.publicFeaturedTests);
}

function renderTestTypes(tests) {
  if (!elements.publicTestTypes) return;
  const counts = new Map();
  tests.forEach((test) => counts.set(test.test_type, (counts.get(test.test_type) || 0) + 1));
  const rows = [...counts.entries()].sort((a, b) => b[1] - a[1]);
  if (!rows.length) {
    elements.publicTestTypes.innerHTML = '<div class="empty-inline">No active test series yet.</div>';
    return;
  }
  elements.publicTestTypes.innerHTML = rows.map(([type, count]) => `
    <div class="compact-list-row">
      <span class="compact-list-icon"><svg class="icon"><use href="#${typeIcon(type)}"></use></svg></span>
      <span><strong>${escapeHtml(testTypeLabel(type))}</strong><small>Published practice</small></span>
      <b>${count}</b>
    </div>
  `).join('');
}

function renderScopes(config) {
  if (!elements.publicScopes) return;
  const examByBoard = new Map();
  (config.exams || []).forEach((exam) => {
    if (!examByBoard.has(exam.board_id)) examByBoard.set(exam.board_id, []);
    examByBoard.get(exam.board_id).push(exam);
  });
  const rows = (config.boards || []).map((board) => {
    const exams = examByBoard.get(board.board_id) || [];
    return `
      <div class="compact-list-row scope-row">
        <span class="compact-list-icon"><svg class="icon"><use href="#i-target"></use></svg></span>
        <span><strong>${escapeHtml(board.board_name)}</strong><small>${escapeHtml(exams.map((exam) => exam.exam_name).join(' · ') || 'Active board')}</small></span>
        <svg class="icon row-arrow"><use href="#i-arrow"></use></svg>
      </div>
    `;
  });
  elements.publicScopes.innerHTML = rows.join('') || '<div class="empty-inline">No active exam scope.</div>';
}

async function loadPublicConfiguration() {
  publicConfig = await api.getPublicConfiguration();
  const settings = publicConfig.settings || {};
  document.getElementById('brandName').textContent = settings.app_name || APP_CONFIG.name;
  document.getElementById('brandTagline').textContent = settings.app_tagline || 'Prepare smarter';
  document.getElementById('scopeBadge').textContent = settings.scope_badge || 'Dynamic exam platform';
  document.getElementById('heroTitle').textContent = settings.hero_title || 'Prepare Smarter';
  document.getElementById('heroSubtitle').textContent = settings.hero_subtitle || 'Previous-year questions, sectional practice and meaningful analytics.';
  const stats = publicConfig.stats || {};
  document.getElementById('statQuestions').textContent = stats.published_questions ?? 0;
  document.getElementById('statPapers').textContent = stats.pyq_papers ?? 0;
  document.getElementById('statTests').textContent = stats.published_tests ?? 0;
  document.getElementById('statAttempts').textContent = stats.student_attempts ?? 0;
  renderScopes(publicConfig);
}

async function loadPublicTests() {
  renderSkeletons(elements.publicTestList, 3);
  renderSkeletons(elements.publicFeaturedTests, 2, true);
  renderSkeletons(elements.publicTestTypes, 3, true);
  try {
    publicTests = await api.listTests({ pageSize: 50 });
    renderTests(publicTests);
    renderFeaturedTests(publicTests);
    renderTestTypes(publicTests);
  } catch (error) {
    elements.publicTestList.innerHTML = `
      <div class="empty-state catalogue-empty error">
        <h3>Tests could not be loaded</h3>
        <p>${escapeHtml(error.message)}</p>
        <button id="retryPublicTests" class="button button-ghost" type="button">Retry</button>
      </div>
    `;
    document.getElementById('retryPublicTests')?.addEventListener('click', loadPublicTests);
  }
}

function bindNetworkState() {
  const syncState = document.getElementById('syncState');
  const update = () => {
    if (!syncState) return;
    const online = navigator.onLine;
    syncState.innerHTML = `<span class="sync-dot"></span>${online ? 'Online' : 'Offline'}`;
    syncState.classList.toggle('offline', !online);
  };
  window.addEventListener('online', update);
  window.addEventListener('offline', update);
  update();
}

function bindUi() {
  bindAuthTabs();
  bindStudentAuth({ onAuthenticated: redirectToStudent });
  bindNetworkState();

  document.querySelectorAll('[data-scroll-to]').forEach((button) => {
    button.addEventListener('click', () => {
      document.getElementById(button.dataset.scrollTo)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });
  document.getElementById('refreshPublicTests')?.addEventListener('click', loadPublicTests);
}

async function initialize() {
  bindUi();

  if (!isConfigured) {
    elements.setupNotice?.classList.remove('hidden');
    revealPublicView();
    renderTests([]);
    renderFeaturedTests([]);
    renderTestTypes([]);
    renderScopes(publicConfig);
    return;
  }

  try {
    const user = await api.getUser();
    if (user) {
      redirectToStudent();
      return;
    }
  } catch (error) {
    toast.error(error.message);
  }

  revealPublicView();
  renderSkeletons(elements.publicTestList, 3);
  await Promise.allSettled([
    loadPublicConfiguration().catch((error) => toast.error(error.message)),
    loadPublicTests(),
  ]);

  api.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_IN' && session?.user) redirectToStudent();
  });

  const reason = new URLSearchParams(window.location.search).get('reason');
  if (reason === 'signin') toast.info('Sign in to access your ScoreMore student dashboard.');
}

initialize();
