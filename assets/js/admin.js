import { isConfigured } from './config.js';
import { api } from './api.js';
import { toast } from './toast.js';
import { downloadJson, formatBytes, parseImportHtml } from './importEngine.js';

const elements = {
  setupNotice: document.getElementById('adminSetupNotice'),
  loginPanel: document.getElementById('adminLoginPanel'),
  adminPanel: document.getElementById('adminPanel'),
  signOut: document.getElementById('adminSignOut'),
  loginForm: document.getElementById('adminLoginForm'),
  draftForm: document.getElementById('draftForm'),
  sourceUploadForm: document.getElementById('sourceUploadForm'),
  draftList: document.getElementById('draftList'),
  statusFilter: document.getElementById('draftStatusFilter'),
  dialog: document.getElementById('draftDialog'),
  dialogContent: document.getElementById('draftDialogContent'),
  testForm: document.getElementById('testForm'),
  publishedQuestionList: document.getElementById('publishedQuestionList'),
  selectedQuestionCount: document.getElementById('selectedQuestionCount'),
  adminTestList: document.getElementById('adminTestList'),
  testStatusFilter: document.getElementById('testStatusFilter'),
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
};

let profile = null;
let drafts = [];
let referenceData = { boards: [], exams: [], subjects: [], topics: [] };
let publishedQuestions = [];
let configuredTests = [];
let parsedImportPackage = null;
let currentImportReport = null;
let recentImportBatches = [];
let currentImportBatchId = null;
let selectedDraftItemIds = new Set();
let selectedOccurrenceItemIds = new Set();
let visibleImportItemLimit = 20;
const IMPORT_ITEM_PAGE_SIZE = 20;
const DRAFT_IMPORT_CHUNK_SIZE = 10;

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
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

function showLogin() {
  profile = null;
  elements.loginPanel.classList.remove('hidden');
  elements.adminPanel.classList.add('hidden');
  elements.signOut.classList.add('hidden');
}

async function showAdmin() {
  const user = await api.getUser();
  if (!user) return showLogin();
  profile = await api.getProfile();
  if (profile?.role !== 'ADMIN') {
    await api.signOut();
    showLogin();
    throw new Error('This account is not authorized as a ScoreMore admin.');
  }
  elements.loginPanel.classList.add('hidden');
  elements.adminPanel.classList.remove('hidden');
  elements.signOut.classList.remove('hidden');
  await loadReferenceData();
  await Promise.all([loadDrafts(), loadConfiguredTests(), loadRecentImportBatches()]);
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
  );
}

function renderDrafts() {
  if (!drafts.length) {
    elements.draftList.innerHTML = '<div class="empty-state">No drafts match this status.</div>';
    return;
  }
  elements.draftList.innerHTML = drafts.map((draft) => {
    const ready = isDraftPublishReady(draft);
    return `
    <article class="draft-item">
      <div class="draft-item-header">
        <div>
          <span class="eyebrow">${escapeHtml(draft.review_status)} · ${escapeHtml(draft.question_type)}</span>
          <h3>${escapeHtml(draft.proposed_question_id || 'Question ID required')}</h3>
        </div>
        <span class="chip">${escapeHtml(draft.subject_id || 'No subject')}</span>
      </div>
      <p>${escapeHtml(draft.question_text)}</p>
      <div class="test-meta">
        <span class="chip">Answer: ${escapeHtml(draft.answer_source || 'NOT REVIEWED')}</span>
        <span class="chip">Topic: ${escapeHtml(draft.topic_id || draft.suggested_topic_code || 'UNRESOLVED')}</span>
        ${draft.answer_confidence ? `<span class="chip">Answer confidence: ${escapeHtml(draft.answer_confidence)}</span>` : ''}
        ${draft.source_quality ? `<span class="chip">Source: ${escapeHtml(draft.source_quality)}</span>` : ''}
        ${draft.is_supplemental ? '<span class="chip warning-chip">SUPPLEMENTAL NORMAL QUESTION</span>' : ''}
      </div>
      <div class="draft-item-actions">
        <button class="button button-ghost" data-review="${draft.draft_id}" type="button">Review and verify</button>
        ${['PENDING','IN_REVIEW','REJECTED'].includes(draft.review_status) && ready
          ? `<button class="button button-primary" data-publish="${draft.draft_id}" type="button">Publish</button>` : ''}
        ${draft.review_status !== 'PUBLISHED'
          ? `<button class="button button-danger" data-reject="${draft.draft_id}" type="button">Reject</button>` : ''}
      </div>
      ${!ready && draft.review_status !== 'PUBLISHED' ? '<p class="review-required-note">Human answer confirmation, explanation and approved topic are required before publication.</p>' : ''}
    </article>`;
  }).join('');

  elements.draftList.querySelectorAll('[data-review]').forEach((button) => button.addEventListener('click', () => openReview(button.dataset.review)));
  elements.draftList.querySelectorAll('[data-publish]').forEach((button) => button.addEventListener('click', () => publish(button.dataset.publish)));
  elements.draftList.querySelectorAll('[data-reject]').forEach((button) => button.addEventListener('click', () => openRejectDialog(button.dataset.reject)));
}

