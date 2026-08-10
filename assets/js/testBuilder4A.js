import { APP_CONFIG, isConfigured } from './config.js';
import { api } from './api.js';
import { toast } from './toast.js';

const PAGE_SIZE = 40;
const SINGLE_PACKAGE_MODES = new Set(['PYQ_ORIGINAL', 'PYQ_COMPLETED']);
const FILTER_KEYS = [
  'package_ids', 'subject_ids', 'topic_ids', 'board_ids', 'exam_ids',
  'exam_years', 'shift_nos', 'section_codes', 'languages', 'difficulties',
  'question_types', 'membership_types',
];
const FACET_MAP = {
  package_ids: 'packages',
  subject_ids: 'subjects',
  topic_ids: 'topics',
  board_ids: 'boards',
  exam_ids: 'exams',
  exam_years: 'exam_years',
  shift_nos: 'shift_nos',
  section_codes: 'section_codes',
  languages: 'languages',
  difficulties: 'difficulties',
  question_types: 'question_types',
  membership_types: 'membership_types',
};
const FILTER_LABELS = {
  package_ids: 'Package',
  subject_ids: 'Subject',
  topic_ids: 'Topic',
  board_ids: 'Board',
  exam_ids: 'Exam',
  exam_years: 'Year',
  shift_nos: 'Shift',
  section_codes: 'Section',
  languages: 'Language',
  difficulties: 'Difficulty',
  question_types: 'Question type',
  membership_types: 'Membership',
};

const elements = {
  setupNotice: document.getElementById('phase4aSetupNotice'),
  loginPanel: document.getElementById('phase4aLoginPanel'),
  loginForm: document.getElementById('phase4aLoginForm'),
  builderPanel: document.getElementById('phase4aBuilderPanel'),
  signOut: document.getElementById('phase4aSignOut'),
  refresh: document.getElementById('phase4aRefresh'),
  modePicker: document.getElementById('phase4aModePicker'),
  modeNote: document.getElementById('phase4aModeNote'),
  clearFilters: document.getElementById('phase4aClearFilters'),
  includeSupplements: document.getElementById('phase4aIncludeSupplements'),
  includeSuperseded: document.getElementById('phase4aIncludeSuperseded'),
  includeUnassigned: document.getElementById('phase4aIncludeUnassigned'),
  filterChips: document.getElementById('phase4aFilterChips'),
  facetSummary: document.getElementById('phase4aFacetSummary'),
  search: document.getElementById('phase4aSearch'),
  order: document.getElementById('phase4aOrder'),
  loadQuestions: document.getElementById('phase4aLoadQuestions'),
  questionMeta: document.getElementById('phase4aQuestionMeta'),
  questionList: document.getElementById('phase4aQuestionList'),
  loadMore: document.getElementById('phase4aLoadMore'),
  selectVisible: document.getElementById('phase4aSelectVisible'),
  selectAllFiltered: document.getElementById('phase4aSelectAllFiltered'),
  clearSelection: document.getElementById('phase4aClearSelection'),
  selectedBar: document.getElementById('phase4aSelectedBar'),
  testForm: document.getElementById('phase4aTestForm'),
  customTypeField: document.getElementById('phase4aCustomTypeField'),
  previewButton: document.getElementById('phase4aPreviewButton'),
  previewState: document.getElementById('phase4aPreviewState'),
  previewPanel: document.getElementById('phase4aPreviewPanel'),
  confirmDialog: document.getElementById('phase4aConfirmDialog'),
  confirmContent: document.getElementById('phase4aConfirmContent'),
};

const state = {
  profile: null,
  mode: 'CUSTOM',
  filters: Object.fromEntries(FILTER_KEYS.map((key) => [key, []])),
  facets: {},
  summary: {},
  questions: [],
  visibleQuestionIds: [],
  total: 0,
  offset: 0,
  hasMore: false,
  selectedIds: new Set(),
  selectedOrder: [],
  preview: null,
  previewSignature: '',
  facetRequestId: 0,
  questionRequestId: 0,
};

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function normalizeValue(value) {
  return String(value ?? '').trim().toUpperCase();
}

function selectedValues(key) {
  return state.filters[key] || [];
}

function setSelectedValues(key, values) {
  state.filters[key] = [...new Set((values || []).map(normalizeValue).filter(Boolean))];
}

