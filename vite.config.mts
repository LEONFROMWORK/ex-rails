import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import vue from '@vitejs/plugin-vue'
import path from 'path'

export default defineConfig({
  plugins: [
    RubyPlugin(),
    vue(),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './app/javascript'),
      '~': path.resolve(__dirname, './app/javascript'),
    },
  },
  server: {
    hmr: {
      host: 'localhost',
    },
  },
  build: {
    // Improve build performance
    rollupOptions: {
      output: {
        manualChunks: {
          'vue-vendor': ['vue', 'vue-router', 'pinia'],
          'ui-vendor': ['radix-vue', 'class-variance-authority', 'clsx', 'tailwind-merge'],
        },
      },
    },
  },
})