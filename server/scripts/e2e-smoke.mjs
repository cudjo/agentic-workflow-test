#!/usr/bin/env node
/**
 * scripts/e2e-smoke.mjs — сценарная проверка «Сервис заметок» (NFR-28, PLAN §6.3).
 *
 * Прогоняет полный пользовательский путь по реальному HTTP против запущенного сервера
 * (прод-режим: один процесс Fastify отдаёт API + собранный SPA):
 *
 *   health → SPA (тем же процессом) → регистрация → me → CSRF-защита →
 *   создание заметки с тегами → список → поиск по тексту → фильтр по тегу → комбинированно →
 *   редактирование → изоляция пользователей (второй не видит/не меняет заметки первого,
 *   чужой id → 404) → удаление → logout.
 *
 * Запуск (сервер уже поднят, `web/dist` собран):
 *   node server/scripts/e2e-smoke.mjs
 *   SMOKE_BASE_URL=http://127.0.0.1:3000 node server/scripts/e2e-smoke.mjs
 *
 * Требования окружения: Node ≥ 22 (глобальный `fetch`, `Headers.getSetCookie`). Скрипт делает
 * реальные HTTP-запросы с cookie-jar и заголовком `X-CSRF-Token` (double-submit, NFR-11).
 * Код выхода 0 — все проверки пройдены, 1 — есть падения.
 */
import assert from 'node:assert/strict';
import process from 'node:process';

const BASE_URL =
  process.env.SMOKE_BASE_URL ??
  `http://127.0.0.1:${process.env.SMOKE_PORT ?? process.env.PORT ?? 3000}`;
const PASSWORD = 'Smoke-Pass-123';

const runId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
const emailA = `smoke.a.${runId}@example.com`;
const emailB = `smoke.b.${runId}@example.com`;
const marker = `mk${runId.replace(/[^a-z0-9]/gi, '')}`;

/** Клиент с собственным cookie-jar (сессия + CSRF double-submit). */
class Session {
  /** @param {string} baseUrl */
  constructor(baseUrl) {
    this.baseUrl = baseUrl;
    /** @type {Map<string, string>} */
    this.cookies = new Map();
  }

  /** @param {string} name */
  has(name) {
    return this.cookies.has(name);
  }

  /** Значение CSRF-токена из читаемого cookie `XSRF-TOKEN`. */
  csrf() {
    const raw = this.cookies.get('XSRF-TOKEN');
    return raw === undefined ? undefined : decodeURIComponent(raw);
  }

  /** Сохраняет/удаляет cookie из `Set-Cookie` ответа (учитывает `Max-Age=0`). */
  absorb(response) {
    const setCookies =
      typeof response.headers.getSetCookie === 'function' ? response.headers.getSetCookie() : [];
    for (const raw of setCookies) {
      const [pair, ...attrs] = raw.split(';');
      const eq = pair.indexOf('=');
      if (eq === -1) continue;
      const name = pair.slice(0, eq).trim();
      const value = pair.slice(eq + 1).trim();
      const maxAge = attrs
        .map((a) => a.trim())
        .find((a) => a.toLowerCase().startsWith('max-age='));
      if (maxAge && Number.parseInt(maxAge.split('=')[1], 10) === 0) {
        this.cookies.delete(name);
      } else {
        this.cookies.set(name, value);
      }
    }
  }

  /**
   * @param {string} method
   * @param {string} path
   * @param {{body?: unknown, sendCsrf?: boolean, accept?: string}} [options]
   */
  async request(method, path, options = {}) {
    const { body, sendCsrf = true, accept } = options;
    /** @type {Record<string,string>} */
    const headers = {};
    if (accept) headers.accept = accept;
    if (body !== undefined) headers['content-type'] = 'application/json';
    const cookie = [...this.cookies].map(([k, v]) => `${k}=${v}`).join('; ');
    if (cookie) headers.cookie = cookie;
    if (sendCsrf) {
      const token = this.csrf();
      if (token) headers['x-csrf-token'] = token;
    }

    let response;
    try {
      response = await fetch(new URL(path, this.baseUrl), {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        redirect: 'manual',
      });
    } catch (error) {
      throw new Error(`сеть: ${method} ${path} — ${error instanceof Error ? error.message : error}`);
    }
    this.absorb(response);

    const text = await response.text();
    let json = null;
    if (text) {
      try {
        json = JSON.parse(text);
      } catch {
        json = null;
      }
    }
    return { status: response.status, headers: response.headers, text, json };
  }
}

const results = [];

/** @param {string} name @param {() => Promise<void>} fn */
async function step(name, fn) {
  try {
    await fn();
    results.push({ name, ok: true });
    console.log(`  \u2713 ${name}`);
  } catch (error) {
    results.push({ name, ok: false, error });
    console.error(`  \u2717 ${name}`);
    console.error(`      ${error instanceof Error ? error.message : String(error)}`);
  }
}

