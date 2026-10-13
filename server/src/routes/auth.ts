/**
 * routes/auth.ts — аутентификация: register/login/logout/me (PLAN §3.2, §4).
 *
 * Инварианты безопасности:
 *   * пароль никогда не покидает сервер (в ответах только `{id,email}`) и хешируется bcrypt (cost 10);
 *   * вход отвечает обобщеённой 401 без раскрытия существования email (AC-5);
 *   * сессия — opaque token в HttpOnly-cookie, в БД — SHA-256; CSRF-токен дублируется в cookie;
 *   * неудачные попытки входа/регистрации ограничены in-memory лимитером (429 + Retry-After).
 */
import type { FastifyInstance, FastifyReply } from 'fastify';
import { nowIso, runInsert, transaction } from '../db/client.js';
import type { Config } from '../config.js';
import { AppError } from '../lib/errors.js';
import { DUMMY_PASSWORD_HASH, hashPassword, verifyPassword } from '../lib/password.js';
import {
  createSession,
  deleteSessionByToken,
  parseCookies,
  SESSION_COOKIE,
  SESSION_MAX_AGE_SECONDS,
  serializeCookie,
  type IssuedSession,
} from '../lib/sessions.js';
import { assertValidCredentials, normalizeEmail } from '../lib/validation.js';
import { publicUser, requireAuth } from '../middleware/auth.js';
import {
  createRateLimiter,
  loginRateLimitKey,
  tooManyRequests,
  type RateLimiter,
} from '../middleware/rateLimit.js';

interface UserRow {
  id: number;
  email: string;
  email_norm: string;
  password_hash: string;
  created_at: string;
}

/** Сообщение для неверного входа — одинаковое для «нет email» и «неверный пароль» (AC-5). */
const INVALID_CREDENTIALS_MESSAGE = 'Неверные учётные данные';

/** Cookie сессии и CSRF-токена (PLAN §4.2/§4.3). */
function sessionCookies(config: Config, issued: IssuedSession): string[] {
  const common = {
    maxAge: SESSION_MAX_AGE_SECONDS,
    secure: config.cookieSecure,
    sameSite: 'Lax' as const,
    path: '/',
  };
  return [
    serializeCookie(SESSION_COOKIE, issued.token, { ...common, httpOnly: true }),
    // Читаемый cookie для double-submit — без HttpOnly, чтобы фронтенд мог прочитать токен.
    serializeCookie('XSRF-TOKEN', issued.csrfToken, { ...common, httpOnly: false }),
  ];
}

/** Очистка cookie при logout. */
function clearedCookies(config: Config): string[] {
  const common = {
    maxAge: 0,
    secure: config.cookieSecure,
    sameSite: 'Lax' as const,
    path: '/',
  };
  return [
    serializeCookie(SESSION_COOKIE, '', { ...common, httpOnly: true }),
    serializeCookie('XSRF-TOKEN', '', { ...common, httpOnly: false }),
  ];
}

/** Нарушение UNIQUE-ограничения SQLite (гонка при параллельной регистрации). */
function isUniqueViolation(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return /UNIQUE constraint failed/i.test(message);
}

export interface AuthRoutesOptions {
  /** Инъекция лимитера (тесты); иначе создаётся свой на время жизни приложения. */
  limiter?: RateLimiter;
}

export async function authRoutes(
  app: FastifyInstance,
  options: AuthRoutesOptions = {},
): Promise<void> {
  const limiter = options.limiter ?? createRateLimiter();
  const config = app.config;

  app.post('/api/auth/register', async (request, reply) => {
    const rateKey = loginRateLimitKey(request);
    const status = limiter.check(rateKey);
    if (!status.allowed) tooManyRequests(reply, status.retryAfter);

    const { email, password } = assertValidCredentials(request.body);

    const existing = app.stmts.getUserByEmail.get(email) as UserRow | undefined;
    if (existing) {
      limiter.fail(rateKey);
      throw new AppError(409, 'CONFLICT', 'Этот email уже зарегистрирован', { field: 'email' });
    }

    const passwordHash = await hashPassword(password);
    const now = nowIso();

    let userId: number;
    let issued: IssuedSession;
    try {
      const result = transaction(app.db, () => {
        const id = runInsert(app.stmts.insertUser, email, email, passwordHash, now);
        return { userId: id, issued: createSession(app.stmts, id, new Date(now)) };
      });
      userId = result.userId;
      issued = result.issued;
    } catch (error) {
      if (isUniqueViolation(error)) {
        limiter.fail(rateKey);
        throw new AppError(409, 'CONFLICT', 'Этот email уже зарегистрирован', { field: 'email' });
      }
      throw error;
    }

    limiter.reset(rateKey);
    reply.header('Set-Cookie', sessionCookies(config, issued));
    return reply.code(201).send({ user: { id: userId, email } });
  });

  app.post('/api/auth/login', async (request, reply) => {
    const rateKey = loginRateLimitKey(request);
    const status = limiter.check(rateKey);
    if (!status.allowed) tooManyRequests(reply, status.retryAfter);

    const body = (request.body ?? {}) as { email?: unknown; password?: unknown };
    const email = typeof body.email === 'string' ? normalizeEmail(body.email) : '';
    const password = typeof body.password === 'string' ? body.password : '';

    const row = email === '' ? undefined : (app.stmts.getUserByEmail.get(email) as UserRow | undefined);
    // Всегда выполняем bcrypt-сравнение (в т.ч. с фиктивным хешем) — выравниваем время ответа (AC-5).
    const passwordOk = await verifyPassword(password, row?.password_hash ?? DUMMY_PASSWORD_HASH);
    if (!row || !passwordOk) {
      limiter.fail(rateKey);
      throw new AppError(401, 'UNAUTHORIZED', INVALID_CREDENTIALS_MESSAGE);
    }

    const issued = createSession(app.stmts, row.id);
    limiter.reset(rateKey);
    reply.header('Set-Cookie', sessionCookies(config, issued));
    return reply.code(200).send({ user: { id: row.id, email: row.email } });
  });

  app.post('/api/auth/logout', async (request, reply) => {
    const rawToken = parseCookies(request.headers.cookie)[SESSION_COOKIE];
    if (rawToken) {
      deleteSessionByToken(app.stmts, rawToken);
    }
    reply.header('Set-Cookie', clearedCookies(config));
    return reply.code(204).send();
  });

  app.get('/api/auth/me', { preHandler: requireAuth }, async (request) => {
    return { user: publicUser(request.user!) };
  });
}
