import { APP_CONFIG, isConfigured, resolvePublicSettings } from './config.js';
import { api } from './api.js';
import { bindConnectionBadge } from './connectionState.js';
import { assertPasswordPolicy, PASSWORD_POLICY_MESSAGE } from './passwordPolicy.js';
import { navigate, startRouter, subscribeRoute } from './router.js';
import { mountTestEngine } from './testEngine.js';
import { testTypeIcon as typeIcon, testTypeLabel } from './testTypes.js';
import { toast } from './toast.js';

const PENDING_TEST_KEY = `${APP_CONFIG.cacheVersion}:pending-test-id`;
const TEST_PAGE_SIZE = 12;
const SAVED_PAGE_SIZE = 20;
const RESULT_PAGE_SIZE = 12;

const elements = Object.fromEntries([
  'setupNotice', 'studentLoading', 'studentView', 'mobileNav', 'dashboardHome',
  'catalogueSection', 'savedSection', 'resultsSection', 'profileSection',
  'attemptSection', 'testEngineRoot', 'studentTestList', 'testTabs',
  'catalogueCount', 'catalogueResultText', 'catalogueScopeText',
  'clearCatalogueFilters', 'testPagination', 'savedList', 'savedCount',
  'savedPagination', 'revisionTestAction', 'resultList', 'resultCount',
  'resultPagination', 'resultsListView', 'resultDetailView', 'profileContent',
  'continueAttemptButton', 'continueAttemptCard', 'homeRecentResults',
].map((id) => [id, document.getElementById(id)]));

const input = (id) => document.getElementById(id);

let currentUser = null;
let homeData = null;
let testFacets = null;
let unmountTestEngine = null;
let routeSequence = 0;
let searchTimer = null;
let requiresOnboarding = false;
let onboardingNoticeShown = false;

const testFilters = {
  testType: '', search: '', subjectId: '', topicId: '', examYear: '', examDate: '',
  shiftNo: '', access: 'ALL', progress: 'ALL', sort: 'RECOMMENDED', page: 0,
};
let testResult = { items: [], total: 0, page: 0, has_more: false };

const savedFilters = {
  kind: 'BOOKMARKS', search: '', subjectId: '', topicId: '', status: 'ALL', offset: 0,
};
let savedResult = { items: [], total: 0, has_more: false, revision_test: null };

const resultFilters = { search: '', sort: 'NEWEST', page: 0 };
let resultData = { items: [], total: 0, page: 0, has_more: false };
let currentReview = { detail: null, items: [], filter: 'ALL' };

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#039;');
}

function formatNumber(value, maximumFractionDigits = 2) {
  return Number(value || 0).toLocaleString('en-IN', { maximumFractionDigits });
}

function formatDate(value, { includeTime = false } = {}) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
    ...(includeTime ? { hour: '2-digit', minute: '2-digit' } : {}),
  }).format(date);
}

function formatDuration(totalSeconds) {
  const seconds = Math.max(0, Number(totalSeconds) || 0);
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const rest = Math.floor(seconds % 60);
  return hours ? `${hours}h ${minutes}m` : `${minutes}m ${rest}s`;
}

function safeImageUrl(value) {
  try {
    const parsed = new URL(String(value || ''), window.location.href);
    return ['http:', 'https:', 'blob:', 'data:'].includes(parsed.protocol) ? parsed.href : '';
  } catch { return ''; }
}

function imageMarkup(refs) {
  const images = (Array.isArray(refs) ? refs : []).map((item) => ({
    url: safeImageUrl(typeof item === 'string' ? item : item?.url),
    alt: typeof item === 'object' ? item?.alt || 'Question diagram' : 'Question diagram',
    blocked: Boolean(item?.blocked),
  })).filter((item) => item.url || item.blocked);
  if (!images.length) return '';
  if (images.some((item) => item.blocked)) return '<div class="question-image-review"><strong>Diagram temporarily unavailable</strong><span>The approved student image could not be loaded.</span></div>';
  return `<div class="question-images">${images.map((item) => `<figure class="question-image-frame"><img class="question-image" src="${escapeHtml(item.url)}" alt="${escapeHtml(item.alt)}" loading="lazy" decoding="async" /></figure>`).join('')}</div>`;
}

function renderSkeletons(container, count = 3) {
  if (container) container.innerHTML = Array.from({ length: count }, () => '<div class="skeleton" aria-hidden="true"></div>').join('');
}

function emptyState({ icon = 'i-search', title, message, action = '' }) {
  return `<div class="empty-state catalogue-empty"><span class="empty-icon"><svg class="icon"><use href="#${icon}"></use></svg></span><h3>${escapeHtml(title)}</h3><p>${escapeHtml(message)}</p>${action}</div>`;
}

function errorState(message, retryId) {
  return emptyState({
    icon: 'i-refresh', title: 'Could not load this section', message,
    action: `<button id="${retryId}" class="button button-ghost" type="button">Retry</button>`,
  });
}

function debounce(callback, delay = 300) {
  window.clearTimeout(searchTimer);
  searchTimer = window.setTimeout(callback, delay);
}

function redirectToLanding(reason = 'signin') {
  const target = new URL('./index.html', window.location.href);
  if (reason) target.searchParams.set('reason', reason);
  window.location.replace(target.href);
}

async function loadBrand() {
  try {
    const config = await api.getPublicConfiguration();
    const settings = resolvePublicSettings(config.settings || {});
    input('brandName').textContent = settings.appName;
    input('brandTagline').textContent = settings.tagline;
  } catch (error) {
    toast.warning(error.message);
  }
}

function setSelectOptions(select, rows, { valueKey = 'id', labelKey = 'name', firstLabel = 'All' } = {}) {
  if (!select) return;
  const current = select.value;
  select.innerHTML = `<option value="">${escapeHtml(firstLabel)}</option>${(rows || []).map((row) => `<option value="${escapeHtml(row[valueKey])}">${escapeHtml(row[labelKey])}</option>`).join('')}`;
  if ([...select.options].some((option) => option.value === current)) select.value = current;
}

