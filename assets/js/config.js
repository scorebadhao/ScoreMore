import { getBuildTarget } from '../../build-targets.js';

const BUILD_TARGET = getBuildTarget(import.meta.env.MODE);

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
  requestTimeoutMs: 15000,
  questionBatchSize: 10,
  cacheVersion: BUILD_TARGET.cacheVersion,
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

export const isConfigured = Boolean(
  APP_CONFIG.supabaseUrl && APP_CONFIG.supabasePublishableKey,
);
