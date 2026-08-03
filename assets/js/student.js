import { APP_CONFIG, isConfigured } from './config.js';
import { api } from './api.js';
import { bindAuthTabs, bindStudentAuth } from './auth.js';
import { navigate, startRouter, subscribeRoute } from './router.js';
import { mountTestEngine } from './testEngine.js';
import { toast } from './toast.js';

const elements = {
  setupNotice: document.getElementById('setupNotice'),
  publicView: document.getElementById('publicView'),
  studentView: document.getElementById('studentView'),
  mobileNav: document.getElementById('mobileNav'),
  signOutButton: document.getElementById('signOutButton'),
  publicTestList: document.getElementById('publicTestList'),
  studentTestList: document.getElementById('studentTestList'),
  testTypeFilter: document.getElementById('testTypeFilter'),
  continueAttemptButton: document.getElementById('continueAttemptButton'),
  attemptSection: document.getElementById('attemptSection'),
  catalogueSection: document.getElementById('catalogueSection'),
  testEngineRoot: document.getElementById('testEngineRoot'),
};

let currentUser = null;
let currentProfile = null;
let cachedTests = [];

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

function renderTests(container, tests, { publicMode = false } = {}) {
  if (!tests.length) {
    container.innerHTML = '<div class="empty-state">No published tests match this view yet.</div>';
    return;
  }
  container.innerHTML = tests.map((test) => {
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
          <button class="button button-primary" data-start-test="${escapeHtml(test.test_id)}" type="button">${publicMode ? 'Sign in to start' : 'Start / Resume'}</button>
        </div>
      </article>
    `;
  }).join('');

  container.querySelectorAll('[data-start-test]').forEach((button) => {
    button.addEventListener('click', async () => {
      if (!currentUser) {
        document.getElementById('authCard')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
        toast.info('Sign in to start or resume a test.');
        return;
      }
      await startAttempt(button.dataset.startTest);
    });
  });
}

async function loadPublicConfig() {
  try {
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
  } catch (error) {
    toast.error(error.message);
  }
}

async function loadTests(testType = '') {
  renderSkeletons(elements.publicTestList, 3);
  if (currentUser) renderSkeletons(elements.studentTestList, 3);
  try {
    cachedTests = await api.listTests({ testType });
    renderTests(elements.publicTestList, cachedTests, { publicMode: true });
    if (currentUser) renderTests(elements.studentTestList, cachedTests);
  } catch (error) {
    const html = `<div class="empty-state">${escapeHtml(error.message)} <button id="retryTests" class="button button-ghost" type="button">Retry</button></div>`;
    elements.publicTestList.innerHTML = html;
    if (currentUser) elements.studentTestList.innerHTML = html;
    document.querySelectorAll('#retryTests').forEach((button) => button.addEventListener('click', () => loadTests(testType)));
  }
}

async function showStudent(user) {
  currentUser = user || await api.getUser();
  if (!currentUser) return showPublic();
  currentProfile = await api.getProfile();
  elements.publicView.classList.add('hidden');
  elements.studentView.classList.remove('hidden');
  elements.mobileNav.classList.remove('hidden');
  elements.signOutButton.classList.remove('hidden');
  document.getElementById('welcomeTitle').textContent = `Welcome, ${currentProfile?.full_name || currentUser.email?.split('@')[0] || 'Student'}`;
  document.getElementById('targetExamLabel').textContent = currentProfile?.target_exam_id
    ? `Target exam: ${currentProfile.target_exam_id}`
    : 'Choose and attempt any available published test.';
  const active = await api.getInProgressAttempt();
  if (active) {
    elements.continueAttemptButton.classList.remove('hidden');
    elements.continueAttemptButton.textContent = `Continue: ${active.tests?.test_name || 'Test'}`;
    elements.continueAttemptButton.onclick = () => navigate('attempt', { id: active.attempt_id });
  } else {
    elements.continueAttemptButton.classList.add('hidden');
  }
  await loadTests(elements.testTypeFilter.value);
}

function showPublic() {
  currentUser = null;
  currentProfile = null;
  elements.publicView.classList.remove('hidden');
  elements.studentView.classList.add('hidden');
  elements.mobileNav.classList.add('hidden');
  elements.signOutButton.classList.add('hidden');
  elements.attemptSection.classList.add('hidden');
}

async function startAttempt(testId) {
  const loading = toast.loading('Preparing your test…');
  try {
    const attempt = await api.createOrResumeAttempt(testId);
    loading.close();
    navigate('attempt', { id: attempt.attempt_id || attempt });
  } catch (error) {
    loading.close();
    toast.error(error.message);
  }
}

async function handleRoute(route) {
  document.querySelectorAll('[data-route]').forEach((button) => {
    button.classList.toggle('active', button.dataset.route === `#${route.path}`);
  });
  if (!currentUser) return;

  if (route.path === 'attempt') {
    const attemptId = route.params.get('id');
    if (!attemptId) return navigate('tests');
    elements.catalogueSection.classList.add('hidden');
    elements.attemptSection.classList.remove('hidden');
    try {
      await mountTestEngine(elements.testEngineRoot, attemptId, {
        onExit: () => {
          elements.testEngineRoot.innerHTML = '';
          navigate('tests');
        },
      });
    } catch (error) {
      toast.error(error.message);
      navigate('tests');
    }
    return;
  }

  elements.attemptSection.classList.add('hidden');
  elements.catalogueSection.classList.remove('hidden');
  if (route.path === 'home') window.scrollTo({ top: 0, behavior: 'smooth' });
  if (route.path === 'tests' || route.path === 'practice') elements.catalogueSection.scrollIntoView({ behavior: 'smooth' });
  if (['bookmarks', 'mistakes', 'results', 'profile'].includes(route.path)) {
    toast.info('This module is reserved in the architecture and will be connected in its development phase.');
    navigate('home');
  }
}

