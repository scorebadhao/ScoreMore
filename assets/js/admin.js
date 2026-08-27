import { APP_CONFIG, isConfigured } from './config.js';
import { api } from './api.js';
import { toast } from './toast.js';
import { downloadJson, formatBytes, parseImportHtml } from './importEngine.js';

const elements = {
  setupNotice: document.getElementById('adminSetupNotice'),
  sessionPanel: document.getElementById('adminSessionPanel'),
  sessionMessage: document.getElementById('adminSessionMessage'),
  sessionRetry: document.getElementById('adminSessionRetry'),
  loginPanel: document.getElementById('adminLoginPanel'),
  adminPanel: document.getElementById('adminPanel'),
  signOut: document.getElementById('adminSignOut'),
  loginForm: document.getElementById('adminLoginForm'),
  draftForm: document.getElementById('draftForm'),
  sourceUploadForm: document.getElementById('sourceUploadForm'),
  draftList: document.getElementById('draftList'),
  statusFilter: document.getElementById('draftStatusFilter'),
  reviewNextDraft: document.getElementById('reviewNextDraft'),
  draftListMeta: document.getElementById('draftListMeta'),
  loadMoreDrafts: document.getElementById('loadMoreDrafts'),
  dialog: document.getElementById('draftDialog'),
  dialogContent: document.getElementById('draftDialogContent'),
  testForm: document.getElementById('testForm'),
  publishedQuestionList: document.getElementById('publishedQuestionList'),
  selectedQuestionCount: document.getElementById('selectedQuestionCount'),
  adminTestList: document.getElementById('adminTestList'),
  testStatusFilter: document.getElementById('testStatusFilter'),
  testBuilderMode: document.getElementById('testBuilderMode'),
  testCatalogueStats: document.getElementById('testCatalogueStats'),
  testCatalogueSearch: document.getElementById('testCatalogueSearch'),
  testTypeFilter: document.getElementById('testTypeFilter'),
  testBoardFilter: document.getElementById('testBoardFilter'),
  testExamFilter: document.getElementById('testExamFilter'),
  testSubjectFilter: document.getElementById('testSubjectFilter'),
  testYearFilter: document.getElementById('testYearFilter'),
  clearTestCatalogueFilters: document.getElementById('clearTestCatalogueFilters'),
  dashboardRepairCount: document.getElementById('adminDashboardRepairCount'),
  dashboardRepairLabel: document.getElementById('adminDashboardRepairLabel'),
  dashboardRepairNext: document.getElementById('adminDashboardRepairNext'),
  dashboardPublishedImageCount: document.getElementById('adminDashboardPublishedImageCount'),
  dashboardPublishedImageLabel: document.getElementById('adminDashboardPublishedImageLabel'),
  dashboardPublishedImageNext: document.getElementById('adminDashboardPublishedImageNext'),
  dashboardReviewCount: document.getElementById('adminDashboardReviewCount'),
  dashboardReviewLabel: document.getElementById('adminDashboardReviewLabel'),
  dashboardReviewNext: document.getElementById('adminDashboardReviewNext'),
  dashboardPublishCount: document.getElementById('adminDashboardPublishCount'),
  dashboardPublishLabel: document.getElementById('adminDashboardPublishLabel'),
  dashboardPublishNext: document.getElementById('adminDashboardPublishNext'),
  taskInboxMeta: document.getElementById('adminTaskInboxMeta'),
  refreshAdminTasks: document.getElementById('refreshAdminTasks'),
  continueDraftRepairTask: document.getElementById('continueDraftRepairTask'),
  continuePublishedImageTask: document.getElementById('continuePublishedImageTask'),
  continueFinalReviewTask: document.getElementById('continueFinalReviewTask'),
  continuePublishTask: document.getElementById('continuePublishTask'),
  testQuestionSearch: document.getElementById('testQuestionSearch'),
  questionSelectionMeta: document.getElementById('questionSelectionMeta'),
  testPaperFields: document.getElementById('testPaperFields'),
  htmlImportForm: document.getElementById('htmlImportForm'),
  htmlImportFile: document.getElementById('htmlImportFile'),
  importPackagePreview: document.getElementById('importPackagePreview'),
  importReportPanel: document.getElementById('importReportPanel'),
  importReportTitle: document.getElementById('importReportTitle'),
  importReportMeta: document.getElementById('importReportMeta'),
  importSummaryGrid: document.getElementById('importSummaryGrid'),
  importItemList: document.getElementById('importItemList'),
  importItemFilter: document.getElementById('importItemFilter'),
  downloadImportReport: document.getElementById('downloadImportReport'),
  importValidDrafts: document.getElementById('importValidDrafts'),
  linkDuplicateOccurrences: document.getElementById('linkDuplicateOccurrences'),
  importSelectionSummary: document.getElementById('importSelectionSummary'),
  importProgressPanel: document.getElementById('importProgressPanel'),
  importProgressTitle: document.getElementById('importProgressTitle'),
  importProgressText: document.getElementById('importProgressText'),
  importProgressBar: document.getElementById('importProgressBar'),
  syncImportBatch: document.getElementById('syncImportBatch'),
  repairImportBatch: document.getElementById('repairImportBatch'),
  resetImportDrafts: document.getElementById('resetImportDrafts'),
  loadMoreImportItems: document.getElementById('loadMoreImportItems'),
  recentImportPanel: document.getElementById('recentImportPanel'),
  recentImportList: document.getElementById('recentImportList'),
  publishQueueMeta: document.getElementById('publishQueueMeta'),
  publishQueueList: document.getElementById('publishQueueList'),
  publishSelectionCount: document.getElementById('publishSelectionCount'),
  publishSelectedDrafts: document.getElementById('publishSelectedDrafts'),
  selectAllPublishReady: document.getElementById('selectAllPublishReady'),
  clearPublishSelection: document.getElementById('clearPublishSelection'),
  refreshPublishQueue: document.getElementById('refreshPublishQueue'),
  loadMorePublishQueue: document.getElementById('loadMorePublishQueue'),
  imageRepairFilters: document.getElementById('imageRepairFilters'),
  imageRepairStats: document.getElementById('imageRepairStats'),
  imageRepairQueueMeta: document.getElementById('imageRepairQueueMeta'),
  imageRepairList: document.getElementById('imageRepairList'),
  imageRepairStatus: document.getElementById('imageRepairStatus'),
  imageRepairSearch: document.getElementById('imageRepairSearch'),
  refreshImageRepairs: document.getElementById('refreshImageRepairs'),
  clearImageRepairFilters: document.getElementById('clearImageRepairFilters'),
  loadMoreImageRepairs: document.getElementById('loadMoreImageRepairs'),
  imageRepairDialog: document.getElementById('imageRepairDialog'),
  imageRepairDialogContent: document.getElementById('imageRepairDialogContent'),
  draftRepairQueueTab: document.getElementById('draftRepairQueueTab'),
  publishedImageRepairQueueTab: document.getElementById('publishedImageRepairQueueTab'),
  draftRepairTabCount: document.getElementById('draftRepairTabCount'),
  publishedImageRepairTabCount: document.getElementById('publishedImageRepairTabCount'),
  publishedImageRepairFilters: document.getElementById('publishedImageRepairFilters'),
  publishedImageRepairStats: document.getElementById('publishedImageRepairStats'),
  publishedImageRepairQueueMeta: document.getElementById('publishedImageRepairQueueMeta'),
  publishedImageRepairList: document.getElementById('publishedImageRepairList'),
  publishedImageRepairStatus: document.getElementById('publishedImageRepairStatus'),
  publishedImageRepairSearch: document.getElementById('publishedImageRepairSearch'),
  refreshPublishedImageRepairs: document.getElementById('refreshPublishedImageRepairs'),
  clearPublishedImageRepairFilters: document.getElementById('clearPublishedImageRepairFilters'),
  loadMorePublishedImageRepairs: document.getElementById('loadMorePublishedImageRepairs'),
};

let profile = null;
let adminRestorePromise = null;
let adminSessionRecheckTimer = null;
let adminAuthSubscription = null;
let drafts = [];
let referenceData = { boards: [], exams: [], subjects: [], topics: [] };
let publishedQuestions = [];
let configuredTests = [];
let selectedTestQuestionIds = new Set();
let editingTestId = null;
let parsedImportPackage = null;
let currentImportReport = null;
let recentImportBatches = [];
let currentImportBatchId = null;
let selectedDraftItemIds = new Set();
let selectedOccurrenceItemIds = new Set();
let visibleImportItemLimit = 20;
const IMPORT_ITEM_PAGE_SIZE = 20;
const DRAFT_IMPORT_CHUNK_SIZE = 10;
const DRAFT_PAGE_SIZE = 24;
const PUBLISH_PAGE_SIZE = 25;
const PUBLISH_CHUNK_SIZE = 10;
let draftPage = 0;
let draftHasMore = false;
let publishQueue = [];
let publishQueueTotal = 0;
let publishQueuePage = 0;
let publishQueueHasMore = false;
let selectedPublishDraftIds = new Set();
const IMAGE_REPAIR_PAGE_SIZE = 20;
let imageRepairPage = 0;
let imageRepairTotal = 0;
let imageRepairHasMore = false;
let imageRepairItems = [];
let imageRepairSummary = {
  total_candidates: 0,
  needs_repair: 0,
  content_needs_repair: 0,
  image_needs_repair: 0,
  pending: 0,
  approved: 0,
  no_image_required: 0,
  content_ready: 0,
};
let adminTaskInbox = null;
let activeRepairQueue = 'draft';
let publishedImageRepairPage = 0;
let publishedImageRepairTotal = 0;
let publishedImageRepairHasMore = false;
let publishedImageRepairItems = [];
let publishedImageRepairSummary = {
  total_candidates: 0,
  needs_repair: 0,
  pending: 0,
  approved: 0,
  no_image_required: 0,
};
let activeRepairObjectUrl = '';


const ADMIN_VIEW_META = Object.freeze({
  dashboard: {
    eyebrow: 'Operations overview',
    title: 'Admin Dashboard',
    description: 'See the current queues, continue the next safe action, and move between admin functions without scrolling through one long page.',
  },
  import: {
    eyebrow: 'Question workflow · Stage 1',
    title: 'Import Centre',
    description: 'Bring source material into controlled drafts. Validate packages before any database write.',
  },
  repair: {
    eyebrow: 'Question workflow · Stage 2',
    title: 'Image & Content Repair',
    description: 'Correct draft presentation and resolve the separate published image-safety backlog.',
  },
  review: {
    eyebrow: 'Question workflow · Stage 3',
    title: 'Final Review Centre',
    description: 'Review the final student presentation, then verify answer, explanation and topic.',
  },
  publish: {
    eyebrow: 'Question workflow · Stage 4',
    title: 'Publish Centre',
    description: 'Publish only drafts whose current repair revision has passed Final Review.',
  },
  tests: {
    eyebrow: 'Test operations',
    title: 'Build Tests',
    description: 'Create fixed-question tests from student-ready published master questions without copying them.',
  },
  catalogue: {
    eyebrow: 'Test operations',
    title: 'Test Catalogue',
    description: 'Find configured tests, edit their fixed question list, or safely change visibility.',
  },
});

let activeAdminView = 'dashboard';

function closeAdminSidebar() {
  document.body.classList.remove('admin-sidebar-open');
  const toggle = document.getElementById('adminSidebarToggle');
  if (toggle) toggle.setAttribute('aria-expanded', 'false');
}

