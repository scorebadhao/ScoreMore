export const BUILD_TARGETS = Object.freeze({
  scoremore: Object.freeze({
    id: 'scoremore',
    appName: 'ScoreMore',
    appMark: 'S+',
    tagline: 'Prepare smarter',
    environment: 'development',
    base: '/ScoreMore/',
    cacheVersion: 'scoremore-v0.1.0',
    legacyBrandNames: Object.freeze([]),
    publicDefaults: Object.freeze({
      scopeBadge: 'GSSSB CCE',
      heroTitle: 'Prepare Smarter for GSSSB CCE',
      heroSubtitle: 'અસલ PYQ, વિભાગવાર પ્રેક્ટિસ, ફુલ ટેસ્ટ અને સ્માર્ટ એનાલિટિક્સ સાથે તૈયારી કરો.',
    }),
  }),
  ranktiger: Object.freeze({
    id: 'ranktiger',
    appName: 'RankTiger',
    appMark: 'RT',
    tagline: 'Prepare smarter',
    environment: 'production',
    base: '/',
    cacheVersion: 'ranktiger-v0.1.0',
    legacyBrandNames: Object.freeze(['ScoreMore']),
    publicDefaults: Object.freeze({
      scopeBadge: 'GSSSB CCE',
      heroTitle: 'Prepare Smarter for GSSSB CCE',
      heroSubtitle: 'અસલ PYQ, વિભાગવાર પ્રેક્ટિસ, ફુલ ટેસ્ટ અને સ્માર્ટ એનાલિટિક્સ સાથે તૈયારી કરો.',
    }),
  }),
});

export function getBuildTarget(mode = 'scoremore') {
  return BUILD_TARGETS[mode] || BUILD_TARGETS.scoremore;
}
