/**
 * middleware/auth.ts — контекст сессии и guard авторизации (PLAN §4.2, §2).
 *
 * `attachSession` (onRequest) разбирает cookie `session`, находит сессию в БД, проверяет срок,
 * выполняет скользящее продление и кладёт `request.session` (или `null`).
 * `requireAuth` (preHandler) превращает `req.session` в `req.user` либо отдаёт 401.
 *
 * Используется T-03 (`/me`, `/logout`) и T-04+ (`req.user` для ownership).
 */
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { nowIso } from '../db/client.js';
import { AppError } from '../lib/errors.js';
import {
  deleteSessionByToken,
  findSession,
  isExpired,
  parseCookies,
  SESSION_COOKIE,
  touchSession,
  type SessionRecord,
} from '../lib/sessions.js';

export interface AuthUser {
  id: number;
  email: string;
}

declare module 'fastify' {
  interface FastifyRequest {
    /** Текущая сессия из cookie (null — если cookie нет/недействительна/просрочена). */
    session: SessionRecord | null;
    /** Аутентифицированный пользователь (заполняет `requireAuth`). */
    user: AuthUser | null;
  }
}

/** Регистрирует декораторы запроса и onRequest-хук разбора сессии. */
export function attachSession(app: FastifyInstance): void {
  app.decorateRequest('session', null);
  app.decorateRequest('user', null);

  app.addHook('onRequest', async (request) => {
    request.session = null;
    request.user = null;

    const rawToken = parseCookies(request.headers.cookie)[SESSION_COOKIE];
    if (!rawToken) return;

    const session = findSession(request.server.stmts, rawToken);
    if (!session) return;

    if (isExpired(session, nowIso())) {
      // Просроченную сессию удаляем и считаем неаутентифицированной (AC-9/AC-10).
      deleteSessionByToken(request.server.stmts, rawToken);
      return;
    }

    request.session = session;
    // Скользящее продление срока (Q-A4): активная сессия не «протухает» в течение 7 суток.
    touchSession(request.server.stmts, session.id);
  });
}

/** preHandler: требует валидную сессию, иначе 401 (без раскрытия деталей). */
export async function requireAuth(
  request: FastifyRequest,
  _reply: FastifyReply,
): Promise<void> {
  const session = request.session;
  if (!session) {
    throw new AppError(401, 'UNAUTHORIZED', 'Требуется авторизация');
  }
  const row = request.server.stmts.getUserById.get(session.user_id) as
    | { id: number; email: string }
    | undefined;
  if (!row) {
    // Пользователь удалён — сессия осиротела (AC-10).
    request.session = null;
    throw new AppError(401, 'UNAUTHORIZED', 'Требуется авторизация');
  }
  request.user = { id: row.id, email: row.email };
}

/** Публичный пользователь для ответов API — только `{id,email}` (PLAN §3.2). */
export function publicUser(user: AuthUser): AuthUser {
  return { id: user.id, email: user.email };
}