function setAdminView(view, { updateHash = true, scroll = true } = {}) {
  const nextView = Object.hasOwn(ADMIN_VIEW_META, view) ? view : 'dashboard';
  const meta = ADMIN_VIEW_META[nextView];
  activeAdminView = nextView;

  document.querySelectorAll('[data-admin-view-panel]').forEach((panel) => {
    panel.hidden = panel.dataset.adminViewPanel !== nextView;
  });

  document.querySelectorAll('[data-admin-view]').forEach((control) => {
    const active = control.dataset.adminView === nextView;
    control.classList.toggle('active', active);
    if (active) control.setAttribute('aria-current', 'page');
    else control.removeAttribute('aria-current');
  });

  const eyebrow = document.getElementById('adminPageEyebrow');
  const title = document.getElementById('adminPageTitle');
  const description = document.getElementById('adminPageDescription');
  if (eyebrow) eyebrow.textContent = meta.eyebrow;
  if (title) title.textContent = meta.title;
  if (description) description.textContent = meta.description;

  try { sessionStorage.setItem('scoremore-admin-active-view', nextView); } catch {}
  if (updateHash) history.replaceState(null, '', `#admin-${nextView}`);
  closeAdminSidebar();

  if (scroll) {
    const content = document.querySelector('.admin-workspace-main');
    content?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
}

function initializeAdminWorkspaceNavigation() {
  const fromHash = String(location.hash || '').match(/^#admin-(dashboard|import|repair|review|publish|tests|catalogue)$/)?.[1];
  let stored = '';
  try { stored = sessionStorage.getItem('scoremore-admin-active-view') || ''; } catch {}
  setAdminView(fromHash || stored || 'dashboard', { updateHash: Boolean(fromHash), scroll: false });

  document.querySelectorAll('[data-admin-view]').forEach((control) => {
    control.addEventListener('click', () => setAdminView(control.dataset.adminView));
  });

  window.addEventListener('hashchange', () => {
    const requested = String(location.hash || '').match(/^#admin-(dashboard|import|repair|review|publish|tests|catalogue)$/)?.[1];
    if (requested && requested !== activeAdminView) setAdminView(requested, { updateHash: false, scroll: false });
  });
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function safePreviewUrl(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  try {
    const parsed = new URL(raw, window.location.href);
    return ['http:', 'https:', 'data:', 'blob:'].includes(parsed.protocol) ? parsed.href : '';
  } catch {
    return '';
  }
}

function setBusy(form, busy) {
  form?.querySelectorAll('button, input, textarea, select').forEach((element) => {
    if (busy) {
      element.dataset.scoremoreWasDisabled = element.disabled ? '1' : '0';
      element.disabled = true;
      return;
    }
    element.disabled = element.dataset.scoremoreWasDisabled === '1';
    delete element.dataset.scoremoreWasDisabled;
  });
}

function showRestoringAdminSession(message = 'Checking your existing secure session. You should not need to sign in again.') {
  elements.sessionMessage.textContent = message;
  elements.sessionRetry.classList.add('hidden');
  elements.sessionPanel.classList.remove('hidden');
  elements.loginPanel.classList.add('hidden');
  if (!document.body.classList.contains('admin-authenticated')) {
    elements.adminPanel.classList.add('hidden');
    elements.signOut.classList.add('hidden');
  }
}

function showSessionProblem(error) {
  const message = error?.message || 'The admin session could not be verified right now.';
  if (document.body.classList.contains('admin-authenticated')) {
    toast.warning(`${message} Your current admin workspace has been kept open.`);
    return;
  }
  elements.sessionMessage.textContent = `${message} Your stored session has not been cleared. Retry when the connection is ready.`;
  elements.sessionRetry.classList.remove('hidden');
  elements.sessionPanel.classList.remove('hidden');
  elements.loginPanel.classList.add('hidden');
  elements.adminPanel.classList.add('hidden');
  elements.signOut.classList.add('hidden');
}

function showLogin() {
  profile = null;
  document.body.classList.remove('admin-authenticated');
  closeAdminSidebar();
  elements.sessionPanel.classList.add('hidden');
  elements.loginPanel.classList.remove('hidden');
  elements.adminPanel.classList.add('hidden');
  elements.signOut.classList.add('hidden');
}

async function showAdmin({ reloadData = true, announceSessionError = true } = {}) {
  if (adminRestorePromise) return adminRestorePromise;

  adminRestorePromise = (async () => {
    if (!document.body.classList.contains('admin-authenticated')) {
      showRestoringAdminSession();
    }

    const context = await api.getAdminContext({ attempts: 2, retryDelayMs: 350 });
    if (context.status === 'SIGNED_OUT') {
      showLogin();
      return false;
    }

    if (context.status === 'UNAUTHORIZED') {
      // This is the only automatic sign-out path: the profile lookup completed
      // successfully and confirmed that the current account is not an admin.
      try { await api.signOut(); } catch {}
      showLogin();
      throw new Error(`This account is not authorized as a ${APP_CONFIG.name} admin.`);
    }

    if (context.status === 'ERROR') {
      showSessionProblem(context.error);
      if (announceSessionError && document.body.classList.contains('admin-authenticated')) {
        toast.warning('Admin session verification will retry automatically.');
      }
      return false;
    }

    profile = context.profile;
    elements.sessionPanel.classList.add('hidden');
    elements.loginPanel.classList.add('hidden');
    elements.adminPanel.classList.remove('hidden');
    document.body.classList.add('admin-authenticated');
    elements.signOut.classList.remove('hidden');

    if (reloadData) {
      try {
        await loadReferenceData();
        await Promise.all([
          loadAdminTaskInbox(),
          loadDrafts(),
          loadPublishQueue(),
          loadConfiguredTests(),
          loadRecentImportBatches(),
          loadImageRepairQueue(),
          loadPublishedImageRepairQueue(),
        ]);
        renderAdminDashboard();
      } catch (error) {
        // Data/API failures must never be interpreted as an authentication failure.
        toast.error(`${error.message} Admin session remains active.`);
      }
    }

    return true;
  })();

  try {
    return await adminRestorePromise;
  } finally {
    adminRestorePromise = null;
  }
}

function scheduleAdminSessionRecheck({ reloadData = false } = {}) {
  window.clearTimeout(adminSessionRecheckTimer);
  adminSessionRecheckTimer = window.setTimeout(() => {
    showAdmin({ reloadData, announceSessionError: false }).catch((error) => {
      showSessionProblem(error);
    });
  }, 120);
}

function bindAdminAuthLifecycle() {
  const authState = api.onAuthStateChange((event, session) => {
    // Supabase recommends keeping auth callbacks lightweight. Defer any API
    // work so token refresh/navigation cannot deadlock the auth callback.
    window.setTimeout(() => {
      if (event === 'SIGNED_OUT') {
        showLogin();
        return;
      }
      if (session?.user && ['INITIAL_SESSION', 'SIGNED_IN', 'TOKEN_REFRESHED', 'USER_UPDATED'].includes(event)) {
        scheduleAdminSessionRecheck({ reloadData: false });
      }
    }, 0);
  });
  adminAuthSubscription = authState?.data?.subscription || null;

  window.addEventListener('pageshow', () => {
    if (isConfigured) scheduleAdminSessionRecheck({ reloadData: false });
  });

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && document.body.classList.contains('admin-authenticated')) {
      scheduleAdminSessionRecheck({ reloadData: false });
    }
  });
}

function taskBucket(name) {
  const value = adminTaskInbox?.[name];
  return value && typeof value === 'object' ? value : { count: 0, next: null };
}

function taskDisplayId(task) {
  return task?.display_id || task?.proposed_question_id || task?.question_id || '';
}

function renderTaskCard({ bucket, countElement, labelElement, nextElement, buttonElement, emptyLabel, openLabel }) {
  const task = taskBucket(bucket);
  const count = Number(task.count || 0);
  const nextId = taskDisplayId(task.next);
  if (countElement) countElement.textContent = String(count);
  if (labelElement) labelElement.textContent = count ? openLabel(count) : emptyLabel;
  if (nextElement) nextElement.textContent = nextId ? `Next: ${nextId}` : 'No task is waiting in this queue.';
  if (buttonElement) {
    buttonElement.disabled = !task.next;
    buttonElement.setAttribute('aria-disabled', task.next ? 'false' : 'true');
  }
}

function renderAdminDashboard() {
  renderTaskCard({
    bucket: 'draft_repairs',
    countElement: elements.dashboardRepairCount,
    labelElement: elements.dashboardRepairLabel,
    nextElement: elements.dashboardRepairNext,
    buttonElement: elements.continueDraftRepairTask,
    emptyLabel: 'No draft presentation is blocked.',
    openLabel: (count) => `${count} draft repair task${count === 1 ? '' : 's'} need action`,
  });
  renderTaskCard({
    bucket: 'published_image_safety',
    countElement: elements.dashboardPublishedImageCount,
    labelElement: elements.dashboardPublishedImageLabel,
    nextElement: elements.dashboardPublishedImageNext,
    buttonElement: elements.continuePublishedImageTask,
    emptyLabel: 'All published visual questions are resolved.',
    openLabel: (count) => `${count} published image-safety task${count === 1 ? '' : 's'} need action`,
  });
  renderTaskCard({
    bucket: 'final_reviews',
    countElement: elements.dashboardReviewCount,
    labelElement: elements.dashboardReviewLabel,
    nextElement: elements.dashboardReviewNext,
    buttonElement: elements.continueFinalReviewTask,
    emptyLabel: 'No repair-ready draft awaits Final Review.',
    openLabel: (count) => `${count} repair-ready draft${count === 1 ? '' : 's'} await Final Review`,
  });
  renderTaskCard({
    bucket: 'ready_to_publish',
    countElement: elements.dashboardPublishCount,
    labelElement: elements.dashboardPublishLabel,
    nextElement: elements.dashboardPublishNext,
    buttonElement: elements.continuePublishTask,
    emptyLabel: 'No verified draft is ready to publish.',
    openLabel: (count) => `${count} verified draft${count === 1 ? '' : 's'} ready to publish`,
  });

  const generatedAt = adminTaskInbox?.generated_at ? new Date(adminTaskInbox.generated_at) : null;
  if (elements.taskInboxMeta) {
    elements.taskInboxMeta.textContent = generatedAt && !Number.isNaN(generatedAt.getTime())
      ? `Exact database snapshot refreshed ${generatedAt.toLocaleString()}.`
      : 'Exact workflow counts are not available yet.';
  }
  if (elements.draftRepairTabCount) {
    elements.draftRepairTabCount.textContent = String(Number(taskBucket('draft_repairs').count || 0));
  }
  if (elements.publishedImageRepairTabCount) {
    elements.publishedImageRepairTabCount.textContent = String(Number(taskBucket('published_image_safety').count || 0));
  }

  document.querySelectorAll('[data-task-bucket]').forEach((card) => {
    card.classList.toggle('is-recommended-task', card.dataset.taskBucket === adminTaskInbox?.recommended_bucket);
  });
}

async function loadAdminTaskInbox({ announce = false } = {}) {
  if (elements.refreshAdminTasks) elements.refreshAdminTasks.disabled = true;
  try {
    adminTaskInbox = await api.getAdminTaskInbox();
    renderAdminDashboard();
    if (announce) toast.success('Task Inbox refreshed from the database.');
    return adminTaskInbox;
  } catch (error) {
    if (elements.taskInboxMeta) elements.taskInboxMeta.textContent = error.message;
    if (announce) toast.error(error.message);
    return null;
  } finally {
    if (elements.refreshAdminTasks) elements.refreshAdminTasks.disabled = false;
  }
}

function draftHasSourceImages(draft) {
  return Array.isArray(draft?.image_refs) && draft.image_refs.length > 0;
}

function draftContentRepairReady(draft) {
  return !draft?.content_repair_status || draft.content_repair_status === 'READY';
}

function draftImageReady(draft) {
  if (!draftHasSourceImages(draft)) {
    return !draft?.student_image_review_status || draft.student_image_review_status === 'NOT_APPLICABLE';
  }
  return ['SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED'].includes(draft?.student_image_review_status);
}

function draftRepairReady(draft) {
  return draftContentRepairReady(draft) && draftImageReady(draft);
}

function draftReviewMatchesRepairRevision(draft) {
  if (draft?.reviewed_repair_revision === undefined || draft?.repair_revision === undefined) return true;
  return Number(draft.reviewed_repair_revision) === Number(draft.repair_revision);
}

function draftContentConfirmationMatchesRevision(draft) {
  if (draft?.content_source_confirmed_revision === undefined || draft?.repair_revision === undefined) return false;
  return Number(draft.content_source_confirmed_revision) === Number(draft.repair_revision);
}

function isDraftPublishReady(draft) {
  return Boolean(
    draft?.correct_answer
    && draft?.answer_source
    && draft.answer_source !== 'AI_PROPOSED'
    && draft.verification_status === 'VERIFIED'
    && draft.explanation
    && (draft.question_type !== 'PYQ' || draft.topic_id)
    && draft.source_quality !== 'UNREADABLE'
    && (draft.source_option_anomaly !== 'DUPLICATE_OPTIONS_PRINTED' || draft.source_option_anomaly_note)
    && draftRepairReady(draft)
    && draftReviewMatchesRepairRevision(draft)
    && draftContentConfirmationMatchesRevision(draft)
  );
}

function reviewableDrafts() {
  return drafts.filter((draft) => (
    !['PUBLISHED', 'REJECTED'].includes(draft.review_status)
    && !isDraftPublishReady(draft)
    && draftRepairReady(draft)
  ));
}

function nextReviewableDraftId(excludeDraftId = null) {
  return reviewableDrafts().find((draft) => draft.draft_id !== excludeDraftId)?.draft_id || null;
}

function renderDrafts() {
  const reviewable = reviewableDrafts();
  const repairBlocked = drafts.filter((draft) => (
    !['PUBLISHED', 'REJECTED'].includes(draft.review_status)
    && !draftRepairReady(draft)
  ));
  if (elements.draftListMeta) {
    const label = elements.statusFilter.value || 'ALL';
    elements.draftListMeta.textContent = `${drafts.length} ${label.toLowerCase()} draft${drafts.length === 1 ? '' : 's'} loaded · ${repairBlocked.length} need Image & Content Repair · ${reviewable.length} ready for Final Review.`;
  }
  if (elements.reviewNextDraft) elements.reviewNextDraft.disabled = reviewable.length === 0 && !draftHasMore;
  elements.loadMoreDrafts?.classList.toggle('hidden', !draftHasMore);
  renderAdminDashboard();

  if (!drafts.length) {
    elements.draftList.innerHTML = '<div class="empty-state">No drafts match this status.</div>';
    return;
  }

  elements.draftList.innerHTML = drafts.map((draft, index) => {
    const ready = isDraftPublishReady(draft);
    const repairBlocked = !draftRepairReady(draft);
    const contentRepairBlocked = !draftContentRepairReady(draft);
    const repairState = contentRepairBlocked
      ? `Content: ${String(draft.content_repair_status || 'NEEDS_REPAIR').replaceAll('_', ' ')}`
      : draftHasSourceImages(draft)
        ? `Image: ${String(draft.student_image_review_status || 'NEEDS_REVIEW').replaceAll('_', ' ')}`
        : 'Image: not applicable';
    const statusText = ready
      ? 'Final review complete'
      : repairBlocked
        ? 'Repair required first'
        : draft.answer_source === 'AI_PROPOSED'
          ? 'Ready for final review'
          : 'Needs final review';
    return `
    <article class="draft-item compact-draft-item ${repairBlocked ? 'draft-repair-blocked' : ''}">
      <div class="draft-sequence">${index + 1}</div>
      <div class="draft-compact-main">
        <div class="draft-item-header">
          <div>
            <span class="eyebrow">${escapeHtml(draft.review_status)} · ${escapeHtml(draft.question_type)}</span>
            <h3>${escapeHtml(draft.proposed_question_id || 'Question ID required')}</h3>
          </div>
          <span class="chip">${escapeHtml(draft.subject_id || 'No subject')}</span>
        </div>
        <p class="draft-question-preview">${escapeHtml(draft.question_text)}</p>
        <div class="draft-quick-status">
          <span>${escapeHtml(statusText)}</span>
          <span>${escapeHtml(repairState)}</span>
          <span>${draft.correct_answer ? `Answer ${escapeHtml(draft.correct_answer)}` : 'Answer missing'}</span>
          <span>${escapeHtml(draft.topic_id || draft.suggested_topic_code || 'Topic missing')}</span>
          ${contentRepairBlocked ? `<span class="warning-chip">${escapeHtml(String(draft.content_repair_reason_code || 'CONTENT_REPAIR').replaceAll('_', ' '))}</span>` : ''}
          ${Number(draft.content_repair_version || 0) > 0 ? '<span class="repair-edited-chip">Edited in repair</span>' : ''}
          ${draft.source_quality && draft.source_quality !== 'CLEAR' ? `<span class="warning-chip">${escapeHtml(draft.source_quality)}</span>` : ''}
          ${draft.is_supplemental ? '<span class="warning-chip">Supplemental</span>' : ''}
        </div>
      </div>
      <div class="draft-compact-actions">
        ${!['PUBLISHED','REJECTED'].includes(draft.review_status)
          ? repairBlocked
            ? `<button class="button button-secondary" data-repair-draft="${draft.draft_id}" type="button">Repair first</button>`
            : `<button class="button button-primary" data-review="${draft.draft_id}" type="button">${ready ? 'View final review' : 'Final review'}</button>`
          : ''}
      </div>
    </article>`;
  }).join('');

  elements.draftList.querySelectorAll('[data-review]').forEach((button) => button.addEventListener('click', () => openReview(button.dataset.review)));
  elements.draftList.querySelectorAll('[data-repair-draft]').forEach((button) => button.addEventListener('click', () => {
    const draft = drafts.find((item) => item.draft_id === button.dataset.repairDraft);
    if (draft) focusDraftInRepair(draft);
  }));
}

async function loadDrafts({ reset = true } = {}) {
  if (reset) {
    draftPage = 0;
    drafts = [];
    elements.draftList.innerHTML = '<div class="loading-state">Loading compact draft list…</div>';
  } else {
    elements.loadMoreDrafts.disabled = true;
  }

  try {
    const rows = await api.listDrafts({
      status: elements.statusFilter.value,
      page: draftPage,
      pageSize: DRAFT_PAGE_SIZE,
    });
    const existing = new Set(drafts.map((draft) => draft.draft_id));
    drafts = [...drafts, ...rows.filter((draft) => !existing.has(draft.draft_id))];
    draftHasMore = rows.length === DRAFT_PAGE_SIZE;
    if (rows.length) draftPage += 1;
    renderDrafts();
  } catch (error) {
    if (!drafts.length) elements.draftList.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    toast.error(error.message);
  } finally {
    if (elements.loadMoreDrafts) elements.loadMoreDrafts.disabled = false;
  }
}


function updatePublishSelectionControls() {
  const selected = selectedPublishDraftIds.size;
  if (elements.publishSelectionCount) elements.publishSelectionCount.textContent = `${selected} selected`;
  if (elements.publishSelectedDrafts) {
    elements.publishSelectedDrafts.disabled = selected === 0;
    elements.publishSelectedDrafts.textContent = selected ? `Publish selected (${selected})` : 'Publish selected';
  }
  if (elements.clearPublishSelection) elements.clearPublishSelection.disabled = selected === 0;
  if (elements.selectAllPublishReady) elements.selectAllPublishReady.disabled = publishQueue.length === 0;
}

function renderPublishQueue() {
  if (!elements.publishQueueList) return;
  renderAdminDashboard();
  if (elements.publishQueueMeta) {
    elements.publishQueueMeta.textContent = `${publishQueueTotal} verified draft${publishQueueTotal === 1 ? '' : 's'} ready to publish. Publishing is separate from human review.`;
  }
  elements.loadMorePublishQueue?.classList.toggle('hidden', !publishQueueHasMore);

  if (!publishQueue.length) {
    elements.publishQueueList.innerHTML = '<div class="empty-state">No verified draft is ready to publish yet.</div>';
    updatePublishSelectionControls();
    return;
  }

  elements.publishQueueList.innerHTML = publishQueue.map((draft, index) => `
    <article class="publish-queue-item">
      <label class="publish-check" aria-label="Select ${escapeHtml(draft.proposed_question_id)}">
        <input type="checkbox" data-publish-select="${draft.draft_id}" ${selectedPublishDraftIds.has(draft.draft_id) ? 'checked' : ''} />
      </label>
      <div class="publish-queue-main">
        <div class="publish-queue-title">
          <div>
            <span class="eyebrow">Ready ${index + 1}</span>
            <h3>${escapeHtml(draft.proposed_question_id || 'Verified draft')}</h3>
          </div>
          <span class="chip">Answer ${escapeHtml(draft.correct_answer || '—')}</span>
        </div>
        <p>${escapeHtml(draft.question_text || '')}</p>
        <div class="draft-quick-status">
          <span>${escapeHtml(draft.subject_id || 'No subject')}</span>
          <span>${escapeHtml(draft.topic_id || 'No topic')}</span>
          <span>${escapeHtml(draft.answer_source || 'No source')}</span>
          <span>${escapeHtml(String(draft.student_image_review_status || 'NOT_APPLICABLE').replaceAll('_', ' '))}</span>
          <span>Reviewed revision ${escapeHtml(draft.reviewed_repair_revision ?? '—')}</span>
          <span>Source-confirmed revision ${escapeHtml(draft.content_source_confirmed_revision ?? '—')}</span>
          ${Number(draft.content_repair_version || 0) > 0 ? '<span class="repair-edited-chip">Repaired content</span>' : ''}
          ${draft.source_option_anomaly === 'DUPLICATE_OPTIONS_PRINTED' ? '<span class="warning-chip">Printed duplicate options</span>' : ''}
          ${draft.is_supplemental ? '<span class="warning-chip">Supplemental</span>' : ''}
        </div>
      </div>
      <div class="publish-queue-actions">
        <button class="button button-ghost" data-publish-preview="${draft.draft_id}" type="button">Preview</button>
        <button class="button button-primary" data-publish-one="${draft.draft_id}" type="button">Publish</button>
      </div>
    </article>
  `).join('');

  elements.publishQueueList.querySelectorAll('[data-publish-select]').forEach((checkbox) => {
    checkbox.addEventListener('change', () => {
      const id = checkbox.dataset.publishSelect;
      if (checkbox.checked) selectedPublishDraftIds.add(id);
      else selectedPublishDraftIds.delete(id);
      updatePublishSelectionControls();
    });
  });
  elements.publishQueueList.querySelectorAll('[data-publish-preview]').forEach((button) => {
    button.addEventListener('click', () => openPublishPreview(button.dataset.publishPreview));
  });
  elements.publishQueueList.querySelectorAll('[data-publish-one]').forEach((button) => {
    button.addEventListener('click', () => publishSelectedQueue([button.dataset.publishOne]));
  });
  updatePublishSelectionControls();
}

async function loadPublishQueue({ reset = true } = {}) {
  if (!elements.publishQueueList) return;
  if (reset) {
    publishQueuePage = 0;
    publishQueue = [];
    publishQueueTotal = 0;
    publishQueueHasMore = false;
    selectedPublishDraftIds.clear();
    elements.publishQueueList.innerHTML = '<div class="loading-state">Loading verified publish queue…</div>';
  } else if (elements.loadMorePublishQueue) {
    elements.loadMorePublishQueue.disabled = true;
  }

  try {
    const result = await api.listPublishQueue({ page: publishQueuePage, pageSize: PUBLISH_PAGE_SIZE });
    const rows = Array.isArray(result?.items) ? result.items : [];
    const existing = new Set(publishQueue.map((draft) => draft.draft_id));
    publishQueue = [...publishQueue, ...rows.filter((draft) => !existing.has(draft.draft_id))];
    publishQueueTotal = Number(result?.total || publishQueue.length);
    publishQueueHasMore = publishQueue.length < publishQueueTotal;
    if (rows.length) publishQueuePage += 1;
    renderPublishQueue();
  } catch (error) {
    if (!publishQueue.length) elements.publishQueueList.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    toast.error(error.message);
  } finally {
    if (elements.loadMorePublishQueue) elements.loadMorePublishQueue.disabled = false;
  }
}

async function openPublishPreview(draftId) {
  elements.dialogContent.innerHTML = '<div class="review-content"><div class="loading-state">Loading verified question preview…</div></div>';
  if (!elements.dialog.open) elements.dialog.showModal();

  let draft;
  try {
    draft = await api.getDraftReview(draftId);
  } catch (error) {
    elements.dialogContent.innerHTML = `<div class="review-content"><div class="empty-state">${escapeHtml(error.message)}</div></div>`;
    toast.error(error.message);
    return;
  }

  const options = draft.options || {};
  const sourceImages = draftSourceImages(draft);
  const studentImages = draftStudentImages(draft);
  const visual = Array.isArray(draft.image_refs) && draft.image_refs.length > 0;
  const studentStatus = draft.student_image_review_status || (visual ? 'NEEDS_REVIEW' : 'NOT_APPLICABLE');
  const publishImageMarkup = studentStatus === 'SAFE_CROP_APPROVED'
    ? `<div class="final-review-image-grid">${studentImages.map((image) => `<figure class="final-review-student-image"><img loading="lazy" src="${escapeHtml(image.ref)}" alt="${escapeHtml(image.alt)}" /></figure>`).join('')}</div>`
    : studentStatus === 'NO_STUDENT_IMAGE_REQUIRED'
      ? `<div class="final-review-image-state state-no-image"><strong>No student image required ✓</strong><span>${escapeHtml(draft.student_image_review_note || 'Audited repair decision')}</span></div>`
      : '';
  elements.dialogContent.innerHTML = `
    <div class="review-content publish-preview">
      <span class="eyebrow">Final reviewed presentation · Publish Centre</span>
      <h2>${escapeHtml(draft.proposed_question_id || 'Verified draft')}</h2>
      <section class="draft-provenance-card final-review-provenance">
        <div><span class="eyebrow">Paper &amp; source identity</span><h3>Verified occurrence</h3></div>
        ${draftProvenanceMarkup(draft)}
      </section>
      ${draft.source_option_anomaly === 'DUPLICATE_OPTIONS_PRINTED' ? `<div class="import-resolution resolution-warning"><strong>Printed duplicate options</strong><span>${escapeHtml(draft.source_option_anomaly_note || 'The source prints repeated values. The human-verified answer will be published exactly as reviewed.')}</span></div>` : ''}
      <div class="simple-question-text">${escapeHtml(draft.question_text)}</div>
      ${publishImageMarkup}
      <div class="review-options publish-preview-options">
        ${['A','B','C','D'].map((key) => `
          <div class="review-option ${draft.correct_answer === key ? 'correct' : ''}">
            <strong>${key}.</strong><span>${escapeHtml(options[key])}</span>
          </div>
        `).join('')}
      </div>
      <div class="publish-preview-summary">
        <p><strong>Verified answer:</strong> ${escapeHtml(draft.correct_answer || '—')}</p>
        <p><strong>Answer source:</strong> ${escapeHtml(draft.answer_source || '—')}</p>
        <p><strong>Topic:</strong> ${escapeHtml(draft.topic_id || '—')}</p>
        <p><strong>Explanation:</strong> ${escapeHtml(draft.explanation || '—')}</p>
        <p><strong>Source-content confirmation:</strong> Revision ${escapeHtml(draft.content_source_confirmed_revision ?? '—')}</p>
      </div>
      ${sourceImages.length ? `<details class="source-review-panel"><summary>Private source / audit preview</summary><div class="source-review-images">${sourceImages.map((image) => `<img loading="lazy" src="${escapeHtml(image.ref)}" alt="${escapeHtml(image.alt)}" />`).join('')}</div></details>` : ''}
      <div class="simple-review-actions">
        <button id="publishPreviewConfirm" class="button button-primary" type="button">Publish question</button>
        <button id="publishPreviewClose" class="button button-ghost" type="button">Close</button>
      </div>
    </div>
  `;
  elements.dialogContent.querySelector('#publishPreviewClose')?.addEventListener('click', () => elements.dialog.close());
  elements.dialogContent.querySelector('#publishPreviewConfirm')?.addEventListener('click', async () => {
    elements.dialog.close();
    await publishSelectedQueue([draftId]);
  });
}

async function publishSelectedQueue(draftIds) {
  const ids = [...new Set((Array.isArray(draftIds) ? draftIds : []).filter(Boolean))];
  if (!ids.length) return toast.warning('Select at least one verified draft.');

  const selectedDrafts = ids.map((id) => publishQueue.find((draft) => draft.draft_id === id)).filter(Boolean);
  const repairedCount = selectedDrafts.filter((draft) => Number(draft.content_repair_version || 0) > 0).length;
  const safeCropCount = selectedDrafts.filter((draft) => draft.student_image_review_status === 'SAFE_CROP_APPROVED').length;
  const noImageCount = selectedDrafts.filter((draft) => ['NOT_APPLICABLE', 'NO_STUDENT_IMAGE_REQUIRED'].includes(draft.student_image_review_status)).length;
  const supplementalCount = selectedDrafts.filter((draft) => draft.is_supplemental).length;
  const anomalyCount = selectedDrafts.filter((draft) => draft.source_option_anomaly === 'DUPLICATE_OPTIONS_PRINTED').length;

  const confirmed = await requestAdminConfirmation({
    eyebrow: 'Separate Publish Centre',
    title: `Publish ${ids.length} verified question${ids.length === 1 ? '' : 's'}?`,
    message: 'Every selected draft is currently in the protected Publish Centre. Publishing creates master questions and source occurrences only after the database rechecks the current reviewed repair revision.',
    safetyTitle: 'Publication protection',
    safetyMessage: 'Image readiness, verified answer/explanation/topic, repair revision and publish eligibility are checked again on the server. A failed item remains unpublished and is reported separately.',
    buttonLabel: ids.length === 1 ? 'Confirm Publish' : `Confirm Publish (${ids.length})`,
    summaryRows: [
      ['Selected', ids.length],
      ['Image readiness', 'Resolved for all'],
      ['Repaired content', repairedCount],
      ['Safe image crops', safeCropCount],
      ['No student image', noImageCount],
      ['Supplemental', supplementalCount],
      ['Printed option anomalies', anomalyCount],
    ],
  });
  if (!confirmed) return;

  const loading = toast.loading(`Publishing 0 of ${ids.length} verified questions…`);
  let published = 0;
  let already = 0;
  const failures = [];

  try {
    for (let start = 0; start < ids.length; start += PUBLISH_CHUNK_SIZE) {
      const chunkIds = ids.slice(start, start + PUBLISH_CHUNK_SIZE);
      loading.update?.(`Publishing ${Math.min(start + chunkIds.length, ids.length)} of ${ids.length} verified questions…`);
      const result = await api.publishVerifiedDrafts(chunkIds);
      published += Number(result?.published || 0);
      already += Number(result?.already_published || 0);
      (result?.items || []).filter((item) => item.status === 'FAILED').forEach((item) => failures.push(item));
    }

    selectedPublishDraftIds.clear();
    await Promise.all([loadPublishQueue({ reset: true }), loadDrafts({ reset: true }), loadAdminTaskInbox()]);
    loading.close();

    if (failures.length) {
      toast.warning(`${published} published, ${already} already published, ${failures.length} failed. The failed drafts remain in the Publish Centre.`);
    } else {
      toast.success(`${published} question${published === 1 ? '' : 's'} published${already ? ` · ${already} already published` : ''}.`);
    }
  } catch (error) {
    loading.close();
    toast.error(error.message);
    await Promise.all([loadPublishQueue({ reset: true }), loadAdminTaskInbox()]);
  }
}

function imageRepairFilters() {
  const values = Object.fromEntries(new FormData(elements.imageRepairFilters).entries());
  return {
    status: values.status || 'NEEDS_REPAIR',
    search: values.search || '',
    paperCode: values.paperCode || '',
    shiftNo: values.shiftNo || '',
    sectionCode: values.sectionCode || '',
    originalQuestionNo: values.originalQuestionNo || '',
  };
}

function renderImageRepairStats() {
  if (!elements.imageRepairStats) return;
  const cards = [
    ['Repair candidates', imageRepairSummary.total_candidates || 0, 'all'],
    ['Needs repair', imageRepairSummary.needs_repair || 0, 'needs-repair'],
    ['Content requested', imageRepairSummary.content_needs_repair || 0, 'content-repair'],
    ['Image needs work', imageRepairSummary.image_needs_repair || 0, 'image-repair'],
    ['Pending crop', imageRepairSummary.pending || 0, 'pending'],
    ['Image approved', imageRepairSummary.approved || 0, 'approved'],
    ['No image needed', imageRepairSummary.no_image_required || 0, 'no-image-required'],
    ['Repaired content', imageRepairSummary.content_ready || imageRepairSummary.content_edited || 0, 'content-ready'],
  ];
  elements.imageRepairStats.innerHTML = cards.map(([label, value, status]) => `
    <button class="image-repair-stat" data-repair-stat="${status}" type="button">
      <strong>${Number(value)}</strong><span>${escapeHtml(label)}</span>
    </button>
  `).join('');
  elements.imageRepairStats.querySelectorAll('[data-repair-stat]').forEach((button) => {
    button.addEventListener('click', () => {
      const mapping = {
        'needs-repair': 'NEEDS_REPAIR',
        'content-repair': 'CONTENT_REPAIR',
        'image-repair': 'IMAGE_REPAIR',
        pending: 'PENDING',
        approved: 'APPROVED',
        'no-image-required': 'NO_IMAGE_REQUIRED',
        'content-ready': 'CONTENT_READY',
        all: 'ALL',
      };
      elements.imageRepairStatus.value = mapping[button.dataset.repairStat] || 'ALL';
      loadImageRepairQueue({ reset: true });
    });
  });
}

function imageRepairPaperLabel(item) {
  const parts = [];
  if (item.exam_year) parts.push(String(item.exam_year));
  if (item.paper_code) parts.push(String(item.paper_code));
  if (item.shift_no) parts.push(`Shift ${item.shift_no}`);
  if (item.original_question_no) parts.push(`Q${item.original_question_no}`);
  return parts.join(' · ') || item.subject_name || item.subject_id || 'Draft';
}

function draftProvenanceMarkup(draft) {
  const rows = [
    ['Board', draft.board_id],
    ['Exam', [draft.exam_id, draft.exam_year].filter(Boolean).join(' · ')],
    ['Date', draft.exam_date],
    ['Paper', draft.paper_code],
    ['Shift', draft.shift_no ? `Shift ${draft.shift_no}` : ''],
    ['Section', draft.section_code],
    ['Original question', draft.original_question_no ? `Q${draft.original_question_no}` : ''],
    ['Source page', draft.source_page ? `Page ${draft.source_page}` : ''],
    ['Source question ID', draft.source_question_id],
    ['Source file', draft.source_file_id],
  ].filter(([, value]) => value !== null && value !== undefined && String(value).trim() !== '');

  if (!rows.length) {
    return '<div class="draft-provenance-empty">No paper/source metadata was supplied for this draft.</div>';
  }

  return `<dl class="draft-provenance-grid">${rows.map(([label, value]) => `
    <div><dt>${escapeHtml(label)}</dt><dd>${escapeHtml(value)}</dd></div>
  `).join('')}</dl>`;
}

function renderImageRepairQueue() {
  if (!elements.imageRepairList) return;
  renderAdminDashboard();
  const activeStatus = elements.imageRepairStatus?.value || 'NEEDS_REPAIR';
  elements.imageRepairQueueMeta.textContent = `${imageRepairTotal} ${activeStatus.toLowerCase().replaceAll('_', ' ')} repair candidate${imageRepairTotal === 1 ? '' : 's'} · ${imageRepairItems.length} loaded.`;
  elements.loadMoreImageRepairs?.classList.toggle('hidden', !imageRepairHasMore);
  renderImageRepairStats();

  if (!imageRepairItems.length) {
    elements.imageRepairList.innerHTML = '<div class="empty-state">No draft matches these repair filters.</div>';
    return;
  }

  elements.imageRepairList.innerHTML = imageRepairItems.map((item) => {
    const status = String(item.repair_status || 'NEEDS_REPAIR').toLowerCase().replaceAll('_', '-');
    return `
      <article class="image-repair-item">
        <div class="image-repair-item-main">
          <div class="image-repair-item-head">
            <div>
              <span class="eyebrow">${escapeHtml(imageRepairPaperLabel(item))}</span>
              <h3>${escapeHtml(item.proposed_question_id || 'Draft question')}</h3>
            </div>
            <span class="image-repair-status status-${status}">${escapeHtml(String(item.repair_status || '').replaceAll('_', ' '))}</span>
          </div>
          <p>${escapeHtml(item.question_text || '')}</p>
          <div class="draft-quick-status">
            <span>${escapeHtml(item.subject_name || item.subject_id || 'No subject')}</span>
            <span>${Number(item.source_image_count || 0) ? `${Number(item.source_image_count)} source image${Number(item.source_image_count) === 1 ? '' : 's'}` : 'Non-visual draft'}</span>
            ${item.content_repair_status === 'NEEDS_REPAIR' ? `<span class="warning-chip">${escapeHtml(String(item.content_repair_reason_code || 'CONTENT_REPAIR').replaceAll('_', ' '))}</span>` : ''}
            ${Number(item.content_repair_version || 0) > 0 ? '<span class="repair-edited-chip">Content edited</span>' : ''}
            ${item.correct_answer ? `<span>Answer ${escapeHtml(item.correct_answer)}</span>` : '<span>Answer missing</span>'}
            <span>${escapeHtml(item.topic_id || 'Topic missing')}</span>
            <span>Revision ${Number(item.repair_revision || 0)}</span>
          </div>
        </div>
        <button class="button ${['APPROVED', 'NO_IMAGE_REQUIRED'].includes(item.repair_status) ? 'button-secondary' : 'button-primary'}" data-open-image-repair="${escapeHtml(item.draft_id)}" type="button">
          ${item.repair_status === 'CONTENT_REPAIR'
            ? 'Repair content'
            : item.repair_status === 'CONTENT_READY'
              ? 'Inspect repaired content'
              : item.repair_status === 'APPROVED'
            ? 'Inspect repaired draft'
            : item.repair_status === 'NO_IMAGE_REQUIRED'
              ? 'Inspect decision'
              : item.repair_status === 'PENDING'
                ? 'Review pending crop'
                : 'Repair draft'}
        </button>
      </article>
    `;
  }).join('');

  elements.imageRepairList.querySelectorAll('[data-open-image-repair]').forEach((button) => {
    button.addEventListener('click', () => openImageRepair(button.dataset.openImageRepair));
  });
}

async function loadImageRepairQueue({ reset = true } = {}) {
  if (!elements.imageRepairList) return;
  if (reset) {
    imageRepairPage = 0;
    imageRepairItems = [];
    imageRepairTotal = 0;
    imageRepairHasMore = false;
    elements.imageRepairList.innerHTML = '<div class="loading-state">Loading content and image repair candidates…</div>';
  } else if (elements.loadMoreImageRepairs) {
    elements.loadMoreImageRepairs.disabled = true;
  }

  try {
    const result = await api.listDraftImageRepairQueue({
      ...imageRepairFilters(),
      page: imageRepairPage,
      pageSize: IMAGE_REPAIR_PAGE_SIZE,
    });
    const rows = Array.isArray(result?.items) ? result.items : [];
    const existing = new Set(imageRepairItems.map((item) => item.draft_id));
    imageRepairItems = [...imageRepairItems, ...rows.filter((item) => !existing.has(item.draft_id))];
    imageRepairTotal = Number(result?.total || imageRepairItems.length);
    imageRepairSummary = result?.summary || imageRepairSummary;
    imageRepairHasMore = imageRepairItems.length < imageRepairTotal;
    if (rows.length) imageRepairPage += 1;
    renderImageRepairQueue();
  } catch (error) {
    if (!imageRepairItems.length) elements.imageRepairList.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    toast.error(error.message);
  } finally {
    if (elements.loadMoreImageRepairs) elements.loadMoreImageRepairs.disabled = false;
  }
}

function setRepairQueueMode(mode, { focus = false } = {}) {
  activeRepairQueue = mode === 'published' ? 'published' : 'draft';
  document.querySelectorAll('[data-repair-queue-tab]').forEach((tab) => {
    const active = tab.dataset.repairQueueTab === activeRepairQueue;
    tab.classList.toggle('is-active', active);
    tab.setAttribute('aria-selected', active ? 'true' : 'false');
    tab.tabIndex = active ? 0 : -1;
  });
  document.querySelectorAll('[data-repair-queue-panel]').forEach((panel) => {
    panel.hidden = panel.dataset.repairQueuePanel !== activeRepairQueue;
  });
  if (focus) document.querySelector(`[data-repair-queue-panel="${activeRepairQueue}"]`)?.focus();
}

function publishedImageRepairFilters() {
  if (!elements.publishedImageRepairFilters) return {};
  const values = Object.fromEntries(new FormData(elements.publishedImageRepairFilters).entries());
  return {
    status: values.status || 'NEEDS_REPAIR',
    search: values.search || '',
    paperCode: values.paperCode || '',
    shiftNo: values.shiftNo || '',
    sectionCode: values.sectionCode || '',
    originalQuestionNo: values.originalQuestionNo || '',
  };
}

function renderPublishedImageRepairStats() {
  if (!elements.publishedImageRepairStats) return;
  const cards = [
    ['Published visual', publishedImageRepairSummary.total_candidates || 0, 'ALL'],
    ['Needs decision', publishedImageRepairSummary.needs_repair || 0, 'NEEDS_REPAIR'],
    ['Pending crop', publishedImageRepairSummary.pending || 0, 'PENDING'],
    ['Image approved', publishedImageRepairSummary.approved || 0, 'APPROVED'],
    ['No image needed', publishedImageRepairSummary.no_image_required || 0, 'NO_IMAGE_REQUIRED'],
  ];
  elements.publishedImageRepairStats.innerHTML = cards.map(([label, value, status]) => `
    <button class="image-repair-stat" data-published-repair-stat="${status}" type="button">
      <strong>${Number(value)}</strong><span>${escapeHtml(label)}</span>
    </button>
  `).join('');
  elements.publishedImageRepairStats.querySelectorAll('[data-published-repair-stat]').forEach((button) => {
    button.addEventListener('click', () => {
      elements.publishedImageRepairStatus.value = button.dataset.publishedRepairStat || 'ALL';
      loadPublishedImageRepairQueue({ reset: true });
    });
  });
}

function renderPublishedImageRepairQueue() {
  if (!elements.publishedImageRepairList) return;
  const activeStatus = elements.publishedImageRepairStatus?.value || 'NEEDS_REPAIR';
  if (elements.publishedImageRepairQueueMeta) {
    elements.publishedImageRepairQueueMeta.textContent = `${publishedImageRepairTotal} ${activeStatus.toLowerCase().replaceAll('_', ' ')} published question${publishedImageRepairTotal === 1 ? '' : 's'} · ${publishedImageRepairItems.length} loaded.`;
  }
  elements.loadMorePublishedImageRepairs?.classList.toggle('hidden', !publishedImageRepairHasMore);
  renderPublishedImageRepairStats();

  if (!publishedImageRepairItems.length) {
    elements.publishedImageRepairList.innerHTML = '<div class="empty-state">No published visual question matches these filters.</div>';
    return;
  }

  elements.publishedImageRepairList.innerHTML = publishedImageRepairItems.map((item) => {
    const status = String(item.repair_status || 'NEEDS_REPAIR').toLowerCase().replaceAll('_', '-');
    return `
      <article class="image-repair-item published-image-repair-item">
        <div class="image-repair-item-main">
          <div class="image-repair-item-head">
            <div>
              <span class="eyebrow">${escapeHtml(imageRepairPaperLabel(item))}</span>
              <h3>${escapeHtml(item.question_id || 'Published question')}</h3>
            </div>
            <span class="image-repair-status status-${status}">${escapeHtml(String(item.repair_status || '').replaceAll('_', ' '))}</span>
          </div>
          <p>${escapeHtml(item.question_text || '')}</p>
          <div class="draft-quick-status">
            <span>${escapeHtml(item.subject_name || item.subject_id || 'No subject')}</span>
            <span>${Number(item.source_image_count || 0)} private source image${Number(item.source_image_count || 0) === 1 ? '' : 's'}</span>
            <span>${Number(item.student_image_count || 0)} approved student image${Number(item.student_image_count || 0) === 1 ? '' : 's'}</span>
          </div>
        </div>
        <button class="button ${['APPROVED', 'NO_IMAGE_REQUIRED'].includes(item.repair_status) ? 'button-secondary' : 'button-primary'}" data-open-published-image-repair="${escapeHtml(item.question_id)}" type="button">
          ${item.repair_status === 'PENDING'
            ? 'Review pending crop'
            : item.repair_status === 'APPROVED'
              ? 'Inspect approved image'
              : item.repair_status === 'NO_IMAGE_REQUIRED'
                ? 'Inspect decision'
                : 'Resolve image safety'}
        </button>
      </article>
    `;
  }).join('');

  elements.publishedImageRepairList.querySelectorAll('[data-open-published-image-repair]').forEach((button) => {
    button.addEventListener('click', () => openPublishedImageRepair(button.dataset.openPublishedImageRepair));
  });
}

async function loadPublishedImageRepairQueue({ reset = true } = {}) {
  if (!elements.publishedImageRepairList) return;
  if (reset) {
    publishedImageRepairPage = 0;
    publishedImageRepairItems = [];
    publishedImageRepairTotal = 0;
    publishedImageRepairHasMore = false;
    elements.publishedImageRepairList.innerHTML = '<div class="loading-state">Loading published image-safety tasks…</div>';
  } else if (elements.loadMorePublishedImageRepairs) {
    elements.loadMorePublishedImageRepairs.disabled = true;
  }

  try {
    const result = await api.listStudentImageRepairQueue({
      ...publishedImageRepairFilters(),
      page: publishedImageRepairPage,
      pageSize: IMAGE_REPAIR_PAGE_SIZE,
    });
    const rows = Array.isArray(result?.items) ? result.items : [];
    const existing = new Set(publishedImageRepairItems.map((item) => item.question_id));
    publishedImageRepairItems = [...publishedImageRepairItems, ...rows.filter((item) => !existing.has(item.question_id))];
    publishedImageRepairTotal = Number(result?.total || publishedImageRepairItems.length);
    publishedImageRepairSummary = result?.summary || publishedImageRepairSummary;
    publishedImageRepairHasMore = publishedImageRepairItems.length < publishedImageRepairTotal;
    if (rows.length) publishedImageRepairPage += 1;
    renderPublishedImageRepairQueue();
  } catch (error) {
    if (!publishedImageRepairItems.length) {
      elements.publishedImageRepairList.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    }
    toast.error(error.message);
  } finally {
    if (elements.loadMorePublishedImageRepairs) elements.loadMorePublishedImageRepairs.disabled = false;
  }
}

function repairImageMarkup(items, label) {
  const images = (Array.isArray(items) ? items : []).map((item) => {
    if (item?.blocked) return null;
    const raw = typeof item === 'string' ? item : item?.url || item?.ref;
    const url = safePreviewUrl(raw);
    return url ? { url, alt: item?.alt || label } : null;
  }).filter(Boolean);
  if (!images.length) return '<div class="empty-state compact">No previewable image is available.</div>';
  return images.map((image, index) => `
    <figure class="image-repair-preview-frame">
      <img src="${escapeHtml(image.url)}" alt="${escapeHtml(image.alt || `${label} ${index + 1}`)}" loading="lazy" />
    </figure>
  `).join('');
}

function repairHistoryMarkup(repairs) {
  if (!repairs.length) return '<p class="muted">No crop has been uploaded yet.</p>';
  return repairs.map((repair) => `
    <div class="image-repair-history-row">
      <span class="image-repair-status status-${escapeHtml(String(repair.status).toLowerCase())}">${escapeHtml(repair.status)}</span>
      <span>${escapeHtml(repair.original_file_name)}</span>
      <span>${repair.pixel_width || '—'} × ${repair.pixel_height || '—'} px</span>
      <span>${repair.approved_at ? `Approved ${escapeHtml(new Date(repair.approved_at).toLocaleString())}` : `Uploaded ${escapeHtml(new Date(repair.created_at).toLocaleString())}`}</span>
    </div>
  `).join('');
}

function decisionHistoryMarkup(decisions) {
  if (!decisions.length) return '';
  return decisions.map((decision) => `
    <div class="image-repair-history-row image-decision-history-row">
      <span class="image-repair-status status-${escapeHtml(String(decision.status).toLowerCase())}">${escapeHtml(decision.status)}</span>
      <span>${escapeHtml(String(decision.decision || '').replaceAll('_', ' '))}</span>
      <span>${escapeHtml(decision.admin_note || 'No note')}</span>
      <span>${decision.decided_at ? escapeHtml(new Date(decision.decided_at).toLocaleString()) : '—'}</span>
    </div>
  `).join('');
}

async function completePublishedImageRepairAction({ questionId, loadingText, successText, action }) {
  const loading = toast.loading(loadingText);
  try {
    const result = await action();
    loading.close();
    if (result?.cleanup_warning) {
      toast.warning(`${successText} Old private storage cleanup needs a retry, but it is no longer student-ready.`);
    } else {
      toast.success(successText);
    }
    await Promise.all([
      loadPublishedImageRepairQueue({ reset: true }),
      loadAdminTaskInbox(),
    ]);
    await openPublishedImageRepair(questionId);
  } catch (error) {
    loading.close();
    toast.error(error.message);
    await openPublishedImageRepair(questionId);
  }
}

async function confirmPublishedImageRepairAction({ questionId, title, message, buttonLabel, action, loadingText, successText }) {
  elements.imageRepairDialog.close();
  const confirmed = await requestAdminConfirmation({
    eyebrow: 'Published image-safety confirmation',
    title,
    message,
    safetyTitle: 'Published master question remains protected',
    safetyMessage: 'This audited image decision never edits the published question text or answer. Student tests use the master question only when its current image state is student-ready.',
    buttonLabel,
  });
  if (!confirmed) return openPublishedImageRepair(questionId);
  return completePublishedImageRepairAction({ questionId, loadingText, successText, action });
}

function renderPublishedImageRepairDetail(detail) {
  const question = detail.question || {};
  const repairs = Array.isArray(detail.repairs) ? detail.repairs : [];
  const decisions = Array.isArray(detail.decisions) ? detail.decisions : [];
  const pending = repairs.find((repair) => repair.status === 'PENDING');
  const approved = repairs.find((repair) => repair.status === 'APPROVED');
  const reviewStatus = question.student_image_review_status || 'NEEDS_REVIEW';
  const noImageRequired = reviewStatus === 'NO_STUDENT_IMAGE_REQUIRED';
  const visibleStatus = pending
    ? 'PENDING CROP'
    : noImageRequired
      ? 'NO IMAGE REQUIRED'
      : reviewStatus === 'SAFE_CROP_APPROVED'
        ? 'IMAGE APPROVED'
        : 'IMAGE DECISION REQUIRED';
  const visibleStatusClass = pending
    ? 'pending'
    : noImageRequired
      ? 'no-image-required'
      : reviewStatus === 'SAFE_CROP_APPROVED'
        ? 'approved'
        : 'needs-repair';
  const approvedPreview = safePreviewUrl(approved?.preview_url);
  const currentStudentImageMarkup = noImageRequired
    ? `<div class="student-no-image-decision"><strong>No student image required</strong><span>${escapeHtml(question.student_image_review_note || 'Audited decision recorded.')}</span></div>`
    : approvedPreview
      ? `<figure class="image-repair-preview-frame student-crop"><img src="${escapeHtml(approvedPreview)}" alt="${escapeHtml(approved.alt_text || 'Approved student-safe question image')}" loading="lazy" /></figure>`
      : '<div class="empty-state compact">Students currently receive no image from this question.</div>';
  const defaultAlt = pending?.alt_text || approved?.alt_text || `Diagram for ${question.question_id || 'published question'}`;
  const defaultNote = pending?.admin_note || question.student_image_review_note || '';
  const options = question.options || {};

  elements.imageRepairDialogContent.innerHTML = `
    <div class="review-content image-repair-detail published-image-repair-workspace">
      <div class="image-repair-detail-head">
        <div>
          <span class="eyebrow">${escapeHtml(imageRepairPaperLabel(question))}</span>
          <h2>${escapeHtml(question.question_id || 'Published image safety')}</h2>
          <div class="draft-quick-status"><span>${escapeHtml(question.subject_name || question.subject_id || 'No subject')}</span><span>Published master question</span></div>
        </div>
        <span class="image-repair-status status-${visibleStatusClass}">${visibleStatus}</span>
      </div>

      <div class="image-repair-source-warning">
        <strong>Image safety only</strong>
        <span>The published stem and options are read-only. This workspace resolves only the private-source → student-safe image decision.</span>
      </div>

      <section class="draft-provenance-card">
        <div><span class="eyebrow">Paper &amp; source identity</span><h3>Published master record</h3></div>
        ${draftProvenanceMarkup(question)}
      </section>

      <div class="draft-repair-layout published-image-safety-layout">
        <section class="draft-repair-editor-card published-question-readonly">
          <div class="repair-card-heading"><div><span class="eyebrow">Read-only content</span><h3>Published student question</h3></div><span class="chip">Locked</span></div>
          <div class="simple-question-text">${escapeHtml(question.question_text || '')}</div>
          <div class="student-preview-options">
            ${['A','B','C','D'].map((key) => `<div><strong>${key}</strong><span>${escapeHtml(options[key] || '')}</span></div>`).join('')}
          </div>
        </section>

        <section class="draft-repair-media-card">
          <div class="repair-card-heading"><div><span class="eyebrow">Image safety</span><h3>Source → student-safe presentation</h3></div></div>
          <div class="repair-media-tabs" role="tablist" aria-label="Published image views">
            <button class="repair-media-tab is-active" type="button" data-repair-media-tab="source">Private source</button>
            <button class="repair-media-tab" type="button" data-repair-media-tab="student">Student-safe</button>
          </div>
          <div class="repair-media-panels">
            <div class="repair-media-panel is-active" data-repair-media-panel="source"><strong>Private source capture</strong><div class="repair-media-images">${repairImageMarkup(question.source_image_refs || [], 'Original source capture')}</div></div>
            <div class="repair-media-panel" data-repair-media-panel="student"><strong>Current student result</strong><div class="repair-media-images">${currentStudentImageMarkup}</div></div>
          </div>

          <form id="publishedStudentImageForm" class="student-image-upload-form" novalidate>
            <label>Student-safe crop
              <input id="publishedStudentImageFile" name="studentImageFile" type="file" accept="image/png,image/jpeg,image/webp" ${pending ? 'disabled' : ''} />
            </label>
            <label>Accessible image description
              <input id="publishedStudentImageAltText" name="studentImageAltText" value="${escapeHtml(defaultAlt)}" placeholder="Describe only the diagram/table/graph students need" />
            </label>
            <label>Image-safety note
              <textarea id="publishedStudentImageAdminNote" name="studentImageAdminNote" rows="2" placeholder="Why this crop/decision is safe">${escapeHtml(defaultNote)}</textarea>
            </label>
            <div id="localPublishedStudentImagePreview" class="local-student-image-preview hidden"></div>
            <div class="image-repair-action-row">
              ${pending
                ? `<button id="approvePublishedStudentImage" class="button button-primary" type="button">Approve pending crop</button>
                   <button id="discardPublishedStudentImage" class="button button-danger" type="button">Discard pending</button>`
                : '<button class="button button-secondary" type="submit">Upload candidate crop</button>'}
              ${approved ? '<button id="removePublishedStudentImage" class="button button-danger" type="button">Remove approved image</button>' : ''}
              ${noImageRequired ? '<button id="reopenPublishedImageDecision" class="button button-ghost" type="button">Reopen image decision</button>' : ''}
              ${!pending && !noImageRequired ? '<button id="markPublishedImageNotRequired" class="button button-ghost" type="button">No student image required</button>' : ''}
            </div>
          </form>
        </section>
      </div>

      <details class="image-repair-history">
        <summary>Published image audit history (${repairs.length + decisions.length})</summary>
        <div>${decisionHistoryMarkup(decisions)}${repairHistoryMarkup(repairs)}</div>
      </details>
    </div>
  `;

  elements.imageRepairDialogContent.querySelectorAll('[data-repair-media-tab]').forEach((button) => {
    button.addEventListener('click', () => {
      const target = button.dataset.repairMediaTab;
      elements.imageRepairDialogContent.querySelectorAll('[data-repair-media-tab]').forEach((tab) => tab.classList.toggle('is-active', tab === button));
      elements.imageRepairDialogContent.querySelectorAll('[data-repair-media-panel]').forEach((panel) => panel.classList.toggle('is-active', panel.dataset.repairMediaPanel === target));
    });
  });

  const imageForm = elements.imageRepairDialogContent.querySelector('#publishedStudentImageForm');
  const fileInput = elements.imageRepairDialogContent.querySelector('#publishedStudentImageFile');
  const localPreview = elements.imageRepairDialogContent.querySelector('#localPublishedStudentImagePreview');
  const noteValue = () => elements.imageRepairDialogContent.querySelector('#publishedStudentImageAdminNote')?.value;
  const altValue = () => elements.imageRepairDialogContent.querySelector('#publishedStudentImageAltText')?.value;

  fileInput?.addEventListener('change', () => {
    if (activeRepairObjectUrl) URL.revokeObjectURL(activeRepairObjectUrl);
    activeRepairObjectUrl = '';
    const file = fileInput.files?.[0];
    if (!file) {
      localPreview?.classList.add('hidden');
      if (localPreview) localPreview.innerHTML = '';
      return;
    }
    activeRepairObjectUrl = URL.createObjectURL(file);
    if (localPreview) {
      localPreview.classList.remove('hidden');
      localPreview.innerHTML = `<strong>Local candidate preview</strong><img src="${escapeHtml(activeRepairObjectUrl)}" alt="Local student-safe crop preview" />`;
    }
  });

  imageForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (pending) return toast.warning('Approve or discard the pending crop before uploading another one.');
    const file = fileInput?.files?.[0];
    if (!file) return toast.warning('Choose a diagram/table/graph crop first.');
    setBusy(imageForm, true);
    const loading = toast.loading('Uploading private student-safe candidate…');
    try {
      const result = await api.uploadStudentImageRepair({ questionId: question.question_id, file, altText: altValue(), adminNote: noteValue() });
      loading.close();
      if (result?.cleanup_warning) toast.warning('Candidate uploaded. Previous private candidate cleanup needs a retry.');
      else toast.success('Candidate crop uploaded. Approve it to complete the published image task.');
      await Promise.all([loadPublishedImageRepairQueue({ reset: true }), loadAdminTaskInbox()]);
      await openPublishedImageRepair(question.question_id);
    } catch (error) {
      loading.close();
      toast.error(error.message);
      setBusy(imageForm, false);
    }
  });

  elements.imageRepairDialogContent.querySelector('#approvePublishedStudentImage')?.addEventListener('click', () => confirmPublishedImageRepairAction({
    questionId: question.question_id,
    title: 'Approve this published student-safe crop?',
    message: 'The approved crop becomes the only student-facing image for this published master question.',
    buttonLabel: 'Approve crop',
    loadingText: 'Approving student-safe crop…',
    successText: 'Published question image approved.',
    action: () => api.approveStudentImageRepair({ repairId: pending.repair_id, altText: altValue(), adminNote: noteValue() }),
  }));

  elements.imageRepairDialogContent.querySelector('#discardPublishedStudentImage')?.addEventListener('click', () => confirmPublishedImageRepairAction({
    questionId: question.question_id,
    title: 'Discard this pending published crop?',
    message: 'The candidate is removed and the master question remains blocked from new student material until another image decision is completed.',
    buttonLabel: 'Discard crop',
    loadingText: 'Discarding pending crop…',
    successText: 'Pending crop discarded.',
    action: () => api.discardStudentImageUpload({ repairId: pending.repair_id, adminNote: noteValue() }),
  }));

  elements.imageRepairDialogContent.querySelector('#removePublishedStudentImage')?.addEventListener('click', () => {
    const adminNote = String(noteValue() || '').trim();
    if (adminNote.length < 5) return toast.warning('Add a short reason before removing the approved image.');
    return confirmPublishedImageRepairAction({
      questionId: question.question_id,
      title: 'Remove this approved published image?',
      message: 'The master question returns to Needs Image Decision and is blocked from new student test material.',
      buttonLabel: 'Remove image',
      loadingText: 'Removing approved image…',
      successText: 'Approved image removed. A new image decision is required.',
      action: () => api.removeApprovedStudentImage({ questionId: question.question_id, adminNote }),
    });
  });

  elements.imageRepairDialogContent.querySelector('#markPublishedImageNotRequired')?.addEventListener('click', () => {
    const adminNote = String(noteValue() || '').trim();
    if (adminNote.length < 10) return toast.warning('Explain in at least 10 characters why students do not need this source image.');
    return confirmPublishedImageRepairAction({
      questionId: question.question_id,
      title: 'Confirm no student image is required?',
      message: 'Use this only when the private source image is audit evidence and the published text/options are fully understandable without it.',
      buttonLabel: 'Confirm no image needed',
      loadingText: 'Recording audited no-image decision…',
      successText: 'Published no-image-required decision recorded.',
      action: () => api.markStudentImageNotRequired({ questionId: question.question_id, adminNote }),
    });
  });

  elements.imageRepairDialogContent.querySelector('#reopenPublishedImageDecision')?.addEventListener('click', () => {
    const adminNote = String(noteValue() || '').trim();
    if (adminNote.length < 5) return toast.warning('Add a short reason before reopening image review.');
    return confirmPublishedImageRepairAction({
      questionId: question.question_id,
      title: 'Reopen this published image decision?',
      message: 'The no-image decision is revoked and the master question is blocked until a new image decision is completed.',
      buttonLabel: 'Reopen image review',
      loadingText: 'Reopening published image review…',
      successText: 'Published image decision reopened.',
      action: () => api.reopenStudentImageReview({ questionId: question.question_id, adminNote }),
    });
  });
}

