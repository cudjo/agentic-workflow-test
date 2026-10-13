/**
 * tests/notes.test.ts — CRUD заметок с ownership-проверкой (T-04, PLAN §3.2/§4.4).
 *
 * Покрывает приёмку T-04 и связанные AC SPEC:
 *   * создание → 201 с полным Note (AC-16/E2/E3); пустая заметка → 422 (AC-17/E1);
 *   * список — только свои заметки, свежие сверху (AC-13/Q-S3);
 *   * чужой/несуществующий id → 404 без раскрытия данных (AC-11/AC-12/AC-14/Q-A7);
 *   * персистентность после перезапуска сервера (NFR-25); запись атомарна (NFR-26);
 *   * базовая работа с tags[] (полный тег-менеджмент и поиск — T-05).
 *
 * Изоляция: на каждый тест — свой tmp-файл БД (см. tests/auth.test.ts).
 */
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance, InjectOptions, LightMyRequestResponse } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { CSRF_COOKIE, CSRF_HEADER, SESSION_COOKIE } from '../src/lib/sessions.js';

const ALICE = 'alice@example.com';
const BOB = 'bob@example.com';
const PASSWORD = 'correct-horse-battery';
const TEST_SECRET = 'test-session-secret-0123456789abcdef';

let app: FastifyInstance;
let dataDir: string;
let dbPath: string;

beforeEach(async () => {
  dataDir = mkdtempSync(join(tmpdir(), 'notes-crud-'));
  dbPath = join(dataDir, 'app.db');
  app = await newApp(dbPath);
});

afterEach(async () => {
  await app.close().catch(() => undefined);
  rmSync(dataDir, { recursive: true, force: true });
});

/** Собирает приложение на указанном файле БД (для проверки персистентности). */
function newApp(databasePath: string): Promise<FastifyInstance> {
  return buildApp({
    config: loadConfig({
      NODE_ENV: 'test',
      DATABASE_PATH: databasePath,
      SESSION_SECRET: TEST_SECRET,
    }),
    logger: false,
  });
}

// ---------------------------------------------------------------------------
// Помощники
// ---------------------------------------------------------------------------

interface Auth {
  cookie: string;
  csrf: string;
  userId: number;
}

interface ApiNote {
  id: number;
  title: string | null;
  bodyMarkdown: string;
  tags: string[];
  createdAt: string;
  updatedAt: string;
}

type Method = 'GET' | 'POST' | 'PATCH' | 'DELETE';

function responseCookies(res: LightMyRequestResponse): Record<string, string> {
  const raw = res.headers['set-cookie'];
  const lines = raw === undefined ? [] : Array.isArray(raw) ? raw : [raw];
  const cookies: Record<string, string> = {};
  for (const line of lines) {
    const semi = line.indexOf(';');
    const pair = semi === -1 ? line : line.slice(0, semi);
    const eq = pair.indexOf('=');
    if (eq === -1) continue;
    cookies[pair.slice(0, eq).trim()] = decodeURIComponent(pair.slice(eq + 1));
  }
  return cookies;
}

function cookieHeader(cookies: Record<string, string>): string {
  return Object.entries(cookies)
    .map(([name, value]) => `${name}=${encodeURIComponent(value)}`)
    .join('; ');
}

/** Регистрирует пользователя и возвращает cookie/CSRF-контекст (T-03). */
async function registerUser(email: string): Promise<Auth> {
  const res = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email, password: PASSWORD },
  });
  expect(res.statusCode).toBe(201);
  const cookies = responseCookies(res);
  return {
    cookie: cookieHeader(cookies),
    csrf: cookies[CSRF_COOKIE]!,
    userId: res.json<{ user: { id: number } }>().user.id,
  };
}

/** Запрос от имени пользователя: cookie сессии + CSRF-заголовок на state-changing (PLAN §4.3). */
function api(
  auth: Auth,
  method: Method,
  url: string,
  payload?: unknown,
): Promise<LightMyRequestResponse> {
  const headers: Record<string, string> = { cookie: auth.cookie };
  if (method !== 'GET') headers[CSRF_HEADER] = auth.csrf;
  const options: InjectOptions = { method, url, headers };
  if (payload !== undefined) options.payload = payload as InjectOptions['payload'];
  return app.inject(options);
}