function renderHome() {
  if (!homeData) return;
  const profile = homeData.profile || {};
  const summary = homeData.summary || {};
  const quick = homeData.quick_counts || {};
  const target = profile.target_exam_name || profile.target_exam_id || 'GSSSB CCE';
  input('welcomeTitle').textContent = `Welcome, ${profile.full_name || currentUser?.email?.split('@')[0] || 'Student'}`;
  input('targetExamLabel').textContent = `Target: ${target} · ${String(profile.language || 'GUJARATI').toLowerCase().replace(/^./, (c) => c.toUpperCase())}`;
  input('summaryAccuracy').textContent = `${formatNumber(summary.average_accuracy)}%`;
  input('summaryCompleted').textContent = formatNumber(summary.completed_attempts, 0);
  input('summarySaved').textContent = formatNumber(summary.saved_count, 0);
  input('summarySolved').textContent = formatNumber(summary.questions_solved, 0);
  input('quickPyqCount').textContent = quick.PYQ_FULL || 0;
  input('quickSectionalCount').textContent = (quick.PYQ_SECTIONAL || 0) + (quick.SECTIONAL_MOCK || 0);
  input('quickMockCount').textContent = quick.FULL_MOCK || 0;
  input('quickDailyCount').textContent = quick.DAILY_QUIZ || 0;

  const attempt = homeData.continue_attempt;
  elements.continueAttemptButton.classList.toggle('hidden', !attempt);
  elements.continueAttemptCard.classList.toggle('hidden', !attempt);
  if (attempt) {
    const answered = Number(attempt.answered || 0);
    const total = Number(attempt.total_questions || 0);
    const progress = total ? Math.round((answered / total) * 100) : 0;
    elements.continueAttemptButton.onclick = () => navigate('attempt', { id: attempt.attempt_id });
    elements.continueAttemptCard.innerHTML = `<span class="continue-icon"><svg class="icon"><use href="#i-play"></use></svg></span><span class="continue-copy"><small>Continue where you left off · ${answered}/${total} answered</small><strong>${escapeHtml(attempt.test_name)}</strong><span class="mini-progress"><i style="width:${progress}%"></i></span></span><button class="button button-primary" type="button">Resume</button>`;
    elements.continueAttemptCard.querySelector('button')?.addEventListener('click', () => navigate('attempt', { id: attempt.attempt_id }));
  }

  const weak = homeData.weak_subject;
  input('weakSubjectCard').innerHTML = weak
    ? `<span class="hub-insight-icon warning"><svg class="icon"><use href="#i-target"></use></svg></span><div><small>Focus area</small><h3>${escapeHtml(weak.subject_name)}</h3><p>${formatNumber(weak.accuracy)}% accuracy across ${weak.question_count} questions.</p><button class="text-button" data-focus-subject="${escapeHtml(weak.subject_id)}" type="button">Find focused tests →</button></div>`
    : `<span class="hub-insight-icon"><svg class="icon"><use href="#i-target"></use></svg></span><div><small>Focus area</small><h3>Build your baseline</h3><p>Complete a test to receive a subject-level recommendation.</p></div>`;
  input('weakSubjectCard').querySelector('[data-focus-subject]')?.addEventListener('click', (event) => {
    testFilters.subjectId = event.currentTarget.dataset.focusSubject;
    testFilters.testType = 'PYQ_SECTIONAL';
    testFilters.page = 0;
    navigate('tests');
  });

  const recommended = homeData.recommended_test;
  input('recommendedTestCard').innerHTML = recommended
    ? `<span class="hub-insight-icon success"><svg class="icon"><use href="#i-trend"></use></svg></span><div><small>Recommended next</small><h3>${escapeHtml(recommended.test_name)}</h3><p>${recommended.question_count} questions · ${recommended.duration_minutes} min</p><button class="text-button" data-recommended-test="${escapeHtml(recommended.test_id)}" ${recommended.can_start ? '' : 'disabled'} type="button">${recommended.can_start ? 'Start test →' : 'Premium access required'}</button></div>`
    : `<span class="hub-insight-icon"><svg class="icon"><use href="#i-trend"></use></svg></span><div><small>Recommended next</small><h3>No recommendation yet</h3><p>New student-ready tests will appear here.</p></div>`;
  input('recommendedTestCard').querySelector('[data-recommended-test]')?.addEventListener('click', (event) => startAttempt(event.currentTarget.dataset.recommendedTest));

  const packages = homeData.package_summary || {};
  input('packageSummaryCard').innerHTML = `<span class="hub-insight-icon"><svg class="icon"><use href="#i-lock"></use></svg></span><div><small>Package access</small><h3>${Number(packages.active_count || 0) ? `${packages.active_count} active` : 'Free access'}</h3><p>${packages.next_expiry ? `Next expiry: ${formatDate(packages.next_expiry)}` : 'Free tests remain available without a package.'}</p></div>`;

  const recent = homeData.recent_results || [];
  elements.homeRecentResults.innerHTML = recent.length ? recent.map((item) => `<button class="home-result-row" data-home-result="${escapeHtml(item.attempt_id)}" type="button"><span><strong>${escapeHtml(item.test_name)}</strong><small>${formatDate(item.submitted_at)} · ${escapeHtml(testTypeLabel(item.test_type))}</small></span><span class="result-row-score"><b>${formatNumber(item.score)}</b><small>${formatNumber(item.accuracy)}%</small></span><svg class="icon"><use href="#i-arrow"></use></svg></button>`).join('') : emptyState({ icon: 'i-chart', title: 'No submitted results yet', message: 'Complete your first test to unlock analytics.' });
  elements.homeRecentResults.querySelectorAll('[data-home-result]').forEach((button) => button.addEventListener('click', () => navigate('result', { id: button.dataset.homeResult })));
}

async function loadHome({ refresh = false } = {}) {
  if (homeData && !refresh) return renderHome();
  try {
    homeData = await api.getStudentHome();
    renderHome();
  } catch (error) {
    toast.error(error.message);
  }
}

function renderTestTabs() {
  const available = ['', ...(testFacets?.test_types || [])];
  elements.testTabs.innerHTML = available.map((type) => `<button class="catalogue-tab ${testFilters.testType === type ? 'active' : ''}" data-catalogue-type="${escapeHtml(type)}" role="tab" aria-selected="${testFilters.testType === type}" type="button"><span>${type ? escapeHtml(testTypeLabel(type)) : 'All tests'}</span></button>`).join('');
  elements.testTabs.querySelectorAll('[data-catalogue-type]').forEach((button) => button.addEventListener('click', () => {
    testFilters.testType = button.dataset.catalogueType || '';
    testFilters.page = 0;
    syncTestControls();
    loadTests();
  }));
}

function syncTestControls() {
  const mapping = {
    testSearch: 'search', testSubjectFilter: 'subjectId', testTopicFilter: 'topicId',
    testYearFilter: 'examYear', testDateFilter: 'examDate', testShiftFilter: 'shiftNo',
    testAccessFilter: 'access', testProgressFilter: 'progress', testSort: 'sort',
  };
  Object.entries(mapping).forEach(([id, key]) => { if (input(id)) input(id).value = testFilters[key]; });
  const hasFilter = Boolean(testFilters.testType || testFilters.search || testFilters.subjectId || testFilters.topicId || testFilters.examYear || testFilters.examDate || testFilters.shiftNo || testFilters.access !== 'ALL' || testFilters.progress !== 'ALL' || testFilters.sort !== 'RECOMMENDED');
  elements.clearCatalogueFilters.classList.toggle('hidden', !hasFilter);
  renderTestTabs();
}

