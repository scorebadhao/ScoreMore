import { defineConfig } from 'vite';
import { resolve } from 'node:path';

export default defineConfig({
  base: '/ScoreMore/',
  build: {
    rollupOptions: {
      input: {
        public: resolve(import.meta.dirname, 'index.html'),
        student: resolve(import.meta.dirname, 'student.html'),
        admin: resolve(import.meta.dirname, 'admin.html'),
        testBuilder: resolve(import.meta.dirname, 'test-builder.html'),
      },
    },
  },
});