function currentFilters() {
  return {
    ...Object.fromEntries(FILTER_KEYS.map((key) => [key, [...selectedValues(key)]])),
    include_supplemental: Boolean(elements.includeSupplements?.checked),
    include_superseded: Boolean(elements.includeSuperseded?.checked),
    include_unassigned: Boolean(elements.includeUnassigned?.checked),
  };
}

function currentOrder() {
  const order = elements.order?.value || 'PACKAGE_ORIGINAL';
  if (state.mode !== 'CUSTOM' && order === 'SELECTED') return 'PACKAGE_ORIGINAL';
  return order;
}

function currentBrowseOrder() {
  const order = currentOrder();
  return order === 'SELECTED' ? 'PACKAGE_ORIGINAL' : order;
}

function currentSearch() {
  return elements.search?.value.trim() || '';
}

function selectedQuestionArray() {
  return state.selectedOrder.filter((questionId) => state.selectedIds.has(questionId));
}

function modeText(mode) {
  return ({
    CUSTOM: 'Custom mode saves only your manually selected unique master questions. Package filters are optional.',
    PYQ_ORIGINAL: 'Original full PYQ requires exactly one active import Package ID and excludes every supplemental NORMAL question.',
    PYQ_COMPLETED: 'Completed PYQ practice requires exactly one active package and includes its genuine source questions plus clearly labelled supplements.',
    PYQ_SECTIONAL: 'Sectional mode accepts multiple Package IDs and multiple subjects/topics. Repeated master questions are linked once.',
  })[mode] || '';
}

function showLogin() {
  state.profile = null;
  elements.loginPanel?.classList.remove('hidden');
  elements.builderPanel?.classList.add('hidden');
  elements.signOut?.classList.add('hidden');
}

async function showBuilder() {
  const user = await api.getUser();
  if (!user) {
    showLogin();
    return;
  }

  const profile = await api.getProfile();
  if (profile?.role !== 'ADMIN') {
    await api.signOut();
    showLogin();
    throw new Error(`This account is not authorized as a ${APP_CONFIG.name} admin.`);
  }

  state.profile = profile;
  elements.loginPanel?.classList.add('hidden');
  elements.builderPanel?.classList.remove('hidden');
  elements.signOut?.classList.remove('hidden');
  updateModeUI();
  await refreshFacets();
  await loadQuestions({ reset: true });
}

function setBusy(element, busy, busyText = '') {
  if (!element) return;
  if (busy) {
    element.dataset.originalText = element.textContent;
    element.disabled = true;
    if (busyText) element.textContent = busyText;
  } else {
    element.disabled = false;
    if (element.dataset.originalText) element.textContent = element.dataset.originalText;
    delete element.dataset.originalText;
  }
}

function invalidatePreview(message = 'Preview is required before publication.') {
  state.preview = null;
  state.previewSignature = '';
  elements.previewPanel?.classList.add('hidden');
  if (elements.previewPanel) elements.previewPanel.innerHTML = '';
  if (elements.previewState) elements.previewState.textContent = message;
}

function buildPayload() {
  const data = new FormData(elements.testForm);
  return {
    testId: normalizeValue(data.get('testId')),
    testName: String(data.get('testName') || '').trim(),
    builderMode: state.mode,
    filters: currentFilters(),
    questionIds: selectedQuestionArray(),
    order: currentOrder(),
    customTestType: state.mode === 'CUSTOM' ? normalizeValue(data.get('customTestType')) : null,
    durationMinutes: Number(data.get('durationMinutes') || 0),
    marksPerQuestion: Number(data.get('marksPerQuestion') || 1),
    negativeMarks: Number(data.get('negativeMarks') || 0),
    sortOrder: Number(data.get('sortOrder') || 0),
  };
}

function previewSignature(payload) {
  return JSON.stringify({
    builderMode: payload.builderMode,
    filters: payload.filters,
    questionIds: payload.questionIds,
    order: payload.order,
    customTestType: payload.customTestType,
  });
}