async function openPublishedImageRepair(questionId) {
  if (activeRepairObjectUrl) URL.revokeObjectURL(activeRepairObjectUrl);
  activeRepairObjectUrl = '';
  elements.imageRepairDialogContent.innerHTML = '<div class="review-content"><div class="loading-state">Loading published source and student-safe image state…</div></div>';
  if (!elements.imageRepairDialog.open) elements.imageRepairDialog.showModal();
  try {
    const detail = await api.getStudentImageRepairDetail(questionId);
    renderPublishedImageRepairDetail(detail);
  } catch (error) {
    elements.imageRepairDialogContent.innerHTML = `<div class="review-content"><div class="empty-state">${escapeHtml(error.message)}</div></div>`;
    toast.error(error.message);
  }
}

async function completeImageRepairAction({ draftId, loadingText, successText, action }) {
  const loading = toast.loading(loadingText);
  try {
    const result = await action();
    loading.close();
    if (result?.cleanup_warning) toast.warning(`${successText} Old private storage cleanup needs a retry, but it is no longer student-ready.`);
    else toast.success(successText);
    await Promise.all([
      loadImageRepairQueue({ reset: true }),
      loadDrafts({ reset: true }),
      loadPublishQueue({ reset: true }),
      loadAdminTaskInbox(),
    ]);
    await openImageRepair(draftId);
  } catch (error) {
    loading.close();
    toast.error(error.message);
    await openImageRepair(draftId);
  }
}

async function confirmImageRepairAction({ draftId, title, message, buttonLabel, action, loadingText, successText }) {
  elements.imageRepairDialog.close();
  const confirmed = await requestAdminConfirmation({
    eyebrow: 'Draft repair confirmation',
    title,
    message,
    safetyTitle: 'Repair-first review boundary',
    safetyMessage: 'This action is audited. Any content or student-image change invalidates an older human review so the final presentation must be reviewed again before publishing.',
    buttonLabel,
  });
  if (!confirmed) return openImageRepair(draftId);
  return completeImageRepairAction({ draftId, loadingText, successText, action });
}

