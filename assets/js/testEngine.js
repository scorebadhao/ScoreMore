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

function firstImageUrl(imageRefs) {
  if (Array.isArray(imageRefs)) {
    const first = imageRefs.find((item) => typeof item === 'string' || item?.url);
    return typeof first === 'string' ? first : first?.url || '';
  }
  if (typeof imageRefs === 'string') return imageRefs;
  if (imageRefs?.url) return imageRefs.url;
  return '';
}

export async function mountTestEngine(root, attemptId, { onExit } = {}) {
  if (!root) throw new Error('Test engine root was not found.');

  const state = {
    attempt: null,
    questions: new Map(),
    visited: new Set(),
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

  function answerState(question) {
    if (!question) return { selectedAnswer: null, markedReview: false };
    const local = getLocal(question.question_id);
    return {
      selectedAnswer: local?.selectedAnswer ?? question.selected_answer ?? null,
      markedReview: Boolean(local?.markedReview ?? question.marked_review),
    };
  }

  function questionStatus(index) {
    const question = state.questions.get(index);
    if (!question) return state.visited.has(index) ? 'unanswered' : 'not-visited';
    const answer = answerState(question);
    if (answer.markedReview && answer.selectedAnswer) return 'answered-review';
    if (answer.markedReview) return 'review';
    if (answer.selectedAnswer) return 'answered';
    return state.visited.has(index) ? 'unanswered' : 'not-visited';
  }

  function statusCounts() {
    const total = Number(state.attempt?.total_questions || 0);
    const counts = { answered: 0, review: 0, unanswered: 0, notVisited: 0 };
    for (let index = 0; index < total; index += 1) {
      const status = questionStatus(index);
      if (status === 'answered') counts.answered += 1;
      else if (status === 'review' || status === 'answered-review') counts.review += 1;
      else if (status === 'unanswered') counts.unanswered += 1;
      else counts.notVisited += 1;
    }
    return counts;
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
    root.innerHTML = `<div class="loading-state test-loading-state"><span class="spinner"></span>${escapeHtml(message)}</div>`;
  }

  function paletteMarkup(total) {
    return Array.from({ length: total }, (_, index) => {
      const status = questionStatus(index);
      return `<button class="palette-button ${status} ${state.currentIndex === index ? 'current' : ''}" data-question-index="${index}" type="button" aria-label="Open question ${index + 1}">${index + 1}</button>`;
    }).join('');
  }

  function imageMarkup(question) {
    const url = firstImageUrl(question.image_refs);
    return url ? `<img class="question-image" src="${escapeHtml(url)}" alt="Question reference" loading="lazy" />` : '';
  }

  function renderQuestion() {
    const question = currentQuestion();
    if (!question) return renderLoading();
    state.visited.add(state.currentIndex);
    const answer = answerState(question);
    const test = state.attempt.tests || {};
    const total = Number(state.attempt.total_questions || 0);
    const progress = total ? Math.round(((state.currentIndex + 1) / total) * 100) : 0;
    const counts = statusCounts();

    root.innerHTML = `
      <article class="test-workspace">
        <header class="test-workspace-header">
          <button id="engineExit" class="icon-button test-exit-button" type="button" aria-label="Exit test">←</button>
          <div class="test-workspace-title">
            <strong>${escapeHtml(test.test_name || 'Test')}</strong>
            <span>Question ${state.currentIndex + 1} of ${total}</span>
          </div>
          <span class="test-sync-state ${navigator.onLine ? '' : 'offline'}">${navigator.onLine ? 'Saved online' : 'Saved on device'}</span>
        </header>

        <div class="test-progress-track" aria-label="Test progress"><span style="width:${progress}%"></span></div>

        <div class="test-layout">
          <section class="question-panel card">
            <div class="question-card-head">
              <div class="test-meta">
                <span class="chip">${escapeHtml(question.subject_name || 'General')}</span>
                ${question.section_code ? `<span class="chip">${escapeHtml(question.section_code)}</span>` : ''}
                ${question.difficulty ? `<span class="chip">${escapeHtml(question.difficulty)}</span>` : ''}
              </div>
              <span class="question-number-badge">Q${state.currentIndex + 1}</span>
            </div>
            <div class="question-text">${escapeHtml(question.question_text)}</div>
            ${imageMarkup(question)}
            <div class="option-list">
              ${['A', 'B', 'C', 'D'].map((key) => `
                <button class="option-button ${answer.selectedAnswer === key ? 'selected' : ''}" data-answer="${key}" type="button">
                  <span class="option-key">${key}</span>
                  <span class="option-text">${escapeHtml(question.options?.[key] || '')}</span>
                  <span class="option-check">✓</span>
                </button>
              `).join('')}
            </div>
            <div class="question-tools">
              <button id="clearResponse" class="text-button" ${answer.selectedAnswer ? '' : 'disabled'} type="button">Clear response</button>
              <button id="markReview" class="button ${answer.markedReview ? 'button-warning' : 'button-ghost'}" type="button">
                <svg class="icon"><use href="#i-flag"></use></svg><span>${answer.markedReview ? 'Marked for review' : 'Mark for review'}</span>
              </button>
            </div>
          </section>

          <aside class="palette-panel card">
            <div class="palette-head">
              <div><span class="eyebrow">Question navigator</span><h3>Test overview</h3></div>
              <strong>${progress}%</strong>
            </div>
            <div class="status-summary">
              <span><b>${counts.answered}</b> Answered</span>
              <span><b>${counts.review}</b> Review</span>
              <span><b>${counts.unanswered}</b> Unanswered</span>
              <span><b>${counts.notVisited}</b> Not visited</span>
            </div>
            <div class="palette-legend">
              <span><i class="answered"></i>Answered</span>
              <span><i class="review"></i>Review</span>
              <span><i class="unanswered"></i>Unanswered</span>
              <span><i class="not-visited"></i>Not visited</span>
            </div>
            <div class="palette-grid">${paletteMarkup(total)}</div>
          </aside>
        </div>

        <footer class="test-action-bar">
          <button id="previousQuestion" class="button button-ghost" ${state.currentIndex === 0 ? 'disabled' : ''} type="button">← Previous</button>
          ${state.currentIndex + 1 >= total
            ? '<button id="submitAttempt" class="button button-primary" type="button">Submit test</button>'
            : '<button id="nextQuestion" class="button button-primary" type="button">Save & next →</button>'}
        </footer>
      </article>
    `;

    root.querySelectorAll('[data-answer]').forEach((button) => {
      button.addEventListener('click', async () => {
        await persistAnswer(question, button.dataset.answer, answerState(question).markedReview);
      });
    });

    root.querySelectorAll('[data-question-index]').forEach((button) => {
      button.addEventListener('click', () => goTo(Number(button.dataset.questionIndex)));
    });

    root.querySelector('#previousQuestion')?.addEventListener('click', () => move(-1));
    root.querySelector('#nextQuestion')?.addEventListener('click', () => move(1));
    root.querySelector('#engineExit')?.addEventListener('click', () => onExit?.());
    root.querySelector('#clearResponse')?.addEventListener('click', () => persistAnswer(question, null, answerState(question).markedReview));
    root.querySelector('#markReview')?.addEventListener('click', () => {
      const current = answerState(question);
      persistAnswer(question, current.selectedAnswer, !current.markedReview);
    });
    root.querySelector('#submitAttempt')?.addEventListener('click', confirmSubmit);
  }

  async function persistAnswer(question, selectedAnswer, markedReview) {
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
    renderQuestion();
    try {
      await api.saveAnswer(payload);
    } catch {
      enqueueAnswer(payload);
      toast.warning('Answer saved on this device. It will synchronize when the connection returns.');
    }
  }

  async function goTo(index) {
    const total = Number(state.attempt.total_questions || 0);
    const next = Math.min(Math.max(Number(index) || 0, 0), total - 1);
    if (next === state.currentIndex) return;
    renderLoading();
    try {
      await ensureQuestion(next);
      state.currentIndex = next;
      state.questionStartedAt = Date.now();
      state.visited.add(next);
      renderQuestion();
    } catch (error) {
      toast.error(error.message);
      renderQuestion();
    }
  }

  async function move(delta) {
    await goTo(state.currentIndex + delta);
  }

  function confirmSubmit() {
    const counts = statusCounts();
    const total = Number(state.attempt.total_questions || 0);
    const dialog = document.createElement('dialog');
    dialog.className = 'review-dialog submit-dialog';
    dialog.innerHTML = `
      <div class="review-content section">
        <span class="eyebrow">Final submission</span>
        <h2>Submit this test?</h2>
        <p>Your answers will be scored securely on the server. You cannot edit this attempt after submission.</p>
        <div class="submit-summary-grid">
          <span><b>${counts.answered}</b>Answered</span>
          <span><b>${counts.review}</b>Review</span>
          <span><b>${counts.unanswered + counts.notVisited}</b>Unanswered</span>
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
    const total = Number(state.attempt.total_questions || 0);
    const marksPerQuestion = Number(state.attempt.tests?.marks_per_question || 1);
    const maxScore = total * marksPerQuestion;
    const skipped = Number(result.skipped ?? state.attempt.skipped ?? Math.max(0, total - Number(result.correct || 0) - Number(result.wrong || 0)));
    const timeTaken = Number(result.time_taken_seconds ?? state.attempt.time_taken_seconds ?? 0);
    const minutes = Math.floor(timeTaken / 60);
    const seconds = timeTaken % 60;

    root.innerHTML = `
      <article class="result-shell card">
        <div class="result-hero">
          <span class="eyebrow light">Test completed</span>
          <h2>${escapeHtml(state.attempt.tests?.test_name || 'Test complete')}</h2>
          <p>Your attempt was scored securely on the ScoreMore database.</p>
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
    root.querySelector('#resultExit')?.addEventListener('click', () => onExit?.());
    root.querySelector('#resultHome')?.addEventListener('click', () => onExit?.());
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
      skipped: state.attempt.skipped,
      time_taken_seconds: state.attempt.time_taken_seconds,
      reviewAvailable: Boolean(review.length),
    });
    return;
  }
  await ensureQuestion(0);
  state.visited.add(0);
  renderQuestion();
}