function validateModeBeforeRequest() {
  const packages = selectedValues('package_ids');
  const subjects = selectedValues('subject_ids');
  if (SINGLE_PACKAGE_MODES.has(state.mode) && packages.length !== 1) {
    throw new Error('Select exactly one active import Package ID for this full-paper mode.');
  }
  if (state.mode === 'PYQ_SECTIONAL' && packages.length === 0) {
    throw new Error('Select at least one import Package ID for a sectional test.');
  }
  if (state.mode === 'PYQ_SECTIONAL' && subjects.length === 0) {
    throw new Error('Select at least one subject for a sectional test.');
  }
  if (state.mode === 'CUSTOM' && state.selectedIds.size === 0) {
    throw new Error('Select at least one question for a custom test.');
  }
}

function maybeSuggestIdentity() {
  const testId = elements.testForm?.elements?.testId;
  const testName = elements.testForm?.elements?.testName;
  if (!testId || !testName || testId.value.trim() || testName.value.trim()) return;
  const packages = selectedValues('package_ids');
  const packageId = packages[0] || '';
  if (!packageId) return;
  const suffix = ({
    PYQ_ORIGINAL: 'ORIGINAL-FULL-TEST',
    PYQ_COMPLETED: 'COMPLETED-PRACTICE-TEST',
    PYQ_SECTIONAL: 'SECTIONAL-TEST',
    CUSTOM: 'CUSTOM-TEST',
  })[state.mode] || 'TEST';
  testId.value = `${packageId}-${suffix}`.replace(/[^A-Z0-9-]/g, '-').replace(/-+/g, '-');
  const packageOption = (state.facets.packages || []).find((item) => normalizeValue(item.value) === packageId);
  const label = packageOption?.label || packageId;
  testName.value = `${label} · ${suffix.replaceAll('-', ' ').toLowerCase()}`;
}

function applyModeControlState({ normalizeSelections = true } = {}) {
  elements.modeNote.textContent = modeText(state.mode);
  elements.customTypeField?.classList.toggle('hidden', state.mode !== 'CUSTOM');
  const selectedOrderOption = elements.order?.querySelector('option[value="SELECTED"]');
  if (selectedOrderOption) selectedOrderOption.disabled = state.mode !== 'CUSTOM';
  if (state.mode !== 'CUSTOM' && elements.order?.value === 'SELECTED') elements.order.value = 'PACKAGE_ORIGINAL';

  if (state.mode === 'PYQ_ORIGINAL') {
    elements.includeSupplements.checked = false;
    elements.includeSupplements.disabled = true;
    elements.includeUnassigned.checked = false;
    elements.includeUnassigned.disabled = true;
  } else if (state.mode === 'PYQ_COMPLETED' || state.mode === 'PYQ_SECTIONAL') {
    elements.includeSupplements.checked = true;
    elements.includeSupplements.disabled = state.mode === 'PYQ_COMPLETED';
    elements.includeUnassigned.checked = false;
    elements.includeUnassigned.disabled = true;
  } else {
    elements.includeSupplements.disabled = false;
    elements.includeUnassigned.disabled = false;
  }

  if (normalizeSelections && SINGLE_PACKAGE_MODES.has(state.mode) && selectedValues('package_ids').length > 1) {
    setSelectedValues('package_ids', selectedValues('package_ids').slice(0, 1));
  }
}

function updateModeUI() {
  applyModeControlState();
  invalidatePreview();
  renderFilterChips();
  renderSelectedBar();
}

function facetLabel(key, item) {
  if (key === 'package_ids') {
    const status = item.is_active === false ? ' · Superseded' : '';
    const completeness = item.completeness_status ? ` · ${String(item.completeness_status).replaceAll('_', ' ')}` : '';
    return `${item.label}${status}${completeness}`;
  }
  return item.label ?? item.value;
}

function facetSubLabel(key, item) {
  if (key === 'package_ids') {
    return `${Number(item.source_count || 0)} source · ${Number(item.supplemental_count || 0)} supplemental`;
  }
  if (item.code) return item.code;
  return '';
}