/** Создаёт заметку и возвращает её представление (ожидает 201). */
async function createNote(auth: Auth, payload: unknown): Promise<ApiNote> {
  const res = await api(auth, 'POST', '/api/notes', payload);
  expect(res.statusCode).toBe(201);
  return res.json<ApiNote>();
}

/** Заметки пользователя из ответа списка. */
async function listNotes(auth: Auth): Promise<{ items: ApiNote[]; total: number }> {
  const res = await api(auth, 'GET', '/api/notes');
  expect(res.statusCode).toBe(200);
  return res.json<{ items: ApiNote[]; total: number }>();
}

function count(sql: string): number {
  const row = app.db.prepare(sql).get() as { n?: number } | undefined;
  return Number(row?.n ?? 0);
}

function rows<T>(sql: string): T[] {
  return app.db.prepare(sql).all() as T[];
}

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

// ---------------------------------------------------------------------------
// POST /api/notes — создание (AC-16, E1/E2/E3, NFR-25/26)
// ---------------------------------------------------------------------------

describe('POST /api/notes — создание (AC-16, E1/E2/E3)', () => {
  it('создаёт заметку → 201 с полным Note и записью в БД', async () => {
    const alice = await registerUser(ALICE);

    const res = await api(alice, 'POST', '/api/notes', {
      title: 'Заголовок',
      bodyMarkdown: '# Тело\n\nтекст',
      tags: ['работа'],
    });

    expect(res.statusCode).toBe(201);
    const note = res.json<ApiNote>();
    expect(note).toEqual({
      id: expect.any(Number),
      title: 'Заголовок',
      bodyMarkdown: '# Тело\n\nтекст',
      tags: ['работа'],
      createdAt: expect.any(String),
      updatedAt: expect.any(String),
    });
    expect(note.updatedAt).toBe(note.createdAt);
    expect(Number.isNaN(Date.parse(note.createdAt))).toBe(false);

    const row = app.db
      .prepare('SELECT user_id, title, body_markdown, created_at, updated_at FROM notes WHERE id = ?')
      .get(note.id) as { user_id: number; title: string; body_markdown: string } | undefined;
    expect(row).toMatchObject({
      user_id: alice.userId,
      title: 'Заголовок',
      body_markdown: '# Тело\n\nтекст',
    });
  });

  it('без сессии → 401, заметка не создаётся', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/notes',
      payload: { title: 'x', bodyMarkdown: 'y' },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ error: { code: 'UNAUTHORIZED' } });
    expect(count('SELECT COUNT(*) AS n FROM notes')).toBe(0);
  });

  it('без X-CSRF-Token → 403 (AC-15/NFR-11)', async () => {
    const alice = await registerUser(ALICE);
    const res = await app.inject({
      method: 'POST',
      url: '/api/notes',
      headers: { cookie: alice.cookie },
      payload: { bodyMarkdown: 'текст' },
    });
    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ error: { code: 'FORBIDDEN' } });
    expect(count('SELECT COUNT(*) AS n FROM notes')).toBe(0);
  });

  it('только заголовок → bodyMarkdown = "" (E2)', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { title: 'Только заголовок' });
    expect(note.title).toBe('Только заголовок');
    expect(note.bodyMarkdown).toBe('');
    expect(note.tags).toEqual([]);
  });

  it('только текст → title = null (E3)', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { bodyMarkdown: 'первая строка\nвторая' });
    expect(note.title).toBeNull();
    expect(note.bodyMarkdown).toBe('первая строка\nвторая');
  });

  it('заголовок из пробелов + текст → title = null, текст сохранён', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { title: '   ', bodyMarkdown: 'текст' });
    expect(note.title).toBeNull();
    expect(note.bodyMarkdown).toBe('текст');
  });

  it('пустая заметка → 422 с сообщением, в БД ничего нет (AC-17/E1)', async () => {
    const alice = await registerUser(ALICE);
    const cases: unknown[] = [
      {},
      { title: '   ' },
      { bodyMarkdown: '' },
      { bodyMarkdown: '  \n\t ' },
      { title: '', bodyMarkdown: '' },
      { title: '  ', bodyMarkdown: ' \n ' },
    ];

    for (const payload of cases) {
      const res = await api(alice, 'POST', '/api/notes', payload);
      expect(res.statusCode).toBe(422);
      const body = res.json<{ error: { code: string; message: string } }>();
      expect(body.error.code).toBe('VALIDATION_ERROR');
      expect(body.error.message.length).toBeGreaterThan(0);
    }
    expect(count('SELECT COUNT(*) AS n FROM notes')).toBe(0);
  });

  it('границы: title 200/201 и bodyMarkdown 100000/100001 (NFR-7)', async () => {
    const alice = await registerUser(ALICE);
    const okTitle = await api(alice, 'POST', '/api/notes', { title: 'a'.repeat(200), bodyMarkdown: '' });
    expect(okTitle.statusCode).toBe(201);

    const badTitle = await api(alice, 'POST', '/api/notes', { title: 'a'.repeat(201), bodyMarkdown: '' });
    expect(badTitle.statusCode).toBe(422);
    expect(badTitle.json()).toMatchObject({ error: { code: 'VALIDATION_ERROR', field: 'title' } });

    const okBody = await api(alice, 'POST', '/api/notes', { bodyMarkdown: 'b'.repeat(100_000) });
    expect(okBody.statusCode).toBe(201);

    const badBody = await api(alice, 'POST', '/api/notes', { bodyMarkdown: 'b'.repeat(100_001) });
    expect(badBody.statusCode).toBe(422);
    expect(badBody.json()).toMatchObject({
      error: { code: 'VALIDATION_ERROR', field: 'bodyMarkdown' },
    });
  });

  it('заголовок/тело неверного типа → 422 с field', async () => {
    const alice = await registerUser(ALICE);
    const badTitle = await api(alice, 'POST', '/api/notes', { title: 42, bodyMarkdown: 'x' });
    expect(badTitle.statusCode).toBe(422);
    expect(badTitle.json()).toMatchObject({ error: { field: 'title' } });

    const badBody = await api(alice, 'POST', '/api/notes', { bodyMarkdown: 42 });
    expect(badBody.statusCode).toBe(422);
    expect(badBody.json()).toMatchObject({ error: { field: 'bodyMarkdown' } });
  });

  it('заметки персистентны после перезапуска сервера (NFR-25)', async () => {
    const alice = await registerUser(ALICE);
    const created = await createNote(alice, { title: 'До перезапуска', bodyMarkdown: 'черновик' });
    const patched = await api(alice, 'PATCH', `/api/notes/${created.id}`, {
      bodyMarkdown: 'обновлено',
    });
    expect(patched.statusCode).toBe(200);

    await app.close();
    app = await newApp(dbPath);

    const res = await api(alice, 'GET', `/api/notes/${created.id}`);
    expect(res.statusCode).toBe(200);
    expect(res.json<ApiNote>()).toMatchObject({
      id: created.id,
      title: 'До перезапуска',
      bodyMarkdown: 'обновлено',
    });

    const list = await listNotes(alice);
    expect(list.total).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// GET /api/notes — список (AC-13, Q-S3)
// ---------------------------------------------------------------------------

describe('GET /api/notes — список (AC-13, Q-S3)', () => {
  it('пустой список → {items:[], total:0}', async () => {
    const alice = await registerUser(ALICE);
    expect(await listNotes(alice)).toEqual({ items: [], total: 0 });
  });

  it('без сессии → 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/notes' });
    expect(res.statusCode).toBe(401);
  });

  it('содержит только заметки текущего пользователя (AC-13)', async () => {
    const alice = await registerUser(ALICE);
    const bob = await registerUser(BOB);

    const a1 = await createNote(alice, { title: 'A1', bodyMarkdown: '' });
    const b1 = await createNote(bob, { title: 'B1', bodyMarkdown: '' });

    const aliceList = await listNotes(alice);
    expect(aliceList.total).toBe(1);
    expect(aliceList.items.map((n) => n.id)).toEqual([a1.id]);
    expect(JSON.stringify(aliceList)).not.toContain('B1');

    const bobList = await listNotes(bob);
    expect(bobList.total).toBe(1);
    expect(bobList.items.map((n) => n.id)).toEqual([b1.id]);
  });

  it('сортирует по updatedAt DESC; PATCH поднимает заметку наверх (Q-S3)', async () => {
    const alice = await registerUser(ALICE);
    const a = await createNote(alice, { title: 'A', bodyMarkdown: '' });
    await sleep(5);
    const b = await createNote(alice, { title: 'B', bodyMarkdown: '' });
    await sleep(5);
    const c = await createNote(alice, { title: 'C', bodyMarkdown: '' });
    await sleep(5);

    expect((await listNotes(alice)).items.map((n) => n.id)).toEqual([c.id, b.id, a.id]);

    const patched = await api(alice, 'PATCH', `/api/notes/${a.id}`, { title: 'A (правка)' });
    expect(patched.statusCode).toBe(200);
    expect(patched.json<ApiNote>().updatedAt >= a.updatedAt).toBe(true);

    expect((await listNotes(alice)).items.map((n) => n.id)).toEqual([a.id, c.id, b.id]);
  });
});

