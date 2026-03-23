// https://nuxt.com/docs/api/configuration/nuxt-config
import tailwindcss from "@tailwindcss/vite";
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  css: ['./app/assets/css/main.css'],
  modules: ['shadcn-nuxt', '@nuxt/icon'],
  ssr: false,
  shadcn: {
    prefix: '',
    componentDir: '@/components/ui'
  },
  vite: {
    plugins: [
      tailwindcss(),
    ],
  },
})