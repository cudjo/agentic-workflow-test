/**
 * tests/app.test.ts — каркас бэкенда (T-02).
 *
 * Проверяет приёмку T-02:
 *   * GET /health → 200 {ok:true};
 *   * CORS пропускает dev-ориджин http://localhost:5173;
 *   * неизвестный роут → 404 в едином JSON-формате;
 *   * ошибка → JSON {error:{code,message}} без stack (в проде/по умолчанию);
 *   * логгер не содержит паролей/токенов (NFR-9/A9).
 */
import { Writable } from 'node:stream';
import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp, REDACT_PATHS } from '../src/app.js';
import { DEFAULT_CORS_ORIGIN, DEFAULT_PORT, loadConfig } from '../src/config.js';
import { openDatabase } from '../src/db/client.js';
import { AppError, errorBody } from '../src/lib/errors.js';

const open: FastifyInstance[] = [];

async function makeApp(): Promise<FastifyInstance> {
  const app = await buildApp({
    config: loadConfig({ NODE_ENV: 'test' }),
    db: openDatabase(':memory:'),
    logger: false,
  });
  open.push(app);
  return app;
}

afterEach(async () => {
  await Promise.all(open.splice(0).map((app) => app.close()));
});

describe('config', () => {
  it('применяет значения по умолчанию (PORT=3000, CORS=dev-ориджин, COOKIE_SECURE=false в dev)', () => {
    const config = loadConfig({ NODE_ENV: 'development' });
    expect(config.port).toBe(DEFAULT_PORT);
    expect(config.corsOrigin).toBe(DEFAULT_CORS_ORIGIN);
    expect(config.cookieSecure).toBe(false);
    expect(config.isProduction).toBe(false);
    expect(config.sessionSecret).toBeUndefined();
  });

  it('читает переопределения из env', () => {
    const config = loadConfig({
      NODE_ENV: 'test',
      PORT: '4321',
      CORS_ORIGIN: 'http://example.test',
      COOKIE_SECURE: 'true',
      SESSION_SECRET: 'a'.repeat(32),
      DATABASE_PATH: ':memory:',
    });
    expect(config.port).toBe(4321);
    expect(config.corsOrigin).toBe('http://example.test');
    expect(config.cookieSecure).toBe(true);
    expect(config.sessionSecret).toBe('a'.repeat(32));
    expect(config.databasePath).toBe(':memory:');
  });

  it('не требует SESSION_SECRET в проде: целостность сессии на opaque-токене (ревью #1)', () => {
    const config = loadConfig({ NODE_ENV: 'production' });
    expect(config.isProduction).toBe(true);
    expect(config.sessionSecret).toBeUndefined();
  });

  it('в проде по умолчанию включает Secure-cookie (NFR-10, ревью #2)', () => {
    expect(loadConfig({ NODE_ENV: 'production' }).cookieSecure).toBe(true);
    expect(loadConfig({ NODE_ENV: 'test' }).cookieSecure).toBe(false);
    // Явное значение из env перекрывает дефолт (локальный prod-HTTP запуск).
    expect(loadConfig({ NODE_ENV: 'production', COOKIE_SECURE: 'false' }).cookieSecure).toBe(false);
  });
});

describe('GET /health', () => {
  it('отдаёт 200 {ok:true}', async () => {
    const app = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('application/json');
    expect(res.json()).toEqual({ ok: true });
  });
});

describe('CORS', () => {
  it('пропускает dev-ориджин http://localhost:5173 с credentials', async () => {
    const app = await makeApp();
    const res = await app.inject({
      method: 'GET',
      url: '/health',
      headers: { origin: DEFAULT_CORS_ORIGIN },
    });
    expect(res.statusCode).toBe(200);
    expect(res.headers['access-control-allow-origin']).toBe(DEFAULT_CORS_ORIGIN);
    expect(res.headers['access-control-allow-credentials']).toBe('true');
  });

  it('preflight (OPTIONS) разрешает X-CSRF-Token', async () => {
    const app = await makeApp();
    const res = await app.inject({
      method: 'OPTIONS',
      url: '/health',
      headers: {
        origin: DEFAULT_CORS_ORIGIN,
        'access-control-request-method': 'POST',
        'access-control-request-headers': 'x-csrf-token,content-type',
      },
    });
    expect(res.statusCode).toBeLessThan(300);
    expect(res.headers['access-control-allow-origin']).toBe(DEFAULT_CORS_ORIGIN);
    expect(String(res.headers['access-control-allow-headers']).toLowerCase()).toContain(
      'x-csrf-token',
    );
  });
});

describe('централизованные ошибки', () => {
  it('неизвестный роут → 404 JSON {error:{code,message}}', async () => {
    const app = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/nope' });
    expect(res.statusCode).toBe(404);
    const body = res.json() as { error: { code: string; message: string } };
    expect(body.error.code).toBe('NOT_FOUND');
    expect(typeof body.error.message).toBe('string');
    expect(body.error.message.length).toBeGreaterThan(0);
  });

  it('доменная ошибка → свой статус/код/field', async () => {
    const app = await makeApp();
    app.get('/teapot', async () => {
      throw new AppError(422, 'VALIDATION_ERROR', 'поле обязательно', { field: 'email' });
    });
    const res = await app.inject({ method: 'GET', url: '/teapot' });
    expect(res.statusCode).toBe(422);
    expect(res.json()).toEqual({
      error: { code: 'VALIDATION_ERROR', message: 'поле обязательно', field: 'email' },
    });
  });

  it('непредвиденная ошибка → 500 JSON без stack и без деталей', async () => {
    const app = await makeApp();
    app.get('/boom', async () => {
      throw new Error('kaboom SESSION_SECRET=hunter2');
    });
    const res = await app.inject({ method: 'GET', url: '/boom' });
    expect(res.statusCode).toBe(500);
    const raw = res.body;
    expect(raw).not.toContain('kaboom');
    expect(raw).not.toContain('hunter2');
    expect(raw.toLowerCase()).not.toContain('stack');
    const body = JSON.parse(raw) as { error: { code: string; message: string } };
    expect(body.error.code).toBe('INTERNAL');
    expect(body.error.message).toBe('Internal Server Error');
  });
});

describe('логгер (NFR-9/A9)', () => {
  it('редактирует пароли и токены', () => {
    expect(REDACT_PATHS).toContain('password');
    expect(REDACT_PATHS).toContain('token');
  });

  it('не пишет пароль/токен в вывод', async () => {
    const chunks: string[] = [];
    const stream = new Writable({
      write(chunk, _enc, cb) {
        chunks.push(String(chunk));
        cb();
      },
    });
    const app = await buildApp({
      config: loadConfig({ NODE_ENV: 'test' }),
      db: openDatabase(':memory:'),
      loggerStream: stream,
    });
    open.push(app);
    app.log.info({ password: 'hunter2', user: { token: 'tok-123' } }, 'login attempt');
    const output = chunks.join('');
    expect(output).toContain('login attempt');
    expect(output).not.toContain('hunter2');
    expect(output).not.toContain('tok-123');
    expect(output).toContain('[redacted]');
  });
});

describe('errorBody', () => {
  it('опускает field, когда он не задан', () => {
    const body = errorBody('NOT_FOUND', 'нет');
    expect(body).toEqual({ error: { code: 'NOT_FOUND', message: 'нет' } });
    expect('field' in body.error).toBe(false);
  });
});
