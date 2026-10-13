/**
 * tests/spa.test.ts — раздача собранного SPA и SPA-fallback (T-12).
 *
 * Проверяет:
 *   * `isSpaNavigation`/`isApiPath` — какие запросы считаются навигацией (unit);
 *   * `resolveSpaIndex` — SPA доступен только при наличии `index.html`;
 *   * интеграционно (`buildApp` + временный `dist`): `/` и клиентские маршруты отдают HTML,
 *     хэшированные ассеты — со своим типом, а `/api/*` и неизвестные не-навигационные запросы
 *     остаются JSON-404 (API не перехватывается SPA, T-02);
 *   * без сборки (`staticDir: null`) сервер работает API-only и отдаёт JSON-404.
 */
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import type { FastifyRequest } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { openDatabase } from '../src/db/client.js';
import { isApiPath, isSpaNavigation, resolveSpaIndex } from '../src/lib/spa.js';

const open: FastifyInstance[] = [];
const tempDirs: string[] = [];
const HTML_MARKER = '<div id="root">SPA-MARKER</div>';

afterEach(async () => {
  await Promise.all(open.splice(0).map((app) => app.close()));
  for (const dir of tempDirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

/** Создаёт временный `web/dist` с index.html и одним хэшированным ассетом. */
function makeDist(): string {
  const dir = mkdtempSync(join(tmpdir(), 'notes-dist-'));
  tempDirs.push(dir);
  writeFileSync(join(dir, 'index.html'), `<!doctype html><html><body>${HTML_MARKER}</body></html>`);
  mkdirSync(join(dir, 'assets'), { recursive: true });
  writeFileSync(join(dir, 'assets', 'app-abc123.js'), 'export const marker = "asset";');
  return dir;
}

async function makeApp(staticDir?: string | null): Promise<FastifyInstance> {
  const app = await buildApp({
    config: loadConfig({ NODE_ENV: 'test' }),
    db: openDatabase(':memory:'),
    logger: false,
    staticDir,
  });
  open.push(app);
  return app;
}

/** Минимальный request-like объект для unit-проверок. */
function fakeRequest(method: string, url: string, accept?: string): FastifyRequest {
  return {
    method,
    url,
    headers: accept === undefined ? {} : { accept },
  } as unknown as FastifyRequest;
}

describe('isSpaNavigation / isApiPath', () => {
  it('навигация: GET/HEAD вне /api с Accept: text/html', () => {
    expect(isSpaNavigation(fakeRequest('GET', '/notes', 'text/html,application/xhtml+xml'))).toBe(true);
    expect(isSpaNavigation(fakeRequest('GET', '/notes/42/edit?v=1', 'text/html'))).toBe(true);
    expect(isSpaNavigation(fakeRequest('HEAD', '/', 'text/html'))).toBe(true);
  });

  it('не навигация: без Accept: text/html, не-GET, /api, /health', () => {
    expect(isSpaNavigation(fakeRequest('GET', '/notes'))).toBe(false);
    expect(isSpaNavigation(fakeRequest('GET', '/notes', '*/*'))).toBe(false);
    expect(isSpaNavigation(fakeRequest('POST', '/notes', 'text/html'))).toBe(false);
    expect(isSpaNavigation(fakeRequest('GET', '/api/notes', 'text/html'))).toBe(false);
    expect(isSpaNavigation(fakeRequest('GET', '/api', 'text/html'))).toBe(false);
    expect(isSpaNavigation(fakeRequest('GET', '/health', 'text/html'))).toBe(false);
  });

  it('isApiPath распознаёт /api и /api/*', () => {
    expect(isApiPath('/api')).toBe(true);
    expect(isApiPath('/api/notes/1')).toBe(true);
    expect(isApiPath('/apiary')).toBe(false);
    expect(isApiPath('/notes')).toBe(false);
  });
});

describe('resolveSpaIndex', () => {
  it('null при отсутствии каталога/сборки', () => {
    expect(resolveSpaIndex(null)).toBeNull();
    expect(resolveSpaIndex(undefined)).toBeNull();
    expect(resolveSpaIndex(join(tmpdir(), 'notes-dist-does-not-exist'))).toBeNull();
  });

  it('путь к index.html, когда сборка есть', () => {
    const dist = makeDist();
    expect(resolveSpaIndex(dist)).toBe(join(dist, 'index.html'));
  });
});

describe('раздача SPA (однопроцессный деплой)', () => {
  it('/ отдаёт index.html', async () => {
    const app = await makeApp(makeDist());
    const res = await app.inject({ method: 'GET', url: '/', headers: { accept: 'text/html' } });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.body).toContain(HTML_MARKER);
  });

  it('клиентский маршрут (SPA-fallback) отдаёт index.html', async () => {
    const app = await makeApp(makeDist());
    for (const url of ['/notes', '/notes/new', '/notes/7', '/notes/7/edit']) {
      const res = await app.inject({ method: 'GET', url, headers: { accept: 'text/html' } });
      expect(res.statusCode, url).toBe(200);
      expect(res.headers['content-type'], url).toContain('text/html');
      expect(res.body, url).toContain(HTML_MARKER);
    }
  });

  it('хэшированный ассет отдаётся статикой с корректным типом и кэшем', async () => {
    const app = await makeApp(makeDist());
    const res = await app.inject({ method: 'GET', url: '/assets/app-abc123.js' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('javascript');
    expect(String(res.headers['cache-control'])).toContain('immutable');
  });

  it('неизвестный API-роут остаётся JSON-404 (SPA не перехватывает API)', async () => {
    const app = await makeApp(makeDist());
    const res = await app.inject({
      method: 'GET',
      url: '/api/definitely-missing',
      headers: { accept: 'text/html' },
    });
    expect(res.statusCode).toBe(404);
    expect(res.headers['content-type']).toContain('application/json');
    expect((res.json() as { error: { code: string } }).error.code).toBe('NOT_FOUND');
  });

  it('не-навигационный запрос неизвестного пути → JSON-404 (T-02 не нарушен)', async () => {
    const app = await makeApp(makeDist());
    const res = await app.inject({ method: 'GET', url: '/nope' });
    expect(res.statusCode).toBe(404);
    expect((res.json() as { error: { code: string } }).error.code).toBe('NOT_FOUND');
  });

  it('без сборки: навигация тоже JSON-404 (API-only)', async () => {
    const app = await makeApp(null);
    const res = await app.inject({ method: 'GET', url: '/notes', headers: { accept: 'text/html' } });
    expect(res.statusCode).toBe(404);
    expect((res.json() as { error: { code: string } }).error.code).toBe('NOT_FOUND');
  });
});
