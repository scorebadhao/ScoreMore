import { APP_CONFIG, isConfigured } from './config.js';
import { api } from './api.js';
import { assertPasswordPolicy, PASSWORD_POLICY_MESSAGE } from './passwordPolicy.js';
import { toast } from './toast.js';

const elements = {
  setupNotice: document.getElementById('setupNotice'),
  loading: document.getElementById('recoveryLoading'),
  invalid: document.getElementById('recoveryInvalid'),
  form: document.getElementById('resetPasswordForm'),
  policy: document.getElementById('passwordPolicyHelp'),
};

let recoveryAuthorized = false;

function showInvalid(message = 'This password-reset link is invalid or has expired. Request a new link and try again.') {
  elements.loading?.classList.add('hidden');
  elements.form?.classList.add('hidden');
  if (elements.invalid) {
    elements.invalid.querySelector('p').textContent = message;
    elements.invalid.classList.remove('hidden');
  }
}

function showForm() {
  recoveryAuthorized = true;
  elements.loading?.classList.add('hidden');
  elements.invalid?.classList.add('hidden');
  elements.form?.classList.remove('hidden');
  elements.form?.querySelector('[name="password"]')?.focus();

  const cleanUrl = new URL(window.location.href);
  cleanUrl.hash = '';
  cleanUrl.searchParams.delete('code');
  cleanUrl.searchParams.delete('token_hash');
  cleanUrl.searchParams.delete('type');
  window.history.replaceState({}, document.title, `${cleanUrl.pathname}${cleanUrl.search}`);
}

function setBusy(busy) {
  elements.form?.querySelectorAll('button, input').forEach((element) => {
    element.disabled = busy;
  });
}

function initialize() {
  if (elements.policy) elements.policy.textContent = PASSWORD_POLICY_MESSAGE;

  if (!isConfigured) {
    elements.setupNotice?.classList.remove('hidden');
    showInvalid(`${APP_CONFIG.name} authentication is not configured.`);
    return;
  }

  const { data: subscriptionData } = api.onAuthStateChange((event, session) => {
    if (event === 'PASSWORD_RECOVERY' && session?.user) showForm();
  });

  const expiryTimer = window.setTimeout(() => {
    if (!recoveryAuthorized) showInvalid();
  }, 5000);

  window.addEventListener('pagehide', () => {
    window.clearTimeout(expiryTimer);
    subscriptionData?.subscription?.unsubscribe?.();
  }, { once: true });

  elements.form?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!recoveryAuthorized || !event.currentTarget.reportValidity()) return;

    const values = new FormData(event.currentTarget);
    const password = String(values.get('password') || '');
    const confirmation = String(values.get('confirmPassword') || '');

    try {
      assertPasswordPolicy(password);
      if (password !== confirmation) throw new Error('New password and confirmation do not match.');
    } catch (error) {
      toast.error(error.message);
      return;
    }

    setBusy(true);
    const loading = toast.loading('Updating password…');
    try {
      await api.finishPasswordRecovery(password);
      loading.close();
      toast.success('Password updated. Sign in again with your new password.');
      window.setTimeout(() => window.location.replace('./index.html?reason=password-reset#authCard'), 700);
    } catch (error) {
      loading.close();
      setBusy(false);
      toast.error(error.message);
    }
  });
}

initialize();
