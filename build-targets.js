export const BUILD_TARGETS = Object.freeze({
  scoremore: Object.freeze({
    id: 'scoremore',
    appName: 'ScoreMore',
    appMark: 'S+',
    tagline: 'Prepare smarter',
    environment: 'development',
    base: '/ScoreMore/',
    cacheVersion: 'scoremore-v0.1.0',
  }),
  ranktiger: Object.freeze({
    id: 'ranktiger',
    appName: 'RankTiger',
    appMark: 'RT',
    tagline: 'Prepare smarter',
    environment: 'production',
    base: '/',
    cacheVersion: 'ranktiger-v0.1.0',
  }),
});

export function getBuildTarget(mode = 'scoremore') {
  return BUILD_TARGETS[mode] || BUILD_TARGETS.scoremore;
}
