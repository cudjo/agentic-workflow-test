/**
 * tests/auth.test.ts — аутентификация (T-03).
 *
 * Проверяет приёмку T-03 и соответствующие AC SPEC:
 *   * register → 201 + cookie; me → {user:{id,email}}; logout → 204; повторный me → 401 (AC-1/7/8);
 *   * дубликат email в другом регистре → 409 field=email; невалидный email/слабый пароль → 422 field (AC-2/3);
 *   * login неверный → 401 обобщённо; 6-я неудача → 429 + Retry-After (AC-5/6);
 *   * CSRF double-submit: без X-CSRF-Token → 403, с корректным → проходит (AC-15/NFR-11);
 *   * истёкшая/удалённая сессия → 401 без данных (AC-9/10).
 *
 * Изоляция: на каждый тест — свой tmp-файл БД (WAL создаёт -wal/-shm рядом; каталог удаляется
 * в afterEach). Секреты в БД/ответах не попадают (NFR-9).
 */
import { createHash } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance, LightMyRequestResponse } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { CSRF_COOKIE, CSRF_HEADER, SESSION_COOKIE, SESSION_MAX_AGE_SECONDS } from '../src/lib/sessions.js';

const EMAIL = 'user@example.com';
const PASSWORD = 'correct-horse-battery';
const TEST_SECRET = 'test-session-secret-0123456789abcdef';

let app: FastifyInstance;
let dataDir: string;

beforeEach(async () => {
  dataDir = mkdtempSync(join(tmpdir(), 'notes-auth-'));
  app = await buildApp({
    config: loadConfig({
      NODE_ENV: 'test',
      DATABASE_PATH: join(dataDir, 'app.db'),
      SESSION_SECRET: TEST_SECRET,
    }),
    logger: false,
  });
});

