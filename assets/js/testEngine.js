import { APP_CONFIG } from './config.js';
import { api } from './api.js';
import { toast } from './toast.js';

const QUEUE_KEY = `${APP_CONFIG.cacheVersion}:answer-sync-queue`;
const FINAL_STATUSES = new Set(['SUBMITTED', 'AUTO_SUBMITTED', 'ABANDONED']);

function readQueue() {
  try { return JSON.parse(localStorage.getItem(QUEUE_KEY) || '[]'); }
  catch { return []; }
}

function writeQueue(queue) {
  localStorage.setItem(QUEUE_KEY, JSON.stringify(queue));
}

function enqueueAnswer(payload) {
  const queue = readQueue().filter((item) => !(
    item.attemptId === payload.attemptId && item.questionId === payload.questionId
  ));
  queue.push(payload);
  writeQueue(queue);
}

function removeQueuedAnswer(attemptId, questionId) {
  writeQueue(readQueue().filter((item) => !(
    item.attemptId === attemptId && item.questionId === questionId
  )));
}

function clearAttemptQueue(attemptId) {
  writeQueue(readQueue().filter((item) => item.attemptId !== attemptId));
}

function queuedAnswersFor(attemptId) {
  return readQueue().filter((item) => item.attemptId === attemptId);
}

