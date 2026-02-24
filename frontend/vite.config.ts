import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    host: true, // Чтобы можно было открыть по IP сервера, если ты не локально
    proxy: {
      '/api': {
        target: 'http://localhost:8443', // Проксируем запросы на Nginx
        changeOrigin: true,
        secure: false, // Игнорируем самоподписанный SSL (если будет HTTPS)
      }
    }
  }
})