async function loadDrafts() {
  elements.draftList.innerHTML = '<div class="loading-state">Loading drafts…</div>';
  try {
    drafts = await api.listDrafts({ status: elements.statusFilter.value });
    renderDrafts();
  } catch (error) {
    elements.draftList.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    toast.error(error.message);
  }
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
  fillSelect(subjectSelect, subjects, 'subject_id', 'subject_name', 'Optional for full tests');
  const topics = referenceData.topics.filter((row) => !subjectSelect?.value || row.subject_id === subjectSelect.value);
  fillSelect(topicSelect, topics, 'topic_id', 'topic_name', 'Optional topic');
}

async function loadReferenceData() {
  referenceData = await api.getAdminReferenceData();
  refreshDraftReferenceSelects();
  refreshTestReferenceSelects();
}

function resetQuestionPicker() {
  publishedQuestions = [];
  elements.publishedQuestionList.innerHTML = '<div class="empty-state">Catalogue selection changed. Load matching questions again.</div>';
  updateSelectedQuestionCount();
}

function updateSelectedQuestionCount() {
  const count = elements.publishedQuestionList?.querySelectorAll('[data-question-id]:checked').length || 0;
  elements.selectedQuestionCount.textContent = `${count} selected`;
}

function renderPublishedQuestions() {
  if (!publishedQuestions.length) {
    elements.publishedQuestionList.innerHTML = '<div class="empty-state">No published questions match these catalogue fields.</div>';
    updateSelectedQuestionCount();
    return;
  }

  elements.publishedQuestionList.innerHTML = publishedQuestions.map((question) => `
    <label class="question-picker-item">
      <input type="checkbox" data-question-id="${escapeHtml(question.question_id)}" />
      <span>
        <strong>${escapeHtml(question.question_id)}</strong>
        <span class="question-picker-meta">
          <span class="chip">${escapeHtml(question.question_type)}</span>
          <span class="chip">${escapeHtml(question.subject_id)}</span>
          <span class="chip">${escapeHtml(question.difficulty)}</span>
        </span>
        <span class="question-picker-text">${escapeHtml(question.question_text)}</span>
      </span>
    </label>
  `).join('');

  elements.publishedQuestionList.querySelectorAll('[data-question-id]').forEach((checkbox) => {
    checkbox.addEventListener('change', updateSelectedQuestionCount);
  });
  updateSelectedQuestionCount();
}

async function loadPublishedQuestions() {
  const form = elements.testForm;
  const values = Object.fromEntries(new FormData(form).entries());
  if (!values.boardId || !values.examId) {
    return toast.warning('Select a board and exam before loading questions.');
  }

  elements.publishedQuestionList.innerHTML = '<div class="loading-state">Loading published questions…</div>';
  updateSelectedQuestionCount();
  try {
    publishedQuestions = await api.listPublishedQuestions({
      boardId: values.boardId,
      examId: values.examId,
      subjectId: values.subjectId,
      topicId: values.topicId,
      pageSize: 200,
    });
    renderPublishedQuestions();
  } catch (error) {
    elements.publishedQuestionList.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    toast.error(error.message);
  }
}

