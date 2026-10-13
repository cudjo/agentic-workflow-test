/**
 * tests/tags.test.ts — теги (many-to-many) и серверный поиск/фильтр (T-05).
 *
 * Покрывает приёмку T-05 и связанные AC/Q SPEC:
 *   * лимиты Q-T3 (≤20 тегов, длина ≤50) → 422; пустой/пробельный тег отбрасывается (AC-33/36/T1);
 *   * дедупликация без учёта регистра с сохранением первого написания (AC-37/Q-T2), кириллица;
 *   * спецсимволы/юникод в теге сохраняются (T4);
 *   * GET /api/tags → {items:[{name,count}]}, только свои (Q-T4/AC-44);
 *   * поиск q: по title+body, регистронезависимо (S2, включая кириллицу), спецсимволы как
 *     литералы (S1), markdown — как текст (S3), пустой q → все (S4);
 *   * фильтр tag (AC-40), q+tag по «И» (AC-41), поиск ограничен владельцем (AC-44/S7);
 *   * удаление/смена тегов не оставляет битых note_tags и пустых тегов (T6).
 *
 * Изоляция: на каждый тест — свой tmp-файл БД (см. tests/notes.test.ts).
 */
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance, InjectOptions, LightMyRequestResponse } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import type { SqlValue } from '../src/db/client.js';
import { CSRF_COOKIE, CSRF_HEADER } from '../src/lib/sessions.js';

const ALICE = 'alice@example.com';
const BOB = 'bob@example.com';
const PASSWORD = 'correct-horse-battery';
const TEST_SECRET = 'test-session-secret-0123456789abcdef';

let app: FastifyInstance;
let dataDir: string;
let dbPath: string;

beforeEach(async () => {
  dataDir = mkdtempSync(join(tmpdir(), 'notes-tags-'));
  dbPath = join(dataDir, 'app.db');
  app = await newApp(dbPath);
});

afterEach(async () => {
  await app.close().catch(() => undefined);
  rmSync(dataDir, { recursive: true, force: true });
});