function renderTestFacets() {
  if (!testFacets) return;
  setSelectOptions(input('testSubjectFilter'), testFacets.subjects, { firstLabel: 'All subjects' });
  setSelectOptions(input('testTopicFilter'), (testFacets.topics || []).filter((topic) => !testFilters.subjectId || topic.subject_id === testFilters.subjectId), { firstLabel: 'All topics' });
  setSelectOptions(input('savedSubjectFilter'), testFacets.subjects, { firstLabel: 'All subjects' });
  setSelectOptions(input('savedTopicFilter'), (testFacets.topics || []).filter((topic) => !savedFilters.subjectId || topic.subject_id === savedFilters.subjectId), { firstLabel: 'All topics' });
  setSelectOptions(input('testYearFilter'), (testFacets.years || []).map((value) => ({ id: String(value), name: String(value) })), { firstLabel: 'All years' });
  setSelectOptions(input('testDateFilter'), (testFacets.dates || []).map((value) => ({ id: value, name: formatDate(value) })), { firstLabel: 'All dates' });
  setSelectOptions(input('testShiftFilter'), (testFacets.shifts || []).map((value) => ({ id: String(value), name: `Shift ${value}` })), { firstLabel: 'All shifts' });
  syncTestControls();
}

async function loadTestFacets() {
  if (testFacets) return;
  testFacets = await api.getStudentTestFacets();
  renderTestFacets();
}

function testCardMarkup(test) {
  const isResume = test.progress_state === 'IN_PROGRESS';
  const hasHistory = Number(test.attempt_count || 0) > 0;
  const dateShift = [test.exam_date ? formatDate(test.exam_date) : '', test.shift_no ? `Shift ${test.shift_no}` : ''].filter(Boolean).join(' · ');
  const action = isResume ? 'Resume test' : hasHistory ? 'Reattempt' : 'Start test';
  return `<article class="catalogue-test-card test-card">
    <div class="test-card-topline"><span class="eyebrow">${escapeHtml(testTypeLabel(test.test_type))}</span><span class="access-badge ${String(test.access_state).toLowerCase()}">${escapeHtml(test.access_state)}</span></div>
    <div class="test-card-heading"><span class="test-type-icon"><svg class="icon"><use href="#${typeIcon(test.test_type)}"></use></svg></span><div><h3>${escapeHtml(test.test_name)}</h3><p>${escapeHtml(test.board_name || APP_CONFIG.name)} ${test.exam_name ? `· ${escapeHtml(test.exam_name)}` : ''}</p></div></div>
    <div class="test-meta">${test.subject_name ? `<span class="chip">${escapeHtml(test.subject_name)}</span>` : ''}${test.topic_name ? `<span class="chip">${escapeHtml(test.topic_name)}</span>` : ''}${dateShift ? `<span class="chip">${escapeHtml(dateShift)}</span>` : ''}<span class="chip">${test.question_count} questions</span><span class="chip">${test.duration_minutes} min</span></div>
    <div class="test-card-facts"><span><b>${formatNumber(test.marks_per_question)}</b> mark/question</span><span><b>${formatNumber(test.negative_marks)}</b> negative</span>${hasHistory ? `<span><b>${formatNumber(test.best_score)}</b> best score</span>` : ''}</div>
    ${hasHistory ? `<div class="test-performance-strip"><span>Last: <b>${formatNumber(test.last_score)}</b></span><span>${formatNumber(test.last_accuracy)}% accuracy</span><span>${test.attempt_count} attempt${Number(test.attempt_count) === 1 ? '' : 's'}</span></div>` : ''}
    <button class="button ${test.can_start ? 'button-primary' : 'button-ghost'} test-card-action" data-start-test="${escapeHtml(test.test_id)}" data-can-start="${test.can_start}" type="button"><span>${test.can_start ? action : 'Unlock test'}</span><svg class="icon"><use href="#${test.can_start ? (isResume ? 'i-play' : 'i-arrow') : 'i-lock'}"></use></svg></button>
  </article>`;
}

function renderPagination(container, { page, hasMore, onPage }) {
  if (!container) return;
  if (!page && !hasMore) { container.innerHTML = ''; return; }
  container.innerHTML = `<button class="button button-ghost" data-page-direction="previous" ${page <= 0 ? 'disabled' : ''} type="button">← Previous</button><span>Page ${page + 1}</span><button class="button button-ghost" data-page-direction="next" ${hasMore ? '' : 'disabled'} type="button">Next →</button>`;
  container.querySelector('[data-page-direction="previous"]')?.addEventListener('click', () => onPage(page - 1));
  container.querySelector('[data-page-direction="next"]')?.addEventListener('click', () => onPage(page + 1));
}

function renderTests() {
  const tests = testResult.items || [];
  elements.catalogueCount.textContent = testResult.total || 0;
  elements.catalogueResultText.textContent = `${testResult.total || 0} ${Number(testResult.total) === 1 ? 'test' : 'tests'} found`;
  elements.catalogueScopeText.textContent = testFilters.testType ? testTypeLabel(testFilters.testType) : `All student-ready ${APP_CONFIG.name} tests`;
  if (!tests.length) {
    elements.studentTestList.innerHTML = emptyState({ icon: 'i-search', title: 'No matching tests', message: 'Try another filter or clear your search.', action: '<button id="emptyClearFilters" class="button button-ghost" type="button">Clear filters</button>' });
    input('emptyClearFilters')?.addEventListener('click', clearTestFilters);
  } else {
    elements.studentTestList.innerHTML = tests.map(testCardMarkup).join('');
    elements.studentTestList.querySelectorAll('[data-start-test]').forEach((button) => button.addEventListener('click', () => {
      if (button.dataset.canStart !== 'true') return toast.info('This test requires an active package.');
      startAttempt(button.dataset.startTest);
    }));
  }
  renderPagination(elements.testPagination, { page: Number(testResult.page || 0), hasMore: Boolean(testResult.has_more), onPage: (page) => { testFilters.page = page; loadTests(); window.scrollTo({ top: 0, behavior: 'smooth' }); } });
  syncTestControls();
}

