# Этап 1: Сборка (Build)
FROM node:22-alpine AS builder
WORKDIR /app

# Копируем зависимости (кэширование Docker слоев)
COPY package.json package-lock.json ./
RUN npm ci

# Копируем исходники и собираем
COPY . .
# Vite соберет всё в папку /app/dist
RUN npm run build

# Этап 2: Запуск (Run)
FROM nginx:1.26-alpine
# Копируем собранную статику из этапа builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Настраиваем Nginx для SPA (Single Page Application)
# Чтобы при обновлении страницы на /profile не было 404
RUN echo 'server { \
    listen 80; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