function renderImageRepairDetail(detail) {
  const question = detail.question || {};
  const repairs = Array.isArray(detail.repairs) ? detail.repairs : [];
  const decisions = Array.isArray(detail.decisions) ? detail.decisions : [];
  const pending = repairs.find((repair) => repair.status === 'PENDING');
  const approved = repairs.find((repair) => repair.status === 'APPROVED');
  const visual = draftHasSourceImages(question);
  const reviewStatus = question.student_image_review_status || (visual ? 'NEEDS_REVIEW' : 'NOT_APPLICABLE');
  const noImageRequired = reviewStatus === 'NO_STUDENT_IMAGE_REQUIRED';
  const contentNeedsRepair = question.content_repair_status === 'NEEDS_REPAIR';
  const contentReady = draftContentRepairReady(question);
  const options = question.options || {};
  const importedOptions = question.imported_options || {};
  const importedBaselineAvailable = Boolean(String(question.imported_question_text || '').trim())
    && ['A', 'B', 'C', 'D'].every((key) => String(importedOptions[key] || '').trim());
  const differsFromImported = String(question.question_text || '').trim() !== String(question.imported_question_text || '').trim()
    || ['A', 'B', 'C', 'D'].some((key) => String(options[key] || '').trim() !== String(importedOptions[key] || '').trim());
  const studentPreviewRefs = question.student_image_preview_refs || [];
  const currentStudentImageMarkup = !visual
    ? '<div class="student-no-image-decision"><strong>Student image not applicable</strong><span>This is a non-visual draft. Content repair remains fully available.</span></div>'
    : noImageRequired
    ? `<div class="student-no-image-decision"><strong>No student image required</strong><span>${escapeHtml(question.student_image_review_note || 'Audited decision recorded.')}</span></div>`
    : repairImageMarkup(studentPreviewRefs, 'Approved student-safe image');
  const defaultAlt = pending?.alt_text || approved?.alt_text || `Diagram for ${question.question_id || question.proposed_question_id}`;
  const defaultNote = pending?.admin_note || question.student_image_review_note || question.content_repair_note || '';
  const visibleStatus = contentNeedsRepair
    ? 'CONTENT REPAIR REQUIRED'
    : pending
      ? 'PENDING CROP'
      : !visual
        ? 'CONTENT READY'
        : noImageRequired
          ? 'NO IMAGE REQUIRED'
          : approved
            ? 'IMAGE APPROVED'
            : 'IMAGE REPAIR REQUIRED';
  const visibleStatusClass = contentNeedsRepair
    ? 'needs-repair'
    : pending
      ? 'pending'
      : !visual
        ? 'content-edited'
        : noImageRequired
          ? 'no-image-required'
          : approved
            ? 'approved'
            : 'needs-repair';
  const contentEdited = Number(question.content_repair_version || 0) > 0;
  const imageReady = visual
    ? ['SAFE_CROP_APPROVED', 'NO_STUDENT_IMAGE_REQUIRED'].includes(reviewStatus) && !pending
    : reviewStatus === 'NOT_APPLICABLE' && !pending;
  const presentationReady = contentReady && imageReady;
  const imageActionMarkup = visual ? `
    <form id="studentImageUploadForm" class="student-image-upload-form" novalidate>
      <label>Student-safe crop
        <input id="studentImageFile" name="studentImageFile" type="file" accept="image/png,image/jpeg,image/webp" ${pending ? 'disabled' : ''} />
      </label>
      <label>Accessible image description
        <input id="studentImageAltText" name="studentImageAltText" value="${escapeHtml(defaultAlt)}" placeholder="Describe only the diagram/table/graph students need" />
      </label>
      <label>Image repair note
        <textarea id="studentImageAdminNote" name="studentImageAdminNote" rows="2" placeholder="Why this crop/decision is safe">${escapeHtml(defaultNote)}</textarea>
      </label>
      <div id="localStudentImagePreview" class="local-student-image-preview hidden"></div>
      <div class="image-repair-action-row">
        ${pending
          ? `<button id="approveStudentImage" class="button button-primary" type="button" data-repair-id="${pending.repair_id}">Approve pending crop</button>
             <button id="discardStudentImage" class="button button-danger" type="button" data-repair-id="${pending.repair_id}">Discard pending</button>`
          : '<button id="uploadStudentImage" class="button button-secondary" type="submit">Upload candidate crop</button>'}
        ${approved ? '<button id="removeApprovedStudentImage" class="button button-danger" type="button">Remove approved image</button>' : ''}
        ${noImageRequired || approved ? '<button id="reopenStudentImageReview" class="button button-ghost" type="button">Reopen image decision</button>' : ''}
        ${!pending && !noImageRequired ? '<button id="markStudentImageNotRequired" class="button button-ghost" type="button">No student image required</button>' : ''}
      </div>
    </form>
  ` : `
    <div class="student-no-image-decision nonvisual-repair-state">
      <strong>No image action is required</strong>
      <span>This draft has no source image. Complete the requested text/options repair, then send the new revision to Final Review.</span>
    </div>
  `;

  elements.imageRepairDialogContent.innerHTML = `
    <div class="review-content image-repair-detail draft-repair-workspace">
      <div class="image-repair-detail-head">
        <div>
          <span class="eyebrow">${escapeHtml(imageRepairPaperLabel(question))}</span>
          <h2>${escapeHtml(question.proposed_question_id || question.question_id || 'Draft repair')}</h2>
          <div class="draft-quick-status">
            <span>${escapeHtml(question.subject_name || question.subject_id || 'No subject')}</span>
            <span>Repair revision ${Number(question.repair_revision || 0)}</span>
            ${contentEdited ? '<span class="repair-edited-chip">Edited during repair</span>' : '<span>Imported text unchanged</span>'}
          </div>
        </div>
        <span class="image-repair-status status-${visibleStatusClass}">${visibleStatus}</span>
      </div>

      <div class="image-repair-source-warning">
        <strong>Final Review comes after this workspace</strong>
        <span>Correct transcription/presentation issues here. Final Review remains responsible for the verified answer, explanation and topic. Raw source captures and imported text/options remain audit evidence.</span>
      </div>

      ${contentNeedsRepair ? `
        <div class="import-resolution resolution-warning content-repair-request">
          <strong>${escapeHtml(String(question.content_repair_reason_code || 'CONTENT_REPAIR').replaceAll('_', ' '))}</strong>
          <span>${escapeHtml(question.content_repair_reason_note || 'Final Review returned this draft for content repair.')}</span>
        </div>
      ` : ''}

      <section class="draft-provenance-card">
        <div><span class="eyebrow">Paper &amp; source identity</span><h3>Repair the exact draft</h3></div>
        ${draftProvenanceMarkup(question)}
      </section>

      <div class="draft-repair-layout">
        <section class="draft-repair-editor-card">
          <div class="repair-card-heading">
            <div><span class="eyebrow">Content repair</span><h3>Student-facing text &amp; options</h3></div>
            ${contentEdited ? '<span class="repair-edited-chip">Changed</span>' : ''}
          </div>
          <form id="draftContentRepairForm" class="draft-content-repair-form" novalidate>
            <label>Question text
              <textarea name="questionText" rows="6" required>${escapeHtml(question.question_text || '')}</textarea>
            </label>
            <div class="repair-option-grid">
              ${['A','B','C','D'].map((key) => `
                <label>Option ${key}
                  <textarea name="option${key}" rows="2" required>${escapeHtml(options[key] || '')}</textarea>
                </label>
              `).join('')}
            </div>
            <label>Repair note (required when saving a change)
              <textarea name="contentRepairNote" rows="2" minlength="5" placeholder="What was corrected and how it was verified">${escapeHtml(question.content_repair_note || '')}</textarea>
            </label>
            <div class="repair-editor-actions">
              <button class="button button-primary" type="submit">Save content repair</button>
              <button id="resetDraftContent" class="button button-ghost" type="button" ${importedBaselineAvailable && (differsFromImported || contentNeedsRepair) ? '' : 'disabled'}>Reset to imported</button>
            </div>
          </form>

          <details class="repair-imported-version" ${contentNeedsRepair ? 'open' : ''}>
            <summary>View immutable imported version</summary>
            <div class="imported-version-body">
              <p>${escapeHtml(question.imported_question_text || 'Imported baseline unavailable.')}</p>
              <div class="student-preview-options">
                ${['A','B','C','D'].map((key) => `<div><strong>${key}</strong><span>${escapeHtml(importedOptions[key] || '—')}</span></div>`).join('')}
              </div>
            </div>
          </details>
        </section>

        <section class="draft-repair-media-card">
          <div class="repair-card-heading">
            <div><span class="eyebrow">Image repair</span><h3>Source → student-safe presentation</h3></div>
          </div>

          <div class="repair-media-tabs" role="tablist" aria-label="Repair image views">
            <button class="repair-media-tab is-active" type="button" data-repair-media-tab="source">Source</button>
            <button class="repair-media-tab" type="button" data-repair-media-tab="student">Student-safe</button>
          </div>
          <div class="repair-media-panels">
            <div class="repair-media-panel is-active" data-repair-media-panel="source">
              <strong>Private source capture</strong>
              <div class="repair-media-images">${repairImageMarkup(question.source_image_refs || [], 'Original source capture')}</div>
            </div>
            <div class="repair-media-panel" data-repair-media-panel="student">
              <strong>Current student-safe result</strong>
              <div class="repair-media-images">${currentStudentImageMarkup}</div>
            </div>
          </div>

          <div class="student-view-preview">
            <div class="student-view-preview-head">
              <div><span class="eyebrow">Final student presentation preview</span><h3>Question preview</h3></div>
              <span class="image-repair-status status-${visibleStatusClass}">${visibleStatus}</span>
            </div>
            <div class="student-preview-question">${escapeHtml(question.question_text || '')}</div>
            ${currentStudentImageMarkup}
            <div class="student-preview-options">
              ${['A','B','C','D'].map((key) => `<div><strong>${key}</strong><span>${escapeHtml(options[key] || '')}</span></div>`).join('')}
            </div>
          </div>

          ${imageActionMarkup}
        </section>
      </div>

      <div class="repair-workspace-footer">
        <div>
          <strong>${presentationReady ? 'Ready for Final Review' : contentNeedsRepair ? 'Content repair still required' : 'Image decision still required'}</strong>
          <span>${presentationReady
            ? 'The reviewer will see this exact text/options and the resolved image state for the current revision.'
            : contentNeedsRepair
              ? 'Save complete text/options with an audit note to resolve the requested content repair.'
              : 'Resolve the student-safe image state before this visual draft can enter Final Review.'}</span>
        </div>
        ${presentationReady ? '<button id="goToFinalReview" class="button button-primary" type="button">Open Final Review</button>' : ''}
      </div>

      <details class="image-repair-history">
        <summary>Repair audit history (${repairs.length + decisions.length})</summary>
        <div>${decisionHistoryMarkup(decisions)}${repairHistoryMarkup(repairs)}</div>
      </details>
    </div>
  `;

  elements.imageRepairDialogContent.querySelectorAll('[data-repair-media-tab]').forEach((button) => {
    button.addEventListener('click', () => {
      const target = button.dataset.repairMediaTab;
      elements.imageRepairDialogContent.querySelectorAll('[data-repair-media-tab]').forEach((tab) => tab.classList.toggle('is-active', tab === button));
      elements.imageRepairDialogContent.querySelectorAll('[data-repair-media-panel]').forEach((panel) => panel.classList.toggle('is-active', panel.dataset.repairMediaPanel === target));
    });
  });

  const contentForm = elements.imageRepairDialogContent.querySelector('#draftContentRepairForm');
  contentForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!contentForm.reportValidity()) return;
    const values = Object.fromEntries(new FormData(contentForm).entries());
    if (String(values.contentRepairNote || '').trim().length < 5) {
      return toast.warning('Add a repair note of at least 5 characters before saving.');
    }
    const contentChanged = String(values.questionText || '').trim() !== String(question.question_text || '').trim()
      || ['A', 'B', 'C', 'D'].some((key) => String(values[`option${key}`] || '').trim() !== String(options[key] || '').trim());
    if (!contentChanged && !contentNeedsRepair) {
      return toast.info('No content change was detected. This repair revision remains unchanged.');
    }
    setBusy(contentForm, true);
    const loading = toast.loading('Saving content repair and invalidating any older review…');
    try {
      await api.saveDraftRepairContent({
        draftId: question.draft_id,
        expectedRepairRevision: question.repair_revision,
        questionText: values.questionText,
        options: {
          A: values.optionA,
          B: values.optionB,
          C: values.optionC,
          D: values.optionD,
        },
        adminNote: values.contentRepairNote,
      });
      loading.close();
      toast.success('Content repair saved. Final human review is required again.');
      await Promise.all([loadImageRepairQueue({ reset: true }), loadDrafts({ reset: true }), loadPublishQueue({ reset: true }), loadAdminTaskInbox()]);
      await openImageRepair(question.draft_id);
    } catch (error) {
      loading.close();
      toast.error(error.message);
      setBusy(contentForm, false);
    }
  });

  elements.imageRepairDialogContent.querySelector('#resetDraftContent')?.addEventListener('click', async () => {
    elements.imageRepairDialog.close();
    const confirmed = await requestAdminConfirmation({
      eyebrow: 'Content repair reset',
      title: 'Reset to imported question and options?',
      message: 'The immutable imported snapshot will replace the current repaired text/options. This creates a new repair revision and any previous final review becomes invalid.',
      safetyTitle: 'Audit snapshot is preserved',
      safetyMessage: 'This does not alter the original imported snapshot or raw source image.',
      buttonLabel: 'Reset to imported',
    });
    if (!confirmed) return openImageRepair(question.draft_id);
    return completeImageRepairAction({
      draftId: question.draft_id,
      loadingText: 'Resetting repaired content…',
      successText: 'Draft reset to the imported content.',
      action: () => api.resetDraftRepairContent({
        draftId: question.draft_id,
        expectedRepairRevision: question.repair_revision,
        adminNote: 'Admin reset from Image & Content Repair Centre',
      }),
    });
  });

  const imageForm = elements.imageRepairDialogContent.querySelector('#studentImageUploadForm');
  const fileInput = elements.imageRepairDialogContent.querySelector('#studentImageFile');
  const localPreview = elements.imageRepairDialogContent.querySelector('#localStudentImagePreview');

  fileInput?.addEventListener('change', () => {
    if (activeRepairObjectUrl) URL.revokeObjectURL(activeRepairObjectUrl);
    activeRepairObjectUrl = '';
    const file = fileInput.files?.[0];
    if (!file) {
      localPreview?.classList.add('hidden');
      if (localPreview) localPreview.innerHTML = '';
      return;
    }
    activeRepairObjectUrl = URL.createObjectURL(file);
    if (localPreview) {
      localPreview.classList.remove('hidden');
      localPreview.innerHTML = `<strong>Local candidate preview</strong><img src="${escapeHtml(activeRepairObjectUrl)}" alt="Local student-safe crop preview" />`;
    }
  });

  imageForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (pending) return toast.warning('Approve or discard the current pending crop before uploading another one.');
    const file = fileInput?.files?.[0];
    const altText = elements.imageRepairDialogContent.querySelector('#studentImageAltText')?.value;
    const adminNote = elements.imageRepairDialogContent.querySelector('#studentImageAdminNote')?.value;
    if (!file) return toast.warning('Choose a diagram/table/graph crop first.');
    setBusy(imageForm, true);
    const loading = toast.loading('Uploading private student-safe candidate…');
    try {
      const result = await api.uploadDraftStudentImageRepair({
        draftId: question.draft_id,
        file,
        altText,
        adminNote,
      });
      loading.close();
      if (result?.cleanup_warning) toast.warning('Candidate uploaded. Previous private candidate cleanup needs a retry.');
      else toast.success('Candidate crop uploaded. Approve it before Final Review.');
      await Promise.all([loadImageRepairQueue({ reset: true }), loadDrafts({ reset: true }), loadPublishQueue({ reset: true }), loadAdminTaskInbox()]);
      await openImageRepair(question.draft_id);
    } catch (error) {
      loading.close();
      toast.error(error.message);
      setBusy(imageForm, false);
    }
  });

  elements.imageRepairDialogContent.querySelector('#approveStudentImage')?.addEventListener('click', () => {
    const altText = elements.imageRepairDialogContent.querySelector('#studentImageAltText')?.value;
    const adminNote = elements.imageRepairDialogContent.querySelector('#studentImageAdminNote')?.value;
    return confirmImageRepairAction({
      draftId: question.draft_id,
      title: 'Approve this student-safe crop?',
      message: 'Final Review will display this approved crop as the student-facing image for the draft.',
      buttonLabel: 'Approve crop',
      loadingText: 'Approving student-safe crop…',
      successText: 'Student-safe image approved. The draft is ready for Final Review.',
      action: () => api.approveDraftStudentImageRepair({ repairId: pending.repair_id, altText, adminNote }),
    });
  });

  elements.imageRepairDialogContent.querySelector('#discardStudentImage')?.addEventListener('click', () => {
    const adminNote = elements.imageRepairDialogContent.querySelector('#studentImageAdminNote')?.value;
    return confirmImageRepairAction({
      draftId: question.draft_id,
      title: 'Discard this pending crop?',
      message: 'The pending candidate will be removed and the draft will remain blocked until another student-image decision is completed.',
      buttonLabel: 'Discard crop',
      loadingText: 'Discarding pending crop…',
      successText: 'Pending crop discarded.',
      action: () => api.discardDraftStudentImageUpload({ repairId: pending.repair_id, adminNote }),
    });
  });

  elements.imageRepairDialogContent.querySelector('#removeApprovedStudentImage')?.addEventListener('click', () => {
    const adminNote = elements.imageRepairDialogContent.querySelector('#studentImageAdminNote')?.value;
    if (String(adminNote || '').trim().length < 5) return toast.warning('Add a short reason before removing the approved image.');
    return confirmImageRepairAction({
      draftId: question.draft_id,
      title: 'Remove the approved student image?',
      message: 'The draft returns to Needs Repair and any previous Final Review becomes invalid.',
      buttonLabel: 'Remove image',
      loadingText: 'Removing approved image…',
      successText: 'Approved image removed. Repair is required again.',
      action: () => api.removeDraftApprovedStudentImage({ draftId: question.draft_id, adminNote }),
    });
  });

  elements.imageRepairDialogContent.querySelector('#markStudentImageNotRequired')?.addEventListener('click', () => {
    const adminNote = elements.imageRepairDialogContent.querySelector('#studentImageAdminNote')?.value;
    if (String(adminNote || '').trim().length < 10) return toast.warning('Explain in at least 10 characters why students do not need this source image.');
    return confirmImageRepairAction({
      draftId: question.draft_id,
      title: 'Confirm that no student image is required?',
      message: 'Use this only when the source capture is audit evidence but the question is fully understandable from the final text/options alone.',
      buttonLabel: 'Confirm no image needed',
      loadingText: 'Recording audited no-image decision…',
      successText: 'No-student-image decision recorded. The draft is ready for Final Review.',
      action: () => api.markDraftStudentImageNotRequired({ draftId: question.draft_id, adminNote }),
    });
  });

  elements.imageRepairDialogContent.querySelector('#reopenStudentImageReview')?.addEventListener('click', () => {
    const adminNote = elements.imageRepairDialogContent.querySelector('#studentImageAdminNote')?.value;
    if (String(adminNote || '').trim().length < 5) return toast.warning('Add a short reason before reopening image review.');
    return confirmImageRepairAction({
      draftId: question.draft_id,
      title: 'Reopen this image decision?',
      message: 'The current image decision will be revoked, the draft returns to Needs Repair, and any previous Final Review becomes invalid.',
      buttonLabel: 'Reopen repair',
      loadingText: 'Reopening image repair…',
      successText: 'Image decision reopened.',
      action: () => api.reopenDraftStudentImageReview({ draftId: question.draft_id, adminNote }),
    });
  });

  elements.imageRepairDialogContent.querySelector('#goToFinalReview')?.addEventListener('click', async () => {
    elements.imageRepairDialog.close();
    await loadDrafts({ reset: true });
    await openReview(question.draft_id);
  });
}

async function openImageRepair(draftId) {
  if (activeRepairObjectUrl) URL.revokeObjectURL(activeRepairObjectUrl);
  activeRepairObjectUrl = '';
  elements.imageRepairDialogContent.innerHTML = '<div class="review-content"><div class="loading-state">Loading draft source, repaired content and student-safe image state…</div></div>';
  if (!elements.imageRepairDialog.open) elements.imageRepairDialog.showModal();
  try {
    const detail = await api.getDraftImageRepairDetail(draftId);
    renderImageRepairDetail(detail);
  } catch (error) {
    elements.imageRepairDialogContent.innerHTML = `<div class="review-content"><div class="empty-state">${escapeHtml(error.message)}</div></div>`;
    toast.error(error.message);
  }
}

async function openNextAvailableDraft(excludeDraftId = null) {
  let nextId = nextReviewableDraftId(excludeDraftId);
  if (!nextId && draftHasMore) {
    await loadDrafts({ reset: false });
    nextId = nextReviewableDraftId(excludeDraftId);
  }
  if (!nextId) {
    toast.success('No more loaded drafts need review.');
    return;
  }
  await openReview(nextId);
}

function fillSelect(select, rows, valueKey, labelKey, placeholder) {
  if (!select) return;
  const current = select.value;
  select.innerHTML = `<option value="">${escapeHtml(placeholder)}</option>` + rows
    .filter((row) => row.status === 'ACTIVE')
    .map((row) => `<option value="${escapeHtml(row[valueKey])}">${escapeHtml(row[labelKey])}</option>`)
    .join('');
  if ([...select.options].some((option) => option.value === current)) select.value = current;
}

function refreshDraftReferenceSelects() {
  const boardSelect = document.getElementById('draftBoardId');
  const examSelect = document.getElementById('draftExamId');
  const subjectSelect = document.getElementById('draftSubjectId');
  const topicSelect = document.getElementById('draftTopicId');

  fillSelect(boardSelect, referenceData.boards, 'board_id', 'board_name', 'Select board');
  const exams = referenceData.exams.filter((row) => !boardSelect?.value || row.board_id === boardSelect.value);
  fillSelect(examSelect, exams, 'exam_id', 'exam_name', 'Select exam');
  const subjects = referenceData.subjects.filter((row) => !examSelect?.value || row.exam_id === examSelect.value);
  fillSelect(subjectSelect, subjects, 'subject_id', 'subject_name', 'Select subject');
  const topics = referenceData.topics.filter((row) => !subjectSelect?.value || row.subject_id === subjectSelect.value);
  fillSelect(topicSelect, topics, 'topic_id', 'topic_name', 'Optional topic');
}

function refreshTestReferenceSelects() {
  const boardSelect = document.getElementById('testBoardId');
  const examSelect = document.getElementById('testExamId');
  const subjectSelect = document.getElementById('testSubjectId');
  const topicSelect = document.getElementById('testTopicId');

  fillSelect(boardSelect, referenceData.boards, 'board_id', 'board_name', 'Select board');
  const exams = referenceData.exams.filter((row) => !boardSelect?.value || row.board_id === boardSelect.value);
  fillSelect(examSelect, exams, 'exam_id', 'exam_name', 'Select exam');
  const subjects = referenceData.subjects.filter((row) => !examSelect?.value || row.exam_id === examSelect.value);
  fillSelect(subjectSelect, subjects, 'subject_id', 'subject_name', 'All subjects');
  const topics = referenceData.topics.filter((row) => !subjectSelect?.value || row.subject_id === subjectSelect.value);
  fillSelect(topicSelect, topics, 'topic_id', 'topic_name', 'All topics');
}

async function loadReferenceData() {
  referenceData = await api.getAdminReferenceData();
  refreshDraftReferenceSelects();
  refreshTestReferenceSelects();
  updateTestTypeUi();
}

function isPyqTestType(testType) {
  return ['PYQ_FULL', 'PYQ_SECTIONAL'].includes(testType);
}

function testTypeRequiresSubject(testType) {
  return ['PYQ_SECTIONAL', 'SECTIONAL_MOCK', 'TOPIC_PRACTICE'].includes(testType);
}

function updateTestTypeUi() {
  const form = elements.testForm;
  if (!form) return;
  const testType = form.elements.testType.value;
  const pyq = isPyqTestType(testType);
  const paperAware = pyq || testType === 'FULL_MOCK';
  elements.testPaperFields?.classList.toggle('hidden', !paperAware);
  ['examYear', 'shiftNo', 'paperCode'].forEach((name) => {
    if (form.elements[name]) form.elements[name].required = pyq;
  });
  if (form.elements.subjectId) form.elements.subjectId.required = testTypeRequiresSubject(testType);
}

function resetQuestionPicker(message = 'Catalogue selection changed. Load matching questions again.') {
  publishedQuestions = [];
  selectedTestQuestionIds.clear();
  if (elements.testQuestionSearch) elements.testQuestionSearch.value = '';
  elements.publishedQuestionList.innerHTML = `<div class="empty-state">${escapeHtml(message)}</div>`;
  updateSelectedQuestionCount();
}

function visiblePublishedQuestions() {
  const term = String(elements.testQuestionSearch?.value || '').trim().toLowerCase();
  if (!term) return publishedQuestions;
  return publishedQuestions.filter((question) => [
    question.question_id,
    question.question_text,
    question.subject_id,
    question.topic_id,
    question.section_code,
    question.paper_code,
    question.original_question_no,
  ].some((value) => String(value ?? '').toLowerCase().includes(term)));
}

function updateSelectedQuestionCount() {
  const selected = selectedTestQuestionIds.size;
  const loaded = publishedQuestions.length;
  if (elements.selectedQuestionCount) elements.selectedQuestionCount.textContent = `${selected} selected`;
  if (elements.questionSelectionMeta) elements.questionSelectionMeta.textContent = `${loaded} loaded · ${selected} selected`;
}