async function loadTests({ refreshFacets = false } = {}) {
  renderSkeletons(elements.studentTestList, 3);
  try {
    if (refreshFacets) testFacets = null;
    await loadTestFacets();
    testResult = await api.listStudentTests({ ...testFilters, pageSize: TEST_PAGE_SIZE });
    renderTests();
  } catch (error) {
    elements.studentTestList.innerHTML = errorState(error.message, 'retryStudentTests');
    input('retryStudentTests')?.addEventListener('click', () => loadTests());
  }
}

function clearTestFilters() {
  Object.assign(testFilters, { testType: '', search: '', subjectId: '', topicId: '', examYear: '', examDate: '', shiftNo: '', access: 'ALL', progress: 'ALL', sort: 'RECOMMENDED', page: 0 });
  syncTestControls();
  renderTestFacets();
  loadTests();
}

async function startAttempt(testId) {
  if (requiresOnboarding) {
    toast.info('Complete your student profile before starting a test.');
    navigate('profile');
    return;
  }
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

function savedOptionsMarkup(item) {
  return `<div class="saved-option-grid">${['A', 'B', 'C', 'D'].map((key) => {
    const correct = !item.answer_locked && item.correct_answer === key;
    const selectedWrong = !item.answer_locked && item.selected_answer === key && !correct;
    return `<div class="saved-option ${correct ? 'correct' : ''} ${selectedWrong ? 'wrong' : ''}"><b>${key}</b><span>${escapeHtml(item.options?.[key] || '')}</span>${correct ? '<i>Correct</i>' : selectedWrong ? '<i>Your answer</i>' : ''}</div>`;
  }).join('')}</div>`;
}

function savedCardMarkup(item) {
  const isMistake = savedFilters.kind === 'MISTAKES';
  return `<article class="saved-question-card card" data-saved-question="${escapeHtml(item.question_id)}">
    <div class="saved-question-head"><div class="test-meta"><span class="chip">${escapeHtml(item.subject_name)}</span>${item.topic_name ? `<span class="chip">${escapeHtml(item.topic_name)}</span>` : ''}<span class="chip">${escapeHtml(item.difficulty)}</span></div><span class="question-id-label">${escapeHtml(item.question_id)}</span></div>
    <h3>${escapeHtml(item.question_text)}</h3>
    ${imageMarkup(item.image_refs)}
    ${savedOptionsMarkup(item)}
    ${item.answer_locked ? `<div class="answer-lock-note"><svg class="icon"><use href="#i-lock"></use></svg><span><strong>Answer protected</strong>Submit the active attempt containing this question to unlock its answer and explanation.</span></div>` : `<div class="saved-answer-box"><strong>Answer: ${escapeHtml(item.correct_answer || '—')}</strong><p>${escapeHtml(item.explanation || 'No explanation has been added yet.')}</p></div>`}
    <div class="saved-question-footer"><span>${isMistake ? `${item.mistake_count} mistake${Number(item.mistake_count) === 1 ? '' : 's'} · ${formatDate(item.last_mistake_at)}` : `Saved ${formatDate(item.saved_at)}`}</span><div class="button-row">${isMistake ? `<button class="button button-ghost" data-toggle-mistake="${escapeHtml(item.question_id)}" data-resolved="${item.resolved}" type="button">${item.resolved ? 'Mark for revision' : 'Mark revised'}</button>` : `<button class="button button-ghost" data-remove-bookmark="${escapeHtml(item.question_id)}" type="button">Remove bookmark</button>`}</div></div>
  </article>`;
}

function renderSaved() {
  elements.savedCount.textContent = savedResult.total || 0;
  input('mistakeStatusLabel').classList.toggle('hidden', savedFilters.kind !== 'MISTAKES');
  document.querySelectorAll('[data-saved-kind]').forEach((button) => {
    const active = button.dataset.savedKind === savedFilters.kind;
    button.classList.toggle('active', active);
    button.setAttribute('aria-selected', String(active));
  });
  const items = savedResult.items || [];
  elements.savedList.innerHTML = items.length ? items.map(savedCardMarkup).join('') : emptyState({ icon: savedFilters.kind === 'BOOKMARKS' ? 'i-bookmark' : 'i-flag', title: savedFilters.kind === 'BOOKMARKS' ? 'No bookmarks yet' : 'No mistake records here', message: savedFilters.kind === 'BOOKMARKS' ? 'Use Save question inside a test or result review.' : 'Wrong submitted answers appear automatically in your Mistake Book.' });
  elements.savedList.querySelectorAll('[data-remove-bookmark]').forEach((button) => button.addEventListener('click', async () => {
    button.disabled = true;
    try { await api.setStudentBookmark({ questionId: button.dataset.removeBookmark, saved: false }); toast.success('Bookmark removed.'); await Promise.all([loadSaved(), loadHome({ refresh: true })]); }
    catch (error) { button.disabled = false; toast.error(error.message); }
  }));
  elements.savedList.querySelectorAll('[data-toggle-mistake]').forEach((button) => button.addEventListener('click', async () => {
    button.disabled = true;
    try { await api.setMistakeResolved(button.dataset.toggleMistake, button.dataset.resolved !== 'true'); toast.success(button.dataset.resolved === 'true' ? 'Added back to revision.' : 'Mistake marked as revised.'); await Promise.all([loadSaved(), loadHome({ refresh: true })]); }
    catch (error) { button.disabled = false; toast.error(error.message); }
  }));
  const revision = savedResult.revision_test;
  elements.revisionTestAction.innerHTML = revision ? `<button class="button ${revision.can_start ? 'button-primary' : 'button-ghost'}" data-revision-test="${escapeHtml(revision.test_id)}" data-can-start="${revision.can_start}" type="button"><svg class="icon"><use href="#i-play"></use></svg><span>${revision.can_start ? `Start ${escapeHtml(revision.test_name)}` : 'Revision test requires access'}</span></button>` : '';
  elements.revisionTestAction.querySelector('[data-revision-test]')?.addEventListener('click', (event) => event.currentTarget.dataset.canStart === 'true' ? startAttempt(event.currentTarget.dataset.revisionTest) : toast.info('This revision test requires an active package.'));
  renderPagination(elements.savedPagination, { page: Math.floor(savedFilters.offset / SAVED_PAGE_SIZE), hasMore: Boolean(savedResult.has_more), onPage: (page) => { savedFilters.offset = Math.max(0, page) * SAVED_PAGE_SIZE; loadSaved(); } });
}

async function loadSaved() {
  renderSkeletons(elements.savedList, 2);
  try {
    await loadTestFacets();
    savedResult = await api.listStudentSaved({ ...savedFilters, limit: SAVED_PAGE_SIZE });
    renderSaved();
  } catch (error) {
    elements.savedList.innerHTML = errorState(error.message, 'retrySaved');
    input('retrySaved')?.addEventListener('click', loadSaved);
  }
}

function resultCardMarkup(item) {
  return `<article class="result-history-card card"><div class="result-history-main"><span class="result-history-icon"><svg class="icon"><use href="#i-chart"></use></svg></span><div><span class="eyebrow">${escapeHtml(testTypeLabel(item.test_type))}</span><h3>${escapeHtml(item.test_name)}</h3><p>${formatDate(item.submitted_at, { includeTime: true })} · ${formatDuration(item.time_taken_seconds)}</p></div></div><div class="result-history-kpis"><span><b>${formatNumber(item.score)}</b><small>of ${formatNumber(item.max_score)}</small></span><span><b>${formatNumber(item.accuracy)}%</b><small>accuracy</small></span><span class="correct"><b>${item.correct}</b><small>correct</small></span><span class="wrong"><b>${item.wrong}</b><small>wrong</small></span></div><button class="button button-primary" data-open-result="${escapeHtml(item.attempt_id)}" type="button">View analysis <svg class="icon"><use href="#i-arrow"></use></svg></button></article>`;
}

function renderResults() {
  elements.resultCount.textContent = resultData.total || 0;
  const rows = resultData.items || [];
  elements.resultList.innerHTML = rows.length ? rows.map(resultCardMarkup).join('') : emptyState({ icon: 'i-chart', title: 'No results yet', message: 'Complete a test to see score history and detailed analytics.' });
  elements.resultList.querySelectorAll('[data-open-result]').forEach((button) => button.addEventListener('click', () => navigate('result', { id: button.dataset.openResult })));
  renderPagination(elements.resultPagination, { page: Number(resultData.page || 0), hasMore: Boolean(resultData.has_more), onPage: (page) => { resultFilters.page = page; loadResults(); } });
}

async function loadResults() {
  elements.resultsListView.classList.remove('hidden');
  elements.resultDetailView.classList.add('hidden');
  renderSkeletons(elements.resultList, 3);
  try {
    resultData = await api.listStudentResults({ ...resultFilters, pageSize: RESULT_PAGE_SIZE });
    renderResults();
  } catch (error) {
    elements.resultList.innerHTML = errorState(error.message, 'retryResults');
    input('retryResults')?.addEventListener('click', loadResults);
  }
}

function performanceBars(rows, labelKey = 'subject_name') {
  if (!(rows || []).length) return '<p class="muted">Not enough data.</p>';
  return `<div class="performance-bar-list">${rows.map((row) => `<div class="performance-bar-row"><div><strong>${escapeHtml(row[labelKey] || row.difficulty || 'Unclassified')}</strong><span>${row.correct}/${row.total} correct</span></div><div class="performance-track"><i style="width:${Math.max(0, Math.min(100, Number(row.accuracy || 0)))}%"></i></div><b>${formatNumber(row.accuracy)}%</b></div>`).join('')}</div>`;
}

function reviewMatches(item) {
  if (currentReview.filter === 'CORRECT') return item.is_correct === true;
  if (currentReview.filter === 'WRONG') return item.selected_answer && item.is_correct === false;
  if (currentReview.filter === 'SKIPPED') return !item.selected_answer;
  if (currentReview.filter === 'MARKED') return item.marked_review;
  return true;
}

function reviewQuestionMarkup(item) {
  return `<article class="review-question-card card"><div class="saved-question-head"><div class="test-meta"><span class="chip">Q${item.position}</span><span class="chip">${escapeHtml(item.subject_name)}</span>${item.topic_name ? `<span class="chip">${escapeHtml(item.topic_name)}</span>` : ''}</div><span class="review-status ${item.is_correct ? 'correct' : item.selected_answer ? 'wrong' : 'skipped'}">${item.is_correct ? 'Correct' : item.selected_answer ? 'Wrong' : 'Skipped'}</span></div><h3>${escapeHtml(item.question_text)}</h3>${imageMarkup(item.image_refs)}${savedOptionsMarkup(item)}<div class="saved-answer-box"><strong>Correct answer: ${escapeHtml(item.correct_answer)}</strong><p>${escapeHtml(item.explanation || 'No explanation has been added yet.')}</p></div><div class="review-question-footer"><span>${formatDuration(item.time_taken_seconds)}${item.marked_review ? ' · Marked for review' : ''}</span><button class="button ${item.bookmarked ? 'button-primary' : 'button-ghost'}" data-review-bookmark="${escapeHtml(item.question_id)}" data-saved="${item.bookmarked}" type="button"><svg class="icon"><use href="#i-bookmark"></use></svg><span>${item.bookmarked ? 'Saved' : 'Save question'}</span></button></div></article>`;
}

function renderReviewQuestions(attemptId) {
  const list = elements.resultDetailView.querySelector('#resultReviewList');
  if (!list) return;
  const filtered = currentReview.items.filter(reviewMatches);
  list.innerHTML = filtered.length ? filtered.map(reviewQuestionMarkup).join('') : emptyState({ icon: 'i-search', title: 'No questions in this filter', message: 'Choose another review filter.' });
  list.querySelectorAll('[data-review-bookmark]').forEach((button) => button.addEventListener('click', async () => {
    button.disabled = true;
    const saved = button.dataset.saved !== 'true';
    try {
      await api.setStudentBookmark({ questionId: button.dataset.reviewBookmark, attemptId, saved });
      const item = currentReview.items.find((row) => row.question_id === button.dataset.reviewBookmark);
      if (item) item.bookmarked = saved;
      toast.success(saved ? 'Question saved for revision.' : 'Bookmark removed.');
      renderReviewQuestions(attemptId);
      loadHome({ refresh: true });
    } catch (error) { button.disabled = false; toast.error(error.message); }
  }));
}

function renderResultDetail(attemptId) {
  const detail = currentReview.detail || {};
  const summary = detail.summary || {};
  const recommendation = detail.recommendation;
  elements.resultsListView.classList.add('hidden');
  elements.resultDetailView.classList.remove('hidden');
  elements.resultDetailView.innerHTML = `<div class="result-detail-header"><button id="backToResults" class="button button-ghost" type="button">← Results</button><div><span class="eyebrow">Detailed result</span><h1>${escapeHtml(summary.test_name || 'Result')}</h1><p>${formatDate(summary.submitted_at, { includeTime: true })}</p></div></div>
    <div class="result-detail-hero card"><div><span class="eyebrow light">Server-calculated score</span><strong>${formatNumber(summary.score)} <small>/ ${formatNumber(summary.max_score)}</small></strong><p>${formatNumber(summary.accuracy)}% accuracy · ${formatDuration(summary.time_taken_seconds)}</p></div><div class="result-detail-actions"><button class="button button-primary" data-reattempt-test="${escapeHtml(summary.test_id)}" type="button">Reattempt</button></div></div>
    <div class="result-detail-kpis"><article><strong>${summary.correct || 0}</strong><span>Correct</span></article><article><strong>${summary.wrong || 0}</strong><span>Wrong</span></article><article><strong>${summary.skipped || 0}</strong><span>Skipped</span></article><article><strong>−${formatNumber(summary.negative_mark_loss)}</strong><span>Negative loss</span></article></div>
    ${recommendation ? `<div class="recommendation-card card"><span class="hub-insight-icon warning"><svg class="icon"><use href="#i-target"></use></svg></span><div><small>Recommended next action</small><h3>${escapeHtml(recommendation.subject_name)}</h3><p>${escapeHtml(recommendation.message)}</p></div></div>` : ''}
    <div class="analytics-grid"><article class="card"><span class="eyebrow">Subject performance</span><h2>Accuracy by subject</h2>${performanceBars(detail.subject_performance, 'subject_name')}</article><article class="card"><span class="eyebrow">Difficulty</span><h2>Question-level performance</h2>${performanceBars(detail.difficulty_performance, 'difficulty')}</article></div>
    <article class="card timing-card"><span class="eyebrow">Timing analysis</span><div class="timing-grid"><span><b>${formatDuration(detail.timing?.total_seconds)}</b><small>Total time</small></span><span><b>${formatNumber(detail.timing?.average_seconds_per_question)}s</b><small>Average/question</small></span><span><b>${formatNumber(detail.timing?.fastest_answer_seconds)}s</b><small>Fastest answer</small></span><span><b>${formatNumber(detail.timing?.slowest_answer_seconds)}s</b><small>Slowest answer</small></span><span><b>${detail.repeated_mistakes || 0}</b><small>Repeated mistakes</small></span></div></article>
    <div class="section-heading compact"><div><span class="eyebrow">Answer review</span><h2>Question-by-question</h2></div></div>
    <div id="reviewFilters" class="scroll-tabs review-filter-tabs">${['ALL', 'CORRECT', 'WRONG', 'SKIPPED', 'MARKED'].map((filter) => `<button class="catalogue-tab ${currentReview.filter === filter ? 'active' : ''}" data-review-filter="${filter}" type="button">${filter[0]}${filter.slice(1).toLowerCase()}</button>`).join('')}</div>
    <div id="resultReviewList" class="result-review-list"></div>`;
  input('backToResults')?.addEventListener('click', () => navigate('results'));
  elements.resultDetailView.querySelector('[data-reattempt-test]')?.addEventListener('click', (event) => startAttempt(event.currentTarget.dataset.reattemptTest));
  elements.resultDetailView.querySelectorAll('[data-review-filter]').forEach((button) => button.addEventListener('click', () => { currentReview.filter = button.dataset.reviewFilter; renderResultDetail(attemptId); }));
  renderReviewQuestions(attemptId);
}

async function loadResultDetail(attemptId) {
  elements.resultsListView.classList.add('hidden');
  elements.resultDetailView.classList.remove('hidden');
  elements.resultDetailView.innerHTML = '<div class="loading-state"><span class="spinner"></span>Loading secure result analysis…</div>';
  try {
    const [detail, items] = await Promise.all([
      api.getStudentResultDetail(attemptId),
      api.getAttemptReview(attemptId, 0, 100),
    ]);
    currentReview = { detail, items, filter: 'ALL' };
    renderResultDetail(attemptId);
  } catch (error) {
    elements.resultDetailView.innerHTML = errorState(error.message, 'retryResultDetail');
    input('retryResultDetail')?.addEventListener('click', () => loadResultDetail(attemptId));
  }
}

function renderProfile(data) {
  const profile = data.profile || {};
  const stats = data.stats || {};
  const boards = data.boards || [];
  const exams = data.exams || [];
  requiresOnboarding = !profile.mobile;
  const language = profile.language || 'GUJARATI';
  const languageOptions = [...new Set(['GUJARATI', 'ENGLISH', language])];
  const identityProviders = Array.isArray(currentUser?.app_metadata?.providers)
    ? currentUser.app_metadata.providers
    : [currentUser?.app_metadata?.provider].filter(Boolean);
  const hasPasswordIdentity = identityProviders.includes('email');
  const onboardingNotice = requiresOnboarding ? `<div class="notice notice-warning onboarding-notice" role="status"><strong>Finish student setup</strong><span>Google sign in is connected. Add your mobile number and learning preferences before using tests or saved progress.</span></div>` : '';
  const mobileField = requiresOnboarding
    ? '<label><span>Mobile number (+91)</span><input id="profileMobile" type="tel" inputmode="numeric" autocomplete="tel-national" pattern="[6-9][0-9]{9}" minlength="10" maxlength="10" placeholder="10-digit mobile number" required /></label>'
    : '';
  const passwordCard = hasPasswordIdentity ? `<form id="passwordForm" class="profile-form card" autocomplete="off"><div class="section-heading compact"><div><span class="eyebrow">Account security</span><h2>Change password</h2><p>Use a unique password that you do not reuse on other sites.</p></div><svg class="icon"><use href="#i-lock"></use></svg></div>
      <div class="form-grid"><label><span>Current password</span><input id="currentPassword" type="password" autocomplete="current-password" required /></label><label><span>New password</span><input id="newPassword" type="password" autocomplete="new-password" minlength="8" required /></label><label><span>Confirm new password</span><input id="confirmPassword" type="password" autocomplete="new-password" minlength="8" required /></label></div>
      <div class="protected-fields"><p><svg class="icon"><use href="#i-lock"></use></svg>${PASSWORD_POLICY_MESSAGE}</p></div>
      <div class="button-row"><button class="button button-primary" type="submit">Change password</button></div>
    </form>` : `<article class="profile-form card"><div class="section-heading compact"><div><span class="eyebrow">Account security</span><h2>Google sign in</h2><p>Your Google account is your current sign-in method.</p></div><svg class="icon"><use href="#i-lock"></use></svg></div><div class="protected-fields"><p>To add an email-password fallback, sign out and use <strong>Forgot password</strong> with this verified email.</p></div></article>`;
  elements.profileContent.innerHTML = `<article class="profile-card card"><div class="profile-avatar">${escapeHtml((profile.full_name || 'S').trim().charAt(0).toUpperCase())}</div><div><span class="eyebrow">Student account</span><h2>${escapeHtml(profile.full_name || 'Student')}</h2><p>${escapeHtml(profile.target_exam_name || 'Choose your target exam')}</p><span class="profile-status">${escapeHtml(profile.status || 'ACTIVE')}</span></div></article>
    <div class="profile-stat-grid"><article><strong>${stats.completed_attempts || 0}</strong><span>Completed</span></article><article><strong>${formatNumber(stats.average_accuracy)}%</strong><span>Accuracy</span></article><article><strong>${stats.bookmarks || 0}</strong><span>Bookmarks</span></article><article><strong>${stats.open_mistakes || 0}</strong><span>Open mistakes</span></article></div>
    ${onboardingNotice}
    <form id="profileForm" class="profile-form card"><div class="section-heading compact"><div><span class="eyebrow">Learning preferences</span><h2>${requiresOnboarding ? 'Complete profile' : 'Edit profile'}</h2></div><svg class="icon"><use href="#i-edit"></use></svg></div>
      <div class="form-grid"><label><span>Full name</span><input id="profileFullName" name="full_name" value="${escapeHtml(profile.full_name || '')}" minlength="2" maxlength="100" required /></label>${mobileField}<label><span>Preferred language</span><select id="profileLanguage" name="language">${languageOptions.map((value) => `<option value="${escapeHtml(value)}" ${value === language ? 'selected' : ''}>${escapeHtml(value[0] + value.slice(1).toLowerCase())}</option>`).join('')}</select></label><label><span>Target board</span><select id="profileBoard" name="target_board_id" ${requiresOnboarding ? 'required' : ''}><option value="">Choose board</option>${boards.map((board) => `<option value="${escapeHtml(board.board_id)}" ${board.board_id === profile.target_board_id ? 'selected' : ''}>${escapeHtml(board.board_name)}</option>`).join('')}</select></label><label><span>Target exam</span><select id="profileExam" name="target_exam_id" ${requiresOnboarding ? 'required' : ''}></select></label></div>
      <div class="protected-fields"><label><span>Verified email</span><input value="${escapeHtml(profile.email || '')}" readonly /></label>${requiresOnboarding ? '' : `<label><span>Registered mobile</span><input value="${escapeHtml(profile.mobile || '')}" readonly /></label>`}<p><svg class="icon"><use href="#i-lock"></use></svg>Email, role and account authorization cannot be changed here.${requiresOnboarding ? ' Your mobile becomes read-only after setup.' : ''}</p></div>
      <div class="button-row"><button class="button button-primary" type="submit">${requiresOnboarding ? 'Finish setup' : 'Save profile'}</button><button id="profileSignOut" class="button button-ghost" type="button">Sign out</button></div>
    </form>
    ${passwordCard}`;
  const boardSelect = input('profileBoard');
  const examSelect = input('profileExam');
  const syncExamOptions = () => {
    const boardId = boardSelect.value;
    examSelect.innerHTML = `<option value="">Choose exam</option>${exams.filter((exam) => !boardId || exam.board_id === boardId).map((exam) => `<option value="${escapeHtml(exam.exam_id)}" ${exam.exam_id === profile.target_exam_id ? 'selected' : ''}>${escapeHtml(exam.exam_name)}</option>`).join('')}`;
  };
  syncExamOptions();
  boardSelect.addEventListener('change', () => { profile.target_exam_id = ''; syncExamOptions(); });
  input('profileForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!event.currentTarget.reportValidity()) return;
    const submit = event.currentTarget.querySelector('[type="submit"]');
    submit.disabled = true;
    try {
      const payload = { fullName: input('profileFullName').value, language: input('profileLanguage').value, targetBoardId: boardSelect.value, targetExamId: examSelect.value };
      const updated = requiresOnboarding
        ? await api.completeStudentOnboarding({ ...payload, mobile: input('profileMobile').value })
        : await api.updateStudentProfile(payload);
      requiresOnboarding = !updated?.profile?.mobile;
      toast.success(requiresOnboarding ? 'Profile updated.' : 'Student profile saved.');
      renderProfile(updated);
      await loadHome({ refresh: true });
    } catch (error) { submit.disabled = false; toast.error(error.message); }
  });
  input('passwordForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const submit = event.currentTarget.querySelector('[type="submit"]');
    const currentPassword = input('currentPassword').value;
    const newPassword = input('newPassword').value;
    const confirmPassword = input('confirmPassword').value;

    try {
      assertPasswordPolicy(newPassword);
      if (newPassword !== confirmPassword) throw new Error('New password and confirmation do not match.');
      if (newPassword === currentPassword) throw new Error('Choose a new password different from your current password.');
    } catch (error) {
      toast.error(error.message);
      return;
    }

    submit.disabled = true;
    try {
      await api.changePassword({ currentPassword, newPassword });
      toast.success('Password changed. Please sign in again with your new password.');
      try { await api.signOut(); } catch { /* Password is already changed; continue to signed-out landing. */ }
      redirectToLanding('');
    } catch (error) {
      submit.disabled = false;
      toast.error(error.message);
    }
  });
  input('profileSignOut').addEventListener('click', signOut);
}

