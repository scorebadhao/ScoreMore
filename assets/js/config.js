export const APP_CONFIG = Object.freeze({
  name: 'ScoreMore',
  environment: import.meta.env.MODE || 'development',
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL?.trim() || '',
  supabasePublishableKey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() || '',
  requestTimeoutMs: 15000,
  questionBatchSize: 10,
  cacheVersion: 'scoremore-v0.1.0',
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
