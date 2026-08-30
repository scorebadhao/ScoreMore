import { api } from './api.js';
import { assertPasswordPolicy, PASSWORD_POLICY_MESSAGE } from './passwordPolicy.js';
import { toast } from './toast.js';
import { createTurnstileController } from './turnstile.js';

function setBusy(form, busy) {
  form.querySelectorAll('button, input, select').forEach((element) => {
    element.disabled = busy;
  });
}

export function bindAuthTabs() {
  const tabs = [...document.querySelectorAll('[data-auth-tab]')];
  const signInForm = document.getElementById('signInForm');
  const signUpForm = document.getElementById('signUpForm');
  const recoveryForm = document.getElementById('recoveryForm');
  const googlePanel = document.getElementById('googleAuthPanel');
  if (!tabs.length || !signInForm || !signUpForm) return;

  const setMode = (mode) => {
    tabs.forEach((item) => {
      const active = item.dataset.authTab === mode;
      item.classList.toggle('active', active);
      item.setAttribute('aria-selected', String(active));
    });
    signInForm.classList.toggle('hidden', mode !== 'signin');
    signUpForm.classList.toggle('hidden', mode !== 'signup');
    recoveryForm?.classList.toggle('hidden', mode !== 'recovery');
    googlePanel?.classList.toggle('hidden', mode === 'recovery' || googlePanel.dataset.available !== 'true');
  };

  tabs.forEach((tab) => tab.addEventListener('click', () => setMode(tab.dataset.authTab)));
  document.getElementById('forgotPasswordButton')?.addEventListener('click', () => setMode('recovery'));
  document.getElementById('backToSignInButton')?.addEventListener('click', () => setMode('signin'));

  const reason = new URLSearchParams(window.location.search).get('reason');
  setMode(reason === 'recovery' ? 'recovery' : 'signin');
}

export function bindStudentAuth({ onAuthenticated } = {}) {
  const signInForm = document.getElementById('signInForm');
  const signUpForm = document.getElementById('signUpForm');
  const recoveryForm = document.getElementById('recoveryForm');
  const googlePanel = document.getElementById('googleAuthPanel');
  const googleButton = document.getElementById('googleSignInButton');
  const policyHelp = document.getElementById('signUpPasswordPolicy');

  if (policyHelp) policyHelp.textContent = PASSWORD_POLICY_MESSAGE;

  const prepareTurnstile = (container, action) => createTurnstileController(container, action).catch((error) => ({
    enabled: true,
    getToken() { throw error; },
    reset() {},
  }));
  const controllerPromises = {
    signin: prepareTurnstile(document.getElementById('signInTurnstile'), 'student_signin'),
    signup: prepareTurnstile(document.getElementById('signUpTurnstile'), 'student_signup'),
    recovery: prepareTurnstile(document.getElementById('recoveryTurnstile'), 'password_recovery'),
  };

  api.getAuthCapabilities().then(({ google }) => {
    if (!google || !googlePanel) return;
    googlePanel.dataset.available = 'true';
    if (recoveryForm?.classList.contains('hidden')) googlePanel.classList.remove('hidden');
  }).catch(() => {
    // Keep unavailable providers hidden. Email/password remains fully usable.
  });

  googleButton?.addEventListener('click', async () => {
    googleButton.disabled = true;
    const loading = toast.loading('Opening Google sign in…');
    try {
      await api.signInWithGoogle();
    } catch (error) {
      loading.close();
      googleButton.disabled = false;
      toast.error(error.message);
    }
  });

  signInForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!form.reportValidity()) return;
    const values = new FormData(form);
    setBusy(form, true);
    const loading = toast.loading('Signing in…');
    try {
      const controller = await controllerPromises.signin;
      const result = await api.signIn({
        email: values.get('email'),
        password: values.get('password'),
        captchaToken: controller.getToken(),
      });
      loading.close();
      toast.success('Signed in successfully.');
      form.reset();
      await onAuthenticated?.(result.user);
    } catch (error) {
      loading.close();
      toast.error(error.message);
    } finally {
      controllerPromises.signin.then((controller) => controller.reset()).catch(() => {});
      setBusy(form, false);
    }
  });

  signUpForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!form.reportValidity()) return;
    const values = new FormData(form);
    const password = String(values.get('password') || '');
    const confirmation = String(values.get('confirmPassword') || '');
    try {
      assertPasswordPolicy(password);
      if (password !== confirmation) throw new Error('Password and confirmation do not match.');
    } catch (error) {
      toast.error(error.message);
      return;
    }
    setBusy(form, true);
    const loading = toast.loading('Creating account…');
    try {
      const controller = await controllerPromises.signup;
      const result = await api.signUp({
        fullName: values.get('fullName'),
        mobile: values.get('mobile'),
        email: values.get('email'),
        password,
        captchaToken: controller.getToken(),
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
      controllerPromises.signup.then((controller) => controller.reset()).catch(() => {});
      setBusy(form, false);
    }
  });

  recoveryForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    if (!form.reportValidity()) return;
    const values = new FormData(form);
    setBusy(form, true);
    const loading = toast.loading('Requesting a secure reset link…');
    try {
      const controller = await controllerPromises.recovery;
      await api.requestPasswordReset({
        email: values.get('email'),
        captchaToken: controller.getToken(),
      });
      loading.close();
      toast.success('If an account uses that email, a password-reset link has been sent.');
      form.reset();
    } catch {
      loading.close();
      toast.error('We could not send a reset email right now. Please wait and try again.');
    } finally {
      controllerPromises.recovery.then((controller) => controller.reset()).catch(() => {});
      setBusy(form, false);
    }
  });
}