async function loadProfile() {
  elements.profileContent.innerHTML = '<div class="loading-state"><span class="spinner"></span>Loading protected profile…</div>';
  try { renderProfile(await api.getStudentProfile()); }
  catch (error) { elements.profileContent.innerHTML = errorState(error.message, 'retryProfile'); input('retryProfile')?.addEventListener('click', loadProfile); }
}

async function signOut() {
  try { await api.signOut(); toast.success('Signed out.'); redirectToLanding(''); }
  catch (error) { toast.error(error.message); }
}

function setVisibleSection(routePath) {
  const attempt = routePath === 'attempt';
  const normalized = routePath === 'result' ? 'results' : routePath;
  document.body.classList.toggle('attempt-mode', attempt);
  elements.mobileNav.classList.toggle('attempt-hidden', attempt);
  elements.attemptSection.classList.toggle('hidden', !attempt);
  const sectionMap = { home: elements.dashboardHome, tests: elements.catalogueSection, saved: elements.savedSection, results: elements.resultsSection, profile: elements.profileSection };
  Object.entries(sectionMap).forEach(([key, section]) => section.classList.toggle('hidden', attempt || normalized !== key));
}

async function handleRoute(route) {
  const sequence = ++routeSequence;
  const navPath = route.path === 'result' ? 'results' : route.path;
  document.querySelectorAll('#mobileNav [data-route]').forEach((button) => button.classList.toggle('active', button.dataset.route === `#${navPath}`));
  if (!currentUser) return;
  if (requiresOnboarding && route.path !== 'profile') {
    if (!onboardingNoticeShown) {
      onboardingNoticeShown = true;
      toast.info('Complete your student setup to continue.');
    }
    navigate('profile');
    return;
  }

  if (route.path !== 'attempt' && unmountTestEngine) {
    unmountTestEngine();
    unmountTestEngine = null;
    elements.testEngineRoot.innerHTML = '';
  }
  if (['bookmarks', 'mistakes'].includes(route.path)) return navigate('saved', { tab: route.path === 'mistakes' ? 'mistakes' : 'bookmarks' });
  if (!['home', 'tests', 'saved', 'results', 'result', 'profile', 'attempt'].includes(route.path)) return navigate('home');
  setVisibleSection(route.path);

  if (route.path === 'attempt') {
    const attemptId = route.params.get('id');
    if (!attemptId) return navigate('tests');
    try {
      unmountTestEngine = await mountTestEngine(elements.testEngineRoot, attemptId, {
        onExit: async () => { unmountTestEngine = null; elements.testEngineRoot.innerHTML = ''; await Promise.all([loadHome({ refresh: true }), loadTests()]); navigate('tests'); },
        onViewResult: async (id) => { unmountTestEngine = null; elements.testEngineRoot.innerHTML = ''; await loadHome({ refresh: true }); navigate('result', { id }); },
      });
    } catch (error) { toast.error(error.message); navigate('tests'); }
    return;
  }

  if (route.path === 'home') await loadHome();
  if (route.path === 'tests') await loadTests();
  if (route.path === 'saved') {
    const requested = String(route.params.get('tab') || '').toUpperCase();
    if (requested === 'MISTAKES' || requested === 'BOOKMARKS') savedFilters.kind = requested;
    savedFilters.offset = 0;
    await loadSaved();
  }
  if (route.path === 'results') await loadResults();
  if (route.path === 'result') {
    const attemptId = route.params.get('id');
    if (!attemptId) return navigate('results');
    await loadResultDetail(attemptId);
  }
  if (route.path === 'profile') await loadProfile();
  if (sequence === routeSequence) window.scrollTo({ top: 0, behavior: 'smooth' });
}