function renderConfiguredTests() {
  if (!configuredTests.length) {
    elements.adminTestList.innerHTML = '<div class="empty-state">No tests match this status.</div>';
    return;
  }

  elements.adminTestList.innerHTML = configuredTests.map((test) => `
    <article class="test-admin-item">
      <div class="draft-item-header">
        <div>
          <span class="eyebrow">${escapeHtml(test.status)} · ${escapeHtml(test.test_type)}</span>
          <h3>${escapeHtml(test.test_name)}</h3>
          <p class="muted">${escapeHtml(test.test_id)}</p>
        </div>
        <span class="chip">${escapeHtml(test.question_count)} question${Number(test.question_count) === 1 ? '' : 's'}</span>
      </div>
      <div class="test-meta">
        ${test.boards?.board_name ? `<span class="chip">${escapeHtml(test.boards.board_name)}</span>` : ''}
        ${test.exams?.exam_name ? `<span class="chip">${escapeHtml(test.exams.exam_name)}</span>` : ''}
        ${test.subjects?.subject_name ? `<span class="chip">${escapeHtml(test.subjects.subject_name)}</span>` : ''}
        <span class="chip">${escapeHtml(test.duration_minutes)} min</span>
        <span class="chip">${escapeHtml(test.selection_mode)}</span>
      </div>
    </article>
  `).join('');
}

async function loadConfiguredTests() {
  elements.adminTestList.innerHTML = '<div class="loading-state">Loading configured tests…</div>';
  try {
    configuredTests = await api.listAdminTests({ status: elements.testStatusFilter.value });
    renderConfiguredTests();
  } catch (error) {
    elements.adminTestList.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    toast.error(error.message);
  }
}

function topicOptionsForDraft(draft) {
  return referenceData.topics
    .filter((topic) => topic.status === 'ACTIVE' && topic.subject_id === draft.subject_id)
    .map((topic) => `<option value="${escapeHtml(topic.topic_id)}" ${topic.topic_id === draft.topic_id ? 'selected' : ''}>${escapeHtml(topic.topic_name)} (${escapeHtml(topic.topic_code || topic.topic_id)})</option>`)
    .join('');
}

