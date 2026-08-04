import { api } from './api.js';
import { toast } from './toast.js';

function setBusy(form, busy) {
  form.querySelectorAll('button, input, select').forEach((element) => {
    element.disabled = busy;
  });
}

export function bindAuthTabs() {
  const tabs = [...document.querySelectorAll('[data-auth-tab]')];
  const signInForm = document.getElementById('signInForm');
  const signUpForm = document.getElementById('signUpForm');
  if (!tabs.length || !signInForm || !signUpForm) return;

  tabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      const mode = tab.dataset.authTab;
      tabs.forEach((item) => {
        const active = item === tab;
        item.classList.toggle('active', active);
        item.setAttribute('aria-selected', String(active));
      });
      signInForm.classList.toggle('hidden', mode !== 'signin');
      signUpForm.classList.toggle('hidden', mode !== 'signup');
    });
  });
}

export function bindStudentAuth({ onAuthenticated } = {}) {
  const signInForm = document.getElementById('signInForm');
  const signUpForm = document.getElementById('signUpForm');

  signInForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!form.reportValidity()) return;
    const values = new FormData(form);
    setBusy(form, true);
    const loading = toast.loading('Signing in…');
    try {
      const result = await api.signIn({
        email: values.get('email'),
        password: values.get('password'),
      });
      loading.close();
      toast.success('Signed in successfully.');
      form.reset();
      await onAuthenticated?.(result.user);
    } catch (error) {
      loading.close();
      toast.error(error.message);
    } finally {
      setBusy(form, false);
    }
  });

  signUpForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!form.reportValidity()) return;
    const values = new FormData(form);
    setBusy(form, true);
    const loading = toast.loading('Creating account…');
    try {
      const result = await api.signUp({
        fullName: values.get('fullName'),
        mobile: values.get('mobile'),
        email: values.get('email'),
        password: values.get('password'),
      });
      loading.close();
      toast.success(result.user?.confirmed_at
        ? 'Account created and signed in.'
        : 'Account created. Check your email if confirmation is enabled.');
      form.reset();
      if (result.session) await onAuthenticated?.(result.user);
    } catch (error) {
      loading.close();
      toast.error(error.message);
    } finally {
      setBusy(form, false);
    }
  });
}