function bindUi() {
  document.querySelectorAll('[data-route]').forEach((button) => button.addEventListener('click', () => { window.location.hash = button.dataset.route; }));
  document.querySelectorAll('[data-test-filter]').forEach((button) => button.addEventListener('click', () => { testFilters.testType = button.dataset.testFilter; testFilters.page = 0; navigate('tests'); }));
  document.querySelectorAll('[data-saved-kind]').forEach((button) => button.addEventListener('click', () => {
    const nextKind = button.dataset.savedKind;
    if (savedFilters.kind === nextKind && window.location.hash.includes(`tab=${nextKind.toLowerCase()}`)) return;
    savedFilters.kind = nextKind;
    savedFilters.offset = 0;
    navigate('saved', { tab: savedFilters.kind.toLowerCase() });
  }));

  const testControlMap = {
    testSubjectFilter: 'subjectId', testTopicFilter: 'topicId', testYearFilter: 'examYear',
    testDateFilter: 'examDate', testShiftFilter: 'shiftNo', testAccessFilter: 'access',
    testProgressFilter: 'progress', testSort: 'sort',
  };
  Object.entries(testControlMap).forEach(([id, key]) => input(id)?.addEventListener('change', () => {
    testFilters[key] = input(id).value;
    if (id === 'testSubjectFilter') { testFilters.topicId = ''; renderTestFacets(); }
    testFilters.page = 0;
    loadTests();
  }));
  input('testSearch')?.addEventListener('input', () => { testFilters.search = input('testSearch').value.trim(); testFilters.page = 0; debounce(loadTests); });
  input('clearCatalogueFilters')?.addEventListener('click', clearTestFilters);
  input('refreshStudentTests')?.addEventListener('click', () => loadTests({ refreshFacets: true }));

  input('savedSearch')?.addEventListener('input', () => { savedFilters.search = input('savedSearch').value.trim(); savedFilters.offset = 0; debounce(loadSaved); });
  input('savedSubjectFilter')?.addEventListener('change', () => { savedFilters.subjectId = input('savedSubjectFilter').value; savedFilters.topicId = ''; savedFilters.offset = 0; renderTestFacets(); loadSaved(); });
  input('savedTopicFilter')?.addEventListener('change', () => { savedFilters.topicId = input('savedTopicFilter').value; savedFilters.offset = 0; loadSaved(); });
  input('mistakeStatusFilter')?.addEventListener('change', () => { savedFilters.status = input('mistakeStatusFilter').value; savedFilters.offset = 0; loadSaved(); });

  input('resultSearch')?.addEventListener('input', () => { resultFilters.search = input('resultSearch').value.trim(); resultFilters.page = 0; debounce(loadResults); });
  input('resultSort')?.addEventListener('change', () => { resultFilters.sort = input('resultSort').value; resultFilters.page = 0; loadResults(); });
  bindConnectionBadge(input('syncState'), {
    onChange({ state, previousState }) {
      const badge = input('syncState');
      if (badge) {
        badge.title = state === 'online'
          ? 'Connection verified.'
          : 'Answers in an open test remain on this device until they can synchronize.';
      }
      if (state === 'offline') {
        toast.warning('You are offline. Continue answering—responses are saved on this device.');
      } else if (state === 'online' && ['offline', 'issue'].includes(previousState)) {
        toast.info('Back online. Saved answers will synchronize automatically.');
      } else if (state === 'issue' && previousState === 'online') {
        toast.warning('The connection is unstable. Open-test answers will stay on this device until synchronization succeeds.');
      }
    },
  });
}

