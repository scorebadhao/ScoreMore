const TEST_TYPES = Object.freeze({
  PYQ_FULL: Object.freeze({ label: 'PYQ Test', plural: 'PYQ Tests', category: 'PYQ', icon: 'i-file' }),
  PYQ_SECTIONAL: Object.freeze({ label: 'Sectional PYQ Test', plural: 'Sectional PYQ Tests', category: 'SECTIONAL', icon: 'i-layers' }),
  TOPIC_PRACTICE: Object.freeze({ label: 'Topic Test', plural: 'Topic Tests', category: 'TOPIC', icon: 'i-layers' }),
  FULL_MOCK: Object.freeze({ label: 'Mock Test', plural: 'Mock Tests', category: 'MOCK', icon: 'i-target' }),
  SECTIONAL_MOCK: Object.freeze({ label: 'Sectional Test', plural: 'Sectional Tests', category: 'SECTIONAL', icon: 'i-layers' }),
  DAILY_QUIZ: Object.freeze({ label: 'Daily Quiz', plural: 'Daily Quizzes', category: 'DAILY', icon: 'i-clock' }),
  BOOKMARK_REVISION: Object.freeze({ label: 'Bookmark Revision', plural: 'Bookmark Revision Tests', category: 'REVISION', icon: 'i-layers' }),
  MISTAKE_REVISION: Object.freeze({ label: 'Mistake Revision', plural: 'Mistake Revision Tests', category: 'REVISION', icon: 'i-layers' }),
  PERSONALIZED_TEST: Object.freeze({ label: 'Personalized Test', plural: 'Personalized Tests', category: 'PERSONALIZED', icon: 'i-target' }),
});

export const PUBLIC_TEST_CATEGORIES = Object.freeze({
  MOCK: Object.freeze({ label: 'Mock Tests', statKey: 'mock_tests', description: 'Full-exam practice', testTypes: Object.freeze(['FULL_MOCK']) }),
  PYQ: Object.freeze({ label: 'PYQ Tests', statKey: 'pyq_tests', description: 'Previous-year papers', testTypes: Object.freeze(['PYQ_FULL']) }),
  SECTIONAL: Object.freeze({ label: 'Sectional Tests', statKey: 'sectional_tests', description: 'Focused section practice', testTypes: Object.freeze(['PYQ_SECTIONAL', 'SECTIONAL_MOCK']) }),
  TOPIC: Object.freeze({ label: 'Topic Tests', statKey: 'topic_tests', description: 'Focused topic practice', testTypes: Object.freeze(['TOPIC_PRACTICE']) }),
});

function fallbackLabel(value) {
  return String(value || '')
    .replaceAll('_', ' ')
    .toLowerCase()
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export function testTypeLabel(type, { plural = false } = {}) {
  const metadata = TEST_TYPES[type];
  if (!metadata) return fallbackLabel(type);
  return plural ? metadata.plural : metadata.label;
}

export function testTypeIcon(type) {
  return TEST_TYPES[type]?.icon || 'i-layers';
}

export function testCategory(type) {
  return TEST_TYPES[type]?.category || '';
}

export function publicCategoryCount(tests, category) {
  const allowed = new Set(PUBLIC_TEST_CATEGORIES[category]?.testTypes || []);
  return (tests || []).reduce((count, test) => count + (allowed.has(test.test_type) ? 1 : 0), 0);
}