function questionSourceLabel(question) {
  const parts = [];
  if (question.exam_year) parts.push(question.exam_year);
  if (question.shift_no) parts.push(`Shift ${question.shift_no}`);
  if (question.original_question_no) parts.push(`Q${question.original_question_no}`);
  return parts.join(' · ');
}

function renderPublishedQuestions() {
  if (!publishedQuestions.length) {
    elements.publishedQuestionList.innerHTML = '<div class="empty-state">No published questions match these filters.</div>';
    updateSelectedQuestionCount();
    return;
  }

  const visible = visiblePublishedQuestions();
  if (!visible.length) {
    elements.publishedQuestionList.innerHTML = '<div class="empty-state">No loaded question matches this search.</div>';
    updateSelectedQuestionCount();
    return;
  }

  elements.publishedQuestionList.innerHTML = visible.map((question, index) => {
    const source = questionSourceLabel(question);
    return `
    <label class="question-picker-item simplified-question-item">
      <input type="checkbox" data-question-id="${escapeHtml(question.question_id)}" ${selectedTestQuestionIds.has(question.question_id) ? 'checked' : ''} />
      <span class="question-order">${escapeHtml(question.sort_order || question.original_question_no || index + 1)}</span>
      <span class="question-picker-main">
        <span class="question-picker-title"><strong>${escapeHtml(question.question_id)}</strong>${source ? `<small>${escapeHtml(source)}</small>` : ''}</span>
        <span class="question-picker-meta">
          <span class="chip">${escapeHtml(question.subject_id)}</span>
          ${question.topic_id ? `<span class="chip">${escapeHtml(question.topic_id)}</span>` : ''}
          ${question.section_code ? `<span class="chip">${escapeHtml(question.section_code)}</span>` : ''}
        </span>
        <span class="question-picker-text">${escapeHtml(question.question_text)}</span>
      </span>
    </label>`;
  }).join('');

  elements.publishedQuestionList.querySelectorAll('[data-question-id]').forEach((checkbox) => {
    checkbox.addEventListener('change', () => {
      const questionId = checkbox.dataset.questionId;
      if (checkbox.checked) selectedTestQuestionIds.add(questionId);
      else selectedTestQuestionIds.delete(questionId);
      updateSelectedQuestionCount();
    });
  });
  updateSelectedQuestionCount();
}

async function loadPublishedQuestions() {
  const form = elements.testForm;
  const values = Object.fromEntries(new FormData(form).entries());
  if (!values.boardId || !values.examId) {
    return toast.warning('Select a board and exam before loading questions.');
  }
  if (testTypeRequiresSubject(values.testType) && !values.subjectId) {
    return toast.warning('Select a subject for this test type.');
  }
  if (isPyqTestType(values.testType) && (!values.examYear || !values.shiftNo || !values.paperCode)) {
    return toast.warning('For a PYQ test, enter exam year, shift and paper code to load the exact paper.');
  }

  elements.publishedQuestionList.innerHTML = '<div class="loading-state">Loading matching published questions…</div>';
  selectedTestQuestionIds.clear();
  updateSelectedQuestionCount();
  try {
    publishedQuestions = await api.listPublishedQuestions({
      boardId: values.boardId,
      examId: values.examId,
      subjectId: values.subjectId,
      topicId: values.topicId,
      questionType: isPyqTestType(values.testType) ? 'PYQ' : '',
      examYear: values.examYear,
      examDate: values.examDate,
      shiftNo: values.shiftNo,
      paperCode: values.paperCode,
      sectionCode: values.sectionCode,
      pageSize: 500,
    });
    publishedQuestions.sort((a, b) => (
      (Number(a.sort_order) || Number.MAX_SAFE_INTEGER) - (Number(b.sort_order) || Number.MAX_SAFE_INTEGER)
      || (Number(a.original_question_no) || Number.MAX_SAFE_INTEGER) - (Number(b.original_question_no) || Number.MAX_SAFE_INTEGER)
      || String(a.question_id).localeCompare(String(b.question_id))
    ));
    renderPublishedQuestions();
    toast.success(`${publishedQuestions.length} matching published question${publishedQuestions.length === 1 ? '' : 's'} loaded.`);
  } catch (error) {
    elements.publishedQuestionList.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    toast.error(error.message);
  }
}

function selectedOptionLabel(select) {
  return select?.selectedOptions?.[0]?.textContent?.trim() || '';
}

