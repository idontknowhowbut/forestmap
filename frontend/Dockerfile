FROM node:22-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

ARG VITE_KEYCLOAK_URL
ARG VITE_KEYCLOAK_REALM
ARG VITE_KEYCLOAK_CLIENT_ID
ARG VITE_USE_MOCKS
ARG VITE_API_BASE_URL
ARG VITE_DETECTIONS_QUERY_ENDPOINT

ENV VITE_KEYCLOAK_URL=$VITE_KEYCLOAK_URL
ENV VITE_KEYCLOAK_REALM=$VITE_KEYCLOAK_REALM
ENV VITE_KEYCLOAK_CLIENT_ID=$VITE_KEYCLOAK_CLIENT_ID
ENV VITE_USE_MOCKS=$VITE_USE_MOCKS
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
ENV VITE_DETECTIONS_QUERY_ENDPOINT=$VITE_DETECTIONS_QUERY_ENDPOINT

RUN npm run build

FROM nginx:1.26-alpine
COPY --from=builder /app/dist /usr/share/nginx/html

RUN printf '%s\n' \
  'server {' \
  '    listen 80;' \
  '    server_name _;' \
  '    root /usr/share/nginx/html;' \
  '    index index.html;' \
  '' \
  '    location / {' \
  '        try_files $uri $uri/ /index.html;' \
  '    }' \
  '}' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
