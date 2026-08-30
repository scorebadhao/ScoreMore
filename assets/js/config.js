import { getBuildTarget } from '../../build-targets.js';

const BUILD_TARGET = getBuildTarget(import.meta.env.MODE);

function cleanText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

export const APP_CONFIG = Object.freeze({
  name: BUILD_TARGET.appName,
  mark: BUILD_TARGET.appMark,
  tagline: BUILD_TARGET.tagline,
  target: BUILD_TARGET.id,
  environment: BUILD_TARGET.environment,
  mode: import.meta.env.MODE || 'scoremore',
  basePath: BUILD_TARGET.base,
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL?.trim() || '',
  supabasePublishableKey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() || '',
  turnstileSiteKey: import.meta.env.VITE_TURNSTILE_SITE_KEY?.trim() || '',
  requestTimeoutMs: 15000,
  questionBatchSize: 10,
  cacheVersion: BUILD_TARGET.cacheVersion,
  legacyBrandNames: BUILD_TARGET.legacyBrandNames,
  publicDefaults: BUILD_TARGET.publicDefaults,
  sourceBucket: 'source-documents',
  studentImageBucket: 'student-question-images',
  features: Object.freeze({
    publicCatalogue: true,
    studentAttempts: true,
    draftReview: true,
    payments: false,
    smartRank: false,
  }),
});

/**
 * Convert legacy human-readable product wording to the active build identity.
 * Internal protocol identifiers such as scoremore.question-import are deliberately
 * not changed because this helper replaces display-case brand names only.
 */
export function brandRuntimeText(value, fallback = '') {
  let text = cleanText(value) || cleanText(fallback);
  for (const legacyName of APP_CONFIG.legacyBrandNames) {
    text = text.replaceAll(legacyName, APP_CONFIG.name);
  }
  return text;
}

/**
 * Public database settings may control content, but never the product identity.
 * app_name/app_mark/app_environment from the database are intentionally ignored.
 */
export function resolvePublicSettings(settings = {}) {
  return Object.freeze({
    appName: APP_CONFIG.name,
    appMark: APP_CONFIG.mark,
    environment: APP_CONFIG.environment,
    tagline: brandRuntimeText(settings.app_tagline, APP_CONFIG.tagline),
    scopeBadge: brandRuntimeText(settings.scope_badge, APP_CONFIG.publicDefaults.scopeBadge),
    heroTitle: brandRuntimeText(settings.hero_title, APP_CONFIG.publicDefaults.heroTitle),
    heroSubtitle: brandRuntimeText(settings.hero_subtitle, APP_CONFIG.publicDefaults.heroSubtitle),
  });
}

export const isConfigured = Boolean(
  APP_CONFIG.supabaseUrl && APP_CONFIG.supabasePublishableKey,
);