async function flushQueue({ attemptId = '' } = {}) {
  if (!navigator.onLine) return { failed: [], terminal: [] };
  const retained = [];
  const failed = [];
  const terminal = [];

  for (const item of readQueue()) {
    if (attemptId && item.attemptId !== attemptId) {
      retained.push(item);
      continue;
    }

    try {
      const result = await api.saveAnswer(item);
      if (FINAL_STATUSES.has(result?.status)) terminal.push(result);
    } catch {
      failed.push(item);
      retained.push(item);
    }
  }

  writeQueue(retained);
  return { failed, terminal };
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function normalizedLabel(value) {
  return String(value || '').trim().toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
}

function safeImageUrl(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  try {
    const parsed = new URL(raw, window.location.href);
    return ['http:', 'https:', 'blob:', 'data:'].includes(parsed.protocol) ? parsed.href : '';
  } catch {
    return '';
  }
}

function imageItems(imageRefs) {
  const refs = Array.isArray(imageRefs) ? imageRefs : [];
  return refs.map((item) => {
    if (item?.blocked) return { blocked: true };
    const rawUrl = typeof item === 'string' ? item : item?.url || item?.ref;
    const url = safeImageUrl(rawUrl);
    return url ? { url } : null;
  }).filter(Boolean);
}

function formatTimer(totalSeconds) {
  const seconds = Math.max(0, Math.floor(Number(totalSeconds) || 0));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;
  return hours
    ? `${hours}:${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`
    : `${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`;
}

export async function mountTestEngine(root, attemptId, { onExit } = {}) {
  if (!root) throw new Error('Test engine root was not found.');

  const state = {
    attempt: null,
    questions: new Map(),
    navigation: [],
    navigationByIndex: new Map(),
    sections: [],
    lastIndexBySection: new Map(),
    visited: new Set(),
    currentIndex: 0,
    questionStartedAt: Date.now(),
    deadlineEpoch: null,
    timerId: null,
    submitting: false,
    expired: false,
    completed: false,
    destroyed: false,
    syncStatus: navigator.onLine ? 'saved' : 'offline',
  };

  const localVisitedKey = `${APP_CONFIG.cacheVersion}:attempt:${attemptId}:visited`;
  const localLastIndexKey = `${APP_CONFIG.cacheVersion}:attempt:${attemptId}:last-index`;

  function localAnswerKey(questionId) {
    return `${APP_CONFIG.cacheVersion}:attempt:${attemptId}:answer:${questionId}`;
  }

  function saveLocal(questionId, selectedAnswer, markedReview = false) {
    localStorage.setItem(localAnswerKey(questionId), JSON.stringify({ selectedAnswer, markedReview }));
  }

  function getLocal(questionId) {
    try { return JSON.parse(localStorage.getItem(localAnswerKey(questionId)) || 'null'); }
    catch { return null; }
  }

  function removeLocal(questionId) {
    localStorage.removeItem(localAnswerKey(questionId));
  }

  function readLocalVisited() {
    try {
      const value = JSON.parse(localStorage.getItem(localVisitedKey) || '[]');
      return Array.isArray(value) ? value.map(Number).filter(Number.isInteger) : [];
    } catch {
      return [];
    }
  }

  function saveLocalVisited() {
    localStorage.setItem(localVisitedKey, JSON.stringify([...state.visited].sort((a, b) => a - b)));
  }

  function currentQuestion() {
    return state.questions.get(state.currentIndex) || null;
  }

  function navigationItem(index) {
    return state.navigationByIndex.get(index) || null;
  }

  function answerStateForItem(item) {
    if (!item) return { selectedAnswer: null, markedReview: false };
    const local = getLocal(item.question_id);
    return {
      selectedAnswer: local?.selectedAnswer ?? item.selected_answer ?? null,
      markedReview: Boolean(local?.markedReview ?? item.marked_review),
    };
  }

  function answerState(question) {
    if (!question) return { selectedAnswer: null, markedReview: false };
    return answerStateForItem(navigationItem(state.currentIndex) || question);
  }

  function hasVisited(index, item = navigationItem(index)) {
    const answer = answerStateForItem(item);
    return state.visited.has(index) || Boolean(item?.visited_at) || Boolean(answer.selectedAnswer) || answer.markedReview;
  }

  function questionStatus(index) {
    const item = navigationItem(index);
    if (!item) return 'not-visited';
    const answer = answerStateForItem(item);
    if (answer.markedReview && answer.selectedAnswer) return 'answered-review';
    if (answer.markedReview) return 'review';
    if (answer.selectedAnswer) return 'answered';
    return hasVisited(index, item) ? 'unanswered' : 'not-visited';
  }

  function statusCounts(items = state.navigation) {
    const counts = { answered: 0, review: 0, unanswered: 0, notVisited: 0 };
    items.forEach((item) => {
      const index = Number(item.position) - 1;
      const answer = answerStateForItem(item);
      const visited = hasVisited(index, item);
      if (answer.selectedAnswer) counts.answered += 1;
      if (answer.markedReview) counts.review += 1;
      if (!answer.selectedAnswer && visited) counts.unanswered += 1;
      if (!answer.selectedAnswer && !visited) counts.notVisited += 1;
    });
    return counts;
  }

  function sectionKey(item) {
    return String(item?.section_code || item?.subject_id || item?.subject_name || 'GENERAL').trim().toUpperCase();
  }

  function sectionLabel(item) {
    const subject = String(item?.subject_name || '').trim();
    const code = String(item?.section_code || '').trim();
    if (subject && code && normalizedLabel(subject) === normalizedLabel(code)) return subject;
    return subject || code || 'General';
  }

  function rebuildSections() {
    const sectionMap = new Map();
    state.navigation.forEach((item) => {
      const key = sectionKey(item);
      item._sectionKey = key;
      if (!sectionMap.has(key)) sectionMap.set(key, { key, label: sectionLabel(item), items: [] });
      sectionMap.get(key).items.push(item);
    });
    state.sections = [...sectionMap.values()];

    state.sections.forEach((section) => {
      const visited = section.items
        .filter((item) => hasVisited(Number(item.position) - 1, item))
        .sort((a, b) => new Date(b.visited_at || 0) - new Date(a.visited_at || 0));
      if (visited.length) state.lastIndexBySection.set(section.key, Number(visited[0].position) - 1);
    });
  }

  function currentSection() {
    const item = navigationItem(state.currentIndex);
    const key = sectionKey(item);
    return state.sections.find((section) => section.key === key) || state.sections[0] || null;
  }

  function markVisited(index) {
    const item = navigationItem(index);
    state.visited.add(index);
    if (item && !item.visited_at) item.visited_at = new Date().toISOString();
    if (item) state.lastIndexBySection.set(sectionKey(item), index);
    localStorage.setItem(localLastIndexKey, String(index));
    saveLocalVisited();
  }

  function applyNavigationSnapshot(snapshot) {
    const items = Array.isArray(snapshot?.items) ? snapshot.items : [];
    const queuedQuestionIds = new Set(queuedAnswersFor(attemptId).map((item) => item.questionId));
    if (!['saving', 'retrying'].includes(state.syncStatus)) {
      items.forEach((item) => {
        if (!queuedQuestionIds.has(item.question_id)) removeLocal(item.question_id);
      });
    }
    state.navigation = items
      .map((item) => ({ ...item, position: Number(item.position) }))
      .filter((item) => Number.isInteger(item.position) && item.position > 0)
      .sort((a, b) => a.position - b.position);
    state.navigationByIndex = new Map(state.navigation.map((item) => [item.position - 1, item]));

    readLocalVisited().forEach((index) => {
      if (state.navigationByIndex.has(index)) state.visited.add(index);
    });
    state.navigation.forEach((item) => {
      const index = item.position - 1;
      if (item.visited_at || item.selected_answer || item.marked_review) state.visited.add(index);
    });

    const remaining = snapshot?.seconds_remaining;
    state.deadlineEpoch = remaining === null || remaining === undefined
      ? null
      : Date.now() + (Math.max(0, Number(remaining) || 0) * 1000);
    rebuildSections();
  }

  function initialIndex() {
    const total = state.navigation.length;
    const saved = Number(localStorage.getItem(localLastIndexKey));
    if (Number.isInteger(saved) && saved >= 0 && saved < total) return saved;

    const latestVisited = [...state.navigation]
      .filter((item) => item.visited_at)
      .sort((a, b) => new Date(b.visited_at) - new Date(a.visited_at))[0];
    if (latestVisited) return Number(latestVisited.position) - 1;

    const unanswered = state.navigation.find((item) => !answerStateForItem(item).selectedAnswer);
    return unanswered ? Number(unanswered.position) - 1 : 0;
  }

  function sectionTarget(key) {
    const section = state.sections.find((item) => item.key === key);
    if (!section) return state.currentIndex;
    const remembered = state.lastIndexBySection.get(key);
    if (Number.isInteger(remembered)) return remembered;
    const unanswered = section.items.find((item) => !answerStateForItem(item).selectedAnswer);
    return Number((unanswered || section.items[0]).position) - 1;
  }

  async function ensureQuestion(index) {
    if (state.questions.has(index)) return;
    const offset = Math.floor(index / APP_CONFIG.questionBatchSize) * APP_CONFIG.questionBatchSize;
    const batch = await api.loadQuestionBatch(attemptId, offset, APP_CONFIG.questionBatchSize);
    batch.forEach((question, batchIndex) => {
      const normalizedIndex = Number(question.position) - 1;
      const resolvedIndex = Number.isFinite(normalizedIndex) ? normalizedIndex : offset + batchIndex;
      const navItem = navigationItem(resolvedIndex);
      if (navItem) {
        question.selected_answer = answerStateForItem(navItem).selectedAnswer;
        question.marked_review = answerStateForItem(navItem).markedReview;
      }
      state.questions.set(resolvedIndex, question);
    });

    if (!state.questions.has(index)) {
      const snapshot = await api.getAttemptNavigation(attemptId);
      if (FINAL_STATUSES.has(snapshot?.status)) {
        await showFinalAttempt(snapshot);
        const handled = new Error('This attempt has ended.');
        handled.handled = true;
        throw handled;
      }
      throw new Error('This question could not be loaded.');
    }
  }

  function renderLoading(message = 'Loading question…') {
    if (state.destroyed) return;
    root.innerHTML = `<div class="loading-state test-loading-state"><span class="spinner"></span>${escapeHtml(message)}</div>`;
  }

  function sectionTabsMarkup() {
    if (state.sections.length <= 1) return '';
    const activeKey = currentSection()?.key;
    return `
      <nav class="test-section-tabs" aria-label="Test sections" role="tablist">
        ${state.sections.map((section) => {
          const counts = statusCounts(section.items);
          const active = section.key === activeKey;
          return `
            <button class="test-section-tab ${active ? 'active' : ''}" data-section-key="${escapeHtml(section.key)}" type="button" role="tab" aria-selected="${active}">
              <span>${escapeHtml(section.label)}</span><b>${counts.answered}/${section.items.length}</b>
            </button>
          `;
        }).join('')}
      </nav>
    `;
  }

  function paletteMarkup(items) {
    return items.map((item) => {
      const index = Number(item.position) - 1;
      const status = questionStatus(index);
      return `<button class="palette-button ${status} ${state.currentIndex === index ? 'current' : ''}" data-question-index="${index}" type="button" aria-label="Open question ${item.position}">${item.position}</button>`;
    }).join('');
  }

  function imageMarkup(question) {
    const items = imageItems(question.image_refs);
    if (!items.length) return '';
    if (items.some((item) => item.blocked)) {
      return `
        <div class="question-image-review" role="note">
          <strong>Diagram temporarily hidden</strong>
          <span>This source image needs a student-safe crop before it can appear in an exam.</span>
        </div>
      `;
    }
    return `
      <div class="question-images" aria-label="Question diagrams">
        ${items.map((item, index) => `
          <figure class="question-image-frame">
            <img class="question-image" src="${escapeHtml(item.url)}" alt="Question diagram ${index + 1}" loading="lazy" decoding="async" />
          </figure>
        `).join('')}
      </div>
    `;
  }

  function syncLabel() {
    if (state.syncStatus === 'saving') return 'Saving…';
    if (state.syncStatus === 'offline') return 'Saved on device';
    if (state.syncStatus === 'retrying') return 'Retrying…';
    return 'Saved';
  }

  function setSyncStatus(status) {
    state.syncStatus = status;
    const badge = root.querySelector('#testSyncState');
    if (!badge) return;
    badge.textContent = syncLabel();
    badge.classList.toggle('offline', status === 'offline');
    badge.classList.toggle('saving', status === 'saving' || status === 'retrying');
  }

  function remainingSeconds() {
    if (state.deadlineEpoch === null) return null;
    return Math.max(0, Math.ceil((state.deadlineEpoch - Date.now()) / 1000));
  }

  function updateTimerDisplay() {
    const timer = root.querySelector('#testTimer');
    if (!timer || state.deadlineEpoch === null) return;
    const remaining = remainingSeconds();
    timer.textContent = formatTimer(remaining);
    timer.classList.toggle('warning', remaining <= 300 && remaining > 60);
    timer.classList.toggle('urgent', remaining <= 60);
    if (remaining <= 0) handleTimeExpired();
  }

  function startTimer() {
    window.clearInterval(state.timerId);
    if (state.deadlineEpoch === null || state.completed || state.destroyed) return;
    updateTimerDisplay();
    state.timerId = window.setInterval(updateTimerDisplay, 1000);
  }

  function stopTimer() {
    window.clearInterval(state.timerId);
    state.timerId = null;
  }

  function questionMetaMarkup(question) {
    const subject = String(question.subject_name || '').trim();
    const section = String(question.section_code || '').trim();
    const labels = [];
    if (subject) labels.push(subject);
    if (section && normalizedLabel(section) !== normalizedLabel(subject)) labels.push(section);
    if (!labels.length) labels.push('General');
    return labels.map((label) => `<span class="chip">${escapeHtml(label)}</span>`).join('');
  }

  function renderQuestion() {
    if (state.destroyed || state.completed) return;
    const question = currentQuestion();
    if (!question) return renderLoading();

    const answer = answerState(question);
    const test = state.attempt.tests || {};
    const total = Number(state.attempt.total_questions || state.navigation.length || 0);
    const counts = statusCounts();
    const answeredProgress = total ? Math.round((counts.answered / total) * 100) : 0;
    const section = currentSection();
    const sectionCounts = statusCounts(section?.items || []);
    const disabled = state.expired || state.submitting ? 'disabled' : '';

    root.innerHTML = `
      <article class="test-workspace">
        <header class="test-workspace-header">
          <button id="engineExit" class="icon-button test-exit-button" type="button" aria-label="Exit test">←</button>
          <div class="test-workspace-title">
            <strong>${escapeHtml(test.test_name || 'Test')}</strong>
            <span>Question ${state.currentIndex + 1} of ${total} · ${counts.answered} answered</span>
          </div>
          <div class="test-header-status">
            ${state.deadlineEpoch === null ? '' : `<span id="testTimer" class="test-timer" aria-label="Time remaining">${formatTimer(remainingSeconds())}</span>`}
            <span id="testSyncState" class="test-sync-state ${state.syncStatus === 'offline' ? 'offline' : ''} ${['saving', 'retrying'].includes(state.syncStatus) ? 'saving' : ''}" aria-live="polite">${syncLabel()}</span>
          </div>
        </header>

        <div class="test-progress-track" aria-label="${counts.answered} of ${total} questions answered"><span style="width:${answeredProgress}%"></span></div>
        ${sectionTabsMarkup()}

        <div class="test-layout">
          <section class="question-panel card">
            <div class="question-card-head">
              <div class="test-meta">${questionMetaMarkup(question)}</div>
              <span class="question-number-badge">Q${state.currentIndex + 1}</span>
            </div>
            <div class="question-text">${escapeHtml(question.question_text)}</div>
            ${imageMarkup(question)}
            <div class="option-list">
              ${['A', 'B', 'C', 'D'].map((key) => `
                <button class="option-button ${answer.selectedAnswer === key ? 'selected' : ''}" data-answer="${key}" ${disabled} type="button" aria-pressed="${answer.selectedAnswer === key}">
                  <span class="option-key">${key}</span>
                  <span class="option-text">${escapeHtml(question.options?.[key] || '')}</span>
                  <span class="option-check" aria-hidden="true">✓</span>
                </button>
              `).join('')}
            </div>
            <div class="question-tools">
              <button id="clearResponse" class="text-button" ${answer.selectedAnswer && !state.expired ? '' : 'disabled'} type="button">Clear response</button>
              <button id="markReview" class="button ${answer.markedReview ? 'button-warning' : 'button-ghost'}" ${disabled} type="button">
                <svg class="icon"><use href="#i-flag"></use></svg><span>${answer.markedReview ? 'Marked for review' : 'Mark for review'}</span>
              </button>
            </div>
          </section>

          <aside class="palette-panel card">
            <div class="palette-head">
              <div><span class="eyebrow">Question navigator</span><h3>${escapeHtml(section?.label || 'Test overview')}</h3></div>
              <strong>${sectionCounts.answered}/${section?.items.length || total}</strong>
            </div>
            <div class="status-summary">
              <span><b>${sectionCounts.answered}</b> Answered</span>
              <span><b>${sectionCounts.review}</b> Review</span>
              <span><b>${sectionCounts.unanswered}</b> Unanswered</span>
              <span><b>${sectionCounts.notVisited}</b> Not visited</span>
            </div>
            <div class="palette-legend">
              <span><i class="answered"></i>Answered</span>
              <span><i class="review"></i>Review</span>
              <span><i class="unanswered"></i>Unanswered</span>
              <span><i class="not-visited"></i>Not visited</span>
            </div>
            <div class="palette-grid">${paletteMarkup(section?.items || state.navigation)}</div>
          </aside>
        </div>

        <footer class="test-action-bar" aria-label="Question actions">
          <button id="previousQuestion" class="button button-ghost" ${state.currentIndex === 0 || state.expired ? 'disabled' : ''} type="button">← Previous</button>
          ${state.currentIndex + 1 >= total
            ? `<button id="submitAttempt" class="button button-primary" ${state.expired || state.submitting ? 'disabled' : ''} type="button">Submit test</button>`
            : `<button id="nextQuestion" class="button button-primary" ${state.expired ? 'disabled' : ''} type="button">Next →</button>`}
        </footer>
      </article>
    `;

    root.querySelectorAll('[data-answer]').forEach((button) => {
      button.addEventListener('click', () => {
        persistAnswer(question, button.dataset.answer, answerState(question).markedReview);
      });
    });
    root.querySelectorAll('[data-question-index]').forEach((button) => {
      button.addEventListener('click', () => goTo(Number(button.dataset.questionIndex)));
    });
    root.querySelectorAll('[data-section-key]').forEach((button) => {
      button.addEventListener('click', () => goTo(sectionTarget(button.dataset.sectionKey)));
    });
    root.querySelector('#previousQuestion')?.addEventListener('click', () => move(-1));
    root.querySelector('#nextQuestion')?.addEventListener('click', () => move(1));
    root.querySelector('#engineExit')?.addEventListener('click', exitEngine);
    root.querySelector('#clearResponse')?.addEventListener('click', () => persistAnswer(question, null, answerState(question).markedReview));
    root.querySelector('#markReview')?.addEventListener('click', () => {
      const current = answerState(question);
      persistAnswer(question, current.selectedAnswer, !current.markedReview);
    });
    root.querySelector('#submitAttempt')?.addEventListener('click', confirmSubmit);

    root.querySelector('.test-section-tab.active')?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
    updateTimerDisplay();
  }

  async function persistAnswer(question, selectedAnswer, markedReview) {
    if (state.expired || state.submitting || state.completed) return;
    const elapsed = Math.max(0, Math.round((Date.now() - state.questionStartedAt) / 1000));
    const payload = {
      attemptId,
      questionId: question.question_id,
      selectedAnswer,
      markedReview: Boolean(markedReview),
      timeTakenSeconds: elapsed,
    };

    saveLocal(question.question_id, selectedAnswer, payload.markedReview);
    question.selected_answer = selectedAnswer;
    question.marked_review = payload.markedReview;
    const item = navigationItem(state.currentIndex);
    if (item) {
      item.selected_answer = selectedAnswer;
      item.marked_review = payload.markedReview;
    }
    markVisited(state.currentIndex);
    state.syncStatus = navigator.onLine ? 'saving' : 'offline';
    renderQuestion();

    try {
      const result = await api.saveAnswer(payload);
      if (FINAL_STATUSES.has(result?.status)) {
        await showFinalAttempt(result);
        return;
      }
      removeQueuedAnswer(attemptId, question.question_id);
      removeLocal(question.question_id);
      setSyncStatus('saved');
    } catch {
      enqueueAnswer(payload);
      setSyncStatus('offline');
      toast.warning('Answer saved on this device. It will synchronize when the connection returns.');
    }
  }

  async function saveVisit(question) {
    if (!question || state.expired || state.completed || state.destroyed) return;
    try {
      const result = await api.visitAttemptQuestion(attemptId, question.question_id);
      if (FINAL_STATUSES.has(result?.status)) await showFinalAttempt(result);
    } catch {
      // The local visited state remains accurate on this device. A later answer save
      // or navigation refresh will reconcile the protected server snapshot.
    }
  }

  async function goTo(index) {
    if (state.expired || state.completed || state.destroyed) return;
    const total = Number(state.attempt.total_questions || state.navigation.length || 0);
    const next = Math.min(Math.max(Number(index) || 0, 0), total - 1);
    if (next === state.currentIndex) return;
    renderLoading();
    try {
      await ensureQuestion(next);
      state.currentIndex = next;
      state.questionStartedAt = Date.now();
      markVisited(next);
      renderQuestion();
      saveVisit(currentQuestion());
    } catch (error) {
      if (error.handled) return;
      toast.error(error.message);
      renderQuestion();
    }
  }

  async function move(delta) {
    await goTo(state.currentIndex + delta);
  }

  function confirmSubmit() {
    if (state.expired || state.submitting || state.completed) return;
    const counts = statusCounts();
    const total = Number(state.attempt.total_questions || state.navigation.length || 0);
    const dialog = document.createElement('dialog');
    dialog.className = 'review-dialog submit-dialog';
    dialog.innerHTML = `
      <div class="review-content section">
        <span class="eyebrow">Final submission</span>
        <h2>Submit this test?</h2>
        <p>Your answers will be scored securely on the server. You cannot edit this attempt after submission.</p>
        <div class="submit-summary-grid">
          <span><b>${counts.answered}</b>Answered</span>
          <span><b>${counts.review}</b>Marked for review</span>
          <span><b>${total - counts.answered}</b>Unanswered</span>
          <span><b>${total}</b>Total</span>
        </div>
        <div class="draft-item-actions">
          <button id="confirmFinalSubmit" class="button button-primary" type="button">Confirm submit</button>
          <button id="cancelFinalSubmit" class="button button-ghost" type="button">Continue test</button>
        </div>
      </div>
    `;
    const close = () => { dialog.close(); dialog.remove(); };
    dialog.querySelector('#cancelFinalSubmit').addEventListener('click', close);
    dialog.querySelector('#confirmFinalSubmit').addEventListener('click', () => {
      close();
      submit();
    });
    document.body.append(dialog);
    dialog.showModal();
  }

  async function submit({ automatic = false } = {}) {
    if (state.submitting || state.completed || state.destroyed) return;
    state.submitting = true;
    renderQuestion();
    const loading = toast.loading(automatic ? 'Time is up. Submitting your test…' : 'Submitting and calculating result…');
    try {
      if (!automatic) {
        setSyncStatus('retrying');
        await flushQueue({ attemptId });
        if (queuedAnswersFor(attemptId).length) {
          throw new Error('Some answers are still offline. Reconnect before final submission.');
        }
      }
      const result = await api.submitAttempt(attemptId);
      loading.close();
      toast.success(automatic ? 'Time ended. Your test was submitted automatically.' : 'Test submitted successfully.');
      renderResult(result);
    } catch (error) {
      loading.close();
      toast.error(error.message);
      state.submitting = false;
      if (!automatic) renderQuestion();
    }
  }

  async function handleTimeExpired() {
    if (state.expired || state.completed || state.destroyed) return;
    state.expired = true;
    stopTimer();
    renderQuestion();
    if (!navigator.onLine) {
      setSyncStatus('offline');
      toast.warning('Time is up. The attempt is locked and will submit when the connection returns.');
      return;
    }
    await submit({ automatic: true });
  }

  async function showFinalAttempt(result = {}) {
    stopTimer();
    try {
      const attempt = await api.getAttempt(attemptId);
      state.attempt = attempt;
      renderResult({
        score: attempt.score,
        accuracy: attempt.accuracy,
        correct: attempt.correct,
        wrong: attempt.wrong,
        skipped: attempt.skipped,
        time_taken_seconds: attempt.time_taken_seconds,
        status: attempt.status,
        ...result,
      });
    } catch {
      renderResult(result);
    }
  }

  function renderResult(result) {
    stopTimer();
    state.completed = true;
    state.submitting = false;
    clearAttemptQueue(attemptId);
    const total = Number(state.attempt.total_questions || state.navigation.length || 0);
    const marksPerQuestion = Number(state.attempt.tests?.marks_per_question || 1);
    const maxScore = total * marksPerQuestion;
    const skipped = Number(result.skipped ?? state.attempt.skipped ?? Math.max(0, total - Number(result.correct || 0) - Number(result.wrong || 0)));
    const timeTaken = Number(result.time_taken_seconds ?? state.attempt.time_taken_seconds ?? 0);
    const minutes = Math.floor(timeTaken / 60);
    const seconds = timeTaken % 60;
    const automatic = (result.status || state.attempt.status) === 'AUTO_SUBMITTED';

    root.innerHTML = `
      <article class="result-shell card">
        <div class="result-hero">
          <span class="eyebrow light">${automatic ? 'Time completed' : 'Test completed'}</span>
          <h2>${escapeHtml(state.attempt.tests?.test_name || 'Test complete')}</h2>
          <p>${automatic ? 'The time limit ended and your saved answers were scored securely.' : 'Your attempt was scored securely on the ScoreMore database.'}</p>
          <div class="result-score-line"><strong>${escapeHtml(result.score ?? 0)}</strong><span>/ ${escapeHtml(maxScore)}</span></div>
        </div>
        <div class="result-grid">
          <div class="result-kpi"><strong>${escapeHtml(result.accuracy ?? 0)}%</strong><span>Accuracy</span></div>
          <div class="result-kpi correct"><strong>${escapeHtml(result.correct ?? 0)}</strong><span>Correct</span></div>
          <div class="result-kpi wrong"><strong>${escapeHtml(result.wrong ?? 0)}</strong><span>Wrong</span></div>
          <div class="result-kpi skipped"><strong>${escapeHtml(skipped)}</strong><span>Skipped</span></div>
        </div>
        <div class="result-facts">
          <span><svg class="icon"><use href="#i-clock"></use></svg>${minutes}m ${seconds}s</span>
          <span><b>${escapeHtml(state.attempt.tests?.negative_marks ?? 0)}</b> negative marks</span>
          <span>Detailed review: Phase 5</span>
        </div>
        <div class="button-row">
          <button id="resultExit" class="button button-primary" type="button">Back to tests</button>
          <button id="resultHome" class="button button-ghost" type="button">Dashboard</button>
        </div>
      </article>
    `;
    root.querySelector('#resultExit')?.addEventListener('click', exitEngine);
    root.querySelector('#resultHome')?.addEventListener('click', exitEngine);
  }

  async function refreshNavigation() {
    if (state.completed || state.destroyed) return;
    const snapshot = await api.getAttemptNavigation(attemptId);
    if (FINAL_STATUSES.has(snapshot?.status)) {
      await showFinalAttempt(snapshot);
      return;
    }
    applyNavigationSnapshot(snapshot);
    const current = navigationItem(state.currentIndex);
    if (current && state.questions.has(state.currentIndex)) {
      const question = state.questions.get(state.currentIndex);
      question.selected_answer = answerStateForItem(current).selectedAnswer;
      question.marked_review = answerStateForItem(current).markedReview;
    }
    startTimer();
    renderQuestion();
  }

  async function handleOnline() {
    if (state.destroyed || state.completed) return;
    if (state.expired) {
      await submit({ automatic: true });
      return;
    }
    setSyncStatus('retrying');
    await flushQueue({ attemptId });
    await refreshNavigation();
    setSyncStatus(queuedAnswersFor(attemptId).length ? 'offline' : 'saved');
  }

  function handleOffline() {
    if (!state.completed && !state.destroyed) setSyncStatus('offline');
  }

  function handleVisibilityChange() {
    if (document.visibilityState === 'visible' && navigator.onLine && !state.completed && !state.destroyed) {
      refreshNavigation().catch(() => {});
    }
  }

  function destroy() {
    if (state.destroyed) return;
    state.destroyed = true;
    stopTimer();
    window.removeEventListener('online', handleOnline);
    window.removeEventListener('offline', handleOffline);
    document.removeEventListener('visibilitychange', handleVisibilityChange);
  }

  function exitEngine() {
    destroy();
    onExit?.();
  }

  window.addEventListener('online', handleOnline);
  window.addEventListener('offline', handleOffline);
  document.addEventListener('visibilitychange', handleVisibilityChange);

  try {
    renderLoading('Opening your test…');
    await flushQueue({ attemptId });
    state.attempt = await api.getAttempt(attemptId);

    if (state.attempt.status !== 'IN_PROGRESS') {
      await showFinalAttempt();
      return destroy;
    }

    const snapshot = await api.getAttemptNavigation(attemptId);
    if (FINAL_STATUSES.has(snapshot?.status)) {
      await showFinalAttempt(snapshot);
      return destroy;
    }

    applyNavigationSnapshot(snapshot);
    if (!state.navigation.length) throw new Error('This attempt has no available questions.');

    state.currentIndex = initialIndex();
    await ensureQuestion(state.currentIndex);
    state.questionStartedAt = Date.now();
    markVisited(state.currentIndex);
    renderQuestion();
    startTimer();
    saveVisit(currentQuestion());
    return destroy;
  } catch (error) {
    destroy();
    throw error;
  }
}