function newApp(databasePath: string): Promise<FastifyInstance> {
  return buildApp({
    config: loadConfig({ NODE_ENV: 'test', DATABASE_PATH: databasePath, SESSION_SECRET: TEST_SECRET }),
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

interface ApiTag {
  name: string;
  count: number;
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

async function createNote(auth: Auth, payload: unknown): Promise<ApiNote> {
  const res = await api(auth, 'POST', '/api/notes', payload);
  expect(res.statusCode).toBe(201);
  return res.json<ApiNote>();
}

/** Заметки из ответа GET /api/notes (с опциональным query). */
async function listNotes(
  auth: Auth,
  query = '',
): Promise<{ items: ApiNote[]; total: number }> {
  const res = await api(auth, 'GET', `/api/notes${query}`);
  expect(res.statusCode).toBe(200);
  return res.json<{ items: ApiNote[]; total: number }>();
}

/** Теги из ответа GET /api/tags. */
async function listTags(auth: Auth): Promise<ApiTag[]> {
  const res = await api(auth, 'GET', '/api/tags');
  expect(res.statusCode).toBe(200);
  return res.json<{ items: ApiTag[] }>().items;
}

function count(sql: string): number {
  const row = app.db.prepare(sql).get() as { n?: number } | undefined;
  return Number(row?.n ?? 0);
}

function tagRows<T>(sql: string, ...params: SqlValue[]): T[] {
  return app.db.prepare(sql).all(...params) as T[];
}

/** Уникальные имена тегов: `tag-01`…`tag-NN` (гарантированная уникальность и короткая длина). */
function tagNames(n: number): string[] {
  return Array.from({ length: n }, (_, i) => `tag-${String(i + 1).padStart(2, '0')}`);
}

// ---------------------------------------------------------------------------
// Лимиты тегов (Q-T3, AC-33/AC-36)
// ---------------------------------------------------------------------------

describe('лимиты тегов (Q-T3)', () => {
  it('20 тегов — граница, сохраняются все', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { bodyMarkdown: 't', tags: tagNames(20) });
    expect(note.tags).toHaveLength(20);
    expect(count('SELECT COUNT(*) AS n FROM note_tags')).toBe(20);
  });

  it('21 тег → 422 field=tags, заметка не создаётся', async () => {
    const alice = await registerUser(ALICE);
    const res = await api(alice, 'POST', '/api/notes', { bodyMarkdown: 't', tags: tagNames(21) });
    expect(res.statusCode).toBe(422);
    expect(res.json()).toMatchObject({ error: { code: 'VALIDATION_ERROR', field: 'tags' } });
    expect(count('SELECT COUNT(*) AS n FROM notes')).toBe(0);
    expect(count('SELECT COUNT(*) AS n FROM tags')).toBe(0);
  });

  it('лимит количества считается по уникальным тегам: 21 с дублем → 20 уникальных → 201', async () => {
    const alice = await registerUser(ALICE);
    const tags = ['Dup', 'DUP', ...tagNames(19)]; // 21 значение, 20 уникальных
    const note = await createNote(alice, { bodyMarkdown: 't', tags });
    expect(note.tags).toHaveLength(20);
  });

  it('длина тега 50 — граница; 51 → 422 field=tags', async () => {
    const alice = await registerUser(ALICE);
    const ok = await api(alice, 'POST', '/api/notes', { bodyMarkdown: 't', tags: ['a'.repeat(50)] });
    expect(ok.statusCode).toBe(201);

    const bad = await api(alice, 'POST', '/api/notes', { bodyMarkdown: 't', tags: ['a'.repeat(51)] });
    expect(bad.statusCode).toBe(422);
    expect(bad.json()).toMatchObject({ error: { field: 'tags' } });
  });

  it('PATCH с превышением лимитов → 422, заметка не меняется', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { title: 'N', bodyMarkdown: 't', tags: ['Work'] });

    const tooMany = await api(alice, 'PATCH', `/api/notes/${note.id}`, { tags: tagNames(21) });
    expect(tooMany.statusCode).toBe(422);
    expect(tooMany.json()).toMatchObject({ error: { field: 'tags' } });

    const tooLong = await api(alice, 'PATCH', `/api/notes/${note.id}`, { tags: ['a'.repeat(51)] });
    expect(tooLong.statusCode).toBe(422);

    const check = await api(alice, 'GET', `/api/notes/${note.id}`);
    expect(check.json<ApiNote>().tags).toEqual(['Work']);
  });
});

// ---------------------------------------------------------------------------
// Нормализация тегов (Q-T2/T1/T4)
// ---------------------------------------------------------------------------

describe('нормализация тегов (Q-T2/T1/T4)', () => {
  it('пустой/пробельный тег не добавляется (AC-33/AC-36/T1)', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { bodyMarkdown: 't', tags: ['', '   ', '\t', 'Real'] });
    expect(note.tags).toEqual(['Real']);
  });

  it('дубликат в другом регистре не создаётся, сохраняется первое написание (AC-37/T2)', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { bodyMarkdown: 't', tags: ['Work', 'work', 'WORK'] });
    expect(note.tags).toEqual(['Work']);
    expect(count('SELECT COUNT(*) AS n FROM tags')).toBe(1);
  });

  it('кириллический дубликат другого регистра схлопывается (Q-T2)', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { bodyMarkdown: 't', tags: ['Работа', 'работа', 'РАБОТА'] });
    expect(note.tags).toEqual(['Работа']);
    expect(tagRows<{ name: string; name_norm: string }>('SELECT name, name_norm FROM tags')).toEqual([
      { name: 'Работа', name_norm: 'работа' },
    ]);
  });

  it('спецсимволы и юникод в теге сохраняются (T4)', async () => {
    const alice = await registerUser(ALICE);
    const tags = ['C++', 'café', '100%', 'a_b', '🚀'];
    const note = await createNote(alice, { bodyMarkdown: 't', tags });
    expect([...note.tags].sort()).toEqual([...tags].sort());
  });
});