function renderFacet(key) {
  const container = document.querySelector(`[data-filter-options="${key}"]`);
  if (!container) return;
  const options = state.facets[FACET_MAP[key]] || [];
  const selected = new Set(selectedValues(key));

  if (!options.length) {
    container.innerHTML = '<div class="phase4a-filter-empty">No value is available under the current filters.</div>';
    updateFilterSummary(key);
    return;
  }

  container.innerHTML = options.map((item) => {
    const value = normalizeValue(item.value);
    const checked = selected.has(value) ? 'checked' : '';
    const sub = facetSubLabel(key, item);
    return `
      <label class="phase4a-filter-option">
        <input type="checkbox" data-filter-key="${escapeHtml(key)}" value="${escapeHtml(value)}" ${checked} />
        <span class="phase4a-filter-option-main">
          <strong>${escapeHtml(facetLabel(key, item))}</strong>
          ${sub ? `<small>${escapeHtml(sub)}</small>` : ''}
        </span>
        <span class="phase4a-filter-option-count">${escapeHtml(item.count ?? 0)}</span>
      </label>`;
  }).join('');

  container.querySelectorAll('[data-filter-key]').forEach((checkbox) => {
    checkbox.addEventListener('change', () => handleFilterCheckbox(checkbox));
  });
  updateFilterSummary(key);
}

function updateFilterSummary(key) {
  const summary = document.querySelector(`[data-filter-summary="${key}"]`);
  if (!summary) return;
  const values = selectedValues(key);
  if (!values.length) {
    summary.textContent = key === 'package_ids' ? 'All active packages' : 'All';
  } else if (values.length === 1) {
    const options = state.facets[FACET_MAP[key]] || [];
    const match = options.find((item) => normalizeValue(item.value) === values[0]);
    summary.textContent = match?.label || values[0];
  } else {
    summary.textContent = `${values.length} selected`;
  }
}

async function handleFilterCheckbox(checkbox) {
  const key = checkbox.dataset.filterKey;
  const value = normalizeValue(checkbox.value);
  let values = selectedValues(key).filter((item) => item !== value);
  if (checkbox.checked) {
    if (key === 'package_ids' && SINGLE_PACKAGE_MODES.has(state.mode)) values = [value];
    else values.push(value);
  }
  setSelectedValues(key, values);
  invalidatePreview('Filters changed. Preview the resolved test again.');
  renderFilterChips();
  maybeSuggestIdentity();
  await refreshFacets();
  await loadQuestions({ reset: true });
}

function renderFilterChips() {
  const chips = [];
  FILTER_KEYS.forEach((key) => {
    const options = state.facets[FACET_MAP[key]] || [];
    selectedValues(key).forEach((value) => {
      const item = options.find((option) => normalizeValue(option.value) === value);
      chips.push(`
        <span class="phase4a-filter-chip">
          ${escapeHtml(FILTER_LABELS[key])}: ${escapeHtml(item?.label || value)}
          <button type="button" data-remove-filter="${escapeHtml(key)}" data-remove-value="${escapeHtml(value)}" aria-label="Remove filter">×</button>
        </span>`);
    });
  });
  elements.filterChips.innerHTML = chips.length ? chips.join('') : '<span class="muted">No value filter selected.</span>';
  elements.filterChips.querySelectorAll('[data-remove-filter]').forEach((button) => {
    button.addEventListener('click', async () => {
      const key = button.dataset.removeFilter;
      setSelectedValues(key, selectedValues(key).filter((value) => value !== button.dataset.removeValue));
      invalidatePreview('Filters changed. Preview the resolved test again.');
      await refreshFacets();
      await loadQuestions({ reset: true });
    });
  });
}

function renderFacetSummary() {
  const summary = state.summary || {};
  const rows = [
    ['Unique questions', summary.unique_questions || 0],
    ['Matching memberships', summary.matching_memberships || 0],
    ['Source PYQs', summary.source_pyq || 0],
    ['Supplemental', summary.supplemental || 0],
    ['Repeated memberships', summary.repeated_memberships || 0],
  ];
  elements.facetSummary.innerHTML = rows.map(([label, value]) => `
    <div class="phase4a-summary-item"><strong>${escapeHtml(value)}</strong><span>${escapeHtml(label)}</span></div>
  `).join('');
}

async function refreshFacets() {
  const requestId = ++state.facetRequestId;
  try {
    const result = await api.getPhase4ATestBuilderFacets(currentFilters());
    if (requestId !== state.facetRequestId) return;
    state.facets = result || {};
    state.summary = result?.summary || {};
    FILTER_KEYS.forEach(renderFacet);
    renderFilterChips();
    renderFacetSummary();
  } catch (error) {
    if (requestId !== state.facetRequestId) return;
    toast.error(error.message);
    elements.facetSummary.innerHTML = `<div class="phase4a-inline-error">${escapeHtml(error.message)}</div>`;
  }
}