function slugPart(value) {
  return String(value || '').toUpperCase().replace(/[^A-Z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function suggestTestIdentity() {
  const form = elements.testForm;
  const values = Object.fromEntries(new FormData(form).entries());
  if (!values.boardId || !values.examId) return toast.warning('Select a board and exam first.');

  const typeCode = {
    PYQ_FULL: 'PYQ-FULL',
    PYQ_SECTIONAL: 'PYQ-SECTIONAL',
    SECTIONAL_MOCK: 'SECTIONAL',
    FULL_MOCK: 'FULL-MOCK',
    TOPIC_PRACTICE: 'TOPIC',
    DAILY_QUIZ: 'DAILY',
  }[values.testType] || values.testType;

  const idParts = [values.boardId, values.examId];
  if (values.examYear) idParts.push(values.examYear);
  if (values.shiftNo) idParts.push(`S${values.shiftNo}`);
  if (values.subjectId) idParts.push(values.subjectId);
  idParts.push(typeCode);
  const base = idParts.map(slugPart).filter(Boolean).join('-');
  const usedNumbers = configuredTests
    .map((test) => String(test.test_id || ''))
    .filter((testId) => testId.startsWith(`${base}-`))
    .map((testId) => Number(testId.match(/-(\d{4})$/)?.[1] || 0));
  const sequence = String(Math.max(0, ...usedNumbers) + 1).padStart(4, '0');
  form.elements.testId.value = `${base}-${sequence}`;

  if (!String(form.elements.testName.value || '').trim()) {
    const board = selectedOptionLabel(form.elements.boardId);
    const exam = selectedOptionLabel(form.elements.examId);
    const subject = selectedOptionLabel(form.elements.subjectId);
    const shift = values.shiftNo ? `Shift ${values.shiftNo}` : '';
    const names = {
      PYQ_FULL: [board, exam, shift, 'Full PYQ Paper'],
      PYQ_SECTIONAL: [subject, shift, 'PYQ Section'],
      SECTIONAL_MOCK: [subject, 'Sectional Mock'],
      FULL_MOCK: [board, exam, shift, 'Full Mock'],
      TOPIC_PRACTICE: [selectedOptionLabel(form.elements.topicId) || subject, 'Practice'],
      DAILY_QUIZ: [board, exam, 'Daily Quiz'],
    }[values.testType] || [board, exam, 'Test'];
    form.elements.testName.value = names.filter(Boolean).join(' — ');
  }
}

function uniqueTestCatalogueOptions(accessor) {
  const map = new Map();
  configuredTests.forEach((test) => {
    const item = accessor(test);
    const value = String(item?.value ?? '').trim();
    if (!value) return;
    if (!map.has(value)) map.set(value, String(item?.label ?? value));
  });
  return [...map.entries()].sort((a, b) => a[1].localeCompare(b[1], undefined, { numeric: true }));
}

function fillTestCatalogueSelect(select, options, allLabel) {
  if (!select) return;
  const current = select.value;
  select.innerHTML = `<option value="">${escapeHtml(allLabel)}</option>${options.map(([value, label]) => `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`).join('')}`;
  if ([...select.options].some((option) => option.value === current)) select.value = current;
}

function renderTestCatalogueFilters() {
  fillTestCatalogueSelect(elements.testTypeFilter, uniqueTestCatalogueOptions((test) => ({ value: test.test_type, label: String(test.test_type || '').replaceAll('_', ' ') })), 'All types');
  fillTestCatalogueSelect(elements.testBoardFilter, uniqueTestCatalogueOptions((test) => ({ value: test.board_id || test.boards?.board_id, label: test.boards?.board_name || test.board_id })), 'All boards');
  fillTestCatalogueSelect(elements.testExamFilter, uniqueTestCatalogueOptions((test) => ({ value: test.exam_id || test.exams?.exam_id, label: test.exams?.exam_name || test.exam_id })), 'All exams');
  fillTestCatalogueSelect(elements.testSubjectFilter, uniqueTestCatalogueOptions((test) => ({ value: test.subject_id || test.subjects?.subject_id, label: test.subjects?.subject_name || test.subject_id })), 'All subjects');
  fillTestCatalogueSelect(elements.testYearFilter, uniqueTestCatalogueOptions((test) => ({ value: test.exam_year, label: test.exam_year })), 'All years');
}

function renderTestCatalogueStats() {
  if (!elements.testCatalogueStats) return;
  const counts = configuredTests.reduce((result, test) => {
    result.ALL += 1;
    result[test.status] = (result[test.status] || 0) + 1;
    return result;
  }, { ALL: 0, DRAFT: 0, PUBLISHED: 0, ARCHIVED: 0 });
  elements.testCatalogueStats.innerHTML = [
    ['ALL', 'All tests'],
    ['DRAFT', 'Draft'],
    ['PUBLISHED', 'Published'],
    ['ARCHIVED', 'Archived'],
  ].map(([key, label]) => `<button type="button" class="test-stat-card ${elements.testStatusFilter?.value === (key === 'ALL' ? '' : key) ? 'active' : ''}" data-test-stat="${key === 'ALL' ? '' : key}"><strong>${counts[key]}</strong><span>${label}</span></button>`).join('');
  elements.testCatalogueStats.querySelectorAll('[data-test-stat]').forEach((button) => {
    button.addEventListener('click', () => {
      elements.testStatusFilter.value = button.dataset.testStat;
      renderConfiguredTests();
    });
  });
}

function filteredConfiguredTests() {
  const status = elements.testStatusFilter?.value || '';
  const type = elements.testTypeFilter?.value || '';
  const board = elements.testBoardFilter?.value || '';
  const exam = elements.testExamFilter?.value || '';
  const subject = elements.testSubjectFilter?.value || '';
  const year = elements.testYearFilter?.value || '';
  const search = String(elements.testCatalogueSearch?.value || '').trim().toLowerCase();
  return configuredTests.filter((test) => {
    if (status && test.status !== status) return false;
    if (type && test.test_type !== type) return false;
    if (board && String(test.board_id || test.boards?.board_id || '') !== board) return false;
    if (exam && String(test.exam_id || test.exams?.exam_id || '') !== exam) return false;
    if (subject && String(test.subject_id || test.subjects?.subject_id || '') !== subject) return false;
    if (year && String(test.exam_year || '') !== year) return false;
    if (!search) return true;
    return [test.test_id, test.test_name, test.test_type, test.paper_code, test.subjects?.subject_name, test.exams?.exam_name, test.boards?.board_name, test.exam_year]
      .some((value) => String(value ?? '').toLowerCase().includes(search));
  });
}

function testPaperLabel(test) {
  const parts = [];
  if (test.exam_year) parts.push(test.exam_year);
  if (test.shift_no) parts.push(`Shift ${test.shift_no}`);
  if (test.paper_code) parts.push(test.paper_code);
  if (test.section_code) parts.push(test.section_code);
  return parts.join(' · ');
}

function nextStatusAction(test) {
  if (test.status === 'DRAFT') return { label: 'Publish', status: 'PUBLISHED', className: 'button-primary' };
  if (test.status === 'PUBLISHED') return { label: 'Archive', status: 'ARCHIVED', className: 'button-ghost' };
  return { label: 'Restore draft', status: 'DRAFT', className: 'button-ghost' };
}

function renderConfiguredTests() {
  renderTestCatalogueStats();
  renderTestCatalogueFilters();
  renderAdminDashboard();
  const tests = filteredConfiguredTests();
  if (!tests.length) {
    elements.adminTestList.innerHTML = '<div class="empty-state">No configured test matches this filter.</div>';
    return;
  }

  elements.adminTestList.innerHTML = tests.map((test) => {
    const action = nextStatusAction(test);
    const paper = testPaperLabel(test);
    return `
    <article class="test-admin-item simplified-test-item">
      <div class="test-admin-card-main">
        <div class="test-admin-card-topline">
          <span class="status-pill status-${escapeHtml(test.status.toLowerCase())}">${escapeHtml(test.status)}</span>
          <span class="chip">${escapeHtml(test.test_type)}</span>
        </div>
        <h3>${escapeHtml(test.test_name)}</h3>
        <p class="test-admin-id">${escapeHtml(test.test_id)}</p>
        <div class="test-admin-facts">
          <span><strong>${escapeHtml(test.question_count)}</strong> questions</span>
          <span><strong>${escapeHtml(test.duration_minutes)}</strong> min</span>
          <span><strong>${escapeHtml(test.marks_per_question)}</strong> mark/question</span>
          ${Number(test.negative_marks) > 0 ? `<span><strong>−${escapeHtml(test.negative_marks)}</strong> negative</span>` : ''}
        </div>
        <div class="test-meta">
          ${test.boards?.board_name ? `<span class="chip">${escapeHtml(test.boards.board_name)}</span>` : ''}
          ${test.exams?.exam_name ? `<span class="chip">${escapeHtml(test.exams.exam_name)}</span>` : ''}
          ${test.subjects?.subject_name ? `<span class="chip">${escapeHtml(test.subjects.subject_name)}</span>` : ''}
          ${paper ? `<span class="chip">${escapeHtml(paper)}</span>` : ''}
        </div>
      </div>
      <div class="test-admin-actions">
        <button class="button button-secondary" data-edit-test="${escapeHtml(test.test_id)}" type="button">Edit</button>
        ${test.status === 'PUBLISHED' ? '<a class="button button-ghost" href="./student.html#tests">Student view</a>' : ''}
        <button class="button ${action.className}" data-status-test="${escapeHtml(test.test_id)}" data-next-status="${action.status}" type="button">${action.label}</button>
      </div>
    </article>`;
  }).join('');

  elements.adminTestList.querySelectorAll('[data-edit-test]').forEach((button) => {
    button.addEventListener('click', () => loadTestIntoBuilder(button.dataset.editTest));
  });
  elements.adminTestList.querySelectorAll('[data-status-test]').forEach((button) => {
    button.addEventListener('click', () => changeTestStatus(button.dataset.statusTest, button.dataset.nextStatus));
  });
}

async function loadConfiguredTests() {
  elements.adminTestList.innerHTML = '<div class="loading-state">Loading configured tests…</div>';
  try {
    configuredTests = await api.listAdminTests({ pageSize: 200 });
    renderConfiguredTests();
  } catch (error) {
    elements.adminTestList.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    toast.error(error.message);
  }
}

async function changeTestStatus(testId, status) {
  const loading = toast.loading(`Changing ${testId} to ${status.toLowerCase()}…`);
  try {
    await api.setAdminTestStatus(testId, status);
    loading.close();
    toast.success(`${testId} is now ${status}.`);
    await loadConfiguredTests();
  } catch (error) {
    loading.close();
    toast.error(error.message);
  }
}

function setTestSelectValue(name, value) {
  const field = elements.testForm?.elements?.[name];
  if (field) field.value = value ?? '';
}

async function loadTestIntoBuilder(testId) {
  const loading = toast.loading(`Loading ${testId}…`);
  try {
    const detail = await api.getAdminTestDetail(testId);
    const test = detail.test;
    const form = elements.testForm;
    form.reset();
    setTestSelectValue('testType', test.test_type);
    updateTestTypeUi();
    setTestSelectValue('boardId', test.board_id);
    refreshTestReferenceSelects();
    setTestSelectValue('examId', test.exam_id);
    refreshTestReferenceSelects();
    setTestSelectValue('subjectId', test.subject_id);
    refreshTestReferenceSelects();
    setTestSelectValue('topicId', test.topic_id);
    setTestSelectValue('testId', test.test_id);
    setTestSelectValue('testName', test.test_name);
    setTestSelectValue('examYear', test.exam_year);
    setTestSelectValue('examDate', test.exam_date);
    setTestSelectValue('shiftNo', test.shift_no);
    setTestSelectValue('paperCode', test.paper_code);
    setTestSelectValue('sectionCode', test.section_code);
    setTestSelectValue('durationMinutes', test.duration_minutes);
    setTestSelectValue('marksPerQuestion', test.marks_per_question);
    setTestSelectValue('negativeMarks', test.negative_marks);
    setTestSelectValue('sortOrder', test.sort_order);

    editingTestId = test.test_id;
    elements.testBuilderMode.textContent = `Editing ${test.test_id}`;
    elements.testBuilderMode.className = `status-pill status-${String(test.status).toLowerCase()}`;
    publishedQuestions = detail.questions;
    selectedTestQuestionIds = new Set(detail.questions.map((question) => question.question_id));
    if (elements.testQuestionSearch) elements.testQuestionSearch.value = '';
    renderPublishedQuestions();
    updateTestTypeUi();
    setAdminView('tests', { scroll: false });
    document.getElementById('testManagerSection')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    loading.close();
    toast.info('Test loaded. Save with the same ID to update it. Tests with attempts cannot change their structure.');
  } catch (error) {
    loading.close();
    toast.error(error.message);
  }
}

function resetTestBuilder() {
  const form = elements.testForm;
  form?.reset();
  editingTestId = null;
  if (elements.testBuilderMode) {
    elements.testBuilderMode.textContent = 'New test';
    elements.testBuilderMode.className = 'status-pill status-draft';
  }
  refreshTestReferenceSelects();
  updateTestTypeUi();
  resetQuestionPicker('Choose catalogue or paper filters, then load published questions.');
  setAdminView('tests', { scroll: false });
  document.getElementById('testManagerSection')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function topicOptionsForDraft(draft) {
  return referenceData.topics
    .filter((topic) => topic.status === 'ACTIVE' && topic.subject_id === draft.subject_id)
    .map((topic) => `<option value="${escapeHtml(topic.topic_id)}" ${topic.topic_id === draft.topic_id ? 'selected' : ''}>${escapeHtml(topic.topic_name)} (${escapeHtml(topic.topic_code || topic.topic_id)})</option>`)
    .join('');
}

function normalizedPreviewImages(rows, fallbackAlt) {
  return (Array.isArray(rows) ? rows : []).map((item) => {
    if (!item || item.blocked) return null;
    if (typeof item === 'string') return { ref: item, alt: fallbackAlt };
    return {
      ref: item?.url || item?.ref || '',
      alt: item?.alt || fallbackAlt,
    };
  }).filter((item) => item?.ref);
}

function draftSourceImages(draft) {
  return normalizedPreviewImages(draft?.source_image_refs || draft?.image_refs || [], 'Private source preview');
}

function draftStudentImages(draft) {
  return normalizedPreviewImages(draft?.student_image_preview_refs || draft?.student_image_refs || [], 'Student-safe question image');
}

async function focusDraftInRepair(draft, { status = '' } = {}) {
  elements.imageRepairFilters?.reset();
  const targetStatus = status || (draft?.content_repair_status === 'NEEDS_REPAIR' ? 'CONTENT_REPAIR' : 'ALL');
  if (elements.imageRepairStatus) elements.imageRepairStatus.value = targetStatus;
  if (elements.imageRepairSearch) elements.imageRepairSearch.value = draft?.proposed_question_id || draft?.display_id || '';
  setRepairQueueMode('draft');
  setAdminView('repair');
  await loadImageRepairQueue({ reset: true });
  await openImageRepair(draft.draft_id);
}

async function focusPublishedImageInRepair(task, { status = '' } = {}) {
  const questionId = task?.question_id || task?.display_id;
  if (!questionId) return toast.warning('The next published image-safety question is unavailable. Refresh Task Inbox.');
  elements.publishedImageRepairFilters?.reset();
  if (elements.publishedImageRepairStatus) {
    elements.publishedImageRepairStatus.value = status || (task?.task_status === 'PENDING' ? 'PENDING' : 'NEEDS_REPAIR');
  }
  if (elements.publishedImageRepairSearch) elements.publishedImageRepairSearch.value = questionId;
  setRepairQueueMode('published');
  setAdminView('repair');
  await loadPublishedImageRepairQueue({ reset: true });
  await openPublishedImageRepair(questionId);
}

async function openAdminTask(bucket) {
  const task = taskBucket(bucket).next;
  if (!task) return toast.info('No task is currently waiting in this queue.');

  if (bucket === 'draft_repairs') {
    return focusDraftInRepair(task, { status: task.task_status === 'CONTENT_REPAIR' ? 'CONTENT_REPAIR' : 'ALL' });
  }
  if (bucket === 'published_image_safety') {
    return focusPublishedImageInRepair(task);
  }
  if (bucket === 'final_reviews') {
    setAdminView('review');
    return openReview(task.draft_id);
  }
  if (bucket === 'ready_to_publish') {
    setAdminView('publish');
    await loadPublishQueue({ reset: true });
    return openPublishPreview(task.draft_id);
  }
}

async function openReview(draftId) {
  const listDraft = drafts.find((item) => item.draft_id === draftId);
  elements.dialogContent.innerHTML = '<div class="review-content"><div class="loading-state">Loading the final repaired student presentation…</div></div>';
  if (!elements.dialog.open) elements.dialog.showModal();

  let draft;
  try {
    draft = await api.getDraftReview(draftId);
  } catch (error) {
    elements.dialogContent.innerHTML = `<div class="review-content"><div class="empty-state">${escapeHtml(error.message)}</div></div>`;
    toast.error(error.message);
    return;
  }

  const options = draft.options || {};
  const proposedSource = draft.answer_source || 'AI_PROPOSED';
  const reviewSource = ['OFFICIAL_FINAL_KEY', 'OFFICIAL_PROVISIONAL_KEY', 'MANUALLY_VERIFIED', 'SOURCE_BOOK', 'ADMIN_CORRECTED'].includes(proposedSource)
    ? proposedSource
    : '';
  const sourceImages = draftSourceImages(draft);
  const studentImages = draftStudentImages(draft);
  const visual = Array.isArray(draft.image_refs) && draft.image_refs.length > 0;
  const imageReady = draftImageReady(draft);
  const contentReady = draftContentRepairReady(draft);
  const studentImageStatus = draft.student_image_review_status || (visual ? 'NEEDS_REVIEW' : 'NOT_APPLICABLE');
  const queuePosition = Math.max(1, reviewableDrafts().findIndex((item) => item.draft_id === draftId) + 1);
  const queueTotal = Math.max(reviewableDrafts().length, 1);

  if (!contentReady || !imageReady) {
    elements.dialogContent.innerHTML = `
      <div class="review-content repair-gate-card">
        <span class="eyebrow">Final Review blocked</span>
        <h2>${escapeHtml(draft.proposed_question_id || 'Draft question')}</h2>
        <div class="import-resolution resolution-warning">
          <strong>${contentReady ? 'Image repair must be completed first' : 'Requested content repair must be completed first'}</strong>
          <span>${contentReady
            ? `The image state is ${escapeHtml(String(studentImageStatus).replaceAll('_', ' ').toLowerCase())}. Final Review is unavailable until the student presentation is resolved.`
            : escapeHtml(draft.content_repair_reason_note || 'This draft was returned because its student-facing content is incomplete or does not match the source evidence.')}</span>
        </div>
        <div class="simple-question-text">${escapeHtml(draft.question_text || '')}</div>
        <div class="simple-review-actions">
          <button id="reviewRepairFirst" class="button button-primary" type="button">Open exact draft in Repair</button>
          <button id="reviewBlockedClose" class="button button-ghost" type="button">Close</button>
        </div>
      </div>
    `;
    elements.dialogContent.querySelector('#reviewRepairFirst')?.addEventListener('click', () => {
      elements.dialog.close();
      focusDraftInRepair(draft);
    });
    elements.dialogContent.querySelector('#reviewBlockedClose')?.addEventListener('click', () => elements.dialog.close());
    return;
  }

  if (visual && studentImageStatus === 'SAFE_CROP_APPROVED' && studentImages.length === 0) {
    elements.dialogContent.innerHTML = `
      <div class="review-content repair-gate-card">
        <span class="eyebrow">Final Review blocked</span>
        <h2>${escapeHtml(draft.proposed_question_id || 'Draft question')}</h2>
        <div class="import-resolution resolution-warning">
          <strong>Approved student image cannot be previewed</strong>
          <span>Review must show the actual repaired image. Retry from Image &amp; Content Repair before verifying this question.</span>
        </div>
        <div class="simple-review-actions">
          <button id="reviewRepairPreview" class="button button-primary" type="button">Open Image &amp; Content Repair</button>
          <button id="reviewPreviewClose" class="button button-ghost" type="button">Close</button>
        </div>
      </div>
    `;
    elements.dialogContent.querySelector('#reviewRepairPreview')?.addEventListener('click', () => {
      elements.dialog.close();
      focusDraftInRepair(draft);
    });
    elements.dialogContent.querySelector('#reviewPreviewClose')?.addEventListener('click', () => elements.dialog.close());
    return;
  }

  const finalImageMarkup = !visual
    ? '<div class="final-review-image-state state-not-applicable"><strong>Student image</strong><span>Not applicable</span></div>'
    : studentImageStatus === 'NO_STUDENT_IMAGE_REQUIRED'
      ? `<div class="final-review-image-state state-no-image"><strong>No student image required ✓</strong><span>${escapeHtml(draft.student_image_review_note || 'Audited decision recorded during repair.')}</span></div>`
      : `<div class="final-review-image-grid">${studentImages.map((image) => `<figure class="final-review-student-image"><img loading="lazy" src="${escapeHtml(image.ref)}" alt="${escapeHtml(image.alt)}" /></figure>`).join('')}</div>`;
  const contentNoteRequired = Number(draft.content_repair_version || 0) > 0
    || Boolean(draft.content_repair_reason_code)
    || ['LOW_RESOLUTION', 'CROPPED', 'DIAGRAM_REVIEW'].includes(draft.source_quality);

  elements.dialogContent.innerHTML = `
    <div class="review-content simple-review final-review-workspace">
      <div class="simple-review-head">
        <div>
          <span class="eyebrow">Final human review · ${queuePosition} of ${queueTotal} ready</span>
          <h2>${escapeHtml(draft.proposed_question_id || 'Draft question')}</h2>
        </div>
        <div class="simple-review-chips">
          <span>${escapeHtml(draft.subject_id || 'No subject')}</span>
          <span>${escapeHtml(studentImageStatus.replaceAll('_', ' '))}</span>
          ${Number(draft.content_repair_version || 0) > 0 ? '<span class="repair-edited-chip">Edited during repair</span>' : ''}
          <span>Revision ${Number(draft.repair_revision || 0)}</span>
        </div>
      </div>

      ${draft.is_supplemental ? `<div class="import-resolution resolution-warning"><strong>Supplemental normal question</strong><span>${escapeHtml(draft.supplement_reason || 'Missing source question replacement')}</span></div>` : ''}
      ${draft.source_option_anomaly === 'DUPLICATE_OPTIONS_PRINTED' ? `<div class="import-resolution resolution-warning"><strong>Printed duplicate options</strong><span>${escapeHtml(draft.source_option_anomaly_note || 'The genuine source prints repeated option values. Preserve them exactly and verify the correct answer carefully.')}</span></div>` : ''}

      <section class="draft-provenance-card final-review-provenance">
        <div><span class="eyebrow">Paper &amp; source identity</span><h3>Verify the exact occurrence</h3></div>
        ${draftProvenanceMarkup(draft)}
      </section>

      <section class="final-student-presentation">
        <div class="repair-card-heading">
          <div><span class="eyebrow">What the student will see</span><h3>Final repaired presentation</h3></div>
          <span class="image-repair-status status-${studentImageStatus === 'SAFE_CROP_APPROVED' ? 'approved' : studentImageStatus === 'NO_STUDENT_IMAGE_REQUIRED' ? 'no-image-required' : 'current'}">${escapeHtml(studentImageStatus.replaceAll('_', ' '))}</span>
        </div>
        <div class="simple-question-text">${escapeHtml(draft.question_text)}</div>
        ${finalImageMarkup}
        <div class="review-options final-review-options">
          ${['A','B','C','D'].map((key) => `
            <div class="review-option">
              <strong>${key}.</strong>
              <span>${escapeHtml(options[key])}</span>
            </div>
          `).join('')}
        </div>
      </section>

      <details class="source-review-panel final-review-source" open>
        <summary>Source evidence and immutable imported version</summary>
        ${sourceImages.length ? `<div class="source-review-images">${sourceImages.map((image) => `<img loading="lazy" src="${escapeHtml(image.ref)}" alt="${escapeHtml(image.alt)}" />`).join('')}</div>` : '<p class="muted">No source image was attached.</p>'}
        <div class="final-review-imported-copy">
          <strong>Imported question</strong>
          <p>${escapeHtml(draft.imported_question_text || draft.question_text || '')}</p>
          ${draft.imported_options ? `<div class="student-preview-options">${['A','B','C','D'].map((key) => `<div><strong>${key}</strong><span>${escapeHtml(draft.imported_options[key] || '—')}</span></div>`).join('')}</div>` : ''}
        </div>
      </details>

      <form id="draftVerificationForm" class="simple-review-form" novalidate>
        <section class="final-content-confirmation">
          <div>
            <span class="eyebrow">Mandatory content-integrity check</span>
            <h3>Confirm the complete student presentation</h3>
            <p>Compare the final stem, every referenced value/context item, and options A–D with the source image or immutable imported evidence above.</p>
          </div>
          <label class="final-content-confirmation-check">
            <input type="checkbox" name="contentConfirmed" value="SOURCE_PRESENTATION_CONFIRMED" required />
            <span><strong>I confirm this exact repair revision is complete and source-accurate.</strong><small>This confirmation is revision-bound and is invalidated by any later content or image change.</small></span>
          </label>
          <label>Content verification note${contentNoteRequired ? ' (required)' : ' (optional)'}
            <textarea name="contentReviewNote" rows="2" ${contentNoteRequired ? 'required minlength="5"' : ''} placeholder="${contentNoteRequired ? 'Explain how the repaired/flagged content was checked' : 'Optional source-content verification detail'}">${escapeHtml(draft.content_source_review_note || '')}</textarea>
          </label>
        </section>

        <fieldset class="simple-answer-fieldset">
          <legend>Confirm the correct answer</legend>
          <div class="review-options">
            ${['A','B','C','D'].map((key) => `
              <label class="review-option selectable-option ${draft.correct_answer === key ? 'correct' : ''}">
                <input type="radio" name="reviewCorrectAnswer" value="${key}" ${draft.correct_answer === key ? 'checked' : ''} />
                <strong>${key}.</strong>
                <span>${escapeHtml(options[key])}</span>
              </label>
            `).join('')}
          </div>
        </fieldset>

        <div class="simple-review-selects">
          <label>Answer source
            <select name="answerSource" required>
              <option value="" ${reviewSource ? '' : 'selected'}>Select verified answer source</option>
              <option value="MANUALLY_VERIFIED" ${reviewSource === 'MANUALLY_VERIFIED' ? 'selected' : ''}>Manually verified</option>
              <option value="OFFICIAL_FINAL_KEY" ${reviewSource === 'OFFICIAL_FINAL_KEY' ? 'selected' : ''}>Official final key</option>
              <option value="OFFICIAL_PROVISIONAL_KEY" ${reviewSource === 'OFFICIAL_PROVISIONAL_KEY' ? 'selected' : ''}>Official provisional key</option>
              <option value="SOURCE_BOOK" ${reviewSource === 'SOURCE_BOOK' ? 'selected' : ''}>Source book</option>
              <option value="ADMIN_CORRECTED" ${reviewSource === 'ADMIN_CORRECTED' ? 'selected' : ''}>Admin corrected</option>
            </select>
          </label>
          <label>Primary topic
            <select name="topicId" ${draft.question_type === 'PYQ' ? 'required' : ''}>
              <option value="">${draft.question_type === 'PYQ' ? 'Select required topic' : 'Optional topic'}</option>
              ${topicOptionsForDraft(draft)}
            </select>
          </label>
        </div>

        <details class="review-details" open>
          <summary>Explanation and notes</summary>
          <label>Reviewed explanation
            <textarea name="explanation" rows="5" required>${escapeHtml(draft.explanation || '')}</textarea>
          </label>
          <label>Answer review note
            <textarea name="answerReviewNote" rows="2" placeholder="Optional: how the answer was checked">${escapeHtml(draft.answer_review_note || '')}</textarea>
          </label>
          <label>Admin notes
            <textarea name="adminNotes" rows="2" placeholder="Optional: final review note">${escapeHtml(draft.admin_notes || '')}</textarea>
          </label>
        </details>

        <div id="finalReviewBlockers" class="final-review-blockers" aria-live="polite"></div>

        <section id="returnToRepairPanel" class="return-to-repair-panel hidden">
          <div><span class="eyebrow">Audited workflow transition</span><h3>Return this exact draft to Content Repair</h3></div>
          <label>Reason
            <select id="returnRepairReason" required disabled>
              <option value="INCOMPLETE_QUESTION">Incomplete question</option>
              <option value="MISSING_CONTEXT">Missing values or context</option>
              <option value="TRANSCRIPTION_ERROR">Transcription error</option>
              <option value="OPTION_ERROR">Option error</option>
              <option value="SOURCE_MISMATCH">Source mismatch</option>
              <option value="OTHER">Other content problem</option>
            </select>
          </label>
          <label>Repair instruction
            <textarea id="returnRepairNote" rows="3" minlength="10" placeholder="Describe exactly what is incomplete or inaccurate" required disabled></textarea>
          </label>
          <div class="button-row">
            <button id="confirmReturnToRepair" class="button button-primary" type="button">Send exact draft to Repair</button>
            <button id="cancelReturnToRepair" class="button button-ghost" type="button">Cancel</button>
          </div>
        </section>

        <div class="simple-review-actions final-review-sticky-actions">
          <button class="button button-primary" type="submit" name="reviewAction" value="SAVE_NEXT" disabled>Approve &amp; Next</button>
          <button class="button button-secondary" type="submit" name="reviewAction" value="SAVE" disabled>Approve Final Review</button>
          <button id="dialogBackToRepair" class="button button-ghost" type="button">Return for content repair</button>
          <button id="dialogReject" class="button button-danger button-small" type="button">Reject</button>
        </div>
        <p class="review-publish-handoff">This saves approval for repair revision ${Number(draft.repair_revision || 0)}. Any later content/image change invalidates this review and removes the draft from Publish Centre.</p>
      </form>

      ${draft.answer_source === 'AI_PROPOSED' ? '<p class="review-required-note">The highlighted answer is only an AI proposal. Your save changes it to the selected human-verifiable answer source.</p>' : ''}
    </div>
  `;

  const form = elements.dialogContent.querySelector('#draftVerificationForm');
  const reviewBlockers = () => {
    if (!form) return ['Final Review form is unavailable.'];
    const values = Object.fromEntries(new FormData(form).entries());
    const blockers = [];
    if (!String(draft.question_text || '').trim()) blockers.push('Question text is missing.');
    ['A', 'B', 'C', 'D'].forEach((key) => {
      if (!String(options[key] || '').trim()) blockers.push(`Option ${key} is missing.`);
    });
    if (!form.querySelector('input[name="reviewCorrectAnswer"]:checked')) blockers.push('Select the verified correct answer.');
    if (!String(values.answerSource || '').trim()) blockers.push('Select a human-verifiable answer source.');
    if (draft.question_type === 'PYQ' && !String(values.topicId || '').trim()) blockers.push('Select the required primary topic.');
    if (!String(values.explanation || '').trim()) blockers.push('Add the reviewed explanation.');
    if (values.contentConfirmed !== 'SOURCE_PRESENTATION_CONFIRMED') blockers.push('Confirm the complete final presentation against source evidence.');
    if (contentNoteRequired && String(values.contentReviewNote || '').trim().length < 5) blockers.push('Add a content-verification note for the repaired or flagged source.');
    return blockers;
  };

  const updateFinalReviewReadiness = () => {
    const blockers = reviewBlockers();
    const blockerPanel = elements.dialogContent.querySelector('#finalReviewBlockers');
    if (blockerPanel) {
      blockerPanel.innerHTML = blockers.length
        ? `<strong>Approval blocked (${blockers.length})</strong><ul>${blockers.map((item) => `<li>${escapeHtml(item)}</li>`).join('')}</ul>`
        : '<strong class="review-ready-message">All mandatory checks are complete. This revision can be approved.</strong>';
      blockerPanel.classList.toggle('is-ready', blockers.length === 0);
    }
    form?.querySelectorAll('button[type="submit"]').forEach((button) => {
      button.disabled = blockers.length > 0;
    });
    return blockers;
  };

  form?.addEventListener('input', updateFinalReviewReadiness);
  form?.addEventListener('change', updateFinalReviewReadiness);
  updateFinalReviewReadiness();

  form?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const blockers = updateFinalReviewReadiness();
    if (blockers.length) return toast.warning(blockers[0]);
    if (!form.reportValidity()) return;
    const selected = elements.dialogContent.querySelector('input[name="reviewCorrectAnswer"]:checked')?.value;
    if (!selected) return toast.warning('Select the verified correct answer.');

    const submitter = event.submitter;
    const reviewAction = submitter?.value || 'SAVE';
    const values = Object.fromEntries(new FormData(form).entries());
    setBusy(form, true);
    const loading = toast.loading(reviewAction === 'SAVE_NEXT' ? 'Saving Final Review and opening the next ready draft…' : 'Saving Final Review…');

    try {
      const saved = await api.reviewDraftAnswerTopic({
        draftId,
        expectedRepairRevision: draft.repair_revision,
        correctAnswer: selected,
        answerSource: values.answerSource,
        explanation: values.explanation,
        topicId: values.topicId,
        contentConfirmed: values.contentConfirmed === 'SOURCE_PRESENTATION_CONFIRMED',
        contentReviewNote: values.contentReviewNote,
        answerReviewNote: values.answerReviewNote,
        adminNotes: values.adminNotes,
      });

      const index = drafts.findIndex((item) => item.draft_id === draftId);
      if (index >= 0) drafts[index] = { ...drafts[index], ...saved };
      if (elements.statusFilter.value === 'PENDING') {
        drafts = drafts.filter((item) => item.draft_id !== draftId);
      }
      renderDrafts();

      await Promise.all([loadPublishQueue({ reset: true }), loadAdminTaskInbox()]);
      loading.close();
      toast.success('Final Review saved. The current repaired revision is now eligible for Publish Centre.');
      elements.dialog.close();

      if (reviewAction === 'SAVE_NEXT') {
        let nextId = nextReviewableDraftId(draftId);
        if (!nextId) {
          await loadDrafts({ reset: true });
          nextId = nextReviewableDraftId(draftId);
        }
        if (nextId) await openReview(nextId);
        else toast.success('No more repair-ready drafts need Final Review.');
      }
    } catch (error) {
      loading.close();
      toast.error(error.message);
      setBusy(form, false);
    }
  });

  const returnPanel = elements.dialogContent.querySelector('#returnToRepairPanel');
  const setReturnPanelActive = (active) => {
    returnPanel?.classList.toggle('hidden', !active);
    returnPanel?.querySelectorAll('select, textarea, button').forEach((control) => {
      control.disabled = !active;
    });
  };
  elements.dialogContent.querySelector('#dialogBackToRepair')?.addEventListener('click', () => {
    setReturnPanelActive(true);
    returnPanel?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    elements.dialogContent.querySelector('#returnRepairNote')?.focus();
  });
  elements.dialogContent.querySelector('#cancelReturnToRepair')?.addEventListener('click', () => {
    setReturnPanelActive(false);
  });
  elements.dialogContent.querySelector('#confirmReturnToRepair')?.addEventListener('click', async () => {
    const reasonCode = elements.dialogContent.querySelector('#returnRepairReason')?.value;
    const reasonNote = elements.dialogContent.querySelector('#returnRepairNote')?.value.trim();
    if (!reasonCode) return toast.warning('Choose why this draft needs content repair.');
    if (String(reasonNote || '').length < 10) return toast.warning('Describe the content problem in at least 10 characters.');

    setBusy(returnPanel, true);
    const loading = toast.loading('Recording the repair request for this exact draft…');
    try {
      const returned = await api.returnDraftToContentRepair({
        draftId,
        reasonCode,
        reasonNote,
        expectedRepairRevision: draft.repair_revision,
      });
      loading.close();
      elements.dialog.close();
      await Promise.all([loadDrafts({ reset: true }), loadPublishQueue({ reset: true }), loadAdminTaskInbox()]);
      toast.success('Draft returned to Content Repair with an audited reason.');
      await focusDraftInRepair(returned || { ...draft, content_repair_status: 'NEEDS_REPAIR' }, { status: 'CONTENT_REPAIR' });
    } catch (error) {
      loading.close();
      toast.error(error.message);
      setBusy(returnPanel, false);
    }
  });
  elements.dialogContent.querySelector('#dialogReject')?.addEventListener('click', () => openRejectDialog(draftId));

  if (listDraft?.proposed_question_id && listDraft.proposed_question_id !== draft.proposed_question_id) {
    toast.warning('The draft list changed while Final Review data was loading. The latest database version is shown.');
  }
}

async function publish(draftId) {
  return publishSelectedQueue([draftId]);
}

function openRejectDialog(draftId) {
  elements.dialogContent.innerHTML = `
    <div class="review-content">
      <span class="eyebrow">Human review decision</span>
      <h2>Reject draft</h2>
      <p>Enter a clear correction reason. The draft remains available for later repair and review.</p>
      <label>Rejection notes<textarea id="rejectionNotes" rows="5" required></textarea></label>
      <div class="draft-item-actions section">
        <button id="confirmReject" class="button button-danger" type="button">Reject with notes</button>
        <button id="cancelReject" class="button button-ghost" type="button">Cancel</button>
      </div>
    </div>
  `;
  elements.dialogContent.querySelector('#cancelReject')?.addEventListener('click', () => elements.dialog.close());
  elements.dialogContent.querySelector('#confirmReject')?.addEventListener('click', async () => {
    const notes = elements.dialogContent.querySelector('#rejectionNotes')?.value.trim();
    if (!notes) return toast.warning('Add the rejection reason before continuing.');
    elements.dialog.close();
    await reject(draftId, notes);
  });
  if (!elements.dialog.open) elements.dialog.showModal();
}

async function reject(draftId, notes) {
  const loading = toast.loading('Rejecting draft…');
  try {
    await api.rejectDraft(draftId, notes);
    loading.close();
    toast.success('Draft rejected with review notes.');
    await Promise.all([loadDrafts(), loadPublishQueue({ reset: true }), loadAdminTaskInbox()]);
  } catch (error) {
    loading.close();
    toast.error(error.message);
  }
}


function formatIssue(issueRow) {
  const code = escapeHtml(issueRow?.code || 'VALIDATION_MESSAGE');
  const message = escapeHtml(issueRow?.message || String(issueRow || 'Unknown validation message.'));
  const path = issueRow?.path ? `<code>${escapeHtml(issueRow.path)}</code>` : '';
  return `<li><strong>${code}</strong>${path}${message}</li>`;
}

function renderClientPackagePreview(parsed) {
  const validation = parsed.schemaValidation;
  const errorCount = validation.errors.length
    + validation.itemErrors.reduce((total, rows) => total + (rows?.length || 0), 0);
  const warningCount = validation.warnings.length
    + validation.itemWarnings.reduce((total, rows) => total + (rows?.length || 0), 0);
  const status = errorCount ? 'Client schema errors' : warningCount ? 'Schema valid with warnings' : 'Schema valid';
  const issueRows = [
    ...validation.errors,
    ...validation.itemErrors.flatMap((rows) => rows || []),
    ...validation.warnings,
    ...validation.itemWarnings.flatMap((rows) => rows || []),
  ];

  elements.importPackagePreview.classList.remove('hidden');
  elements.importPackagePreview.innerHTML = `
    <div class="import-preview-head">
      <div>
        <span class="eyebrow">Local safe inspection</span>
        <h3>${escapeHtml(parsed.metadata.packageId)}</h3>
      </div>
      <span class="import-status-pill ${errorCount ? 'status-error' : warningCount ? 'status-warning' : 'status-valid'}">${escapeHtml(status)}</span>
    </div>
    <div class="import-file-facts">
      <span><strong>File</strong>${escapeHtml(parsed.metadata.fileName)}</span>
      <span><strong>Size</strong>${escapeHtml(parsed.metadata.fileSizeLabel)}</span>
      <span><strong>Schema</strong>${escapeHtml(parsed.metadata.schemaVersion)}</span>
      <span><strong>Records</strong>${escapeHtml(parsed.metadata.questionCount)}</span>
      <span><strong>Package version</strong>${escapeHtml(parsed.metadata.packageVersion)}</span>
      ${parsed.metadata.paper ? `<span><strong>Declared paper</strong>${escapeHtml(parsed.metadata.paper.declared_total_questions || '—')}</span><span><strong>Missing</strong>${escapeHtml(parsed.metadata.paper.missing_question_count || 0)}</span><span><strong>Supplements</strong>${escapeHtml(parsed.metadata.paper.generated_supplement_count || 0)}</span>` : ''}
    </div>
    <div class="checksum-list">
      <div><strong>Raw HTML SHA-256</strong><code>${escapeHtml(parsed.rawChecksum)}</code></div>
      <div><strong>Canonical package SHA-256</strong><code>${escapeHtml(parsed.packageChecksum)}</code></div>
    </div>
    ${issueRows.length ? `<details class="import-issues"><summary>${errorCount} error(s), ${warningCount} warning(s)</summary><ul>${issueRows.map(formatIssue).join('')}</ul></details>` : ''}
  `;
}

function resetImportSelections() {
  selectedDraftItemIds = new Set();
  selectedOccurrenceItemIds = new Set();
  currentImportBatchId = null;
  updateImportActionControls();
}

function isDraftEligible(item) {
  return ['VALID', 'VALID_WITH_WARNINGS'].includes(item?.validation_status)
    && !item?.created_draft_id;
}

function isOccurrenceActionable(item) {
  return item?.validation_status === 'EXACT_DUPLICATE'
    && Boolean(item?.matched_question_id)
    && Boolean(item?.occurrence_key)
    && item?.resolution_action === 'NONE';
}

function syncImportSelections(report) {
  const batchId = report?.batch?.import_batch_id || null;
  const items = report?.items || [];
  const eligibleDraftIds = new Set(items.filter(isDraftEligible).map((item) => item.import_item_id));
  const actionableOccurrenceIds = new Set(items.filter(isOccurrenceActionable).map((item) => item.import_item_id));

  if (batchId !== currentImportBatchId) {
    currentImportBatchId = batchId;
    selectedDraftItemIds = new Set(eligibleDraftIds);
    selectedOccurrenceItemIds = new Set();
    return;
  }

  selectedDraftItemIds = new Set([...selectedDraftItemIds].filter((id) => eligibleDraftIds.has(id)));
  selectedOccurrenceItemIds = new Set([...selectedOccurrenceItemIds].filter((id) => actionableOccurrenceIds.has(id)));
}


// SCOREMORE_Q81_SOURCE_ANOMALY_FIX_V1
function importItemErrorCodes(item) {
  return (item?.errors || [])
    .map((issue) => String(issue?.code || '').trim().toUpperCase())
    .filter(Boolean);
}

function isConfirmablePrintedDuplicateOptions(item) {
  const errorCodes = importItemErrorCodes(item);
  return Boolean(
    !item?.created_draft_id
    && item?.validation_status === 'INVALID'
    && String(item?.normalized_payload?.question_type || '').toUpperCase() === 'PYQ'
    && errorCodes.length === 1
    && errorCodes[0] === 'DUPLICATE_OPTIONS'
  );
}

function confirmablePrintedSourceAnomalyCount(report = currentImportReport) {
  return report?.items?.filter(isConfirmablePrintedDuplicateOptions).length || 0;
}

function duplicatePrintedOptionLabels(item) {
  const options = item?.normalized_payload?.options || {};
  const rows = ['A', 'B', 'C', 'D']
    .map((label) => [label, String(options?.[label] || '').trim().replace(/\s+/g, ' ')])
    .filter(([, value]) => value);
  const groups = new Map();
  rows.forEach(([label, value]) => {
    const key = value.toLocaleLowerCase();
    const labels = groups.get(key) || [];
    labels.push(label);
    groups.set(key, labels);
  });
  return [...groups.values()].filter((labels) => labels.length > 1);
}

function knownRepairableCount(report = currentImportReport) {
  if (report?.summary && Object.prototype.hasOwnProperty.call(report.summary, 'repairable_items')) {
    return Number(report.summary.repairable_items || 0);
  }

  return report?.items?.filter((item) => (
    !item?.created_draft_id
    && !isConfirmablePrintedDuplicateOptions(item)
    && (
      Number(item?.fingerprint_version || 1) < 2
      || (item?.errors || []).some((issue) => issue?.code === 'DRAFT_INSERT_FAILED')
    )
  )).length || 0;
}

function updateImportActionControls() {
  const batchId = currentImportReport?.batch?.import_batch_id;
  const summary = currentImportReport?.summary || {};
  const ready = Number(summary.ready_for_draft || 0);
  const imported = Number(summary.imported_to_draft || 0);
  const errors = Number(summary.errors || 0);
  const duplicates = Number(summary.duplicates || 0);
  const occurrenceCount = selectedOccurrenceItemIds.size;
  const repairable = knownRepairableCount();
  const reusable = Number(summary.reusable_duplicates || 0);
  const sourceAnomalies = confirmablePrintedSourceAnomalyCount();
  const remainingErrors = Math.max(errors - sourceAnomalies, 0);

  if (elements.importValidDrafts) {
    elements.importValidDrafts.disabled = !batchId || (ready === 0 && repairable === 0 && reusable === 0 && imported === 0);
    elements.importValidDrafts.textContent = '2. Import remaining drafts';
  }
  if (elements.syncImportBatch) elements.syncImportBatch.disabled = !batchId;
  if (elements.repairImportBatch) elements.repairImportBatch.disabled = !batchId || repairable === 0;
  if (elements.resetImportDrafts) elements.resetImportDrafts.disabled = !batchId || imported === 0;
  if (elements.linkDuplicateOccurrences) elements.linkDuplicateOccurrences.disabled = !batchId || occurrenceCount === 0;

  if (elements.importSelectionSummary) {
    elements.importSelectionSummary.textContent = batchId
      ? `${imported} drafts exist. ${ready} new drafts are ready.${repairable ? ` ${repairable} older records will be rechecked automatically.` : ''}${reusable ? ` ${reusable} exact duplicate${reusable === 1 ? '' : 's'} will be reused safely.` : ''}${sourceAnomalies ? ` ${sourceAnomalies} printed source option anomal${sourceAnomalies === 1 ? 'y needs' : 'ies need'} explicit confirmation. Tap Import remaining drafts or use the Errors filter.` : ''}${remainingErrors ? ` ${remainingErrors} other genuine error${remainingErrors === 1 ? '' : 's'}/conflict${remainingErrors === 1 ? '' : 's'} still need attention.` : ''}${duplicates && !reusable ? ` ${duplicates} true duplicates were already resolved.` : ''}${occurrenceCount ? ` ${occurrenceCount} occurrence selected.` : ''}`
      : 'Validate a package, then use one button to import every remaining eligible draft.';
  }
}

function renderPackageValidationFailure(packageValidation) {
  currentImportReport = {
    package_validation: packageValidation,
    batch: null,
    summary: {
      total: parsedImportPackage?.metadata.questionCount || 0,
      valid: 0,
      warnings: 0,
      errors: 1,
      duplicates: 0,
      ready_for_draft: 0,
      imported_to_draft: 0,
      linked_to_existing: 0,
      skipped_duplicates: 0,
      actionable_occurrences: 0,
    },
    items: [],
  };
  resetImportSelections();
  elements.importReportPanel.classList.remove('hidden');
  elements.importReportTitle.textContent = 'Package validation stopped';
  elements.importReportMeta.textContent = packageValidation?.status || 'INVALID';
  renderImportSummary(currentImportReport.summary, currentImportReport.batch);
  const issues = [...(packageValidation?.errors || []), ...(packageValidation?.warnings || [])];
  elements.importItemList.innerHTML = issues.length
    ? `<div class="import-package-errors"><ul>${issues.map(formatIssue).join('')}</ul></div>`
    : '<div class="empty-state">The package could not enter the authoritative dry run.</div>';
  elements.downloadImportReport.disabled = false;
}

function summaryValue(summary, key) {
  return Number(summary?.[key] || 0);
}

function renderImportSummary(summary, batch = null) {
  const rows = [
    ['Total records', summaryValue(summary, 'total')],
    ['Valid', summaryValue(summary, 'valid')],
    ['Warnings', summaryValue(summary, 'warnings')],
    ['Errors/conflicts', summaryValue(summary, 'errors')],
    ['Duplicates', summaryValue(summary, 'duplicates')],
    ['Ready for draft', summaryValue(summary, 'ready_for_draft')],
    ['Drafts created', summaryValue(summary, 'imported_to_draft')],
    ['Occurrences linked', summaryValue(summary, 'linked_to_existing')],
    ['Duplicates skipped', summaryValue(summary, 'skipped_duplicates')],
    ['Occurrences awaiting confirmation', summaryValue(summary, 'actionable_occurrences')],
    ['Exact duplicates ready for reuse', summaryValue(summary, 'reusable_duplicates')],
  ];
  if (summaryValue(summary, 'repairable_items') > 0) rows.splice(6, 0, ['Safely repairable records', summaryValue(summary, 'repairable_items')]);
  if (batch?.declared_total_questions) rows.unshift(['Declared paper questions', Number(batch.declared_total_questions)]);
  if (batch?.extracted_source_questions !== null && batch?.extracted_source_questions !== undefined) rows.splice(1, 0, ['Extracted source questions', Number(batch.extracted_source_questions)]);
  if (batch?.missing_question_count) rows.splice(2, 0, ['Missing source questions', Number(batch.missing_question_count)]);
  if (batch?.generated_supplement_count) rows.splice(3, 0, ['Supplemental normal questions', Number(batch.generated_supplement_count)]);
  elements.importSummaryGrid.innerHTML = rows.map(([label, value]) => `
    <div class="import-summary-card"><strong>${escapeHtml(value)}</strong><span>${escapeHtml(label)}</span></div>
  `).join('');
}

function importItemMatchesFilter(item, filter) {
  const status = item.validation_status;
  if (filter === 'READY') return ['VALID', 'VALID_WITH_WARNINGS'].includes(status);
  if (filter === 'WARNINGS') return ['VALID_WITH_WARNINGS', 'POSSIBLE_DUPLICATE'].includes(status) || (item.warnings?.length || 0) > 0;
  if (filter === 'ERRORS') return ['INVALID', 'ID_CONFLICT', 'ANSWER_CONFLICT', 'SOURCE_CONFLICT'].includes(status);
  if (filter === 'DUPLICATES') return ['EXACT_DUPLICATE', 'POSSIBLE_DUPLICATE'].includes(status);
  if (filter === 'IMPORTED') return status === 'IMPORTED_TO_DRAFT';
  if (filter === 'LINKED') return status === 'LINKED_TO_EXISTING';
  return true;
}

function importActionMarkup(item) {
  if (isDraftEligible(item)) {
    return '<div class="import-resolution resolution-success"><strong>Ready for draft</strong><span>The resumable importer will revalidate this record before insertion.</span></div>';
  }

  if (isOccurrenceActionable(item)) {
    return `
      <label class="import-action-choice occurrence-choice">
        <input type="checkbox" data-import-occurrence-select="${escapeHtml(item.import_item_id)}" ${selectedOccurrenceItemIds.has(item.import_item_id) ? 'checked' : ''} />
        <span><strong>Link this PYQ occurrence</strong><small>Keep one master question and attach this confirmed paper occurrence.</small></span>
      </label>
    `;
  }

  if (isConfirmablePrintedDuplicateOptions(item)) {
    const duplicateGroups = duplicatePrintedOptionLabels(item)
      .map((labels) => labels.join(' = '))
      .join(', ');
    return `
      <div class="import-resolution resolution-warning">
        <strong>Printed duplicate options need confirmation</strong>
        <span>The genuine PYQ source contains duplicate option text${duplicateGroups ? ` (${escapeHtml(duplicateGroups)})` : ''}. Preserve it exactly, record a source-traceability note, then create this controlled draft for Final Review.</span>
        <button
          class="button button-primary"
          type="button"
          data-confirm-source-option-anomaly="${escapeHtml(item.import_item_id)}"
        >Confirm source & create draft</button>
      </div>
    `;
  }

  if (item.validation_status === 'IMPORTED_TO_DRAFT') {
    return `<div class="import-resolution resolution-success"><strong>Draft created</strong><span>${escapeHtml(item.created_draft_id || item.matched_draft_id || '')}</span></div>`;
  }

  if (item.validation_status === 'LINKED_TO_EXISTING') {
    return `<div class="import-resolution resolution-success"><strong>Occurrence linked</strong><span>${escapeHtml(item.matched_question_id || '')}</span></div>`;
  }

  if (item.resolution_action && item.resolution_action !== 'NONE') {
    return `<div class="import-resolution"><strong>${escapeHtml(item.resolution_action)}</strong><span>${escapeHtml(item.resolution_notes || '')}</span></div>`;
  }

  if (item.validation_status === 'POSSIBLE_DUPLICATE') {
    return '<div class="import-resolution resolution-warning"><strong>Human duplicate decision required</strong><span>Possible duplicates are never auto-imported or auto-linked.</span></div>';
  }

  if (item.validation_status === 'EXACT_DUPLICATE') {
    return '<div class="import-resolution"><strong>Duplicate skipped</strong><span>No duplicate draft or master question will be created.</span></div>';
  }

  return '';
}

function bindImportItemSelections() {
  elements.importItemList.querySelectorAll('[data-import-occurrence-select]').forEach((checkbox) => {
    checkbox.addEventListener('change', () => {
      if (checkbox.checked) selectedOccurrenceItemIds.add(checkbox.dataset.importOccurrenceSelect);
      else selectedOccurrenceItemIds.delete(checkbox.dataset.importOccurrenceSelect);
      updateImportActionControls();
    });
  });
}

function renderImportItems() {
  if (!currentImportReport?.items) return;
  const filter = elements.importItemFilter.value;
  const allItems = currentImportReport.items.filter((item) => importItemMatchesFilter(item, filter));
  const items = allItems.slice(0, visibleImportItemLimit);
  const packageErrors = currentImportReport.batch?.package_errors || [];
  const packageWarnings = currentImportReport.batch?.package_warnings || [];
  const packageBlock = (packageErrors.length || packageWarnings.length) ? `
    <div class="import-package-errors">
      <strong>Package-level validation</strong>
      ${packageErrors.length ? `<div class="issue-block issue-error"><strong>Errors</strong><ul>${packageErrors.map(formatIssue).join('')}</ul></div>` : ''}
      ${packageWarnings.length ? `<div class="issue-block issue-warning"><strong>Warnings</strong><ul>${packageWarnings.map(formatIssue).join('')}</ul></div>` : ''}
    </div>
  ` : '';
  if (!items.length) {
    elements.importItemList.innerHTML = `${packageBlock}<div class="empty-state">No import items match this filter.</div>`;
    elements.loadMoreImportItems?.classList.add('hidden');
    updateImportActionControls();
    return;
  }

  elements.importItemList.innerHTML = packageBlock + items.map((item) => {
    const question = item.normalized_payload || {};
    const errors = item.errors || [];
    const warnings = item.warnings || [];
    const duplicateMatch = item.matched_question_id || item.matched_draft_id || '';
    return `
      <article class="import-item-card">
        <div class="import-item-head">
          <div>
            <span class="eyebrow">Record ${escapeHtml(item.item_index)} · ${escapeHtml(item.source_record_id || question.source_record_id || 'No source ID')}</span>
            <h3>${escapeHtml(item.proposed_question_id || question.proposed_question_id || 'Question ID missing')}</h3>
          </div>
          <span class="import-status-pill status-${escapeHtml(String(item.validation_status || 'pending').toLowerCase().replaceAll('_', '-'))}">${escapeHtml(item.validation_status)}</span>
        </div>
        ${importActionMarkup(item)}
        <p class="import-question-preview">${escapeHtml(question.question_text || 'Question text unavailable')}</p>
        <div class="test-meta">
          <span class="chip">${escapeHtml(question.question_type || '—')}</span>
          <span class="chip">${escapeHtml(question.subject_id || '—')}</span>
          <span class="chip">${escapeHtml(question.language || '—')}</span>
          <span class="chip">${escapeHtml(question.difficulty || '—')}</span>
          <span class="chip">Duplicate: ${escapeHtml(item.duplicate_kind || 'NONE')}</span>
          ${question.answer_source ? `<span class="chip">Answer: ${escapeHtml(question.answer_source)}${question.answer_confidence ? ` · ${escapeHtml(question.answer_confidence)}` : ''}</span>` : ''}
          ${question.topic_id || question.suggested_topic_code ? `<span class="chip">Topic: ${escapeHtml(question.topic_id || question.suggested_topic_code)}${question.topic_confidence ? ` · ${escapeHtml(question.topic_confidence)}` : ''}</span>` : ''}
          ${question.source_quality ? `<span class="chip">Source: ${escapeHtml(question.source_quality)}</span>` : ''}
          ${question.source_option_anomaly === 'DUPLICATE_OPTIONS_PRINTED' ? '<span class="chip warning-chip">PRINTED DUPLICATE OPTIONS</span>' : ''}
          ${question.is_supplemental ? '<span class="chip warning-chip">SUPPLEMENTAL NORMAL</span>' : ''}
          ${item.resolution_action && item.resolution_action !== 'NONE' ? `<span class="chip">Action: ${escapeHtml(item.resolution_action)}</span>` : ''}
        </div>
        ${duplicateMatch ? `<p class="import-match"><strong>Matched record:</strong> ${escapeHtml(duplicateMatch)}</p>` : ''}
        <details class="import-item-details">
          <summary>Validation, source and fingerprints</summary>
          <div class="checksum-list compact-checksums">
            <div><strong>Strict</strong><code>${escapeHtml(item.strict_fingerprint || '—')}</code></div>
            <div><strong>Loose</strong><code>${escapeHtml(item.loose_fingerprint || '—')}</code></div>
            <div><strong>Occurrence</strong><code>${escapeHtml(item.occurrence_key || '—')}</code></div>
            <div><strong>Draft</strong><code>${escapeHtml(item.created_draft_id || '—')}</code></div>
          </div>
          ${errors.length ? `<div class="issue-block issue-error"><strong>Errors</strong><ul>${errors.map(formatIssue).join('')}</ul></div>` : ''}
          ${warnings.length ? `<div class="issue-block issue-warning"><strong>Warnings</strong><ul>${warnings.map(formatIssue).join('')}</ul></div>` : ''}
          ${!errors.length && !warnings.length ? '<p class="muted">No item-level validation issues.</p>' : ''}
        </details>
      </article>
    `;
  }).join('');
  bindImportItemSelections();
  if (elements.loadMoreImportItems) {
    elements.loadMoreImportItems.classList.toggle('hidden', allItems.length <= visibleImportItemLimit);
    elements.loadMoreImportItems.textContent = `Show more records (${Math.min(IMPORT_ITEM_PAGE_SIZE, allItems.length - visibleImportItemLimit)} of ${allItems.length - visibleImportItemLimit} remaining)`;
  }
  updateImportActionControls();
}

function renderImportReport(report) {
  currentImportReport = report;
  visibleImportItemLimit = IMPORT_ITEM_PAGE_SIZE;
  const batch = report?.batch;
  syncImportSelections(report);
  elements.importReportPanel.classList.remove('hidden');
  elements.importReportTitle.textContent = batch?.package_id || 'Import reconciliation';
  elements.importReportMeta.textContent = batch
    ? `${batch.status} · Draft import ${batch.draft_import_status || 'NOT_STARTED'} · Batch ${batch.import_batch_id} · ${batch.source_file?.original_file_name || 'HTML package'}`
    : report?.package_validation?.status || 'Package validation';
  renderImportSummary(report?.summary || {}, batch);
  renderImportItems();
  elements.downloadImportReport.disabled = false;
  updateImportActionControls();
}

async function loadRecentImportBatches() {
  try {
    recentImportBatches = await api.listImportBatches({ pageSize: 15 });
    if (!recentImportBatches.length) {
      elements.recentImportPanel.classList.add('hidden');
      elements.recentImportList.innerHTML = '';
      return;
    }
    elements.recentImportPanel.classList.remove('hidden');
    elements.recentImportList.innerHTML = recentImportBatches.map((batch) => `
      <article class="import-history-item">
        <div>
          <strong>${escapeHtml(batch.package_id || 'Unnamed package')}</strong>
          <span>${escapeHtml(batch.status)} · Draft import ${escapeHtml(batch.draft_import_status || 'NOT_STARTED')} · ${escapeHtml(new Date(batch.created_at).toLocaleString())}</span>
          <small>${escapeHtml(batch.source_files?.original_file_name || '')}</small>
        </div>
        <div class="import-history-counts">
          <span>${escapeHtml(batch.total_raw)} total</span>
          <span>${escapeHtml(batch.total_draft || 0)} drafts</span>
          <span>${escapeHtml(batch.total_linked || 0)} linked</span>
          <span>${escapeHtml(batch.total_duplicate)} duplicates</span>
          ${batch.missing_question_count ? `<span>${escapeHtml(batch.missing_question_count)} missing</span>` : ''}
          ${batch.generated_supplement_count ? `<span>${escapeHtml(batch.generated_supplement_count)} supplements</span>` : ''}
        </div>
        <button class="button button-ghost" type="button" data-import-batch="${escapeHtml(batch.import_batch_id)}">Open report</button>
      </article>
    `).join('');
    elements.recentImportList.querySelectorAll('[data-import-batch]').forEach((button) => {
      button.addEventListener('click', async () => {
        const loading = toast.loading('Loading import report…');
        try {
          const report = await api.getImportBatchReport(button.dataset.importBatch);
          renderImportReport(report);
          document.getElementById('importReportPanel')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
          loading.close();
        } catch (error) {
          loading.close();
          toast.error(error.message);
        }
      });
    });
  } catch (error) {
    elements.recentImportPanel.classList.remove('hidden');
    elements.recentImportList.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
  }
}

function setImportProgress({ title, text, value = 0, max = 100 }) {
  if (!elements.importProgressPanel) return;
  elements.importProgressPanel.classList.remove('hidden');
  elements.importProgressTitle.textContent = title;
  elements.importProgressText.textContent = text;
  elements.importProgressBar.max = Math.max(Number(max) || 1, 1);
  elements.importProgressBar.value = Math.min(Math.max(Number(value) || 0, 0), elements.importProgressBar.max);
}

function hideImportProgress() {
  elements.importProgressPanel?.classList.add('hidden');
}

function wait(milliseconds) {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

async function recoverTimedOutDryRun() {
  if (!parsedImportPackage) return false;
  setImportProgress({
    title: 'Checking server state…',
    text: `A timeout does not necessarily mean failure. ${APP_CONFIG.name} is checking whether the server finished safely.`,
    value: 10,
    max: 100,
  });

  for (let attempt = 1; attempt <= 24; attempt += 1) {
    try {
      const batch = await api.findImportBatchByIdentity({
        packageId: parsedImportPackage.metadata.packageId,
        packageChecksum: parsedImportPackage.packageChecksum,
      });
      if (batch?.import_batch_id && String(batch.status || '').startsWith('DRY_RUN_COMPLETE')) {
        const report = await api.getImportBatchReport(batch.import_batch_id);
        renderImportReport(report);
        await loadRecentImportBatches();
        hideImportProgress();
        return true;
      }
    } catch {
      // Keep polling; a still-running transaction is not visible until it commits.
    }
    setImportProgress({
      title: 'Checking server state…',
      text: `Waiting for the authoritative dry run (${attempt}/24).`,
      value: attempt,
      max: 24,
    });
    await wait(5000);
  }

  hideImportProgress();
  return false;
}

async function runImportDryRun(event) {
  event.preventDefault();
  const form = event.currentTarget;
  if (!form.reportValidity()) return;
  const file = new FormData(form).get('htmlImportFile');
  setBusy(form, true);
  currentImportReport = null;
  resetImportSelections();
  elements.downloadImportReport.disabled = true;
  elements.importReportPanel.classList.add('hidden');
  const loading = toast.loading('Inspecting HTML package safely…');

  try {
    parsedImportPackage = await parseImportHtml(file);
    renderClientPackagePreview(parsedImportPackage);

    if (!parsedImportPackage.schemaValidation.valid) {
      loading.close();
      toast.error('Client schema validation found blocking errors. No file or database record was created.');
      return;
    }

    loading.update?.('Checking package identity and duplicates…');
    const packageValidation = await api.validateImportPackage({
      manifest: parsedImportPackage.manifest,
      packageChecksum: parsedImportPackage.packageChecksum,
      rawFileChecksum: parsedImportPackage.rawChecksum,
    });

    if (packageValidation.status === 'EXACT_DUPLICATE' && packageValidation.existing_import_batch_id) {
      const report = await api.getImportBatchReport(packageValidation.existing_import_batch_id);
      renderImportReport({ ...report, package_validation: packageValidation, reused_existing_batch: true });
      loading.close();
      toast.info('This package already exists. Its persistent reconciliation and draft-import state were reused.');
      return;
    }

    if (!['VALID', 'VALID_WITH_WARNINGS'].includes(packageValidation.status)) {
      renderPackageValidationFailure(packageValidation);
      loading.close();
      toast.error('Authoritative package validation stopped this dry run.');
      return;
    }

    const sourceFile = packageValidation.existing_source_file_id
      ? { source_file_id: packageValidation.existing_source_file_id, reused: true }
      : await api.uploadImportHtml(parsedImportPackage.file, parsedImportPackage.rawChecksum);

    const report = await api.stageImportDryRun({
      manifest: parsedImportPackage.manifest,
      rawFileChecksum: parsedImportPackage.rawChecksum,
      packageChecksum: parsedImportPackage.packageChecksum,
      sourceFileId: sourceFile.source_file_id,
    });
    renderImportReport(report);
    await loadRecentImportBatches();
    loading.close();
    toast.success(report.reused_existing_batch
      ? 'Existing reconciliation loaded. No duplicate batch or records were created.'
      : 'Dry validation completed. Review the summary, then import all eligible drafts.');
  } catch (error) {
    if (error.code === 'REQUEST_TIMEOUT' && parsedImportPackage) {
      loading.update?.('The request timed out. Checking whether the server completed it…');
      const recovered = await recoverTimedOutDryRun();
      loading.close();
      if (recovered) toast.success('The server completed the dry run. Its saved report was recovered automatically.');
      else toast.warning('The server state could not be confirmed yet. Retry validation or open Recent dry runs; no draft or published question is created by validation.');
    } else {
      loading.close();
      toast.error(error.message);
    }
  } finally {
    setBusy(form, false);
    elements.downloadImportReport.disabled = !currentImportReport;
    updateImportActionControls();
  }
}

function requestAdminConfirmation({
  eyebrow = 'Admin confirmation',
  title,
  message,
  safetyTitle = 'Protected operation',
  safetyMessage = 'The database validates this action before saving changes.',
  buttonLabel = 'Continue',
  summaryRows = [],
}) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };

    elements.dialogContent.innerHTML = `
      <div class="review-content">
        <span class="eyebrow">${escapeHtml(eyebrow)}</span>
        <h2>${escapeHtml(title)}</h2>
        <p>${escapeHtml(message)}</p>
        ${Array.isArray(summaryRows) && summaryRows.length ? `<div class="admin-confirm-summary">${summaryRows.map(([label, value]) => `<div><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`).join('')}</div>` : ''}
        <div class="import-safety-note">
          <strong>${escapeHtml(safetyTitle)}</strong>
          <span>${escapeHtml(safetyMessage)}</span>
        </div>
        <div class="draft-item-actions">
          <button id="confirmAdminAction" class="button button-primary" type="button">${escapeHtml(buttonLabel)}</button>
          <button id="cancelAdminAction" class="button button-ghost" type="button">Cancel</button>
        </div>
      </div>
    `;
    elements.dialogContent.querySelector('#confirmAdminAction')?.addEventListener('click', () => {
      finish(true);
      elements.dialog.close();
    });
    elements.dialogContent.querySelector('#cancelAdminAction')?.addEventListener('click', () => {
      finish(false);
      elements.dialog.close();
    });
    elements.dialog.addEventListener('close', () => finish(false), { once: true });
    elements.dialog.showModal();
  });
}

