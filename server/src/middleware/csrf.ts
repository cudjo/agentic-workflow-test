/**
 * middleware/csrf.ts — CSRF double-submit (PLAN §4.3, NFR-11/AC-15).
 *
 * Схема: сервер кладёт `csrf_token` в сессию и дублирует его в читаемый cookie `XSRF-TOKEN`.
 * Клиент на state-changing-запросы (`POST`/`PATCH`/`DELETE`) шлёт заголовок `X-CSRF-Token`.
 * Хук сверяет заголовок с `csrf_token` сессии; несовпадение/отсутствие → 403.
 *
 * Неаутентифицированные запросы (login/register — сессии ещё нет) не проверяются:
 * защищать нечего, а `SameSite=Lax` остаётся первым рубежом (PLAN §4.3).
 *
 * Хук регистрируется ПОСЛЕ `attachSession` — иначе `request.session` ещё не заполнен.
 */
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { AppError } from '../lib/errors.js';
import { CSRF_HEADER, tokensMatch } from '../lib/sessions.js';

const STATE_CHANGING_METHODS = new Set(['POST', 'PATCH', 'PUT', 'DELETE']);

/** Извлекает значение заголовка `X-CSRF-Token` (строкой). */
function readCsrfHeader(request: FastifyRequest): string | undefined {
  const raw = request.headers[CSRF_HEADER];
  if (typeof raw === 'string') return raw;
  if (Array.isArray(raw)) return raw[0];
  return undefined;
}

/** Регистрирует глобальный onRequest-хук CSRF-проверки. */
export function csrfGuard(app: FastifyInstance): void {
  app.addHook('onRequest', async (request) => {
    if (!STATE_CHANGING_METHODS.has(request.method)) return;

    const session = request.session;
    if (!session) return; // login/register и прочие без сессии — CSRF неприменим

    const provided = readCsrfHeader(request);
    if (!provided || !tokensMatch(provided, session.csrf_token)) {
      throw new AppError(
        403,
        'FORBIDDEN',
        'CSRF-токен отсутствует или неверен',
        { field: 'x-csrf-token' },
      );
    }
  });
}