function openReview(draftId) {
  const draft = drafts.find((item) => item.draft_id === draftId);
  if (!draft) return;
  const options = draft.options || {};
  const proposedSource = draft.answer_source || 'AI_PROPOSED';
  const reviewSource = proposedSource === 'AI_PROPOSED' ? 'MANUALLY_VERIFIED' : proposedSource;
  elements.dialogContent.innerHTML = `
    <div class="review-content phase3e-review">
      <span class="eyebrow">Human answer and topic verification</span>
      <h2>${escapeHtml(draft.proposed_question_id || 'Draft question')}</h2>
      <div class="review-audit-grid">
        <span><strong>Board</strong>${escapeHtml(draft.board_id)}</span>
        <span><strong>Exam</strong>${escapeHtml(draft.exam_id || '—')}</span>
        <span><strong>Subject</strong>${escapeHtml(draft.subject_id)}</span>
        <span><strong>Source quality</strong>${escapeHtml(draft.source_quality || 'Not set')}</span>
        <span><strong>Transcription confidence</strong>${escapeHtml(draft.transcription_confidence || 'Not set')}</span>
        <span><strong>AI answer confidence</strong>${escapeHtml(draft.answer_confidence || 'Not set')}</span>
      </div>
      ${draft.is_supplemental ? `<div class="import-resolution resolution-warning"><strong>Supplemental normal question</strong><span>${escapeHtml(draft.supplement_reason || 'Missing source question replacement')}</span></div>` : ''}
      ${(draft.suggested_topic_code || draft.suggested_topic_name) ? `<div class="import-resolution"><strong>Suggested topic</strong><span>${escapeHtml(draft.suggested_topic_name || '')} ${draft.suggested_topic_code ? `(${escapeHtml(draft.suggested_topic_code)})` : ''} · Confidence ${escapeHtml(draft.topic_confidence || 'not set')}</span></div>` : ''}
      <div class="question-text">${escapeHtml(draft.question_text)}</div>
      <div class="review-options">
        ${['A','B','C','D'].map((key) => `<label class="review-option selectable-option ${draft.correct_answer === key ? 'correct' : ''}"><input type="radio" name="reviewCorrectAnswer" value="${key}" ${draft.correct_answer === key ? 'checked' : ''} /><strong>${key}.</strong> ${escapeHtml(options[key])}</label>`).join('')}
      </div>
      <form id="draftVerificationForm" class="stack-form" novalidate>
        <div class="form-row">
          <label>Verified answer source
            <select name="answerSource" required>
              <option value="MANUALLY_VERIFIED" ${reviewSource === 'MANUALLY_VERIFIED' ? 'selected' : ''}>Manually verified</option>
              <option value="OFFICIAL_FINAL_KEY" ${reviewSource === 'OFFICIAL_FINAL_KEY' ? 'selected' : ''}>Official final key</option>
              <option value="OFFICIAL_PROVISIONAL_KEY" ${reviewSource === 'OFFICIAL_PROVISIONAL_KEY' ? 'selected' : ''}>Official provisional key</option>
              <option value="SOURCE_BOOK" ${reviewSource === 'SOURCE_BOOK' ? 'selected' : ''}>Source book</option>
              <option value="ADMIN_CORRECTED" ${reviewSource === 'ADMIN_CORRECTED' ? 'selected' : ''}>Admin corrected</option>
            </select>
          </label>
          <label>Approved primary topic
            <select name="topicId" ${draft.question_type === 'PYQ' ? 'required' : ''}>
              <option value="">${draft.question_type === 'PYQ' ? 'Select required topic' : 'Optional topic'}</option>
              ${topicOptionsForDraft(draft)}
            </select>
          </label>
        </div>
        <label>Reviewed explanation<textarea name="explanation" rows="6" required>${escapeHtml(draft.explanation || '')}</textarea></label>
        <label>Answer review note<textarea name="answerReviewNote" rows="3" placeholder="How the answer was checked or corrected">${escapeHtml(draft.answer_review_note || '')}</textarea></label>
        <label>Admin notes<textarea name="adminNotes" rows="3" placeholder="Transcription or topic corrections">${escapeHtml(draft.admin_notes || '')}</textarea></label>
        <div class="draft-item-actions">
          <button id="saveDraftVerification" class="button button-secondary" type="submit">Save human review</button>
          ${isDraftPublishReady(draft) ? `<button id="dialogPublish" class="button button-primary" type="button">Publish reviewed question</button>` : ''}
          <button id="dialogReject" class="button button-danger" type="button">Reject</button>
        </div>
      </form>
      ${draft.answer_source === 'AI_PROPOSED' ? '<p class="review-required-note">AI_PROPOSED is only a suggestion. Saving this review records your selected human-verifiable answer source.</p>' : ''}
    </div>
  `;
  const form = elements.dialogContent.querySelector('#draftVerificationForm');
  form?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!form.reportValidity()) return;
    const selected = elements.dialogContent.querySelector('input[name="reviewCorrectAnswer"]:checked')?.value;
    if (!selected) return toast.warning('Select the verified correct answer.');
    const values = Object.fromEntries(new FormData(form).entries());
    setBusy(form, true);
    const loading = toast.loading('Saving human answer and topic review…');
    try {
      await api.reviewDraftAnswerTopic({
        draftId,
        correctAnswer: selected,
        answerSource: values.answerSource,
        explanation: values.explanation,
        topicId: values.topicId,
        answerReviewNote: values.answerReviewNote,
        adminNotes: values.adminNotes,
      });
      loading.close();
      toast.success('Human answer and topic review saved.');
      elements.dialog.close();
      await loadDrafts();
    } catch (error) {
      loading.close();
      toast.error(error.message);
      setBusy(form, false);
    }
  });
  elements.dialogContent.querySelector('#dialogPublish')?.addEventListener('click', async () => { elements.dialog.close(); await publish(draftId); });
  elements.dialogContent.querySelector('#dialogReject')?.addEventListener('click', () => openRejectDialog(draftId));
  elements.dialog.showModal();
}

