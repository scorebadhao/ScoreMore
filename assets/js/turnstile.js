import { APP_CONFIG } from './config.js';

let loaderPromise = null;

function loadTurnstile() {
  if (!APP_CONFIG.turnstileSiteKey) return Promise.resolve(null);
  if (window.turnstile) return Promise.resolve(window.turnstile);
  if (loaderPromise) return loaderPromise;

  loaderPromise = new Promise((resolve, reject) => {
    const existing = document.querySelector('script[data-scoremore-turnstile]');
    if (existing) {
      existing.addEventListener('load', () => resolve(window.turnstile), { once: true });
      existing.addEventListener('error', () => reject(new Error('Unable to load the security check.')), { once: true });
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
    script.async = true;
    script.defer = true;
    script.dataset.scoremoreTurnstile = 'true';
    script.addEventListener('load', () => resolve(window.turnstile), { once: true });
    script.addEventListener('error', () => reject(new Error('Unable to load the security check.')), { once: true });
    document.head.append(script);
  });

  return loaderPromise;
}

export async function createTurnstileController(container, action) {
  if (!container || !APP_CONFIG.turnstileSiteKey) {
    container?.classList.add('hidden');
    return Object.freeze({ enabled: false, getToken: () => undefined, reset: () => {} });
  }

  const turnstile = await loadTurnstile();
  if (!turnstile) throw new Error('Unable to initialize the security check.');

  let token = '';
  const widgetId = turnstile.render(container, {
    sitekey: APP_CONFIG.turnstileSiteKey,
    action,
    theme: 'auto',
    size: 'flexible',
    callback: (value) => { token = value || ''; },
    'expired-callback': () => { token = ''; },
    'error-callback': () => { token = ''; },
  });

  return Object.freeze({
    enabled: true,
    getToken() {
      if (!token) throw new Error('Complete the security check before continuing.');
      return token;
    },
    reset() {
      token = '';
      turnstile.reset(widgetId);
    },
  });
}