// ---------------------------------------------------------------------------
// GET /api/tags (PLAN §3.2, Q-T4/AC-44)
// ---------------------------------------------------------------------------

describe('GET /api/tags', () => {
  it('пусто → {items:[]}', async () => {
    const alice = await registerUser(ALICE);
    const res = await api(alice, 'GET', '/api/tags');
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ items: [] });
  });

  it('без сессии → 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/tags' });
    expect(res.statusCode).toBe(401);
  });

  it('возвращает теги со счётчиком заметок', async () => {
    const alice = await registerUser(ALICE);
    await createNote(alice, { bodyMarkdown: 'a', tags: ['Work', 'Home'] });
    await createNote(alice, { bodyMarkdown: 'b', tags: ['Work'] });

    const items = await listTags(alice);
    const byName = Object.fromEntries(items.map((t) => [t.name, t.count]));
    expect(byName).toEqual({ Work: 2, Home: 1 });
  });

  it('возвращает только свои теги (Q-T4/AC-44): одинаковое имя у разных пользователей', async () => {
    const alice = await registerUser(ALICE);
    const bob = await registerUser(BOB);
    await createNote(alice, { bodyMarkdown: 'a', tags: ['shared'] });
    await createNote(bob, { bodyMarkdown: 'b', tags: ['shared', 'bob-only'] });

    const aliceTags = await listTags(alice);
    expect(aliceTags).toEqual([{ name: 'shared', count: 1 }]);
    expect(JSON.stringify(aliceTags)).not.toContain('bob-only');
  });
});

// ---------------------------------------------------------------------------
// Поиск q (AC-39, Q-S1/Q-S2, S1..S4)
// ---------------------------------------------------------------------------

describe('поиск q (AC-39, S1..S4)', () => {
  it('находит по заголовку и по телу заметки', async () => {
    const alice = await registerUser(ALICE);
    await createNote(alice, { title: 'JavaScript заметка', bodyMarkdown: 'тело' });
    await createNote(alice, { title: 'Прочее', bodyMarkdown: 'про JavaScript внутри' });

    expect((await listNotes(alice, '?q=javascript')).total).toBe(2);
    expect((await listNotes(alice, '?q=заголовку')).total).toBe(0);
  });

  it('регистронезависим (латиница) в обе стороны (S2)', async () => {
    const alice = await registerUser(ALICE);
    await createNote(alice, { title: 'Alpha Beta', bodyMarkdown: 'x' });
    expect((await listNotes(alice, '?q=ALPHA')).total).toBe(1);
    expect((await listNotes(alice, '?q=alpha')).total).toBe(1);
    expect((await listNotes(alice, '?q=AlPhA')).total).toBe(1);
  });

  it('регистронезависим по кириллице в обе стороны (S2)', async () => {
    const alice = await registerUser(ALICE);
    await createNote(alice, { title: 'Привет Мир', bodyMarkdown: 'Тело заметки' });

    expect((await listNotes(alice, '?q=' + encodeURIComponent('привет'))).total).toBe(1);
    expect((await listNotes(alice, '?q=' + encodeURIComponent('ПРИВЕТ'))).total).toBe(1);
    expect((await listNotes(alice, '?q=' + encodeURIComponent('тело'))).total).toBe(1);
    expect((await listNotes(alice, '?q=' + encodeURIComponent('ТЕЛО'))).total).toBe(1);
    expect((await listNotes(alice, '?q=' + encodeURIComponent('отсутствует'))).total).toBe(0);
  });

  it('пустой q → все заметки (S4)', async () => {
    const alice = await registerUser(ALICE);
    await createNote(alice, { bodyMarkdown: 'a' });
    await createNote(alice, { bodyMarkdown: 'b' });
    expect((await listNotes(alice, '?q=')).total).toBe(2);
    expect((await listNotes(alice)).total).toBe(2);
  });

  it('спецсимволы % _ \\ трактуются как литералы, не wildcard (S1)', async () => {
    const alice = await registerUser(ALICE);
    await createNote(alice, { bodyMarkdown: 'скидка 100% сегодня' });
    await createNote(alice, { bodyMarkdown: '100 процентов' });
    await createNote(alice, { bodyMarkdown: 'a_b подчёркивание' });
    await createNote(alice, { bodyMarkdown: 'abc без подчёркивания' });
    await createNote(alice, { bodyMarkdown: 'путь C:\\temp\\file' });

    const percent = await listNotes(alice, '?q=' + encodeURIComponent('%'));
    expect(percent.total).toBe(1);
    expect(percent.items[0]!.bodyMarkdown).toContain('100%');

    const underscore = await listNotes(alice, '?q=' + encodeURIComponent('_'));
    expect(underscore.total).toBe(1);
    expect(underscore.items[0]!.bodyMarkdown).toContain('a_b');

    const backslash = await listNotes(alice, '?q=' + encodeURIComponent('\\'));
    expect(backslash.total).toBe(1);
    expect(backslash.items[0]!.bodyMarkdown).toContain('C:\\temp');
  });

  it('подстрочный поиск по markdown-синтаксису как по тексту (S3)', async () => {
    const alice = await registerUser(ALICE);
    await createNote(alice, { bodyMarkdown: '**жирный** и # заголовок' });
    expect((await listNotes(alice, '?q=' + encodeURIComponent('**жирный**'))).total).toBe(1);
    expect((await listNotes(alice, '?q=' + encodeURIComponent('# заголовок'))).total).toBe(1);
  });

  it('total отражает число совпадений, порядок — свежие сверху (Q-S3)', async () => {
    const alice = await registerUser(ALICE);
    const first = await createNote(alice, { title: 'match one', bodyMarkdown: '' });
    await new Promise((r) => setTimeout(r, 5));
    const second = await createNote(alice, { title: 'match two', bodyMarkdown: '' });
    await new Promise((r) => setTimeout(r, 5));
    await createNote(alice, { title: 'нет совпадения', bodyMarkdown: '' });

    const res = await listNotes(alice, '?q=match');
    expect(res.total).toBe(2);
    expect(res.items.map((n) => n.id)).toEqual([second.id, first.id]);
  });
});