function renderSelectedBar() {
  const count = state.selectedIds.size;
  const isCustom = state.mode === 'CUSTOM';
  if (isCustom) {
    elements.selectedBar.innerHTML = `<strong>${count} selected</strong><span>Selection stays while filters or pages change.</span>`;
  } else {
    elements.selectedBar.innerHTML = `<strong>Automatic resolution</strong><span>Preview will include the complete matching package mode. ${count ? `${count} custom selection${count === 1 ? '' : 's'} are preserved for Custom mode.` : ''}</span>`;
  }
  elements.selectVisible.disabled = !isCustom;
  elements.selectAllFiltered.disabled = !isCustom;
  elements.clearSelection.disabled = !isCustom || count === 0;
}

function questionMarkup(item) {
  const checked = state.selectedIds.has(item.question_id) ? 'checked' : '';
  const disabled = state.mode === 'CUSTOM' ? '' : 'disabled';
  const packages = Array.isArray(item.package_ids) ? item.package_ids : [];
  const memberships = Array.isArray(item.membership_types) ? item.membership_types : [];
  const qNo = item.original_question_no || item.source_order || item.result_position;
  return `
    <article class="phase4a-question-item">
      <label class="phase4a-question-select" aria-label="Select ${escapeHtml(item.question_id)}">
        <input type="checkbox" data-question-select="${escapeHtml(item.question_id)}" ${checked} ${disabled} />
      </label>
      <div class="phase4a-question-main">
        <div class="phase4a-question-title">
          <span class="phase4a-qno">Q.${escapeHtml(qNo || '—')}</span>
          <strong>${escapeHtml(item.question_id)}</strong>
          ${item.is_supplemental ? '<span class="phase4a-mini-chip warning">Supplemental NORMAL</span>' : ''}
          ${Number(item.membership_count || 0) > 1 ? `<span class="phase4a-mini-chip">Appears ${escapeHtml(item.membership_count)} times</span>` : ''}
        </div>
        <p class="phase4a-question-text">${escapeHtml(item.question_text)}</p>
        <div class="phase4a-question-meta">
          <span class="phase4a-mini-chip">${escapeHtml(item.subject_name || item.subject_id)}</span>
          ${item.topic_name || item.topic_id ? `<span class="phase4a-mini-chip">${escapeHtml(item.topic_name || item.topic_id)}</span>` : ''}
          <span class="phase4a-mini-chip">${escapeHtml(item.question_type)}</span>
          <span class="phase4a-mini-chip">${escapeHtml(item.language)}</span>
          <span class="phase4a-mini-chip">${escapeHtml(item.difficulty)}</span>
          ${memberships.map((value) => `<span class="phase4a-mini-chip">${escapeHtml(String(value).replaceAll('_', ' '))}</span>`).join('')}
        </div>
        <div class="phase4a-package-list">
          ${packages.length ? packages.map((value) => `<span>${escapeHtml(value)}</span>`).join('') : '<span>No import package membership</span>'}
        </div>
      </div>
    </article>`;
}

function bindQuestionCheckboxes() {
  elements.questionList.querySelectorAll('[data-question-select]').forEach((checkbox) => {
    if (checkbox.dataset.bound === '1') return;
    checkbox.dataset.bound = '1';
    checkbox.addEventListener('change', () => {
      const id = checkbox.dataset.questionSelect;
      if (checkbox.checked) addSelected(id);
      else removeSelected(id);
      renderSelectedBar();
      invalidatePreview('Question selection changed. Preview the resolved test again.');
    });
  });
}

function renderQuestions({ append = false } = {}) {
  if (!append && !state.questions.length) {
    elements.questionList.innerHTML = '<div class="empty-state">No published question matches the current filters.</div>';
  } else if (append) {
    elements.questionList.insertAdjacentHTML('beforeend', state.questions.map(questionMarkup).join(''));
  } else {
    elements.questionList.innerHTML = state.questions.map(questionMarkup).join('');
  }
  bindQuestionCheckboxes();
  state.visibleQuestionIds = [...elements.questionList.querySelectorAll('[data-question-select]')]
    .map((input) => input.dataset.questionSelect);
  renderSelectedBar();
  elements.loadMore.classList.toggle('hidden', !state.hasMore);
}

