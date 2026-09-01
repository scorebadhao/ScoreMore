const STATE_COPY = Object.freeze({
  checking: Object.freeze({ full: 'Connecting…', short: 'Checking…' }),
  online: Object.freeze({ full: 'Good Luck, Student!', short: 'Good Luck!' }),
  offline: Object.freeze({ full: 'Offline', short: 'Offline' }),
  issue: Object.freeze({ full: 'Connection issue', short: 'Unstable' }),
});

function renderBadge(element, state) {
  if (!element) return;
  const copy = STATE_COPY[state] || STATE_COPY.checking;
  element.classList.remove('checking', 'online', 'offline', 'issue');
  element.classList.add(state);
  element.setAttribute('aria-label', copy.full);
  element.innerHTML = `<span class="sync-dot" aria-hidden="true"></span><span class="sync-label-full">${copy.full}</span><span class="sync-label-short">${copy.short}</span>`;
}

export function bindConnectionBadge(element, {
  onChange = null,
  probeUrl = new URL('./', document.baseURI).href,
  probeTimeoutMs = 5000,
  minimumProbeIntervalMs = 30000,
} = {}) {
  let state = 'checking';
  let lastProbeAt = 0;
  let activeController = null;
  let destroyed = false;

  const setState = (nextState) => {
    if (destroyed || state === nextState) return;
    const previousState = state;
    state = nextState;
    renderBadge(element, state);
    onChange?.({ state, previousState });
  };

  const verify = async ({ force = false } = {}) => {
    if (destroyed) return state;
    if (!navigator.onLine) {
      activeController?.abort();
      setState('offline');
      return state;
    }

    const now = Date.now();
    if (!force && now - lastProbeAt < minimumProbeIntervalMs && state === 'online') return state;
    lastProbeAt = now;
    setState('checking');
    activeController?.abort();
    const controller = new AbortController();
    activeController = controller;
    const timeout = window.setTimeout(() => controller.abort(), probeTimeoutMs);

    try {
      const url = new URL(probeUrl, document.baseURI);
      url.searchParams.set('connection_check', String(now));
      const response = await fetch(url, {
        method: 'HEAD',
        cache: 'no-store',
        credentials: 'same-origin',
        signal: controller.signal,
      });
      if (activeController !== controller) return state;
      setState(response.ok ? 'online' : 'issue');
    } catch {
      if (activeController !== controller) return state;
      setState(navigator.onLine ? 'issue' : 'offline');
    } finally {
      window.clearTimeout(timeout);
      if (activeController === controller) activeController = null;
    }
    return state;
  };

  const handleOnline = () => { void verify({ force: true }); };
  const handleOffline = () => {
    activeController?.abort();
    setState('offline');
  };
  const handlePageShow = () => { void verify(); };
  const handleVisibility = () => {
    if (document.visibilityState === 'visible') void verify();
  };

  renderBadge(element, state);
  window.addEventListener('online', handleOnline);
  window.addEventListener('offline', handleOffline);
  window.addEventListener('pageshow', handlePageShow);
  document.addEventListener('visibilitychange', handleVisibility);
  void verify({ force: true });

  return Object.freeze({
    get state() { return state; },
    refresh() { return verify({ force: true }); },
    destroy() {
      destroyed = true;
      activeController?.abort();
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
      window.removeEventListener('pageshow', handlePageShow);
      document.removeEventListener('visibilitychange', handleVisibility);
    },
  });
}