// ---------------------------------------------------------------------------
// Фильтр tag и комбинация q+tag (AC-40/AC-41)
// ---------------------------------------------------------------------------

describe('фильтр tag (AC-40) и комбинация q+tag (AC-41)', () => {
  it('tag фильтрует только заметки с этим тегом (регистронезависимо)', async () => {
    const alice = await registerUser(ALICE);
    const work = await createNote(alice, { bodyMarkdown: 'a', tags: ['Work'] });
    await createNote(alice, { bodyMarkdown: 'b', tags: ['Home'] });
    await createNote(alice, { bodyMarkdown: 'c', tags: [] });

    const res = await listNotes(alice, '?tag=work');
    expect(res.total).toBe(1);
    expect(res.items[0]!.id).toBe(work.id);
  });

  it('несуществующий тег → пустой список', async () => {
    const alice = await registerUser(ALICE);
    await createNote(alice, { bodyMarkdown: 'a', tags: ['Work'] });
    expect((await listNotes(alice, '?tag=nope')).total).toBe(0);
  });

  it('q + tag вместе → пересечение по «И» (AC-41)', async () => {
    const alice = await registerUser(ALICE);
    const target = await createNote(alice, {
      title: 'Проект Альфа',
      bodyMarkdown: 'план релиза',
      tags: ['Work'],
    });
    await createNote(alice, { title: 'Проект Альфа', bodyMarkdown: 'другое', tags: ['Home'] });
    await createNote(alice, { title: 'Другое', bodyMarkdown: 'план релиза', tags: ['Work'] });

    const res = await listNotes(alice, '?q=' + encodeURIComponent('Альфа') + '&tag=work');
    expect(res.total).toBe(1);
    expect(res.items[0]!.id).toBe(target.id);
  });

  it('пустой tag → без фильтра (все заметки)', async () => {
    const alice = await registerUser(ALICE);
    await createNote(alice, { bodyMarkdown: 'a', tags: ['Work'] });
    await createNote(alice, { bodyMarkdown: 'b', tags: [] });
    expect((await listNotes(alice, '?tag=')).total).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// Изоляция поиска (AC-44/S7)
// ---------------------------------------------------------------------------

describe('изоляция поиска (AC-44/S7)', () => {
  it('поиск и фильтр возвращают только заметки владельца', async () => {
    const alice = await registerUser(ALICE);
    const bob = await registerUser(BOB);
    await createNote(alice, { title: 'секрет алисы common', bodyMarkdown: 'x', tags: ['shared'] });
    await createNote(bob, { title: 'секрет боба common', bodyMarkdown: 'y', tags: ['shared'] });

    const found = await listNotes(alice, '?q=common');
    expect(found.total).toBe(1);
    expect(JSON.stringify(found)).not.toContain('боба');

    const tagged = await listNotes(alice, '?tag=shared');
    expect(tagged.total).toBe(1);
    expect(JSON.stringify(tagged)).not.toContain('боба');
  });
});

// ---------------------------------------------------------------------------
// Чистка осиротевших тегов (T6)
// ---------------------------------------------------------------------------

describe('чистка осиротевших тегов (T6)', () => {
  it('удаление заметки убирает её теги из /api/tags и не оставляет битых note_tags', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { bodyMarkdown: 'a', tags: ['Only'] });

    expect((await api(alice, 'DELETE', `/api/notes/${note.id}`)).statusCode).toBe(204);

    expect(count('SELECT COUNT(*) AS n FROM note_tags')).toBe(0);
    expect(count('SELECT COUNT(*) AS n FROM tags')).toBe(0);
    expect(await listTags(alice)).toEqual([]);
  });

  it('общий тег остаётся, пока есть заметка; исчезает после удаления последней', async () => {
    const alice = await registerUser(ALICE);
    const n1 = await createNote(alice, { bodyMarkdown: 'a', tags: ['Shared'] });
    const n2 = await createNote(alice, { bodyMarkdown: 'b', tags: ['Shared'] });

    expect(await listTags(alice)).toEqual([{ name: 'Shared', count: 2 }]);

    await api(alice, 'DELETE', `/api/notes/${n1.id}`);
    expect(await listTags(alice)).toEqual([{ name: 'Shared', count: 1 }]);

    await api(alice, 'DELETE', `/api/notes/${n2.id}`);
    expect(await listTags(alice)).toEqual([]);
    expect(count('SELECT COUNT(*) AS n FROM tags')).toBe(0);
  });

  it('PATCH tags на пустой список удаляет осиротевшие теги', async () => {
    const alice = await registerUser(ALICE);
    const note = await createNote(alice, { bodyMarkdown: 'a', tags: ['One', 'Two'] });

    const cleared = await api(alice, 'PATCH', `/api/notes/${note.id}`, { tags: [] });
    expect(cleared.statusCode).toBe(200);
    expect(cleared.json<ApiNote>().tags).toEqual([]);

    expect(await listTags(alice)).toEqual([]);
    expect(count('SELECT COUNT(*) AS n FROM tags')).toBe(0);
  });

  it('в note_tags нет ссылок на несуществующие заметки/теги (нет битых ссылок)', async () => {
    const alice = await registerUser(ALICE);
    await createNote(alice, { bodyMarkdown: 'a', tags: ['X', 'Y'] });
    const second = await createNote(alice, { bodyMarkdown: 'b', tags: ['Y'] });
    await api(alice, 'PATCH', `/api/notes/${second.id}`, { tags: ['Z'] });
    await api(alice, 'DELETE', `/api/notes/${second.id}`);

    const brokenNotes = count(
      'SELECT COUNT(*) AS n FROM note_tags nt LEFT JOIN notes n ON n.id = nt.note_id WHERE n.id IS NULL',
    );
    const brokenTags = count(
      'SELECT COUNT(*) AS n FROM note_tags nt LEFT JOIN tags t ON t.id = nt.tag_id WHERE t.id IS NULL',
    );
    expect({ brokenNotes, brokenTags }).toEqual({ brokenNotes: 0, brokenTags: 0 });
  });
});
