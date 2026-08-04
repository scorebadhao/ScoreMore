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
};

let redirecting = false;

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function renderSkeletons(container, count = 3) {
  container.innerHTML = Array.from({ length: count }, () => '<div class="skeleton" aria-hidden="true"></div>').join('');
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

function revealPublicView() {
  elements.publicLoading?.classList.add('hidden');
  elements.publicView?.classList.remove('hidden');
}

function redirectToStudent() {
  if (redirecting) return;
  redirecting = true;
  window.location.replace('./student.html');
}

function renderTests(tests) {
  if (!tests.length) {
    elements.publicTestList.innerHTML = '<div class="empty-state">No published tests match this view yet.</div>';
    return;
  }

  elements.publicTestList.innerHTML = tests.map((test) => {
    const dateShift = [test.exam_date, test.shift_no ? `Shift ${test.shift_no}` : ''].filter(Boolean).join(' · ');
    return `
      <article class="test-card">
        <div class="test-card-header">
          <div>
            <span class="eyebrow">${escapeHtml(testTypeLabel(test.test_type))}</span>
            <h3>${escapeHtml(test.test_name)}</h3>
          </div>
          <span class="chip ${test.is_free ? '' : 'chip-premium'}">${test.is_free ? 'Free' : 'Premium'}</span>
        </div>
        <div class="test-meta">
          ${test.boards?.board_name ? `<span class="chip">${escapeHtml(test.boards.board_name)}</span>` : ''}
          ${test.exams?.exam_name ? `<span class="chip">${escapeHtml(test.exams.exam_name)}</span>` : ''}
          ${test.subjects?.subject_name ? `<span class="chip">${escapeHtml(test.subjects.subject_name)}</span>` : ''}
          ${dateShift ? `<span class="chip">${escapeHtml(dateShift)}</span>` : ''}
        </div>
        <div class="test-card-footer">
          <span>${escapeHtml(test.question_count)} questions · ${escapeHtml(test.duration_minutes || 0)} min</span>
          <button class="button button-primary" data-start-test="${escapeHtml(test.test_id)}" type="button">Sign in to start</button>
        </div>
      </article>
    `;
  }).join('');

  elements.publicTestList.querySelectorAll('[data-start-test]').forEach((button) => {
    button.addEventListener('click', () => {
      sessionStorage.setItem(PENDING_TEST_KEY, button.dataset.startTest);
      document.getElementById('authCard')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      toast.info('Sign in to start this test.');
    });
  });
}

async function loadPublicConfiguration() {
  const config = await api.getPublicConfiguration();
  const settings = config.settings || {};
  document.getElementById('brandName').textContent = settings.app_name || APP_CONFIG.name;
  document.getElementById('brandTagline').textContent = settings.app_tagline || 'Prepare smarter';
  document.getElementById('scopeBadge').textContent = settings.scope_badge || 'Dynamic exam platform';
  document.getElementById('heroTitle').textContent = settings.hero_title || 'Prepare Smarter';
  document.getElementById('heroSubtitle').textContent = settings.hero_subtitle || 'Previous-year questions, sectional practice and meaningful analytics.';
  const stats = config.stats || {};
  document.getElementById('statQuestions').textContent = stats.published_questions ?? 0;
  document.getElementById('statPapers').textContent = stats.pyq_papers ?? 0;
  document.getElementById('statTests').textContent = stats.published_tests ?? 0;
  document.getElementById('statAttempts').textContent = stats.student_attempts ?? 0;
}

async function loadPublicTests() {
  renderSkeletons(elements.publicTestList, 3);
  try {
    renderTests(await api.listTests());
  } catch (error) {
    elements.publicTestList.innerHTML = `
      <div class="empty-state">
        ${escapeHtml(error.message)}
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
    syncState.textContent = navigator.onLine ? 'Online' : 'Offline';
    syncState.style.color = navigator.onLine ? '' : 'var(--warning)';
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
