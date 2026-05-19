// https://nuxt.com/docs/api/configuration/nuxt-config
import tailwindcss from "@tailwindcss/vite";
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: false },
  css: ['./app/assets/css/main.css'],
  modules: ['shadcn-nuxt', '@nuxt/icon'],
  ssr: false,
  icon: {
    clientBundle: {
      scan: true,
      icons: ['tabler:player-play', 'tabler:player-pause'],
    },
  },
  shadcn: {
    prefix: '',
    componentDir: '@/components/ui'
  },
  vite: {
    plugins: [
      tailwindcss(),
    ],
    optimizeDeps: {
      exclude: ['monaco-editor'],
    },
  },
})