async function publish(draftId) {
  const loading = toast.loading('Publishing reviewed question…');
  try {
    const result = await api.publishDraft(draftId);
    loading.close();
    toast.success(`Published ${result.question_id || 'question'}.`);
    await loadDrafts();
  } catch (error) {
    loading.close();
    toast.error(error.message);
  }
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
    await loadDrafts();
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

function knownRepairableCount(report = currentImportReport) {
  const summaryCount = Number(report?.summary?.repairable_items || 0);
  if (summaryCount > 0) return summaryCount;
  return report?.items?.filter((item) => (
    !item.created_draft_id && (
      (item.validation_status === 'INVALID'
        && String(item.normalized_payload?.answer_source || '').toUpperCase() === 'AI_PROPOSED')
      || (item.errors || []).some((issue) => issue?.code === 'DRAFT_INSERT_FAILED')
      || Boolean(item.matched_draft_id)
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

  if (elements.importValidDrafts) {
    elements.importValidDrafts.disabled = !batchId || (ready === 0 && repairable === 0 && imported === 0);
    elements.importValidDrafts.textContent = ready > 0
      ? `2. Import ${ready} eligible draft${ready === 1 ? '' : 's'}`
      : repairable > 0
        ? `2. Repair ${repairable} record${repairable === 1 ? '' : 's'} and import`
        : imported > 0
          ? '2. Sync / resume draft import'
          : '2. Import all eligible drafts';
  }
  if (elements.syncImportBatch) elements.syncImportBatch.disabled = !batchId;
  if (elements.repairImportBatch) elements.repairImportBatch.disabled = !batchId || repairable === 0;
  if (elements.resetImportDrafts) elements.resetImportDrafts.disabled = !batchId || imported === 0;
  if (elements.linkDuplicateOccurrences) elements.linkDuplicateOccurrences.disabled = !batchId || occurrenceCount === 0;

  if (elements.importSelectionSummary) {
    elements.importSelectionSummary.textContent = batchId
      ? `${ready} ready for draft · ${imported} already drafted · ${errors} errors/conflicts · ${duplicates} duplicates${repairable ? ` · ${repairable} safely repairable` : ''}${occurrenceCount ? ` · ${occurrenceCount} occurrence selected` : ''}.`
      : 'Validate or open a package to see what is ready.';
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
    text: 'A timeout does not necessarily mean failure. ScoreMore is checking whether the server finished safely.',
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

function requestImportConfirmation({ title, message, buttonLabel }) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };

    elements.dialogContent.innerHTML = `
      <div class="review-content">
        <span class="eyebrow">Controlled import confirmation</span>
        <h2>${escapeHtml(title)}</h2>
        <p>${escapeHtml(message)}</p>
        <div class="import-safety-note">
          <strong>Architecture lock</strong>
          <span>This action creates draft_questions only. It never publishes directly to the master questions table.</span>
        </div>
        <div class="draft-item-actions">
          <button id="confirmImportAction" class="button button-primary" type="button">${escapeHtml(buttonLabel)}</button>
          <button id="cancelImportAction" class="button button-ghost" type="button">Cancel</button>
        </div>
      </div>
    `;
    elements.dialogContent.querySelector('#confirmImportAction')?.addEventListener('click', () => {
      finish(true);
      elements.dialog.close();
    });
    elements.dialogContent.querySelector('#cancelImportAction')?.addEventListener('click', () => {
      finish(false);
      elements.dialog.close();
    });
    elements.dialog.addEventListener('close', () => finish(false), { once: true });
    elements.dialog.showModal();
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
    const importedBefore = Number(report?.summary?.imported_to_draft || 0);

    if (ready === 0) {
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
      title: `Import ${ready} eligible record${ready === 1 ? '' : 's'}?`,
      message: 'ScoreMore will create drafts in small resumable chunks. Every record is revalidated, duplicates are skipped, and nothing is published automatically.',
      buttonLabel: 'Import all eligible drafts',
    });
    if (!confirmed) {
      hideImportProgress();
      return;
    }

    loading = toast.loading('Creating controlled drafts in small chunks…');
    let totalImportedThisRun = 0;
    let remaining = ready;
    const totalTarget = importedBefore + ready;

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
        remaining = Number(recoveredReport?.summary?.ready_for_draft || 0);
        if (remaining >= beforeRemaining) throw error;
      }
    }

    await api.reconcileImportBatchState(batchId);
    report = await api.getImportBatchReport(batchId);
    renderImportReport(report);
    await Promise.all([loadDrafts(), loadRecentImportBatches()]);
    hideImportProgress();
    loading.close();
    toast.success(`${totalImportedThisRun} new draft${totalImportedThisRun === 1 ? '' : 's'} created. Existing drafts were reused and no question was published.`);
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
    await Promise.all([loadDrafts(), loadRecentImportBatches()]);
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
    await Promise.all([loadDrafts(), loadRecentImportBatches()]);
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
  elements.loginForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!form.reportValidity()) return;
    const values = new FormData(form);
    setBusy(form, true);
    const loading = toast.loading('Signing in…');
    try {
      await api.signIn({ email: values.get('email'), password: values.get('password') });
      await showAdmin();
      loading.close();
      toast.success('Admin access verified.');
      form.reset();
    } catch (error) {
      loading.close();
      toast.error(error.message);
      try { await api.signOut(); } catch {}
    } finally { setBusy(form, false); }
  });

  elements.signOut?.addEventListener('click', async () => {
    try { await api.signOut(); toast.success('Signed out.'); showLogin(); }
    catch (error) { toast.error(error.message); }
  });

  elements.htmlImportForm?.addEventListener('submit', runImportDryRun);
  elements.importItemFilter?.addEventListener('change', () => { visibleImportItemLimit = IMPORT_ITEM_PAGE_SIZE; renderImportItems(); });
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

  document.getElementById('refreshDrafts')?.addEventListener('click', loadDrafts);
  elements.statusFilter?.addEventListener('change', loadDrafts);
  document.getElementById('draftBoardId')?.addEventListener('change', refreshDraftReferenceSelects);
  document.getElementById('draftExamId')?.addEventListener('change', refreshDraftReferenceSelects);
  document.getElementById('draftSubjectId')?.addEventListener('change', refreshDraftReferenceSelects);

  document.getElementById('refreshTests')?.addEventListener('click', loadConfiguredTests);
  elements.testStatusFilter?.addEventListener('change', loadConfiguredTests);
  document.getElementById('loadPublishedQuestions')?.addEventListener('click', loadPublishedQuestions);
  ['testBoardId', 'testExamId', 'testSubjectId', 'testTopicId'].forEach((id) => {
    document.getElementById(id)?.addEventListener('change', () => {
      refreshTestReferenceSelects();
      resetQuestionPicker();
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
      await loadDrafts();
    } catch (error) {
      loading.close();
      toast.error(error.message);
    } finally { setBusy(form, false); }
  });

  elements.testForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!form.reportValidity()) return;

    const questionIds = [...elements.publishedQuestionList.querySelectorAll('[data-question-id]:checked')]
      .map((checkbox) => checkbox.dataset.questionId)
      .filter(Boolean);

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
  try { await showAdmin(); }
  catch (error) { toast.error(error.message); showLogin(); }
}

initialize();