async function loadQuestions({ reset = true } = {}) {
  const requestId = ++state.questionRequestId;
  const offset = reset ? 0 : state.offset;
  if (reset) {
    state.questions = [];
    state.visibleQuestionIds = [];
    elements.questionList.innerHTML = '<div class="loading-state">Loading filtered published questions…</div>';
  }
  setBusy(reset ? elements.loadQuestions : elements.loadMore, true, reset ? 'Loading…' : 'Loading more…');

  try {
    const result = await api.searchPhase4ATestBuilderQuestions({
      filters: currentFilters(),
      search: currentSearch(),
      order: currentBrowseOrder(),
      offset,
      limit: PAGE_SIZE,
    });
    if (requestId !== state.questionRequestId) return;

    const items = Array.isArray(result?.items) ? result.items : [];
    if (reset) state.questions = items;
    else state.questions = items;
    state.total = Number(result?.total || 0);
    state.offset = offset + items.length;
    state.hasMore = state.offset < state.total;
    elements.questionMeta.textContent = state.mode === 'CUSTOM'
      ? `${state.total} unique question${state.total === 1 ? '' : 's'} match · ${state.selectedIds.size} selected`
      : `${state.total} unique question${state.total === 1 ? '' : 's'} match · automatic mode resolves the authoritative set`;
    renderQuestions({ append: !reset });
  } catch (error) {
    if (requestId !== state.questionRequestId) return;
    if (reset) elements.questionList.innerHTML = `<div class="phase4a-inline-error">${escapeHtml(error.message)}</div>`;
    toast.error(error.message);
  } finally {
    setBusy(reset ? elements.loadQuestions : elements.loadMore, false);
  }
}

function addSelected(questionId) {
  if (!state.selectedIds.has(questionId)) state.selectedOrder.push(questionId);
  state.selectedIds.add(questionId);
}

function removeSelected(questionId) {
  state.selectedIds.delete(questionId);
  state.selectedOrder = state.selectedOrder.filter((value) => value !== questionId);
}

function syncVisibleCheckboxes() {
  elements.questionList.querySelectorAll('[data-question-select]').forEach((checkbox) => {
    checkbox.checked = state.selectedIds.has(checkbox.dataset.questionSelect);
  });
}

async function selectAllFiltered() {
  if (state.mode !== 'CUSTOM') {
    toast.info('This mode resolves all matching package questions automatically. Use Custom selected for manual selection.');
    return;
  }
  setBusy(elements.selectAllFiltered, true, 'Selecting…');
  try {
    const result = await api.selectAllPhase4ATestBuilderQuestionIds({
      filters: currentFilters(),
      search: currentSearch(),
      order: currentBrowseOrder(),
    });
    const ids = Array.isArray(result?.question_ids) ? result.question_ids : [];
    ids.forEach(addSelected);
    syncVisibleCheckboxes();
    renderSelectedBar();
    invalidatePreview('Question selection changed. Preview the resolved test again.');
    toast.success(`${ids.length} filtered unique question${ids.length === 1 ? '' : 's'} selected.`);
  } catch (error) {
    toast.error(error.message);
  } finally {
    setBusy(elements.selectAllFiltered, false);
  }
}

function renderPreview(preview) {
  const warnings = Array.isArray(preview?.warnings) ? preview.warnings : [];
  const packages = Array.isArray(preview?.packages) ? preview.packages : [];
  const rows = [
    ['Questions', preview.question_count || 0],
    ['Source PYQs', preview.source_pyq_count || 0],
    ['Supplemental', preview.supplemental_count || 0],
    ['Subjects', preview.subject_count || 0],
    ['Topics', preview.topic_count || 0],
    ['Test type', preview.proposed_test_type || '—'],
    ['Ordering', String(preview.ordering || '').replaceAll('_', ' ')],
    ['Repeated removed', preview.repeated_memberships_removed || 0],
  ];

  elements.previewPanel.innerHTML = `
    <div>
      <span class="eyebrow">Authoritative database preview</span>
      <h3>${escapeHtml(String(preview.builder_mode || '').replaceAll('_', ' '))}</h3>
      <p class="muted">Board ${escapeHtml(preview.board_id || '—')} · Exam ${escapeHtml(preview.exam_id || '—')}</p>
    </div>
    <div class="phase4a-preview-grid">
      ${rows.map(([label, value]) => `<div class="phase4a-preview-stat"><strong>${escapeHtml(value)}</strong><span>${escapeHtml(label)}</span></div>`).join('')}
    </div>
    ${packages.length ? `<div class="phase4a-package-list"><strong>Import packages</strong>${packages.map((pkg) => `<span>${escapeHtml(pkg.package_id)} · ${escapeHtml(pkg.completeness_status || 'UNSPECIFIED')} · ${escapeHtml(pkg.extracted_source_questions ?? '—')} source · ${escapeHtml(pkg.generated_supplement_count ?? 0)} supplemental</span>`).join('')}</div>` : ''}
    ${warnings.length ? `<div class="phase4a-warning-list">${warnings.map((warning) => `<div class="phase4a-warning-item"><strong>${escapeHtml(warning.code || 'WARNING')}</strong><br>${escapeHtml(warning.message || '')}</div>`).join('')}</div>` : '<div class="notice notice-success">No blocking preview warning.</div>'}
  `;
  elements.previewPanel.classList.remove('hidden');
  elements.previewState.textContent = `${preview.question_count} questions resolved as ${preview.proposed_test_type}.`;
}

