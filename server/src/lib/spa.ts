/**
 * lib/spa.ts — раздача собранного SPA (`web/dist`) и SPA-fallback (T-12, PLAN §2/§6).
 *
 * Однопроцессный деплой: единственный Fastify-процесс отдаёт и API (`/api`, `/health`),
 * и собранный React-фронтенд. Правила:
 *   * статика (`/assets/*`, `index.html`) — через `@fastify/static`;
 *   * любой GET/HEAD-навигационный запрос вне `/api`/`/health` (клиентский роутинг React
 *     Router: `/notes`, `/notes/new`, `/notes/:id`, `/notes/:id/edit`) получает `index.html`;
 *   * API-адреса всегда отвечают JSON — даже 404 (fallback их не перехватывает).
 *
 * SPA-fallback включается только при наличии сборки (`web/dist/index.html`); без неё сервер
 * работает как API-only (dev/tests) и неизвестный роут отдаёт JSON-404 (T-02).
 */
import fastifyStatic from '@fastify/static';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import type { FastifyInstance, FastifyRequest } from 'fastify';

/** Префикс API — всегда JSON, SPA-fallback не применяется. */
const API_PREFIX = '/api';
/** Health-check (T-02) — служебный JSON-роут. */
const HEALTH_PATH = '/health';
/** Хэшированные ассеты Vite живут в `assets/` и кэшируются надолго. */
const ASSETS_SEGMENT = /[/\\]assets[/\\]/;

/** Путь запроса без query-строки. */
function requestPath(request: FastifyRequest): string {
  const url = request.url;
  const queryIndex = url.indexOf('?');
  return queryIndex === -1 ? url : url.slice(0, queryIndex);
}

/** Является ли запрос API-путём (`/api` или `/api/...`). */
export function isApiPath(path: string): boolean {
  return path === API_PREFIX || path.startsWith(`${API_PREFIX}/`);
}

/**
 * Навигация в SPA: GET/HEAD, не API-путь, не health и клиент принимает HTML.
 *
 * Проверка `Accept: text/html` отделяет переходы браузера (SPA) от fetch/asset-запросов
 * (браузерный fetch по умолчанию HTML не запрашивает), поэтому неизвестный API-роут и запросы
 * к отсутствующим ассетам остаются JSON-404 — SPA-fallback срабатывает только на реальных переходах.
 */
export function isSpaNavigation(request: FastifyRequest): boolean {
  if (request.method !== 'GET' && request.method !== 'HEAD') return false;
  const path = requestPath(request);
  if (isApiPath(path)) return false;
  if (path === HEALTH_PATH) return false;
  const accept = request.headers.accept;
  return typeof accept === 'string' && accept.includes('text/html');
}

/** Путь к `index.html`, если сборка фронтенда присутствует; иначе `null` (SPA не раздаётся). */
export function resolveSpaIndex(staticDir: string | null | undefined): string | null {
  if (!staticDir) return null;
  const indexFile = join(staticDir, 'index.html');
  return existsSync(indexFile) ? indexFile : null;
}

/**
 * Регистрирует раздачу статики и возвращает `true`, если SPA доступен.
 * SPA-fallback для клиентских маршрутов настраивается отдельно в `setNotFoundHandler` (app.ts).
 */
export async function registerStatic(
  app: FastifyInstance,
  staticDir: string | null,
): Promise<boolean> {
  if (!resolveSpaIndex(staticDir)) return false;

  await app.register(fastifyStatic, {
    root: staticDir as string,
    // index.html отдаётся на `/`; для клиентских маршрутов его отдаёт notFoundHandler.
    index: ['index.html'],
    cacheControl: true,
    setHeaders(reply, filePath) {
      if (filePath.endsWith('index.html')) {
        // HTML — без кэша: деплой подменяет сборку, а имена ассетов хэшированы.
        reply.header('Cache-Control', 'no-cache');
      } else if (ASSETS_SEGMENT.test(filePath)) {
        reply.header('Cache-Control', 'public, max-age=31536000, immutable');
      }
    },
  });
  return true;
}
