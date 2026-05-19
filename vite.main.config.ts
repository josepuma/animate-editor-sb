import { defineConfig } from 'vite'

export default defineConfig({
  build: {
    target: 'node22',
    outDir: '.vite/build/main',
    lib: {
      entry: 'electron/main.ts',
      formats: ['cjs'],
      fileName: () => 'main.cjs',
    },
    rollupOptions: {
      external: ['electron'],
    },
  },
})
