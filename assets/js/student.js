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
  testSearch: document.getElementById('testSearch'),
  testTabs: document.getElementById('testTabs'),
  continueAttemptButton: document.getElementById('continueAttemptButton'),
  continueAttemptCard: document.getElementById('continueAttemptCard'),
  attemptSection: document.getElementById('attemptSection'),
  catalogueSection: document.getElementById('catalogueSection'),
  dashboardHome: document.getElementById('dashboardHome'),
  testEngineRoot: document.getElementById('testEngineRoot'),
  catalogueCount: document.getElementById('catalogueCount'),
  catalogueResultText: document.getElementById('catalogueResultText'),
  catalogueScopeText: document.getElementById('catalogueScopeText'),
  clearCatalogueFilters: document.getElementById('clearCatalogueFilters'),
};

let currentUser = null;
let currentProfile = null;
let activeAttempt = null;
let allTests = [];
let redirecting = false;
let selectedType = '';
let searchTerm = '';

const STANDARD_TYPES = [
  ['', 'All tests'],
  ['PYQ_FULL', 'Previous papers'],
  ['PYQ_SECTIONAL', 'Sectional PYQ'],
  ['SECTIONAL_MOCK', 'Sectional mock'],
  ['FULL_MOCK', 'Full mock'],
  ['TOPIC_PRACTICE', 'Topic practice'],
  ['DAILY_QUIZ', 'Daily quiz'],
];

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function renderSkeletons(container, count = 3) {
  if (!container) return;
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

function typeIcon(type) {
  if (type === 'PYQ_FULL') return 'i-file';
  if (type === 'FULL_MOCK') return 'i-target';
  return 'i-layers';
}

function redirectToLanding(reason = 'signin') {
  if (redirecting) return;
  redirecting = true;
  const target = new URL('./index.html', window.location.href);
  if (reason) target.searchParams.set('reason', reason);
  window.location.replace(target.href);
}

function countType(type) {
  return allTests.filter((test) => test.test_type === type).length;
}

function updateDashboardCounts() {
  const pyqCount = countType('PYQ_FULL');
  const sectionalCount = countType('PYQ_SECTIONAL') + countType('SECTIONAL_MOCK');
  const mockCount = countType('FULL_MOCK');
  const practiceCount = sectionalCount + mockCount + countType('TOPIC_PRACTICE') + countType('DAILY_QUIZ');

  document.getElementById('summaryTestCount').textContent = allTests.length;
  document.getElementById('summaryPyqCount').textContent = pyqCount;
  document.getElementById('summaryPracticeCount').textContent = practiceCount;
  document.getElementById('summaryActiveAttempt').textContent = activeAttempt ? 1 : 0;
  document.getElementById('quickPyqCount').textContent = pyqCount;
  document.getElementById('quickSectionalCount').textContent = sectionalCount;
  document.getElementById('quickMockCount').textContent = mockCount;
}

function renderContinueAttempt() {
  if (!activeAttempt) {
    elements.continueAttemptButton?.classList.add('hidden');
    elements.continueAttemptCard?.classList.add('hidden');
    return;
  }

  const title = activeAttempt.tests?.test_name || 'Active test';
  elements.continueAttemptButton?.classList.remove('hidden');
  elements.continueAttemptButton.innerHTML = `<svg class="icon"><use href="#i-play"></use></svg><span>Continue test</span>`;
  elements.continueAttemptButton.onclick = () => navigate('attempt', { id: activeAttempt.attempt_id });

  elements.continueAttemptCard?.classList.remove('hidden');
  elements.continueAttemptCard.innerHTML = `
    <span class="continue-icon"><svg class="icon"><use href="#i-play"></use></svg></span>
    <span class="continue-copy"><small>Continue where you left off</small><strong>${escapeHtml(title)}</strong></span>
    <button class="button button-primary" type="button">Resume</button>
  `;
  elements.continueAttemptCard.querySelector('button')?.addEventListener('click', () => navigate('attempt', { id: activeAttempt.attempt_id }));
}

function renderTestTabs() {
  if (!elements.testTabs) return;
  elements.testTabs.innerHTML = STANDARD_TYPES.map(([type, label]) => {
    const count = type ? countType(type) : allTests.length;
    return `
      <button class="catalogue-tab ${selectedType === type ? 'active' : ''}" data-catalogue-type="${escapeHtml(type)}" role="tab" aria-selected="${selectedType === type}" type="button">
        <span>${escapeHtml(label)}</span><b>${count}</b>
      </button>
    `;
  }).join('');

  elements.testTabs.querySelectorAll('[data-catalogue-type]').forEach((button) => {
    button.addEventListener('click', () => setTypeFilter(button.dataset.catalogueType || ''));
  });
}

function matchesSearch(test) {
  if (!searchTerm) return true;
  const haystack = [
    test.test_name,
    testTypeLabel(test.test_type),
    test.boards?.board_name,
    test.exams?.exam_name,
    test.subjects?.subject_name,
    test.exam_year,
    test.paper_code,
  ].filter(Boolean).join(' ').toLowerCase();
  return haystack.includes(searchTerm);
}

function filteredTests() {
  return allTests.filter((test) => (!selectedType || test.test_type === selectedType) && matchesSearch(test));
}

function testCardMarkup(test) {
  const dateShift = [test.exam_date, test.shift_no ? `Shift ${test.shift_no}` : ''].filter(Boolean).join(' · ');
  const isResume = activeAttempt?.test_id === test.test_id;
  return `
    <article class="catalogue-test-card test-card">
      <div class="test-card-topline">
        <span class="eyebrow">${escapeHtml(testTypeLabel(test.test_type))}</span>
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
        <span>${isResume ? 'Resume test' : 'Start test'}</span><svg class="icon"><use href="#${isResume ? 'i-play' : 'i-arrow'}"></use></svg>
      </button>
    </article>
  `;
}

function renderTests() {
  const tests = filteredTests();
  elements.catalogueCount.textContent = tests.length;
  elements.catalogueResultText.textContent = `${tests.length} ${tests.length === 1 ? 'test' : 'tests'} found`;
  elements.catalogueScopeText.textContent = selectedType ? testTypeLabel(selectedType) : 'All published ScoreMore tests';
  elements.clearCatalogueFilters.classList.toggle('hidden', !selectedType && !searchTerm);

  if (!tests.length) {
    elements.studentTestList.innerHTML = `
      <div class="empty-state catalogue-empty">
        <span class="empty-icon"><svg class="icon"><use href="#i-search"></use></svg></span>
        <h3>No matching tests</h3>
        <p>Try another test type or clear your search.</p>
        <button id="emptyClearFilters" class="button button-ghost" type="button">Clear filters</button>
      </div>
    `;
    document.getElementById('emptyClearFilters')?.addEventListener('click', clearFilters);
    return;
  }

  elements.studentTestList.innerHTML = tests.map(testCardMarkup).join('');
  elements.studentTestList.querySelectorAll('[data-start-test]').forEach((button) => {
    button.addEventListener('click', () => startAttempt(button.dataset.startTest));
  });
}

function applyCatalogue() {
  elements.testTypeFilter.value = selectedType;
  renderTestTabs();
  renderTests();
}

function setTypeFilter(type) {
  selectedType = type;
  applyCatalogue();
}

function clearFilters() {
  selectedType = '';
  searchTerm = '';
  if (elements.testSearch) elements.testSearch.value = '';
  applyCatalogue();
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

async function loadTests({ refresh = false } = {}) {
  if (!allTests.length || refresh) renderSkeletons(elements.studentTestList, 3);
  try {
    allTests = await api.listTests({ pageSize: 100 });
    updateDashboardCounts();
    applyCatalogue();
  } catch (error) {
    elements.studentTestList.innerHTML = `
      <div class="empty-state catalogue-empty error">
        <h3>Tests could not be loaded</h3>
        <p>${escapeHtml(error.message)}</p>
        <button id="retryStudentTests" class="button button-ghost" type="button">Retry</button>
      </div>
    `;
    document.getElementById('retryStudentTests')?.addEventListener('click', () => loadTests({ refresh: true }));
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
    : 'Continue your preparation with reviewed questions and dynamic tests.';

  activeAttempt = await api.getInProgressAttempt();
  renderContinueAttempt();
  await loadTests();
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

function setVisibleSection(routePath) {
  const inAttempt = routePath === 'attempt';
  elements.attemptSection.classList.toggle('hidden', !inAttempt);
  elements.catalogueSection.classList.toggle('hidden', inAttempt);
  elements.dashboardHome.classList.toggle('hidden', inAttempt || routePath === 'tests' || routePath === 'practice');
  elements.mobileNav.classList.toggle('attempt-hidden', inAttempt);
}

async function handleRoute(route) {
  document.querySelectorAll('[data-route]').forEach((button) => {
    button.classList.toggle('active', button.dataset.route === `#${route.path}`);
  });
  if (!currentUser) return;

  setVisibleSection(route.path);

  if (route.path === 'attempt') {
    const attemptId = route.params.get('id');
    if (!attemptId) return navigate('tests');
    try {
      await mountTestEngine(elements.testEngineRoot, attemptId, {
        onExit: async () => {
          elements.testEngineRoot.innerHTML = '';
          activeAttempt = await api.getInProgressAttempt();
          renderContinueAttempt();
          updateDashboardCounts();
          navigate('tests');
        },
      });
    } catch (error) {
      toast.error(error.message);
      navigate('tests');
    }
    return;
  }

  if (route.path === 'home') {
    window.scrollTo({ top: 0, behavior: 'smooth' });
    return;
  }

  if (route.path === 'tests') {
    elements.catalogueSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
    return;
  }

  if (route.path === 'practice') {
    if (!selectedType) setTypeFilter('SECTIONAL_MOCK');
    elements.catalogueSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
    return;
  }

  if (['bookmarks', 'mistakes', 'results', 'profile'].includes(route.path)) {
    toast.info('This module is reserved in the locked roadmap and will be connected in its approved development phase.');
    navigate('home');
  }
}

function bindNetworkState() {
  const syncState = document.getElementById('syncState');
  const update = () => {
    if (!syncState) return;
    const online = navigator.onLine;
    syncState.innerHTML = `<span class="sync-dot"></span>${online ? 'Online' : 'Offline'}`;
    syncState.classList.toggle('offline', !online);
    syncState.title = online ? 'Connected' : 'Answers remain on this device until connectivity returns.';
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
    button.addEventListener('click', () => {
      setTypeFilter(button.dataset.testFilter);
      navigate('tests');
    });
  });
  elements.testTypeFilter?.addEventListener('change', () => setTypeFilter(elements.testTypeFilter.value));
  elements.testSearch?.addEventListener('input', () => {
    searchTerm = elements.testSearch.value.trim().toLowerCase();
    renderTests();
  });
  elements.clearCatalogueFilters?.addEventListener('click', clearFilters);
  document.getElementById('refreshStudentTests')?.addEventListener('click', () => loadTests({ refresh: true }));
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