async function initialize() {
  bindUi();
  subscribeRoute(handleRoute);
  if (!isConfigured) {
    elements.setupNotice.classList.remove('hidden');
    elements.studentLoading.textContent = `${APP_CONFIG.name} is not configured.`;
    return;
  }
  try {
    currentUser = await api.getUser();
    if (!currentUser) return redirectToLanding('signin');
    const [, home, facets, profileData] = await Promise.all([loadBrand(), api.getStudentHome(), api.getStudentTestFacets(), api.getStudentProfile()]);
    homeData = home;
    testFacets = facets;
    requiresOnboarding = !profileData?.profile?.mobile;
    elements.studentLoading.classList.add('hidden');
    elements.studentView.classList.remove('hidden');
    elements.mobileNav.classList.remove('hidden');
    renderHome();
    renderTestFacets();
    api.onAuthStateChange((event) => { if (event === 'SIGNED_OUT') redirectToLanding('signin'); });
    startRouter();
    const pendingTestId = sessionStorage.getItem(PENDING_TEST_KEY);
    if (pendingTestId && !requiresOnboarding) { sessionStorage.removeItem(PENDING_TEST_KEY); await startAttempt(pendingTestId); }
  } catch (error) {
    toast.error(error.message);
    redirectToLanding('signin');
  }
}

initialize();