// ---------------------------------------------------------------------------
// Ownership (AC-11/AC-12/AC-14, Q-A7)
// ---------------------------------------------------------------------------

describe('ownership: чужой id → 404 без раскрытия (AC-11/AC-12/AC-14)', () => {
  it('GET чужой заметки → 404, данные не раскрываются', async () => {
    const alice = await registerUser(ALICE);
    const bob = await registerUser(BOB);
    const secret = await createNote(bob, { title: 'Секрет B', bodyMarkdown: 'тело B' });

    const res = await api(alice, 'GET', `/api/notes/${secret.id}`);
    expect(res.statusCode).toBe(404);
    const body = res.json<{ error: { code: string; message: string } }>();
    expect(body.error.code).toBe('NOT_FOUND');
    const serialized = JSON.stringify(body);
    expect(serialized).not.toContain('Секрет B');
    expect(serialized).not.toContain('тело B');
    expect(serialized).not.toContain('NOT_FOUND_FORBIDDEN');
  });

  it('GET несуществующий и нечисловой id → 404', async () => {
    const alice = await registerUser(ALICE);
    const missing = await api(alice, 'GET', '/api/notes/999999');
    expect(missing.statusCode).toBe(404);
    const malformed = await api(alice, 'GET', '/api/notes/abc');
    expect(malformed.statusCode).toBe(404);
    expect(malformed.json()).toMatchObject({ error: { code: 'NOT_FOUND' } });
  });

  it('PATCH чужой заметки → 404, заметка не меняется (AC-12)', async () => {
    const alice = await registerUser(ALICE);
    const bob = await registerUser(BOB);
    const note = await createNote(bob, { title: 'B', bodyMarkdown: 'исходный' });

    const res = await api(alice, 'PATCH', `/api/notes/${note.id}`, {
      title: 'Взлом',
      bodyMarkdown: 'взлом',
      tags: ['hacked'],
    });
    expect(res.statusCode).toBe(404);

    const row = app.db
      .prepare('SELECT title, body_markdown, updated_at FROM notes WHERE id = ?')
      .get(note.id) as { title: string; body_markdown: string; updated_at: string };
    expect(row).toMatchObject({ title: 'B', body_markdown: 'исходный', updated_at: note.updatedAt });
    expect(count('SELECT COUNT(*) AS n FROM note_tags')).toBe(0);
  });

  it('DELETE чужой заметки → 404, заметка остаётся (AC-12)', async () => {
    const alice = await registerUser(ALICE);
    const bob = await registerUser(BOB);
    const note = await createNote(bob, { title: 'B', bodyMarkdown: 'текст' });

    const res = await api(alice, 'DELETE', `/api/notes/${note.id}`);
    expect(res.statusCode).toBe(404);
    expect(count('SELECT COUNT(*) AS n FROM notes')).toBe(1);
    expect((await api(bob, 'GET', `/api/notes/${note.id}`)).statusCode).toBe(200);
  });

  it('PATCH/DELETE несуществующего id → 404', async () => {
    const alice = await registerUser(ALICE);
    expect((await api(alice, 'PATCH', '/api/notes/4242', { title: 'x' })).statusCode).toBe(404);
    expect((await api(alice, 'DELETE', '/api/notes/4242')).statusCode).toBe(404);
  });

  it('чужой id в списке не появляется и не влияет на total (AC-13)', async () => {
    const alice = await registerUser(ALICE);
    const bob = await registerUser(BOB);
    await createNote(alice, { bodyMarkdown: 'a' });
    await createNote(bob, { bodyMarkdown: 'b' });
    await createNote(bob, { bodyMarkdown: 'c' });

    const list = await listNotes(alice);
    expect(list.total).toBe(1);
    expect(list.items).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// PATCH/DELETE своей заметки (AC-18..AC-21 на уровне API)
// ---------------------------------------------------------------------------

describe('PATCH/DELETE своей заметки', () => {
  it('PATCH частично: меняет только переданные поля и персистит', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { title: 'T', bodyMarkdown: 'B1' });

    const onlyTitle = await api(alice, 'PATCH', `/api/notes/${note.id}`, { title: 'T2' });
    expect(onlyTitle.statusCode).toBe(200);
    expect(onlyTitle.json<ApiNote>()).toMatchObject({ title: 'T2', bodyMarkdown: 'B1' });

    const onlyBody = await api(alice, 'PATCH', `/api/notes/${note.id}`, { bodyMarkdown: 'B2' });
    expect(onlyBody.json<ApiNote>()).toMatchObject({ title: 'T2', bodyMarkdown: 'B2' });

    const row = app.db
      .prepare('SELECT title, body_markdown FROM notes WHERE id = ?')
      .get(note.id) as { title: string; body_markdown: string };
    expect(row).toEqual({ title: 'T2', body_markdown: 'B2' });
  });

  it('PATCH на неизвестном id → 404 (без сессии → 401)', async () => {
    const alice = await registerUser(ALICE);
    expect((await api(alice, 'PATCH', '/api/notes/77', { title: 'x' })).statusCode).toBe(404);
    const noAuth = await app.inject({
      method: 'PATCH',
      url: '/api/notes/77',
      payload: { title: 'x' },
    });
    expect(noAuth.statusCode).toBe(401);
  });

  it('PATCH без полей → 422; PATCH, делающий заметку пустой → 422', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { title: 'T', bodyMarkdown: 'B' });

    const empty = await api(alice, 'PATCH', `/api/notes/${note.id}`, {});
    expect(empty.statusCode).toBe(422);
    expect(empty.json()).toMatchObject({ error: { code: 'VALIDATION_ERROR' } });

    const wipe = await api(alice, 'PATCH', `/api/notes/${note.id}`, {
      title: '',
      bodyMarkdown: '',
    });
    expect(wipe.statusCode).toBe(422);

    const row = app.db
      .prepare('SELECT title, body_markdown FROM notes WHERE id = ?')
      .get(note.id) as { title: string; body_markdown: string };
    expect(row).toEqual({ title: 'T', body_markdown: 'B' });
  });

  it('PATCH title > 200 → 422 field=title', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { bodyMarkdown: 'текст' });
    const res = await api(alice, 'PATCH', `/api/notes/${note.id}`, { title: 'a'.repeat(201) });
    expect(res.statusCode).toBe(422);
    expect(res.json()).toMatchObject({ error: { field: 'title' } });
  });

  it('DELETE → 204 без тела, затем GET → 404 и список пуст', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { title: 'Удалить', bodyMarkdown: '' });

    const res = await api(alice, 'DELETE', `/api/notes/${note.id}`);
    expect(res.statusCode).toBe(204);
    expect(res.body).toBe('');
    expect(count('SELECT COUNT(*) AS n FROM notes')).toBe(0);
    expect((await api(alice, 'GET', `/api/notes/${note.id}`)).statusCode).toBe(404);
    expect(await listNotes(alice)).toEqual({ items: [], total: 0 });
  });

  it('DELETE заметки каскадно очищает note_tags', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { bodyMarkdown: 'текст', tags: ['Work', 'Home'] });
    expect(count('SELECT COUNT(*) AS n FROM note_tags')).toBe(2);

    expect((await api(alice, 'DELETE', `/api/notes/${note.id}`)).statusCode).toBe(204);
    expect(count('SELECT COUNT(*) AS n FROM note_tags')).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// tags — базовая поддержка (T-04); лимиты/поиск — T-05