function bindUi() {
  bindAuthTabs();
  bindStudentAuth({ onAuthenticated: showStudent });

  document.querySelectorAll('[data-scroll-to]').forEach((button) => {
    button.addEventListener('click', () => document.getElementById(button.dataset.scrollTo)?.scrollIntoView({ behavior: 'smooth' }));
  });
  document.querySelectorAll('[data-route]').forEach((button) => {
    button.addEventListener('click', () => window.location.hash = button.dataset.route);
  });
  document.querySelectorAll('[data-test-filter]').forEach((button) => {
    button.addEventListener('click', async () => {
      elements.testTypeFilter.value = button.dataset.testFilter;
      await loadTests(button.dataset.testFilter);
      elements.catalogueSection.scrollIntoView({ behavior: 'smooth' });
    });
  });
  elements.testTypeFilter?.addEventListener('change', () => loadTests(elements.testTypeFilter.value));
  document.getElementById('refreshPublicTests')?.addEventListener('click', () => loadTests(''));
  elements.signOutButton?.addEventListener('click', async () => {
    try {
      await api.signOut();
      toast.success('Signed out.');
      showPublic();
      navigate('home');
    } catch (error) { toast.error(error.message); }
  });
  window.addEventListener('online', () => {
    document.getElementById('syncState').textContent = 'Online';
    document.getElementById('syncState').style.color = '';
  });
  window.addEventListener('offline', () => {
    document.getElementById('syncState').textContent = 'Offline — answers stay on device';
    document.getElementById('syncState').style.color = 'var(--warning)';
  });
}

async function initialize() {
  bindUi();
  subscribeRoute(handleRoute);
  if (!isConfigured) {
    elements.setupNotice.classList.remove('hidden');
    renderTests(elements.publicTestList, []);
    startRouter();
    return;
  }

  renderSkeletons(elements.publicTestList, 3);
  await Promise.all([loadPublicConfig(), loadTests('')]);
  try {
    const user = await api.getUser();
    if (user) await showStudent(user);
    else showPublic();
    api.onAuthStateChange(async (event, session) => {
      if (event === 'SIGNED_OUT') showPublic();
      if (event === 'SIGNED_IN' && session?.user) await showStudent(session.user);
    });
  } catch (error) {
    toast.error(error.message);
    showPublic();
  }
  startRouter();
}

initialize();