async function previewTest({ silent = false } = {}) {
  validateModeBeforeRequest();
  const payload = buildPayload();
  setBusy(elements.previewButton, true, 'Previewing…');
  try {
    const preview = await api.previewPhase4ADynamicTest(payload);
    state.preview = preview;
    state.previewSignature = previewSignature(payload);
    renderPreview(preview);
    if (!silent) toast.success('Resolved test preview is ready.');
    return preview;
  } catch (error) {
    state.preview = null;
    state.previewSignature = '';
    elements.previewPanel.classList.remove('hidden');
    elements.previewPanel.innerHTML = `<div class="phase4a-inline-error">${escapeHtml(error.message)}</div>`;
    elements.previewState.textContent = 'Preview failed. Resolve the reported issue.';
    throw error;
  } finally {
    setBusy(elements.previewButton, false);
  }
}

function requestConfirmation({ publish, preview }) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };
    const warnings = Array.isArray(preview?.warnings) ? preview.warnings : [];
    elements.confirmContent.innerHTML = `
      <div class="phase4a-confirm-content">
        <span class="eyebrow">${publish ? 'Publication confirmation' : 'Draft confirmation'}</span>
        <h2>${publish ? 'Publish' : 'Save'} this ${escapeHtml(preview.question_count)}-question fixed test?</h2>
        <p>The server will re-resolve every filter, validate published questions and write only links to existing master questions.</p>
        ${warnings.length ? `<div class="phase4a-warning-list">${warnings.map((warning) => `<div class="phase4a-warning-item">${escapeHtml(warning.message || '')}</div>`).join('')}</div>` : ''}
        <div class="phase4a-confirm-actions">
          <button id="phase4aConfirmYes" class="button button-primary" type="button">${publish ? 'Publish test' : 'Save draft'}</button>
          <button id="phase4aConfirmNo" class="button button-ghost" type="button">Cancel</button>
        </div>
      </div>`;
    elements.confirmContent.querySelector('#phase4aConfirmYes')?.addEventListener('click', () => {
      finish(true);
      elements.confirmDialog.close();
    });
    elements.confirmContent.querySelector('#phase4aConfirmNo')?.addEventListener('click', () => {
      finish(false);
      elements.confirmDialog.close();
    });
    elements.confirmDialog.addEventListener('close', () => finish(false), { once: true });
    if (!elements.confirmDialog.open) elements.confirmDialog.showModal();
  });
}

async function saveTest(event) {
  event.preventDefault();
  const submitter = event.submitter;
  const publish = submitter?.value === 'PUBLISH';
  const payload = buildPayload();

  if (!payload.testId || !payload.testName) {
    toast.warning('Test ID and test name are required.');
    return;
  }
  if (!/^[A-Z0-9]+(?:-[A-Z0-9]+)+$/.test(payload.testId)) {
    toast.warning('Test ID must contain uppercase letters, numbers and hyphens only.');
    return;
  }

  try {
    validateModeBeforeRequest();
    const signature = previewSignature(payload);
    const preview = state.preview && state.previewSignature === signature
      ? state.preview
      : await previewTest({ silent: true });
    const confirmed = await requestConfirmation({ publish, preview });
    if (!confirmed) return;

    [...elements.testForm.elements].forEach((control) => { control.disabled = true; });
    const loading = toast.loading?.(`${publish ? 'Publishing' : 'Saving'} fixed test…`);
    const result = await api.savePhase4ADynamicTest({ ...payload, publish });
    loading?.close?.();
    toast.success(`${result?.question_count || preview.question_count} questions linked. Test ${publish ? 'published' : 'saved as draft'} successfully.`);
    state.preview = result?.preview || preview;
    state.previewSignature = signature;
    renderPreview(state.preview);
  } catch (error) {
    toast.error(error.message);
  } finally {
    [...elements.testForm.elements].forEach((control) => { control.disabled = false; });
    applyModeControlState({ normalizeSelections: false });
  }
}

