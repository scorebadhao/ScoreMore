import { isConfigured } from './config.js';
import { api } from './api.js';
import { toast } from './toast.js';

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
};

let profile = null;
let drafts = [];
let referenceData = { boards: [], exams: [], subjects: [], topics: [] };

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function setBusy(form, busy) {
  form?.querySelectorAll('button, input, textarea, select').forEach((element) => element.disabled = busy);
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
  await loadDrafts();
}

function renderDrafts() {
  if (!drafts.length) {
    elements.draftList.innerHTML = '<div class="empty-state">No drafts match this status.</div>';
    return;
  }
  elements.draftList.innerHTML = drafts.map((draft) => `
    <article class="draft-item">
      <div class="draft-item-header">
        <div>
          <span class="eyebrow">${escapeHtml(draft.review_status)} · ${escapeHtml(draft.question_type)}</span>
          <h3>${escapeHtml(draft.proposed_question_id || 'Question ID required')}</h3>
        </div>
        <span class="chip">${escapeHtml(draft.subject_id || 'No subject')}</span>
      </div>
      <p>${escapeHtml(draft.question_text)}</p>
      <div class="draft-item-actions">
        <button class="button button-ghost" data-review="${draft.draft_id}" type="button">Review</button>
        ${['PENDING','IN_REVIEW','REJECTED'].includes(draft.review_status)
          ? `<button class="button button-primary" data-publish="${draft.draft_id}" type="button">Publish</button>` : ''}
        ${draft.review_status !== 'PUBLISHED'
          ? `<button class="button button-danger" data-reject="${draft.draft_id}" type="button">Reject</button>` : ''}
      </div>
    </article>
  `).join('');

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

function refreshReferenceSelects() {
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

async function loadReferenceData() {
  referenceData = await api.getAdminReferenceData();
  refreshReferenceSelects();
}

function openReview(draftId) {
  const draft = drafts.find((item) => item.draft_id === draftId);
  if (!draft) return;
  const options = draft.options || {};
  elements.dialogContent.innerHTML = `
    <div class="review-content">
      <span class="eyebrow">Human review</span>
      <h2>${escapeHtml(draft.proposed_question_id || 'Draft question')}</h2>
      <p><strong>Board:</strong> ${escapeHtml(draft.board_id)} · <strong>Exam:</strong> ${escapeHtml(draft.exam_id || '—')} · <strong>Subject:</strong> ${escapeHtml(draft.subject_id)}</p>
      <div class="question-text">${escapeHtml(draft.question_text)}</div>
      <div class="review-options">
        ${['A','B','C','D'].map((key) => `<div class="review-option ${draft.correct_answer === key ? 'correct' : ''}"><strong>${key}.</strong> ${escapeHtml(options[key])}</div>`).join('')}
      </div>
      <p><strong>Explanation:</strong> ${escapeHtml(draft.explanation || 'Not provided')}</p>
      <p><strong>Verification:</strong> ${escapeHtml(draft.verification_status)} · <strong>Answer source:</strong> ${escapeHtml(draft.answer_source || 'Not set')}</p>
      <div class="draft-item-actions">
        ${draft.review_status !== 'PUBLISHED' ? `<button id="dialogPublish" class="button button-primary" type="button">Publish reviewed question</button>` : ''}
        ${draft.review_status !== 'PUBLISHED' ? `<button id="dialogReject" class="button button-danger" type="button">Reject</button>` : ''}
      </div>
    </div>
  `;
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

function bindEvents() {
  elements.loginForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
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

  document.getElementById('refreshDrafts')?.addEventListener('click', loadDrafts);
  elements.statusFilter?.addEventListener('change', loadDrafts);
  document.getElementById('draftBoardId')?.addEventListener('change', refreshReferenceSelects);
  document.getElementById('draftExamId')?.addEventListener('change', refreshReferenceSelects);
  document.getElementById('draftSubjectId')?.addEventListener('change', refreshReferenceSelects);

  elements.sourceUploadForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
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