async function main() {
  console.log(`[e2e-smoke] NFR-28 против ${BASE_URL} (run ${runId})`);

  const a = new Session(BASE_URL);
  const b = new Session(BASE_URL);
  /** @type {number|null} */
  let noteId = null;
  /** @type {string|null} */
  let updatedAtBefore = null;

  await step('GET /health → 200 {ok:true}', async () => {
    const res = await a.request('GET', '/health');
    assert.equal(res.status, 200, `status ${res.status}: ${res.text}`);
    assert.deepEqual(res.json, { ok: true });
  });

  await step('SPA отдаётся тем же процессом: GET / (Accept: text/html) → index.html', async () => {
    const res = await a.request('GET', '/', { accept: 'text/html' });
    assert.equal(res.status, 200, `status ${res.status}: ${res.text}`);
    assert.match(String(res.headers.get('content-type')), /text\/html/);
    assert.match(res.text, /id="root"/);
  });

  await step('SPA-fallback: GET /notes (клиентский маршрут) → index.html', async () => {
    const res = await a.request('GET', '/notes', { accept: 'text/html' });
    assert.equal(res.status, 200, `status ${res.status}`);
    assert.match(String(res.headers.get('content-type')), /text\/html/);
  });

  await step('API не перехватывается SPA: GET /api/definitely-missing → 404 JSON', async () => {
    const res = await a.request('GET', '/api/definitely-missing', { accept: 'text/html' });
    assert.equal(res.status, 404);
    assert.equal(res.json?.error?.code, 'NOT_FOUND');
  });

  await step('регистрация пользователя A → 201 + cookie сессии и XSRF-TOKEN', async () => {
    const res = await a.request('POST', '/api/auth/register', {
      body: { email: emailA, password: PASSWORD },
    });
    assert.equal(res.status, 201, `status ${res.status}: ${res.text}`);
    assert.equal(res.json?.user?.email, emailA);
    assert.ok(a.has('session'), 'нет cookie session');
    assert.ok(a.has('XSRF-TOKEN'), 'нет cookie XSRF-TOKEN');
  });

  await step('GET /api/auth/me (A) → 200 с email пользователя', async () => {
    const res = await a.request('GET', '/api/auth/me');
    assert.equal(res.status, 200);
    assert.equal(res.json?.user?.email, emailA);
  });

  await step('state-changing без X-CSRF-Token → 403 (NFR-11)', async () => {
    const res = await a.request('POST', '/api/notes', {
      body: { title: 'без csrf', bodyMarkdown: 'x' },
      sendCsrf: false,
    });
    assert.equal(res.status, 403, `status ${res.status}: ${res.text}`);
    assert.equal(res.json?.error?.code, 'FORBIDDEN');
  });

  await step('создание заметки с тегами (тримминг/дедуп) → 201', async () => {
    const res = await a.request('POST', '/api/notes', {
      body: {
        title: `Smoke ${marker}`,
        bodyMarkdown: `Полный **smoke** проход ${marker}`,
        tags: [' Work ', 'work', 'Home', ''],
      },
    });
    assert.equal(res.status, 201, `status ${res.status}: ${res.text}`);
    noteId = res.json?.id ?? null;
    assert.ok(Number.isInteger(noteId), `нет id заметки: ${res.text}`);
    const tags = Array.isArray(res.json?.tags) ? [...res.json.tags].sort() : [];
    assert.deepEqual(tags, ['Home', 'Work'], `теги: ${JSON.stringify(res.json?.tags)}`);
    updatedAtBefore = res.json?.updatedAt ?? null;
  });

  await step('GET /api/notes (A) → содержит созданную заметку', async () => {
    const res = await a.request('GET', '/api/notes');
    assert.equal(res.status, 200);
    assert.ok((res.json?.total ?? 0) >= 1, `total=${res.json?.total}`);
    assert.ok(res.json?.items?.some((n) => n.id === noteId), 'заметки нет в списке');
  });

  await step(`поиск по тексту: ?q=${marker} (lowercase) → находит`, async () => {
    const res = await a.request('GET', `/api/notes?q=${encodeURIComponent(marker)}`);
    assert.equal(res.status, 200);
    assert.ok(res.json?.items?.some((n) => n.id === noteId), `items=${res.json?.total}`);
  });

  await step('поиск регистронезависим: ?q=<MARKER> (uppercase) → находит', async () => {
    const res = await a.request('GET', `/api/notes?q=${encodeURIComponent(marker.toUpperCase())}`);
    assert.equal(res.status, 200);
    assert.ok(res.json?.items?.some((n) => n.id === noteId));
  });

  await step('фильтр по тегу: ?tag=work → находит', async () => {
    const res = await a.request('GET', '/api/notes?tag=work');
    assert.equal(res.status, 200);
    assert.ok(res.json?.items?.some((n) => n.id === noteId));
  });

  await step('комбинированно: ?q=<marker>&tag=work → находит', async () => {
    const res = await a.request(
      'GET',
      `/api/notes?q=${encodeURIComponent(marker)}&tag=work`,
    );
    assert.equal(res.status, 200);
    assert.ok(res.json?.items?.some((n) => n.id === noteId));
  });

  await step('комбинированно (пустое пересечение): ?q=<marker-нет>&tag=work → 0', async () => {
    const res = await a.request(
      'GET',
      `/api/notes?q=${encodeURIComponent(`zzz-${marker}`)}&tag=work`,
    );
    assert.equal(res.status, 200);
    assert.equal(res.json?.total, 0, `total=${res.json?.total}`);
  });

  await step('GET /api/tags (A) → теги Work и Home со счётчиками', async () => {
    const res = await a.request('GET', '/api/tags');
    assert.equal(res.status, 200);
    const names = (res.json?.items ?? []).map((t) => t.name);
    assert.ok(names.includes('Work'), `tags=${JSON.stringify(names)}`);
    assert.ok(names.includes('Home'), `tags=${JSON.stringify(names)}`);
    const work = res.json.items.find((t) => t.name === 'Work');
    assert.ok(work.count >= 1, `count Work=${work.count}`);
  });

  await step('редактирование: PATCH /api/notes/:id → 200 с новым заголовком', async () => {
    const res = await a.request('PATCH', `/api/notes/${noteId}`, {
      body: { title: `Smoke ${marker} обновлено` },
    });
    assert.equal(res.status, 200, `status ${res.status}: ${res.text}`);
    assert.equal(res.json?.title, `Smoke ${marker} обновлено`);
    if (updatedAtBefore) assert.ok(res.json?.updatedAt >= updatedAtBefore, 'updatedAt не вырос');
  });

  await step('изменения персистентны: GET /api/notes/:id → обновлённый заголовок', async () => {
    const res = await a.request('GET', `/api/notes/${noteId}`);
    assert.equal(res.status, 200);
    assert.equal(res.json?.title, `Smoke ${marker} обновлено`);
    assert.match(res.json?.bodyMarkdown ?? '', new RegExp(marker));
  });

  await step('регистрация пользователя B → 201', async () => {
    const res = await b.request('POST', '/api/auth/register', {
      body: { email: emailB, password: PASSWORD },
    });
    assert.equal(res.status, 201, `status ${res.status}: ${res.text}`);
    assert.equal(res.json?.user?.email, emailB);
  });

  await step('изоляция: список заметок B пуст', async () => {
    const res = await b.request('GET', '/api/notes');
    assert.equal(res.status, 200);
    assert.equal(res.json?.total, 0, `total B=${res.json?.total}`);
  });

  await step('изоляция: поиск B по тексту A → ничего', async () => {
    const res = await b.request('GET', `/api/notes?q=${encodeURIComponent(marker)}`);
    assert.equal(res.status, 200);
    assert.equal(res.json?.total, 0);
  });

  await step('изоляция: B GET чужой заметки по id → 404', async () => {
    const res = await b.request('GET', `/api/notes/${noteId}`);
    assert.equal(res.status, 404, `status ${res.status}: ${res.text}`);
    assert.equal(res.json?.error?.code, 'NOT_FOUND');
  });

  await step('изоляция: B PATCH чужой заметки → 404', async () => {
    const res = await b.request('PATCH', `/api/notes/${noteId}`, {
      body: { title: 'взлом' },
    });
    assert.equal(res.status, 404);
  });

  await step('изоляция: B DELETE чужой заметки → 404', async () => {
    const res = await b.request('DELETE', `/api/notes/${noteId}`);
    assert.equal(res.status, 404);
  });

  await step('изоляция: заметка A после атак B не изменилась', async () => {
    const res = await a.request('GET', `/api/notes/${noteId}`);
    assert.equal(res.status, 200);
    assert.equal(res.json?.title, `Smoke ${marker} обновлено`);
  });

  await step('удаление заметки (A) → 204', async () => {
    const res = await a.request('DELETE', `/api/notes/${noteId}`);
    assert.equal(res.status, 204, `status ${res.status}: ${res.text}`);
  });

  await step('GET удалённой заметки → 404', async () => {
    const res = await a.request('GET', `/api/notes/${noteId}`);
    assert.equal(res.status, 404);
  });

  await step('logout (A) → 204, me после logout → 401', async () => {
    const logout = await a.request('POST', '/api/auth/logout');
    assert.equal(logout.status, 204, `status ${logout.status}: ${logout.text}`);
    const me = await a.request('GET', '/api/auth/me');
    assert.equal(me.status, 401, `status ${me.status}`);
  });

  await step('logout (B) → 204', async () => {
    const res = await b.request('POST', '/api/auth/logout');
    assert.equal(res.status, 204, `status ${res.status}: ${res.text}`);
  });

  const failed = results.filter((r) => !r.ok);
  const passed = results.length - failed.length;
  console.log(`\n[e2e-smoke] пройдено ${passed}/${results.length} проверок (${BASE_URL})`);
  if (failed.length > 0) {
    console.error(`[e2e-smoke] ПРОВАЛЕНО: ${failed.length}`);
    process.exitCode = 1;
  } else {
    console.log('[e2e-smoke] OK — сценарий NFR-28 пройден полностью');
  }
}

main().catch((error) => {
  console.error('[e2e-smoke] фатальная ошибка:', error);
  process.exitCode = 1;
});
