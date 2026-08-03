const listeners = new Set();

export function getRoute() {
  const raw = window.location.hash || '#home';
  const [path, queryString = ''] = raw.slice(1).split('?');
  return {
    path: path || 'home',
    params: new URLSearchParams(queryString),
    raw,
  };
}

export function navigate(path, params = {}) {
  const query = new URLSearchParams(params);
  const suffix = query.toString() ? `?${query}` : '';
  window.location.hash = `#${path}${suffix}`;
}

export function subscribeRoute(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function notify() {
  const route = getRoute();
  listeners.forEach((listener) => listener(route));
}

window.addEventListener('hashchange', notify);
window.addEventListener('popstate', notify);

export function startRouter() {
  if (!window.location.hash) window.location.hash = '#home';
  notify();
}
