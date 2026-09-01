import { APP_CONFIG, isConfigured, resolvePublicSettings } from './config.js';
import { api } from './api.js';
import { bindAuthTabs, bindStudentAuth } from './auth.js';
import { bindConnectionBadge } from './connectionState.js';
import {
  PUBLIC_TEST_CATEGORIES,
  publicCategoryCount,
  testTypeIcon,
  testTypeLabel,
} from './testTypes.js';
import { toast } from './toast.js';

const PENDING_TEST_KEY = `${APP_CONFIG.cacheVersion}:pending-test-id`;

const elements = {
  setupNotice: document.getElementById('setupNotice'),
  publicLoading: document.getElementById('publicLoading'),
  publicView: document.getElementById('publicView'),
  publicTestList: document.getElementById('publicTestList'),
  publicFeaturedTests: document.getElementById('publicFeaturedTests'),
  publicTestTypes: document.getElementById('publicTestTypes'),
  publicScopes: document.getElementById('publicScopes'),
  publicCategoryFilter: document.getElementById('publicCategoryFilter'),
  publicCategoryFilterLabel: document.getElementById('publicCategoryFilterLabel'),
  clearPublicCategory: document.getElementById('clearPublicCategory'),
};

let redirecting = false;
let publicTests = [];
let publicConfig = { boards: [], exams: [], settings: {}, stats: {} };
let activeCategory = '';

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
        <span class="mini-test-icon"><svg class="icon"><use href="#${testTypeIcon(test.test_type)}"></use></svg></span>
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
        <span class="test-type-icon"><svg class="icon"><use href="#${testTypeIcon(test.test_type)}"></use></svg></span>
        <div>
          <h3>${escapeHtml(test.test_name)}</h3>
          <p>${escapeHtml(test.boards?.board_name || APP_CONFIG.name)} ${test.exams?.exam_name ? `· ${escapeHtml(test.exams.exam_name)}` : ''}</p>
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
    const category = PUBLIC_TEST_CATEGORIES[activeCategory];
    elements.publicTestList.innerHTML = `
      <div class="empty-state catalogue-empty">
        <span class="empty-icon"><svg class="icon"><use href="#i-grid"></use></svg></span>
        <h3>${category ? `${escapeHtml(category.label)} are coming soon` : 'No published tests yet'}</h3>
        <p>${category ? `Choose another category or check again after new student-ready tests are published.` : `Reviewed tests will appear here as soon as the ${APP_CONFIG.name} administrator publishes them.`}</p>
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
      <span class="compact-list-icon"><svg class="icon"><use href="#${testTypeIcon(type)}"></use></svg></span>
      <span><strong>${escapeHtml(testTypeLabel(type, { plural: count !== 1 }))}</strong><small>Available now</small></span>
      <b>${count}</b>
    </div>
  `).join('');
}

function renderCategoryStats(stats = publicConfig.stats || {}, tests = publicTests) {
  const elementIds = {
    MOCK: 'statMockTests',
    PYQ: 'statPyqTests',
    SECTIONAL: 'statSectionalTests',
    TOPIC: 'statTopicTests',
  };

  Object.entries(PUBLIC_TEST_CATEGORIES).forEach(([category, metadata]) => {
    const databaseCount = Number(stats?.[metadata.statKey]);
    const count = Number.isFinite(databaseCount) ? databaseCount : publicCategoryCount(tests, category);
    const value = document.getElementById(elementIds[category]);
    const card = document.querySelector(`[data-public-category="${category}"]`);
    if (value) value.textContent = count.toLocaleString('en-IN');
    if (!card) return;
    card.dataset.count = String(count);
    card.classList.toggle('coming-soon', count === 0);
    card.setAttribute('aria-label', count === 0
      ? `${metadata.label}: coming soon`
      : `${count} ${metadata.label}. Show this category.`);
    const detail = card.querySelector('small');
    if (detail) detail.textContent = count === 0 ? 'Coming soon' : metadata.description;
  });
}

function renderCategoryFilter() {
  const metadata = PUBLIC_TEST_CATEGORIES[activeCategory];
  elements.publicCategoryFilter?.classList.toggle('hidden', !metadata);
  if (elements.publicCategoryFilterLabel) {
    elements.publicCategoryFilterLabel.textContent = metadata?.label || 'all tests';
  }
  document.querySelectorAll('[data-public-category]').forEach((card) => {
    const active = card.dataset.publicCategory === activeCategory;
    card.classList.toggle('active', active);
    card.setAttribute('aria-pressed', String(active));
  });
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
  const settings = resolvePublicSettings(publicConfig.settings || {});
  document.getElementById('brandName').textContent = settings.appName;
  document.getElementById('brandTagline').textContent = settings.tagline;
  document.getElementById('scopeBadge').textContent = settings.scopeBadge;
  document.getElementById('heroTitle').textContent = settings.heroTitle;
  document.getElementById('heroSubtitle').textContent = settings.heroSubtitle;
  renderCategoryStats(publicConfig.stats, publicTests);
  renderScopes(publicConfig);
}

async function loadPublicTests() {
  const category = PUBLIC_TEST_CATEGORIES[activeCategory];
  renderSkeletons(elements.publicTestList, 3);
  if (!category) {
    renderSkeletons(elements.publicFeaturedTests, 2, true);
    renderSkeletons(elements.publicTestTypes, 3, true);
  }
  try {
    const tests = await api.listTests({ testTypes: category?.testTypes || [], pageSize: 50 });
    renderTests(tests);
    if (!category) {
      publicTests = tests;
      renderFeaturedTests(publicTests);
      renderTestTypes(publicTests);
      renderCategoryStats(publicConfig.stats, publicTests);
    }
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

async function selectPublicCategory(category) {
  const metadata = PUBLIC_TEST_CATEGORIES[category];
  if (!metadata) return;
  const card = document.querySelector(`[data-public-category="${category}"]`);
  if (Number(card?.dataset.count || 0) === 0) {
    toast.info(`${metadata.label} are coming soon.`);
    return;
  }
  activeCategory = category;
  renderCategoryFilter();
  await loadPublicTests();
  document.getElementById('publicTests')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

async function clearPublicCategory() {
  if (!activeCategory) return;
  activeCategory = '';
  renderCategoryFilter();
  await loadPublicTests();
}

function bindUi() {
  bindAuthTabs();
  bindStudentAuth({ onAuthenticated: redirectToStudent });
  bindConnectionBadge(document.getElementById('syncState'));

  document.querySelectorAll('[data-scroll-to]').forEach((button) => {
    button.addEventListener('click', () => {
      document.getElementById(button.dataset.scrollTo)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });
  document.getElementById('refreshPublicTests')?.addEventListener('click', () => loadPublicTests());
  document.querySelectorAll('[data-public-category]').forEach((card) => {
    card.addEventListener('click', () => selectPublicCategory(card.dataset.publicCategory));
  });
  elements.clearPublicCategory?.addEventListener('click', clearPublicCategory);
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
  if (reason === 'signin') toast.info(`Sign in to access your ${APP_CONFIG.name} student dashboard.`);
}

initialize();