// ---------------------------------------------------------------------------

describe('tags: базовое сохранение (T-04)', () => {
  it('POST сохраняет теги: тримминг, отбрасывание пустых, дедуп без учёта регистра', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, {
      bodyMarkdown: 'текст',
      tags: [' Work ', '', 'work', 'Home', '   '],
    });

    expect(note.tags).toEqual(['Home', 'Work']);
    expect(rows<{ name: string }>('SELECT name FROM tags ORDER BY name')).toEqual([
      { name: 'Home' },
      { name: 'Work' },
    ]);
    expect(count('SELECT COUNT(*) AS n FROM note_tags')).toBe(2);
  });

  it('PATCH tags заменяет набор и переиспользует тег в исходном написании', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { bodyMarkdown: 'текст', tags: ['Home', 'Work'] });

    const patched = await api(alice, 'PATCH', `/api/notes/${note.id}`, { tags: ['home', 'New'] });
    expect(patched.statusCode).toBe(200);
    // Q-T2: регистронезависимое сопоставление сохраняет первое написание ('Home').
    expect(patched.json<ApiNote>().tags).toEqual(['Home', 'New']);
    expect(count('SELECT COUNT(*) AS n FROM note_tags')).toBe(2);

    const cleared = await api(alice, 'PATCH', `/api/notes/${note.id}`, { tags: [] });
    expect(cleared.json<ApiNote>().tags).toEqual([]);
    expect(count('SELECT COUNT(*) AS n FROM note_tags')).toBe(0);
  });

  it('GET отдельной заметки возвращает её теги; теги изолированы по владельцу', async () => {
    const alice = await registerUser(ALICE);
    const bob = await registerUser(BOB);
    const aliceNote = await createNote(alice, { bodyMarkdown: 'a', tags: ['shared'] });
    const bobNote = await createNote(bob, { bodyMarkdown: 'b', tags: ['shared'] });

    const res = await api(alice, 'GET', `/api/notes/${aliceNote.id}`);
    expect(res.json<ApiNote>().tags).toEqual(['shared']);
    // У каждого пользователя — свой тег (tags.user_id), связи не пересекаются.
    expect(count('SELECT COUNT(*) AS n FROM tags')).toBe(2);
    expect(
      count(`SELECT COUNT(*) AS n FROM note_tags WHERE note_id = ${bobNote.id}`),
    ).toBe(1);
  });

  it('tags не массив или содержит не строки → 422 field=tags', async () => {
    const alice = await registerUser(ALICE);
    const notArray = await api(alice, 'POST', '/api/notes', { bodyMarkdown: 'x', tags: 'Work' });
    expect(notArray.statusCode).toBe(422);
    expect(notArray.json()).toMatchObject({ error: { field: 'tags' } });

    const badItem = await api(alice, 'POST', '/api/notes', { bodyMarkdown: 'x', tags: [1] });
    expect(badItem.statusCode).toBe(422);
    expect(badItem.json()).toMatchObject({ error: { field: 'tags' } });
    expect(count('SELECT COUNT(*) AS n FROM notes')).toBe(0);
  });
});
