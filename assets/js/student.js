import { APP_CONFIG, isConfigured } from './config.js';
import { api } from './api.js';
import { navigate, startRouter, subscribeRoute } from './router.js';
import { mountTestEngine } from './testEngine.js';
import { toast } from './toast.js';

const PENDING_TEST_KEY = 'scoremore:pending-test-id';

const elements = {
  setupNotice: document.getElementById('setupNotice'),
  studentLoading: document.getElementById('studentLoading'),
  studentView: document.getElementById('studentView'),
  mobileNav: document.getElementById('mobileNav'),
  signOutButton: document.getElementById('signOutButton'),
  studentTestList: document.getElementById('studentTestList'),
  testTypeFilter: document.getElementById('testTypeFilter'),
  continueAttemptButton: document.getElementById('continueAttemptButton'),
  attemptSection: document.getElementById('attemptSection'),
  catalogueSection: document.getElementById('catalogueSection'),
  testEngineRoot: document.getElementById('testEngineRoot'),
};

let currentUser = null;
let currentProfile = null;
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

function redirectToLanding(reason = 'signin') {
  if (redirecting) return;
  redirecting = true;
  const target = new URL('./index.html', window.location.href);
  if (reason) target.searchParams.set('reason', reason);
  window.location.replace(target.href);
}

function renderTests(tests) {
  if (!tests.length) {
    elements.studentTestList.innerHTML = '<div class="empty-state">No published tests match this view yet.</div>';
    return;
  }

  elements.studentTestList.innerHTML = tests.map((test) => {
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
          <button class="button button-primary" data-start-test="${escapeHtml(test.test_id)}" type="button">Start / Resume</button>
        </div>
      </article>
    `;
  }).join('');

  elements.studentTestList.querySelectorAll('[data-start-test]').forEach((button) => {
    button.addEventListener('click', () => startAttempt(button.dataset.startTest));
  });
}

async function loadBrand() {
  try {
    const config = await api.getPublicConfiguration();
    const settings = config.settings || {};
    document.getElementById('brandName').textContent = settings.app_name || APP_CONFIG.name;
    document.getElementById('brandTagline').textContent = settings.app_tagline || 'Prepare smarter';
  } catch (error) {
    toast.warning(error.message);
  }
}

async function loadTests(testType = '') {
  renderSkeletons(elements.studentTestList, 3);
  try {
    renderTests(await api.listTests({ testType }));
  } catch (error) {
    elements.studentTestList.innerHTML = `
      <div class="empty-state">
        ${escapeHtml(error.message)}
        <button id="retryStudentTests" class="button button-ghost" type="button">Retry</button>
      </div>
    `;
    document.getElementById('retryStudentTests')?.addEventListener('click', () => loadTests(testType));
  }
}

async function showStudent(user) {
  currentUser = user;
  currentProfile = await api.getProfile();
  elements.studentLoading?.classList.add('hidden');
  elements.studentView?.classList.remove('hidden');
  elements.mobileNav?.classList.remove('hidden');
  elements.signOutButton?.classList.remove('hidden');

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

function bindNetworkState() {
  const syncState = document.getElementById('syncState');
  const update = () => {
    if (!syncState) return;
    syncState.textContent = navigator.onLine ? 'Online' : 'Offline — answers stay on device';
    syncState.style.color = navigator.onLine ? '' : 'var(--warning)';
  };
  window.addEventListener('online', update);
  window.addEventListener('offline', update);
  update();
}

function bindUi() {
  document.querySelectorAll('[data-route]').forEach((button) => {
    button.addEventListener('click', () => { window.location.hash = button.dataset.route; });
  });
  document.querySelectorAll('[data-test-filter]').forEach((button) => {
    button.addEventListener('click', async () => {
      elements.testTypeFilter.value = button.dataset.testFilter;
      await loadTests(button.dataset.testFilter);
      navigate('tests');
    });
  });
  elements.testTypeFilter?.addEventListener('change', () => loadTests(elements.testTypeFilter.value));
  elements.signOutButton?.addEventListener('click', async () => {
    try {
      await api.signOut();
      toast.success('Signed out.');
      redirectToLanding('');
    } catch (error) {
      toast.error(error.message);
    }
  });
  bindNetworkState();
}

async function initialize() {
  bindUi();
  subscribeRoute(handleRoute);

  if (!isConfigured) {
    elements.setupNotice?.classList.remove('hidden');
    elements.studentLoading.textContent = 'ScoreMore is not configured.';
    return;
  }

  try {
    const user = await api.getUser();
    if (!user) {
      redirectToLanding('signin');
      return;
    }

    await Promise.all([loadBrand(), showStudent(user)]);
    api.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') redirectToLanding('signin');
    });
    startRouter();

    const pendingTestId = sessionStorage.getItem(PENDING_TEST_KEY);
    if (pendingTestId) {
      sessionStorage.removeItem(PENDING_TEST_KEY);
      await startAttempt(pendingTestId);
    }
  } catch (error) {
    toast.error(error.message);
    redirectToLanding('signin');
  }
}

initialize();
