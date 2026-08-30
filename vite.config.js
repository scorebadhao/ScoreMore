import { defineConfig } from 'vite';
import { resolve } from 'node:path';
import { getBuildTarget } from './build-targets.js';

export default defineConfig(({ mode }) => {
  const target = getBuildTarget(mode);

  return {
    base: target.base,
    plugins: [
      {
        name: 'scoremore-ranktiger-build-identity',
        transformIndexHtml(html) {
          return html
            .replaceAll('__APP_NAME__', target.appName)
            .replaceAll('__APP_MARK__', target.appMark)
            .replaceAll('__APP_TAGLINE__', target.tagline)
            .replaceAll('__APP_ENVIRONMENT__', target.environment);
        },
      },
    ],
    build: {
      rollupOptions: {
        input: {
          public: resolve(import.meta.dirname, 'index.html'),
          resetPassword: resolve(import.meta.dirname, 'reset-password.html'),
          student: resolve(import.meta.dirname, 'student.html'),
          admin: resolve(import.meta.dirname, 'admin.html'),
          testBuilder: resolve(import.meta.dirname, 'test-builder.html'),
        },
      },
    },
  };
});
