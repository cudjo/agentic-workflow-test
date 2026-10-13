# syntax=docker/dockerfile:1
#
# Notes Service — прод-образ (T-12, PLAN §2/§6). Однопроцессный деплой: Fastify раздаёт
# и API (`/api`, `/health`), и собранный SPA (`web/dist`) из одного процесса.
#
# Multi-stage:
#   1) web-build   — сборка фронтенда (Vite) → web/dist;
#   2) server-deps — только production-зависимости сервера;
#   3) runtime     — минимальный образ: Node + серверный код + собранная статика.
#
# Секреты в образ НЕ запекаются (NFR-8): SESSION_SECRET и прочее передаются в runtime через env
# (docker-compose/tmpl). База SQLite — в томе `/data` (персистентность, NFR-25).
#
# Примечание: сервер запускается напрямую из TypeScript через `tsx` (production-зависимость),
# без отдельного шага компиляции — так же, как `npm start` в остальных окружениях.

# ---- 1. Сборка SPA ----
FROM node:22-alpine AS web-build
WORKDIR /build/web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

# ---- 2. Production-зависимости сервера ----
FROM node:22-alpine AS server-deps
WORKDIR /build/server
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev

# ---- 3. Runtime ----
FROM node:22-alpine AS runtime

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000 \
    STATIC_DIR=/app/web/dist \
    DATABASE_PATH=/data/app.db \
    CORS_ORIGIN=http://localhost:3000

WORKDIR /app

# Зависимости (в т.ч. tsx) — из отдельного слоя, чтобы кэшировались.
COPY --from=server-deps /build/server/node_modules ./server/node_modules
COPY server/package.json ./server/package.json
COPY server/tsconfig.json ./server/tsconfig.json
COPY server/src ./server/src

# Собранный фронтенд раздаётся Fastify из того же процесса.
COPY --from=web-build /build/web/dist ./web/dist

# Каталог персистентных данных SQLite (монтируется томом) — доступен непривилегированному пользователю.
RUN mkdir -p /data && chown -R node:node /app /data

WORKDIR /app/server
USER node

EXPOSE 3000

# Health-check контейнера (T-02): GET /health.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "--import", "tsx", "src/index.ts"]