function requestSourceOptionAnomalyConfirmation(item) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };

    const question = item?.normalized_payload || {};
    const sourceLabel = [
      question.paper_code || currentImportReport?.batch?.paper_code,
      question.original_question_no ? `Q${question.original_question_no}` : item?.source_record_id,
      question.source_page ? `page ${question.source_page}` : '',
    ].filter(Boolean).join(' · ');
    const duplicateGroups = duplicatePrintedOptionLabels(item)
      .map((labels) => labels.join(' = '))
      .join(', ');
    const defaultNote = `Checked against the original source${sourceLabel ? ` (${sourceLabel})` : ''}. The genuine PYQ prints identical option text${duplicateGroups ? ` in ${duplicateGroups}` : ' in more than one option'}. Preserve all option text exactly as printed. Record as DUPLICATE_OPTIONS_PRINTED. The proposed answer remains unverified and requires human review.`;

    elements.dialogContent.innerHTML = `
      <div class="review-content">
        <span class="eyebrow">Controlled source anomaly</span>
        <h2>Confirm printed duplicate options</h2>
        <p>${escapeHtml(sourceLabel || item?.proposed_question_id || 'This genuine PYQ record')}</p>
        ${duplicateGroups ? `<p><strong>Duplicate printed labels:</strong> ${escapeHtml(duplicateGroups)}</p>` : ''}
        <div class="import-safety-note">
          <strong>Source preservation</strong>
          <span>This does not fix, merge or rewrite the printed options. It records the genuine source anomaly and creates only a draft for human review. Nothing is published.</span>
        </div>
        <label class="field">
          <span>Source traceability note</span>
          <textarea id="sourceOptionAnomalyNote" rows="5" required>${escapeHtml(defaultNote)}</textarea>
        </label>
        <div class="draft-item-actions">
          <button id="confirmSourceOptionAnomaly" class="button button-primary" type="button">Confirm & create draft</button>
          <button id="cancelSourceOptionAnomaly" class="button button-ghost" type="button">Cancel</button>
        </div>
      </div>
    `;

    elements.dialogContent.querySelector('#confirmSourceOptionAnomaly')?.addEventListener('click', () => {
      const note = elements.dialogContent.querySelector('#sourceOptionAnomalyNote')?.value?.trim() || '';
      if (!note) {
        toast.warning('Add a source traceability note before confirming the printed duplicate options.');
        return;
      }
      finish(note);
      elements.dialog.close();
    });

    elements.dialogContent.querySelector('#cancelSourceOptionAnomaly')?.addEventListener('click', () => {
      finish(null);
      elements.dialog.close();
    });

    elements.dialog.addEventListener('close', () => finish(null), { once: true });
    elements.dialog.showModal();
  });
}

