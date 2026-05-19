import { defineConfig } from 'vite'

export default defineConfig({
  build: {
    target: 'node22',
    outDir: '.vite/build/preload',
    lib: {
      entry: 'electron/preload.ts',
      formats: ['cjs'],
      fileName: () => 'preload.cjs',
    },
    rollupOptions: {
      external: ['electron'],
    },
  },
})