async function clearFilters() {
  FILTER_KEYS.forEach((key) => setSelectedValues(key, []));
  elements.includeSupplements.checked = state.mode !== 'PYQ_ORIGINAL';
  elements.includeSuperseded.checked = false;
  elements.includeUnassigned.checked = state.mode === 'CUSTOM';
  elements.search.value = '';
  invalidatePreview('Filters cleared. Preview the resolved test again.');
  await refreshFacets();
  await loadQuestions({ reset: true });
}

function bindEvents() {
  elements.loginForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const data = new FormData(elements.loginForm);
    setBusy(elements.loginForm.querySelector('button[type="submit"]'), true, 'Signing in…');
    try {
      await api.signIn({ email: data.get('email'), password: data.get('password') });
      await showBuilder();
      toast.success('Admin access verified.');
    } catch (error) {
      toast.error(error.message);
    } finally {
      setBusy(elements.loginForm.querySelector('button[type="submit"]'), false);
    }
  });

  elements.signOut?.addEventListener('click', async () => {
    try {
      await api.signOut();
      showLogin();
      toast.success('Signed out.');
    } catch (error) {
      toast.error(error.message);
    }
  });

  elements.modePicker?.querySelectorAll('input[name="builderMode"]').forEach((radio) => {
    radio.addEventListener('change', async () => {
      if (!radio.checked) return;
      state.mode = radio.value;
      updateModeUI();
      maybeSuggestIdentity();
      await refreshFacets();
      await loadQuestions({ reset: true });
    });
  });

  [elements.includeSupplements, elements.includeSuperseded, elements.includeUnassigned].forEach((checkbox) => {
    checkbox?.addEventListener('change', async () => {
      invalidatePreview('Filters changed. Preview the resolved test again.');
      await refreshFacets();
      await loadQuestions({ reset: true });
    });
  });

  elements.clearFilters?.addEventListener('click', clearFilters);
  elements.refresh?.addEventListener('click', async () => {
    await refreshFacets();
    await loadQuestions({ reset: true });
    toast.success('Dynamic catalogue refreshed.');
  });
  elements.loadQuestions?.addEventListener('click', () => loadQuestions({ reset: true }));
  elements.loadMore?.addEventListener('click', () => loadQuestions({ reset: false }));
  elements.search?.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      loadQuestions({ reset: true });
    }
  });
  elements.order?.addEventListener('change', () => {
    invalidatePreview('Question order changed. Preview the resolved test again.');
    loadQuestions({ reset: true });
  });

  elements.selectVisible?.addEventListener('click', () => {
    state.visibleQuestionIds.forEach(addSelected);
    syncVisibleCheckboxes();
    renderSelectedBar();
    invalidatePreview('Question selection changed. Preview the resolved test again.');
  });
  elements.selectAllFiltered?.addEventListener('click', selectAllFiltered);
  elements.clearSelection?.addEventListener('click', () => {
    state.selectedIds.clear();
    state.selectedOrder = [];
    syncVisibleCheckboxes();
    renderSelectedBar();
    invalidatePreview('Question selection cleared.');
  });

  elements.previewButton?.addEventListener('click', async () => {
    try {
      await previewTest();
    } catch (error) {
      toast.error(error.message);
    }
  });
  elements.testForm?.addEventListener('submit', saveTest);
  elements.testForm?.addEventListener('input', (event) => {
    if (event.target.matches('input, select')) invalidatePreview('Test settings changed. Preview the resolved test again.');
  });
}

async function initialize() {
  bindEvents();
  if (!isConfigured) {
    elements.setupNotice?.classList.remove('hidden');
    showLogin();
    return;
  }
  try {
    await showBuilder();
  } catch (error) {
    toast.error(error.message);
  }
}

initialize();