afterEach(async () => {
  await app.close();
  rmSync(dataDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Помощники
// ---------------------------------------------------------------------------

/** Разбирает Set-Cookie ответа в словарь name → value (атрибуты игнорируются). */
function responseCookies(res: LightMyRequestResponse): Record<string, string> {
  const raw = res.headers['set-cookie'];
  const lines = raw === undefined ? [] : Array.isArray(raw) ? raw : [raw];
  const cookies: Record<string, string> = {};
  for (const line of lines) {
    const semi = line.indexOf(';');
    const pair = semi === -1 ? line : line.slice(0, semi);
    const eq = pair.indexOf('=');
    if (eq === -1) continue;
    const name = pair.slice(0, eq).trim();
    if (name === '') continue;
    cookies[name] = decodeURIComponent(pair.slice(eq + 1));
  }
  return cookies;
}

/** Собирает заголовок Cookie из словаря. */
function cookieHeader(cookies: Record<string, string>): string {
  return Object.entries(cookies)
    .map(([name, value]) => `${name}=${encodeURIComponent(value)}`)
    .join('; ');
}

/** Строки Set-Cookie как массив (для проверки атрибутов). */
function setCookieLines(res: LightMyRequestResponse): string[] {
  const raw = res.headers['set-cookie'];
  return raw === undefined ? [] : Array.isArray(raw) ? raw : [raw];
}

/** Значение одного атрибута cookie. */
function cookieLine(res: LightMyRequestResponse, name: string): string {
  const line = setCookieLines(res).find((item) => item.startsWith(`${name}=`));
  if (!line) throw new Error(`Set-Cookie для ${name} не найден`);
  return line;
}

/** Одна скалярная величина из БД (число). */
function scalar(sql: string): number {
  const row = app.db.prepare(sql).get() as { n?: number } | undefined;
  return Number(row?.n ?? 0);
}

/** Одна строка из БД. */
function dbRow<T>(sql: string): T | undefined {
  return app.db.prepare(sql).get() as T | undefined;
}

function register(
  email: string = EMAIL,
  password: string = PASSWORD,
): Promise<LightMyRequestResponse> {
  return app.inject({ method: 'POST', url: '/api/auth/register', payload: { email, password } });
}

function login(email: string, password: string): Promise<LightMyRequestResponse> {
  return app.inject({ method: 'POST', url: '/api/auth/login', payload: { email, password } });
}

function me(cookie: string): Promise<LightMyRequestResponse> {
  return app.inject({ method: 'GET', url: '/api/auth/me', headers: { cookie } });
}

// ---------------------------------------------------------------------------
// AC-1 / AC-7 / AC-8: register → me → logout → me
// ---------------------------------------------------------------------------

describe('register / me / logout (AC-1, AC-7, AC-8)', () => {
  it('register → 201 {user:{id,email}} + HttpOnly-сессия и читаемый XSRF-TOKEN', async () => {
    const res = await register();

    expect(res.statusCode).toBe(201);
    const body = res.json() as { user: { id: number; email: string } };
    expect(body).toEqual({ user: { id: expect.any(Number), email: EMAIL } });
    // Пароль/хеш не покидают сервер (NFR-9).
    expect(JSON.stringify(body)).not.toContain(PASSWORD);
    expect(body.user).not.toHaveProperty('password');
    expect(body.user).not.toHaveProperty('passwordHash');

    const cookies = responseCookies(res);
    expect(cookies[SESSION_COOKIE]).toBeTruthy();
    expect(cookies[CSRF_COOKIE]).toBeTruthy();

    const sessionLine = cookieLine(res, SESSION_COOKIE);
    expect(sessionLine).toContain('HttpOnly');
    expect(sessionLine).toContain('SameSite=Lax');
    expect(sessionLine).toContain('Path=/');
    expect(sessionLine).toContain(`Max-Age=${SESSION_MAX_AGE_SECONDS}`);

    // CSRF-cookie должен читаться фронтендом → без HttpOnly (PLAN §4.3).
    expect(cookieLine(res, CSRF_COOKIE)).not.toContain('HttpOnly');
  });

  it('в БД хранится только SHA-256 токена, raw token — лишь в cookie', async () => {
    const res = await register();
    const rawToken = responseCookies(res)[SESSION_COOKIE]!;

    const row = dbRow<{ token_hash: string }>('SELECT token_hash FROM sessions');
    expect(row?.token_hash).toBe(createHash('sha256').update(rawToken).digest('hex'));
    expect(row?.token_hash).not.toBe(rawToken);
    expect(res.headers['set-cookie']).toBeDefined();
  });

  it('me с cookie → 200 {user:{id,email}} (AC-8)', async () => {
    const reg = await register();
    const cookie = cookieHeader(responseCookies(reg));

    const res = await me(cookie);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ user: { id: reg.json<{ user: { id: number } }>().user.id, email: EMAIL } });
  });

  it('me без cookie → 401 без данных (AC-10)', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/auth/me' });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ error: { code: 'UNAUTHORIZED' } });
    expect(JSON.stringify(res.json())).not.toContain('email');
  });

  it('logout → 204, cookie очищены, сессия удалена, повторный me → 401 (AC-7)', async () => {
    const reg = await register();
    const cookies = responseCookies(reg);
    const cookie = cookieHeader(cookies);

    const out = await app.inject({
      method: 'POST',
      url: '/api/auth/logout',
      headers: { cookie, [CSRF_HEADER]: cookies[CSRF_COOKIE]! },
    });
    expect(out.statusCode).toBe(204);
    expect(out.body).toBe('');

    const cleared = responseCookies(out);
    expect(cleared[SESSION_COOKIE]).toBe('');
    expect(cleared[CSRF_COOKIE]).toBe('');
    expect(cookieLine(out, SESSION_COOKIE)).toContain('Max-Age=0');
    expect(scalar('SELECT COUNT(*) AS n FROM sessions')).toBe(0);

    const after = await me(cookie);
    expect(after.statusCode).toBe(401);
  });
});

// ---------------------------------------------------------------------------
// AC-2 / AC-3: дубликат email, валидация
// ---------------------------------------------------------------------------