async function confirmPrintedSourceOptionAnomaly(importItemId) {
  const batchId = currentImportReport?.batch?.import_batch_id;
  const item = currentImportReport?.items?.find((row) => row.import_item_id === importItemId);

  if (!batchId || !item) {
    toast.error('Open the current import report and try again.');
    return false;
  }

  if (!isConfirmablePrintedDuplicateOptions(item)) {
    toast.warning('This record is not eligible for the printed duplicate-option exception.');
    return false;
  }

  const note = await requestSourceOptionAnomalyConfirmation(item);
  if (!note) return false;

  const loading = toast.loading('Confirming the printed source anomaly…');
  try {
    const confirmation = await api.confirmImportSourceOptionAnomaly({
      importItemId,
      note,
    });

    const status = String(confirmation?.status || '').toUpperCase();
    if (!['VALID', 'VALID_WITH_WARNINGS'].includes(status)) {
      throw new Error(`The source anomaly was recorded, but the item is still ${status || 'blocked'}.`);
    }

    loading.update?.('Creating the controlled draft…');

    await api.importBatchItemsToDrafts({
      importBatchId: batchId,
      importItemIds: [importItemId],
    });

    await api.reconcileImportBatchState(batchId);
    const report = await api.getImportBatchReport(batchId);
    renderImportReport(report);

    await Promise.all([
      loadDrafts({ reset: true }),
      loadRecentImportBatches(),
      loadAdminTaskInbox(),
    ]);
    renderAdminDashboard();

    loading.close();
    toast.success('Printed source anomaly confirmed. Draft created for Final Review. Nothing was published.');
    return true;
  } catch (error) {
    loading.close();
    toast.error(error.message);
    try {
      const report = await api.getImportBatchReport(batchId);
      renderImportReport(report);
    } catch {
      // Preserve the original actionable error.
    }
    return false;
  }
}

function requestImportConfirmation({ title, message, buttonLabel }) {
  return requestAdminConfirmation({
    eyebrow: 'Controlled import confirmation',
    title,
    message,
    safetyTitle: 'Architecture lock',
    safetyMessage: 'This action creates draft_questions only. It never publishes directly to the master questions table.',
    buttonLabel,
  });
}

async function repairKnownBatchItems(batchId, estimatedCount = 0) {
  let processed = 0;
  let repaired = 0;
  let remaining = Math.max(Number(estimatedCount) || 0, 1);

  for (let cycle = 0; cycle < 100 && remaining > 0; cycle += 1) {
    setImportProgress({
      title: 'Repairing known import-state errors…',
      text: `${repaired} repaired · ${remaining} remaining.`,
      value: processed,
      max: Math.max(Number(estimatedCount) || remaining, 1),
    });
    const chunk = await api.repairAiProposedImportChunk({ importBatchId: batchId, limit: 20 });
    processed += Number(chunk?.processed || 0);
    repaired += Number(chunk?.repaired || 0);
    remaining = Number(chunk?.remaining || 0);
    if (Number(chunk?.processed || 0) === 0 && remaining > 0) break;
  }

  return { processed, repaired, remaining };
}

async function importSelectedDrafts() {
  const batchId = currentImportReport?.batch?.import_batch_id;
  const pendingSourceAnomaly = currentImportReport?.items?.find(isConfirmablePrintedDuplicateOptions);
  if (batchId && pendingSourceAnomaly) {
    await confirmPrintedSourceOptionAnomaly(pendingSourceAnomaly.import_item_id);
    return;
  }
  if (!batchId) return toast.warning('Open an import report first.');

  elements.importValidDrafts.disabled = true;
  elements.linkDuplicateOccurrences.disabled = true;
  let loading = toast.loading('Checking the actual database state…');

  try {
    await api.reconcileImportBatchState(batchId);
    let report = await api.getImportBatchReport(batchId);
    let repairable = knownRepairableCount(report);

    if (repairable > 0) {
      loading.update?.(`Repairing ${repairable} known false-error or stale-state record${repairable === 1 ? '' : 's'}…`);
      await repairKnownBatchItems(batchId, repairable);
      await api.reconcileImportBatchState(batchId);
      report = await api.getImportBatchReport(batchId);
    }

    renderImportReport(report);
    await loadRecentImportBatches();

    const ready = Number(report?.summary?.ready_for_draft || 0);
    const reusable = Number(report?.summary?.reusable_duplicates || 0);
    const importedBefore = Number(report?.summary?.imported_to_draft || 0);

    if (ready === 0 && reusable === 0) {
      hideImportProgress();
      loading.close();
      if (importedBefore > 0) {
        toast.info(`${importedBefore} actual draft${importedBefore === 1 ? '' : 's'} already exist for this batch. No duplicate draft was created.`);
      } else {
        toast.warning('No eligible record is ready. Review the remaining genuine errors, conflicts or duplicate statuses.');
      }
      return;
    }

    loading.close();
    const confirmed = await requestImportConfirmation({
      title: `Process ${ready + reusable} remaining record${ready + reusable === 1 ? '' : 's'}?`,
      message: `${APP_CONFIG.name} will create only new drafts. Exact duplicates will reuse an existing draft or master question, and nothing is published automatically.`,
      buttonLabel: 'Import remaining drafts',
    });
    if (!confirmed) {
      hideImportProgress();
      return;
    }

    loading = toast.loading('Creating controlled drafts in small chunks…');
    let totalImportedThisRun = 0;
    let remaining = ready + reusable;
    const totalTarget = importedBefore + remaining;

    for (let cycle = 0; cycle < 100 && remaining > 0; cycle += 1) {
      const beforeRemaining = remaining;
      setImportProgress({
        title: 'Creating controlled drafts…',
        text: `${totalImportedThisRun} created in this run · ${remaining} remaining.`,
        value: totalTarget - remaining,
        max: totalTarget,
      });

      try {
        const chunk = await api.importNextValidDraftChunk({
          importBatchId: batchId,
          limit: DRAFT_IMPORT_CHUNK_SIZE,
        });
        totalImportedThisRun += Number(chunk?.imported || 0);
        remaining = Number(chunk?.remaining || 0);
        if (Number(chunk?.processed || 0) === 0 && remaining > 0) {
          throw new Error('Draft import did not make progress. Use Sync actual draft state, then retry.');
        }
      } catch (error) {
        if (error.code !== 'REQUEST_TIMEOUT') throw error;
        loading.update?.('A chunk timed out. Synchronizing the actual database state…');
        await api.reconcileImportBatchState(batchId);
        const recoveredReport = await api.getImportBatchReport(batchId);
        remaining = Number(recoveredReport?.summary?.ready_for_draft || 0)
          + Number(recoveredReport?.summary?.reusable_duplicates || 0);
        if (remaining >= beforeRemaining) throw error;
      }
    }

    await api.reconcileImportBatchState(batchId);
    report = await api.getImportBatchReport(batchId);
    renderImportReport(report);
    await Promise.all([loadDrafts(), loadRecentImportBatches(), loadAdminTaskInbox()]);
    hideImportProgress();
    loading.close();
    const finalLinked = Number(report?.summary?.linked_to_existing || 0);
    const finalSkipped = Number(report?.summary?.skipped_duplicates || 0);
    toast.success(`${totalImportedThisRun} new draft${totalImportedThisRun === 1 ? '' : 's'} created. ${finalLinked} occurrence${finalLinked === 1 ? '' : 's'} linked and ${finalSkipped} duplicate${finalSkipped === 1 ? '' : 's'} reused. Nothing was published.`);
    document.getElementById('importReportPanel')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  } catch (error) {
    hideImportProgress();
    loading.close();
    try {
      await api.reconcileImportBatchState(batchId);
      const report = await api.getImportBatchReport(batchId);
      renderImportReport(report);
      await loadRecentImportBatches();
    } catch {
      // Preserve the original actionable error.
    }
    toast.error(error.code === 'REQUEST_TIMEOUT'
      ? 'The connection timed out. The actual draft state has been synchronized; tap Sync / resume draft import to continue safely.'
      : error.message);
  } finally {
    updateImportActionControls();
  }
}

async function syncCurrentImportBatch() {
  const batchId = currentImportReport?.batch?.import_batch_id;
  if (!batchId) return toast.warning('Open an import report first.');
  const loading = toast.loading('Synchronizing actual drafts with the import ledger…');
  try {
    const result = await api.reconcileImportBatchState(batchId);
    const report = await api.getImportBatchReport(batchId);
    renderImportReport(report);
    await Promise.all([loadDrafts(), loadRecentImportBatches(), loadAdminTaskInbox()]);
    loading.close();
    toast.success(`Synchronized: ${Number(result?.drafts_found || 0)} actual drafts found; ${Number(result?.stale_items_released || 0)} stale records released.`);
  } catch (error) {
    loading.close();
    toast.error(error.message);
  }
}

async function repairCurrentImportBatch() {
  const batchId = currentImportReport?.batch?.import_batch_id;
  const repairable = knownRepairableCount();
  if (!batchId || repairable === 0) return toast.warning('This report has no known false-invalid, failed-insert or stale draft-match records to repair.');

  const confirmed = await requestImportConfirmation({
    title: `Recheck ${repairable} repairable record${repairable === 1 ? '' : 's'}?`,
    message: 'This revalidates known Phase 3E false-invalid answers, failed insert records and stale draft matches in small chunks. It does not create drafts or publish questions.',
    buttonLabel: 'Recheck batch',
  });
  if (!confirmed) return;

  const loading = toast.loading('Rechecking the batch with the corrected validator…');
  try {
    const result = await repairKnownBatchItems(batchId, repairable);
    await api.reconcileImportBatchState(batchId);
    const report = await api.getImportBatchReport(batchId);
    renderImportReport(report);
    await loadRecentImportBatches();
    hideImportProgress();
    loading.close();
    toast.success(`${result.repaired} record${result.repaired === 1 ? '' : 's'} repaired. Review the updated counters before importing drafts.`);
  } catch (error) {
    hideImportProgress();
    loading.close();
    toast.error(error.message);
  }
}

async function resetCurrentImportDrafts() {
  const batchId = currentImportReport?.batch?.import_batch_id;
  const imported = Number(currentImportReport?.summary?.imported_to_draft || 0);
  if (!batchId || imported === 0) return toast.warning('This batch has no imported drafts to reset.');

  const confirmed = await requestImportConfirmation({
    title: `Reset up to ${imported} untouched draft${imported === 1 ? '' : 's'}?`,
    message: 'Only PENDING, unreviewed and unpublished drafts from this batch will be removed. Import history and audit records remain. Reviewed or published content is protected.',
    buttonLabel: 'Reset unreviewed drafts',
  });
  if (!confirmed) return;

  const loading = toast.loading('Resetting untouched drafts safely…');
  try {
    const result = await api.resetUnreviewedImportDrafts(batchId);
    const report = await api.getImportBatchReport(batchId);
    renderImportReport(report);
    await Promise.all([loadDrafts(), loadRecentImportBatches(), loadAdminTaskInbox()]);
    loading.close();
    toast.success(`${Number(result?.deleted_unreviewed_drafts || 0)} untouched draft${Number(result?.deleted_unreviewed_drafts || 0) === 1 ? '' : 's'} reset. Protected drafts were not changed.`);
  } catch (error) {
    loading.close();
    toast.error(error.message);
  }
}

async function linkSelectedOccurrences() {
  const batchId = currentImportReport?.batch?.import_batch_id;
  const itemIds = [...selectedOccurrenceItemIds];
  if (!batchId || !itemIds.length) return toast.warning('Select at least one exact duplicate PYQ occurrence.');

  const confirmed = await requestImportConfirmation({
    title: `Link ${itemIds.length} source occurrence${itemIds.length === 1 ? '' : 's'}?`,
    message: 'This does not create another master question. It links each confirmed paper occurrence to the existing exact master question.',
    buttonLabel: 'Link confirmed occurrences',
  });
  if (!confirmed) return;

  elements.importValidDrafts.disabled = true;
  elements.linkDuplicateOccurrences.disabled = true;
  const loading = toast.loading('Linking confirmed source occurrences…');
  try {
    const report = await api.linkImportBatchOccurrences({ importBatchId: batchId, importItemIds: itemIds });
    renderImportReport(report);
    await loadRecentImportBatches();
    const result = report.occurrence_link_result || {};
    loading.close();
    toast.success(`${Number(result.linked || 0)} occurrence${Number(result.linked || 0) === 1 ? '' : 's'} linked without duplicating master questions.`);
  } catch (error) {
    loading.close();
    toast.error(error.message);
  } finally {
    updateImportActionControls();
  }
}

function downloadCurrentImportReport() {
  if (!currentImportReport) return;
  const packageId = currentImportReport.batch?.package_id || parsedImportPackage?.metadata.packageId || 'scoremore-import';
  downloadJson(`${packageId}-reconciliation.json`, {
    exported_at: new Date().toISOString(),
    local_file: parsedImportPackage ? {
      file_name: parsedImportPackage.metadata.fileName,
      file_size_bytes: parsedImportPackage.metadata.fileSize,
      raw_checksum_sha256: parsedImportPackage.rawChecksum,
      package_checksum_sha256: parsedImportPackage.packageChecksum,
      client_schema_validation: parsedImportPackage.schemaValidation,
    } : null,
    report: currentImportReport,
  });
}

function bindEvents() {
  initializeAdminWorkspaceNavigation();
  setRepairQueueMode('draft');
  elements.refreshAdminTasks?.addEventListener('click', () => loadAdminTaskInbox({ announce: true }));
  elements.continueDraftRepairTask?.addEventListener('click', () => openAdminTask('draft_repairs'));
  elements.continuePublishedImageTask?.addEventListener('click', () => openAdminTask('published_image_safety'));
  elements.continueFinalReviewTask?.addEventListener('click', () => openAdminTask('final_reviews'));
  elements.continuePublishTask?.addEventListener('click', () => openAdminTask('ready_to_publish'));
  document.querySelectorAll('[data-repair-queue-tab]').forEach((tab) => {
    tab.addEventListener('click', () => setRepairQueueMode(tab.dataset.repairQueueTab, { focus: true }));
    tab.addEventListener('keydown', (event) => {
      if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      const tabs = [...document.querySelectorAll('[data-repair-queue-tab]')];
      const currentIndex = tabs.indexOf(tab);
      const nextIndex = event.key === 'Home'
        ? 0
        : event.key === 'End'
          ? tabs.length - 1
          : (currentIndex + (['ArrowRight', 'ArrowDown'].includes(event.key) ? 1 : -1) + tabs.length) % tabs.length;
      const nextTab = tabs[nextIndex];
      setRepairQueueMode(nextTab.dataset.repairQueueTab);
      nextTab.focus();
    });
  });
  elements.loginForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!form.reportValidity()) return;
    const values = new FormData(form);
    setBusy(form, true);
    const loading = toast.loading('Signing in…');
    try {
      await api.signIn({ email: values.get('email'), password: values.get('password') });
      const restored = await showAdmin();
      loading.close();
      if (restored) {
        toast.success('Admin access verified.');
        form.reset();
      }
    } catch (error) {
      loading.close();
      toast.error(error.message);
      // Never destroy a valid stored session because a follow-up profile/data
      // request failed transiently. Explicit sign-out remains user-controlled.
    } finally { setBusy(form, false); }
  });

  elements.sessionRetry?.addEventListener('click', () => {
    showRestoringAdminSession('Retrying your secure admin session…');
    showAdmin({ reloadData: true }).catch((error) => showSessionProblem(error));
  });

  elements.signOut?.addEventListener('click', async () => {
    try { await api.signOut(); toast.success('Signed out.'); showLogin(); }
    catch (error) { toast.error(error.message); }
  });

  elements.htmlImportForm?.addEventListener('submit', runImportDryRun);
  elements.importItemFilter?.addEventListener('change', () => { visibleImportItemLimit = IMPORT_ITEM_PAGE_SIZE; renderImportItems(); });
  elements.importItemList?.addEventListener('click', (event) => {
    const button = event.target.closest('[data-confirm-source-option-anomaly]');
    if (!button) return;
    confirmPrintedSourceOptionAnomaly(button.dataset.confirmSourceOptionAnomaly);
  });
  elements.downloadImportReport?.addEventListener('click', downloadCurrentImportReport);
  elements.importValidDrafts?.addEventListener('click', importSelectedDrafts);
  elements.syncImportBatch?.addEventListener('click', syncCurrentImportBatch);
  elements.repairImportBatch?.addEventListener('click', repairCurrentImportBatch);
  elements.resetImportDrafts?.addEventListener('click', resetCurrentImportDrafts);
  elements.linkDuplicateOccurrences?.addEventListener('click', linkSelectedOccurrences);
  elements.loadMoreImportItems?.addEventListener('click', () => { visibleImportItemLimit += IMPORT_ITEM_PAGE_SIZE; renderImportItems(); });
  document.getElementById('refreshImportBatches')?.addEventListener('click', async () => {
    await loadRecentImportBatches();
    elements.recentImportPanel?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
  elements.htmlImportFile?.addEventListener('change', () => {
    parsedImportPackage = null;
    currentImportReport = null;
    elements.importPackagePreview.classList.add('hidden');
    elements.importReportPanel.classList.add('hidden');
    elements.downloadImportReport.disabled = true;
    hideImportProgress();
    visibleImportItemLimit = IMPORT_ITEM_PAGE_SIZE;
    resetImportSelections();
  });

  document.getElementById('refreshDrafts')?.addEventListener('click', () => loadDrafts({ reset: true }));
  elements.statusFilter?.addEventListener('change', () => loadDrafts({ reset: true }));
  elements.reviewNextDraft?.addEventListener('click', () => openNextAvailableDraft());
  elements.loadMoreDrafts?.addEventListener('click', () => loadDrafts({ reset: false }));
  elements.refreshPublishQueue?.addEventListener('click', () => loadPublishQueue({ reset: true }));
  elements.loadMorePublishQueue?.addEventListener('click', () => loadPublishQueue({ reset: false }));
  elements.selectAllPublishReady?.addEventListener('click', () => {
    publishQueue.forEach((draft) => selectedPublishDraftIds.add(draft.draft_id));
    renderPublishQueue();
  });
  elements.clearPublishSelection?.addEventListener('click', () => {
    selectedPublishDraftIds.clear();
    renderPublishQueue();
  });
  elements.publishSelectedDrafts?.addEventListener('click', () => publishSelectedQueue([...selectedPublishDraftIds]));
  elements.imageRepairFilters?.addEventListener('submit', (event) => {
    event.preventDefault();
    loadImageRepairQueue({ reset: true });
  });
  elements.refreshImageRepairs?.addEventListener('click', () => loadImageRepairQueue({ reset: true }));
  elements.loadMoreImageRepairs?.addEventListener('click', () => loadImageRepairQueue({ reset: false }));
  elements.clearImageRepairFilters?.addEventListener('click', () => {
    elements.imageRepairFilters.reset();
    elements.imageRepairStatus.value = 'NEEDS_REPAIR';
    loadImageRepairQueue({ reset: true });
  });
  ['imageRepairPaperCode', 'imageRepairSectionCode'].forEach((id) => {
    document.getElementById(id)?.addEventListener('input', (event) => {
      event.target.value = event.target.value.toUpperCase().replace(/\s+/g, '_');
    });
  });
  elements.imageRepairDialog?.addEventListener('close', () => {
    if (activeRepairObjectUrl) URL.revokeObjectURL(activeRepairObjectUrl);
    activeRepairObjectUrl = '';
  });
  elements.publishedImageRepairFilters?.addEventListener('submit', (event) => {
    event.preventDefault();
    loadPublishedImageRepairQueue({ reset: true });
  });
  elements.refreshPublishedImageRepairs?.addEventListener('click', () => loadPublishedImageRepairQueue({ reset: true }));
  elements.loadMorePublishedImageRepairs?.addEventListener('click', () => loadPublishedImageRepairQueue({ reset: false }));
  elements.clearPublishedImageRepairFilters?.addEventListener('click', () => {
    elements.publishedImageRepairFilters.reset();
    elements.publishedImageRepairStatus.value = 'NEEDS_REPAIR';
    loadPublishedImageRepairQueue({ reset: true });
  });
  ['publishedImageRepairPaperCode', 'publishedImageRepairSectionCode'].forEach((id) => {
    document.getElementById(id)?.addEventListener('input', (event) => {
      event.target.value = event.target.value.toUpperCase().replace(/\s+/g, '_');
    });
  });
  document.getElementById('draftBoardId')?.addEventListener('change', refreshDraftReferenceSelects);
  document.getElementById('draftExamId')?.addEventListener('change', refreshDraftReferenceSelects);
  document.getElementById('draftSubjectId')?.addEventListener('change', refreshDraftReferenceSelects);

  document.getElementById('refreshTests')?.addEventListener('click', loadConfiguredTests);
  elements.testStatusFilter?.addEventListener('change', renderConfiguredTests);
  elements.testCatalogueSearch?.addEventListener('input', renderConfiguredTests);
  [elements.testTypeFilter, elements.testBoardFilter, elements.testExamFilter, elements.testSubjectFilter, elements.testYearFilter].forEach((select) => {
    select?.addEventListener('change', renderConfiguredTests);
  });
  elements.clearTestCatalogueFilters?.addEventListener('click', () => {
    [elements.testStatusFilter, elements.testTypeFilter, elements.testBoardFilter, elements.testExamFilter, elements.testSubjectFilter, elements.testYearFilter].forEach((select) => {
      if (select) select.value = '';
    });
    if (elements.testCatalogueSearch) elements.testCatalogueSearch.value = '';
    renderConfiguredTests();
  });
  document.getElementById('loadPublishedQuestions')?.addEventListener('click', loadPublishedQuestions);
  document.getElementById('newTest')?.addEventListener('click', resetTestBuilder);
  document.getElementById('suggestTestId')?.addEventListener('click', suggestTestIdentity);
  elements.testQuestionSearch?.addEventListener('input', renderPublishedQuestions);
  document.getElementById('selectAllQuestions')?.addEventListener('click', () => {
    visiblePublishedQuestions().forEach((question) => selectedTestQuestionIds.add(question.question_id));
    renderPublishedQuestions();
  });
  document.getElementById('clearQuestionSelection')?.addEventListener('click', () => {
    selectedTestQuestionIds.clear();
    renderPublishedQuestions();
  });
  document.getElementById('testType')?.addEventListener('change', () => {
    updateTestTypeUi();
    resetQuestionPicker();
  });
  ['testBoardId', 'testExamId', 'testSubjectId', 'testTopicId'].forEach((id) => {
    document.getElementById(id)?.addEventListener('change', () => {
      refreshTestReferenceSelects();
      resetQuestionPicker();
    });
  });
  ['testExamYear', 'testExamDate', 'testShiftNo', 'testPaperCode', 'testSectionCode'].forEach((id) => {
    document.getElementById(id)?.addEventListener('change', () => resetQuestionPicker());
  });
  ['testId', 'paperCode', 'sectionCode'].forEach((name) => {
    elements.testForm?.elements?.[name]?.addEventListener('input', (event) => {
      event.target.value = event.target.value.toUpperCase().replace(/\s+/g, '-');
    });
  });

  elements.sourceUploadForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!form.reportValidity()) return;
    const file = new FormData(form).get('sourceFile');
    if (!(file instanceof File) || !file.size) return toast.warning('Choose a PDF or image first.');
    setBusy(form, true);
    const loading = toast.loading('Uploading source file privately…');
    try {
      const source = await api.uploadSourceFile(file);
      loading.close();
      toast.success('Source file uploaded. It has not published any question.');
      document.getElementById('uploadedSourcePath').textContent = `Source ID: ${source.source_file_id}`;
      elements.draftForm.elements.sourceFileId.value = source.source_file_id;
      form.reset();
    } catch (error) {
      loading.close();
      toast.error(error.message);
    } finally { setBusy(form, false); }
  });

  elements.draftForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!form.reportValidity()) return;
    const values = Object.fromEntries(new FormData(form).entries());
    setBusy(form, true);
    const loading = toast.loading('Saving to draft questions…');
    try {
      await api.createDraft(values);
      loading.close();
      toast.success('Draft saved. Human publication is still required.');
      const retainedSource = form.elements.sourceFileId.value;
      form.reset();
      form.elements.sourceFileId.value = retainedSource;
      form.elements.language.value = 'GUJARATI';
      await Promise.all([loadDrafts(), loadAdminTaskInbox()]);
    } catch (error) {
      loading.close();
      toast.error(error.message);
    } finally { setBusy(form, false); }
  });

  elements.testForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    updateTestTypeUi();
    if (!form.reportValidity()) return;

    const questionIds = publishedQuestions
      .filter((question) => selectedTestQuestionIds.has(question.question_id))
      .map((question) => question.question_id);

    if (!questionIds.length) return toast.warning('Select at least one published question.');

    const values = Object.fromEntries(new FormData(form).entries());
    const publishTest = event.submitter?.value === 'PUBLISH';
    setBusy(form, true);
    const loading = toast.loading(publishTest ? 'Publishing test…' : 'Saving test draft…');
    try {
      const result = await api.saveFixedQuestionTest({
        ...values,
        questionIds,
        publish: publishTest,
      });
      editingTestId = result.test_id;
      elements.testBuilderMode.textContent = `Editing ${result.test_id}`;
      elements.testBuilderMode.className = `status-pill status-${String(result.status).toLowerCase()}`;
      loading.close();
      toast.success(`${result.test_id} saved as ${result.status}.`);
      await loadConfiguredTests();
    } catch (error) {
      loading.close();
      toast.error(error.message);
    } finally { setBusy(form, false); }
  });
}

async function initialize() {
  bindEvents();
  if (!isConfigured) {
    elements.setupNotice.classList.remove('hidden');
    showLogin();
    return;
  }
  bindAdminAuthLifecycle();
  try {
    await showAdmin();
  } catch (error) {
    toast.error(error.message);
    if (!document.body.classList.contains('admin-authenticated')) showSessionProblem(error);
  }
}

initialize();
