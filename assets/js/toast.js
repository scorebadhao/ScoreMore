const DEFAULT_DURATION = 4200;

function root() {
  return document.getElementById('toastRoot');
}

export function showToast(message, type = 'info', options = {}) {
  const container = root();
  if (!container) return { close() {} };

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.setAttribute('role', type === 'error' ? 'alert' : 'status');

  const icon = document.createElement('span');
  icon.textContent = type === 'success' ? '✓' : type === 'error' ? '!' : type === 'warning' ? '⚠' : 'i';

  const text = document.createElement('div');
  text.textContent = String(message || '');

  const closeButton = document.createElement('button');
  closeButton.type = 'button';
  closeButton.setAttribute('aria-label', 'Dismiss notification');
  closeButton.textContent = '×';

  toast.append(icon, text, closeButton);
  container.append(toast);

  let timer;
  const close = () => {
    window.clearTimeout(timer);
    toast.remove();
  };
  closeButton.addEventListener('click', close);

  if (type !== 'loading' && options.persist !== true) {
    timer = window.setTimeout(close, options.duration ?? DEFAULT_DURATION);
  }

  return { close, element: toast };
}

export const toast = Object.freeze({
  success: (message, options) => showToast(message, 'success', options),
  error: (message, options) => showToast(message, 'error', options),
  warning: (message, options) => showToast(message, 'warning', options),
  info: (message, options) => showToast(message, 'info', options),
  loading: (message, options) => showToast(message, 'loading', { ...options, persist: true }),
});