describe('регистрация: дубликат и валидация (AC-2, AC-3)', () => {
  it('дубликат email в другом регистре → 409 field=email, второй аккаунт не создан', async () => {
    await register('User@Example.com');
    const dup = await register('user@example.COM');

    expect(dup.statusCode).toBe(409);
    expect(dup.json()).toMatchObject({ error: { code: 'CONFLICT', field: 'email' } });
    // Сессия для отклонённой регистрации не выдаётся.
    expect(dup.headers['set-cookie']).toBeUndefined();
    expect(scalar('SELECT COUNT(*) AS n FROM users')).toBe(1);
  });

  it('email хранится в lowercase, вход проходит в любом регистре (AC-4)', async () => {
    await register('Mixed.Case@Example.com');
    const stored = dbRow<{ email: string }>('SELECT email FROM users');
    expect(stored?.email).toBe('mixed.case@example.com');

    const res = await login('MIXED.CASE@EXAMPLE.COM', PASSWORD);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ user: { email: 'mixed.case@example.com' } });
  });

  const invalid: Array<[string, Record<string, unknown>, string]> = [
    ['некорректный email', { email: 'not-an-email', password: PASSWORD }, 'email'],
    ['пустой email', { email: '   ', password: PASSWORD }, 'email'],
    ['пароль из 7 символов', { email: EMAIL, password: '1234567' }, 'password'],
    ['пароль не строка', { email: EMAIL, password: 12345678 }, 'password'],
  ];

  it.each(invalid)('register: %s → 422 с field=%s', async (_name, payload, field) => {
    const res = await app.inject({ method: 'POST', url: '/api/auth/register', payload });
    expect(res.statusCode).toBe(422);
    expect(res.json()).toMatchObject({ error: { code: 'VALIDATION_ERROR', field } });
    expect(scalar('SELECT COUNT(*) AS n FROM users')).toBe(0);
  });

  it('пароль ровно 8 символов принимается (граница)', async () => {
    const res = await register(EMAIL, '12345678');
    expect(res.statusCode).toBe(201);
  });

  it('отсутствующее тело → 422 field=email (не 500)', async () => {
    const res = await app.inject({ method: 'POST', url: '/api/auth/register' });
    expect(res.statusCode).toBe(422);
    expect(res.json()).toMatchObject({ error: { code: 'VALIDATION_ERROR', field: 'email' } });
  });
});

// ---------------------------------------------------------------------------
// AC-4 / AC-5 / AC-6: вход, обобщённая ошибка, rate-limit
// ---------------------------------------------------------------------------

describe('вход и rate-limit (AC-4, AC-5, AC-6)', () => {
  it('login с корректными данными → 200 {user} + cookie (AC-4)', async () => {
    await register('log.inner@example.com');
    const res = await login('log.inner@example.com', PASSWORD);

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ user: { email: 'log.inner@example.com' } });
    const cookies = responseCookies(res);
    expect(cookies[SESSION_COOKIE]).toBeTruthy();
    expect(cookies[CSRF_COOKIE]).toBeTruthy();
  });

  it('неверный пароль и несуществующий email → идентичный 401 без раскрытия (AC-5)', async () => {
    await register();
    const wrongPassword = await login(EMAIL, 'definitely-wrong');
    const unknownUser = await login('ghost@example.com', 'definitely-wrong');

    expect(wrongPassword.statusCode).toBe(401);
    expect(unknownUser.statusCode).toBe(401);
    expect(wrongPassword.json()).toEqual(unknownUser.json());
    expect(wrongPassword.json()).toMatchObject({ error: { code: 'UNAUTHORIZED' } });
    // Нет cookie сессии при неуспехе.
    expect(wrongPassword.headers['set-cookie']).toBeUndefined();
  });

  it('6-я неудачная попытка входа → 429 + Retry-After (AC-6)', async () => {
    await register();

    for (let i = 0; i < 5; i += 1) {
      expect((await login(EMAIL, `wrong-${i}`)).statusCode).toBe(401);
    }

    const sixth = await login(EMAIL, 'wrong-again');
    expect(sixth.statusCode).toBe(429);
    expect(sixth.json()).toMatchObject({ error: { code: 'RATE_LIMITED' } });

    const retryAfter = Number(sixth.headers['retry-after']);
    expect(Number.isInteger(retryAfter)).toBe(true);
    expect(retryAfter).toBeGreaterThan(0);
  });

  it('успешный вход сбрасывает счётчик неудач', async () => {
    await register();
    for (let i = 0; i < 4; i += 1) {
      expect((await login(EMAIL, 'wrong')).statusCode).toBe(401);
    }
    expect((await login(EMAIL, PASSWORD)).statusCode).toBe(200);
    for (let i = 0; i < 5; i += 1) {
      expect((await login(EMAIL, 'wrong')).statusCode).toBe(401);
    }
    expect((await login(EMAIL, 'wrong')).statusCode).toBe(429);
  });

  it('лимит действует и на регистрацию: 6-я попытка с занятым email → 429', async () => {
    await register();
    for (let i = 0; i < 5; i += 1) {
      expect((await register()).statusCode).toBe(409);
    }
    expect((await register()).statusCode).toBe(429);
  });

  it('ключ лимита учитывает email: другой email не блокируется', async () => {
    await register();
    for (let i = 0; i < 6; i += 1) {
      await login(EMAIL, 'wrong');
    }
    expect((await login(EMAIL, 'wrong')).statusCode).toBe(429);
    // Другой email — своё окно.
    expect((await login('other@example.com', 'wrong')).statusCode).toBe(401);
  });
});

