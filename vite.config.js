import { defineConfig } from 'vite';
import { resolve } from 'node:path';

export default defineConfig({
  base: '/ScoreMore/',
  build: {
    rollupOptions: {
      input: {
        student: resolve(import.meta.dirname, 'index.html'),
        admin: resolve(import.meta.dirname, 'admin.html'),
      },
    },
  },
});
