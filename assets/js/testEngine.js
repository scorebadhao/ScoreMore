import { APP_CONFIG } from './config.js';
import { api } from './api.js';
import { toast } from './toast.js';

const QUEUE_KEY = `${APP_CONFIG.cacheVersion}:answer-sync-queue`;

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

async function flushQueue() {
  if (!navigator.onLine) return;
  const queue = readQueue();
  if (!queue.length) return;
  const failed = [];
  for (const item of queue) {
    try { await api.saveAnswer(item); }
    catch { failed.push(item); }
  }
  writeQueue(failed);
}

window.addEventListener('online', () => {
  flushQueue().catch(() => {});
});

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

export async function mountTestEngine(root, attemptId, { onExit } = {}) {
  if (!root) throw new Error('Test engine root was not found.');

  const state = {
    attempt: null,
    questions: new Map(),
    currentIndex: 0,
    questionStartedAt: Date.now(),
    submitting: false,
  };

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

  function currentQuestion() {
    return state.questions.get(state.currentIndex) || null;
  }

  async function ensureQuestion(index) {
    if (state.questions.has(index)) return;
    const offset = Math.floor(index / APP_CONFIG.questionBatchSize) * APP_CONFIG.questionBatchSize;
    const batch = await api.loadQuestionBatch(attemptId, offset, APP_CONFIG.questionBatchSize);
    batch.forEach((question, batchIndex) => {
      const normalizedIndex = Number(question.position) - 1;
      state.questions.set(Number.isFinite(normalizedIndex) ? normalizedIndex : offset + batchIndex, question);
    });
    if (!state.questions.has(index)) throw new Error('This question could not be loaded.');
  }

  function renderLoading(message = 'Loading question…') {
    root.innerHTML = `<div class="loading-state">${escapeHtml(message)}</div>`;
  }

  function renderQuestion() {
    const question = currentQuestion();
    if (!question) return renderLoading();
    const local = getLocal(question.question_id);
    const selected = local?.selectedAnswer ?? question.selected_answer ?? null;
    const test = state.attempt.tests || {};
    const total = Number(state.attempt.total_questions || 0);

    root.innerHTML = `
      <article class="test-engine">
        <header class="test-engine-header">
          <div>
            <strong>${escapeHtml(test.test_name || 'Test')}</strong>
            <div class="question-progress">Question ${state.currentIndex + 1} of ${total}</div>
          </div>
          <button id="engineExit" class="button button-ghost" type="button">Exit</button>
        </header>
        <div class="test-engine-body">
          <div class="test-meta">
            <span class="chip">${escapeHtml(question.subject_name || 'General')}</span>
            ${question.section_code ? `<span class="chip">${escapeHtml(question.section_code)}</span>` : ''}
            ${question.difficulty ? `<span class="chip">${escapeHtml(question.difficulty)}</span>` : ''}
          </div>
          <div class="question-text">${escapeHtml(question.question_text)}</div>
          <div class="option-list">
            ${['A','B','C','D'].map((key) => `
              <button class="option-button ${selected === key ? 'selected' : ''}" data-answer="${key}" type="button">
                <span class="option-key">${key}</span>
                <span>${escapeHtml(question.options?.[key] || '')}</span>
              </button>
            `).join('')}
          </div>
        </div>
        <footer class="test-engine-footer">
          <button id="previousQuestion" class="button button-ghost" ${state.currentIndex === 0 ? 'disabled' : ''} type="button">Previous</button>
          <div class="test-meta">
            <button id="markReview" class="button button-ghost" type="button">${local?.markedReview || question.marked_review ? 'Unmark review' : 'Mark review'}</button>
            ${state.currentIndex + 1 >= total
              ? '<button id="submitAttempt" class="button button-primary" type="button">Submit Test</button>'
              : '<button id="nextQuestion" class="button button-primary" type="button">Next</button>'}
          </div>
        </footer>
      </article>
    `;

    root.querySelectorAll('[data-answer]').forEach((button) => {
      button.addEventListener('click', async () => {
        const answer = button.dataset.answer;
        const elapsed = Math.max(0, Math.round((Date.now() - state.questionStartedAt) / 1000));
        const currentLocal = getLocal(question.question_id);
        const payload = {
          attemptId,
          questionId: question.question_id,
          selectedAnswer: answer,
          markedReview: Boolean(currentLocal?.markedReview || question.marked_review),
          timeTakenSeconds: elapsed,
        };
        saveLocal(question.question_id, answer, payload.markedReview);
        renderQuestion();
        try {
          await api.saveAnswer(payload);
        } catch {
          enqueueAnswer(payload);
          toast.warning('Answer saved on this device. It will synchronize when the connection returns.');
        }
      });
    });

    root.querySelector('#previousQuestion')?.addEventListener('click', () => move(-1));
    root.querySelector('#nextQuestion')?.addEventListener('click', () => move(1));
    root.querySelector('#engineExit')?.addEventListener('click', () => onExit?.());
    root.querySelector('#markReview')?.addEventListener('click', async () => {
      const currentLocal = getLocal(question.question_id);
      const nextMarked = !(currentLocal?.markedReview || question.marked_review);
      const selectedAnswer = currentLocal?.selectedAnswer ?? question.selected_answer ?? null;
      const elapsed = Math.max(0, Math.round((Date.now() - state.questionStartedAt) / 1000));
      const payload = { attemptId, questionId: question.question_id, selectedAnswer, markedReview: nextMarked, timeTakenSeconds: elapsed };
      saveLocal(question.question_id, selectedAnswer, nextMarked);
      question.marked_review = nextMarked;
      renderQuestion();
      try { await api.saveAnswer(payload); }
      catch { enqueueAnswer(payload); toast.warning('Review status is queued for synchronization.'); }
    });
    root.querySelector('#submitAttempt')?.addEventListener('click', confirmSubmit);
  }

  async function move(delta) {
    const total = Number(state.attempt.total_questions || 0);
    const next = Math.min(Math.max(state.currentIndex + delta, 0), total - 1);
    if (next === state.currentIndex) return;
    renderLoading();
    try {
      await ensureQuestion(next);
      state.currentIndex = next;
      state.questionStartedAt = Date.now();
      renderQuestion();
    } catch (error) {
      toast.error(error.message);
      renderQuestion();
    }
  }

  function confirmSubmit() {
    const dialog = document.createElement('dialog');
    dialog.className = 'review-dialog';
    dialog.innerHTML = `
      <div class="review-content section">
        <span class="eyebrow">Final submission</span>
        <h2>Submit this test?</h2>
        <p>Your answers will be scored on the server. The attempt cannot return to exam mode after submission.</p>
        <div class="draft-item-actions">
          <button id="confirmFinalSubmit" class="button button-primary" type="button">Confirm Submit</button>
          <button id="cancelFinalSubmit" class="button button-ghost" type="button">Continue Test</button>
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

  async function submit() {
    if (state.submitting) return;
    state.submitting = true;
    const loading = toast.loading('Submitting and calculating result…');
    try {
      await flushQueue();
      if (readQueue().length) throw new Error('Some answers are still offline. Reconnect before final submission.');
      const result = await api.submitAttempt(attemptId);
      loading.close();
      toast.success('Test submitted successfully.');
      renderResult(result);
    } catch (error) {
      loading.close();
      toast.error(error.message);
      state.submitting = false;
    }
  }

  function renderResult(result) {
    root.innerHTML = `
      <article class="test-engine">
        <div class="test-engine-body">
          <span class="eyebrow">Result</span>
          <h2>${escapeHtml(state.attempt.tests?.test_name || 'Test complete')}</h2>
          <div class="stats-grid section">
            <div class="stat-card"><strong>${escapeHtml(result.score ?? 0)}</strong><span>Score</span></div>
            <div class="stat-card"><strong>${escapeHtml(result.accuracy ?? 0)}%</strong><span>Accuracy</span></div>
            <div class="stat-card"><strong>${escapeHtml(result.correct ?? 0)}</strong><span>Correct</span></div>
            <div class="stat-card"><strong>${escapeHtml(result.wrong ?? 0)}</strong><span>Wrong</span></div>
          </div>
          <button id="resultExit" class="button button-primary" type="button">Back to Tests</button>
        </div>
      </article>
    `;
    root.querySelector('#resultExit')?.addEventListener('click', () => onExit?.());
  }

  renderLoading('Opening your test…');
  await flushQueue();
  state.attempt = await api.getAttempt(attemptId);
  if (state.attempt.status !== 'IN_PROGRESS') {
    const review = await api.getAttemptReview(attemptId, 0, 1);
    renderResult({
      score: state.attempt.score,
      accuracy: state.attempt.accuracy,
      correct: state.attempt.correct,
      wrong: state.attempt.wrong,
      reviewAvailable: Boolean(review.length),
    });
    return;
  }
  await ensureQuestion(0);
  renderQuestion();
}