// ---------------------------------------------------------------------------
// AC-15 / NFR-11: CSRF double-submit
// ---------------------------------------------------------------------------

describe('CSRF double-submit (AC-15, NFR-11)', () => {
  it('csrf_token сессии совпадает с cookie XSRF-TOKEN', async () => {
    const reg = await register();
    const cookieToken = responseCookies(reg)[CSRF_COOKIE];
    const row = dbRow<{ csrf_token: string }>('SELECT csrf_token FROM sessions');
    expect(row?.csrf_token).toBe(cookieToken);
  });

  it('state-changing без X-CSRF-Token → 403, сессия не инвалидируется', async () => {
    const reg = await register();
    const cookie = cookieHeader(responseCookies(reg));

    const res = await app.inject({ method: 'POST', url: '/api/auth/logout', headers: { cookie } });
    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ error: { code: 'FORBIDDEN' } });
    expect(scalar('SELECT COUNT(*) AS n FROM sessions')).toBe(1);
    expect((await me(cookie)).statusCode).toBe(200);
  });

  it('неверный X-CSRF-Token → 403', async () => {
    const reg = await register();
    const cookie = cookieHeader(responseCookies(reg));
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/logout',
      headers: { cookie, [CSRF_HEADER]: 'not-the-right-token' },
    });
    expect(res.statusCode).toBe(403);
  });

  it('токен другой сессии → 403', async () => {
    const first = await register('first@example.com');
    const second = await register('second@example.com');
    const firstCookies = responseCookies(first);
    const secondCookies = responseCookies(second);

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/logout',
      headers: {
        cookie: cookieHeader(firstCookies),
        [CSRF_HEADER]: secondCookies[CSRF_COOKIE]!,
      },
    });
    expect(res.statusCode).toBe(403);
  });

  it('с корректным X-CSRF-Token state-changing проходит → 204', async () => {
    const reg = await register();
    const cookies = responseCookies(reg);
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/logout',
      headers: { cookie: cookieHeader(cookies), [CSRF_HEADER]: cookies[CSRF_COOKIE]! },
    });
    expect(res.statusCode).toBe(204);
  });

  it('login/register без сессии не требуют CSRF-токена', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { email: EMAIL, password: PASSWORD },
    });
    expect(res.statusCode).toBe(201);
  });

  it('безопасный GET с сессией не требует CSRF', async () => {
    const reg = await register();
    expect((await me(cookieHeader(responseCookies(reg)))).statusCode).toBe(200);
  });
});

// ---------------------------------------------------------------------------
// AC-9 / AC-10: истёкшая и удалённая сессия
// ---------------------------------------------------------------------------

describe('истёкшая и удалённая сессия (AC-9, AC-10)', () => {
  it('истёкшая сессия → 401, запись удаляется (AC-9)', async () => {
    const reg = await register();
    const cookie = cookieHeader(responseCookies(reg));
    app.db.prepare("UPDATE sessions SET expires_at = '2000-01-01T00:00:00.000Z'").run();

    const res = await me(cookie);
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ error: { code: 'UNAUTHORIZED' } });
    expect(scalar('SELECT COUNT(*) AS n FROM sessions')).toBe(0);
  });

  it('активная сессия продлевается при использовании (скользящий срок, Q-A4)', async () => {
    const reg = await register();
    const cookie = cookieHeader(responseCookies(reg));

    const soon = new Date(Date.now() + 60_000).toISOString();
    app.db.prepare('UPDATE sessions SET expires_at = ?').run(soon);

    expect((await me(cookie)).statusCode).toBe(200);

    const row = dbRow<{ expires_at: string }>('SELECT expires_at FROM sessions');
    expect(row).toBeDefined();
    expect(row!.expires_at > soon).toBe(true);
    // Продление ~на 7 суток вперёд.
    expect(new Date(row!.expires_at).getTime() - Date.now()).toBeGreaterThan(
      6 * 24 * 60 * 60 * 1000,
    );
  });

  it('удалённый пользователь → 401 (каскад удаляет сессию) (AC-10)', async () => {
    const reg = await register();
    const cookie = cookieHeader(responseCookies(reg));
    app.db.prepare('DELETE FROM users').run();

    expect(scalar('SELECT COUNT(*) AS n FROM sessions')).toBe(0);
    expect((await me(cookie)).statusCode).toBe(401);
  });

  it('подделанный/несуществующий токен сессии → 401', async () => {
    const res = await me(`${SESSION_COOKIE}=not-a-real-token`);
    expect(res.statusCode).toBe(401);
  });
});
