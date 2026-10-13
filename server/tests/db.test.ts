/**
 * T-01 — интеграционные тесты схемы БД и runner'а миграций (vitest, node:sqlite).
 *
 * Проверяем приёмку T-01 как пользователь БД:
 *   1) 5 таблиц + индексы + FK=ON; файл БД создаётся;
 *   2) migrate идемпотентен (повтор не падает и не дублирует);
 *   3) вставка/чтение через подготовленные statements;
 *   4) каскады user→notes/sessions/tags и note→note_tags;
 *   5) регистронезависимая уникальность email/тегов;
 *   6) индекс notes(user_id, updated_at DESC) реально используется;
 *   7) обратимость: up → down → up.
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { DatabaseSync } from 'node:sqlite';
import { openDatabase, prepareStatements, runInsert, transaction, type Statements } from '../src/db/client.js';
import { getAppliedMigrations, migrateDown, migrateUp } from '../src/db/migrate.js';

/** Внутренние строки БД (sqlite_master и т.п.). */
type Row = Record<string, unknown>;

function tableNames(db: DatabaseSync): string[] {
  return (db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all() as unknown as Row[])
    .map((r) => String(r.name))
    // sqlite_sequence — внутренняя таблица AUTOINCREMENT, не часть схемы
    .filter((name) => !name.startsWith('sqlite_'))
    .sort();
}

function indexNames(db: DatabaseSync): string[] {
  return (db.prepare("SELECT name FROM sqlite_master WHERE type='index'").all() as unknown as Row[])
    .map((r) => String(r.name))
    .filter((n) => !n.startsWith('sqlite_autoindex'))
    .sort();
}

function count(db: DatabaseSync, table: string): number {
  const row = db.prepare(`SELECT COUNT(*) AS c FROM ${table}`).get() as unknown as Row;
  return Number(row.c);
}

function foreignKeysOn(db: DatabaseSync): number {
  const row = db.prepare('PRAGMA foreign_keys').get() as unknown as Row;
  return Number(row.foreign_keys);
}

function seedUser(stmts: Statements, email = 'alice@example.com'): number {
  const now = '2026-10-13T10:00:00.000Z';
  return runInsert(stmts.insertUser, email, email.toLowerCase(), 'bcrypt-hash', now);
}

describe('T-01 DB schema & migrations', () => {
  let dir: string;
  let dbPath: string;
  let db: DatabaseSync;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'notes-db-'));
    dbPath = join(dir, 'app.db');
    db = openDatabase(dbPath);
  });

  afterEach(() => {
    try {
      db.close();
    } catch {
      /* already closed */
    }
    rmSync(dir, { recursive: true, force: true });
  });

  it('создаёт файл БД, 5 таблиц, индексы и включает FK', () => {
    const ran = migrateUp(db);
    expect(ran).toEqual(['001_init.sql']);

    // файл БД реально создан на диске (персистентность, NFR-25)
    expect(existsSync(dbPath)).toBe(true);

    expect(tableNames(db)).toEqual([
      'note_tags',
      'notes',
      'schema_migrations',
      'sessions',
      'tags',
      'users',
    ]);
    expect(indexNames(db)).toEqual([
      'idx_note_tags_tag',
      'idx_notes_user_updated',
      'idx_sessions_user',
    ]);
    expect(foreignKeysOn(db)).toBe(1);
  });

  it('идемпотентен: повторный migrate не падает и не дублирует', () => {
    expect(migrateUp(db)).toEqual(['001_init.sql']);
    expect(migrateUp(db)).toEqual([]);
    expect(migrateUp(db)).toEqual([]);
    expect(getAppliedMigrations(db)).toHaveLength(1);
    expect(count(db, 'schema_migrations')).toBe(1);
  });

  it('вставляет и читает заметку с тегами через statements', () => {
    migrateUp(db);
    const stmts = prepareStatements(db);
    const userId = seedUser(stmts);

    const createdAt = '2026-10-13T10:00:00.000Z';
    const noteId = runInsert(stmts.insertNote, userId, 'План', '# заголовок', createdAt, createdAt);
    const tagId = runInsert(stmts.insertTag, userId, 'Работа', 'работа');
    stmts.linkNoteTag.run(noteId, tagId);

    const note = stmts.getNoteById.get(noteId, userId) as unknown as Row;
    expect(note.title).toBe('План');
    expect(note.body_markdown).toBe('# заголовок');

    expect(stmts.listNotesByUser.all(userId)).toHaveLength(1);

    const tags = stmts.getTagsForNote.all(noteId) as unknown as Row[];
    expect(tags.map((t) => t.name)).toEqual(['Работа']);

    const withCount = stmts.listTagsByUser.all(userId) as unknown as Row[];
    expect(withCount).toHaveLength(1);
    expect(Number(withCount[0]?.count)).toBe(1);
  });

  it('каскадно удаляет notes/sessions/tags при удалении user', () => {
    migrateUp(db);
    const stmts = prepareStatements(db);
    const userId = seedUser(stmts);
    const otherId = seedUser(stmts, 'bob@example.com');

    const t = '2026-10-13T10:00:00.000Z';
    const noteId = runInsert(stmts.insertNote, userId, 'N', 'body', t, t);
    const tagId = runInsert(stmts.insertTag, userId, 'Tag', 'tag');
    stmts.linkNoteTag.run(noteId, tagId);
    stmts.insertSession.run('hash-1', userId, 'csrf', t, '2026-10-20T10:00:00.000Z');

    // «шум» от другого пользователя не должен исчезнуть
    const otherNote = runInsert(stmts.insertNote, otherId, 'B', 'body', t, t);

    stmts.deleteUser.run(userId);

    expect(count(db, 'users')).toBe(1);
    expect(count(db, 'notes')).toBe(1);
    expect(count(db, 'sessions')).toBe(0);
    expect(count(db, 'tags')).toBe(0);
    expect(count(db, 'note_tags')).toBe(0);
    expect((stmts.getNoteById.get(otherNote, otherId) as unknown as Row).title).toBe('B');
  });

  it('каскадно удаляет note_tags при удалении note', () => {
    migrateUp(db);
    const stmts = prepareStatements(db);
    const userId = seedUser(stmts);
    const t = '2026-10-13T10:00:00.000Z';

    const noteId = runInsert(stmts.insertNote, userId, 'N', 'body', t, t);
    const tagId = runInsert(stmts.insertTag, userId, 'Tag', 'tag');
    stmts.linkNoteTag.run(noteId, tagId);

    expect(count(db, 'note_tags')).toBe(1);
    stmts.deleteNote.run(noteId, userId);
    expect(count(db, 'note_tags')).toBe(0);
    // тег остаётся (чистку осиротевших делает T-05)
    expect(count(db, 'tags')).toBe(1);
  });

  it('email/теги уникальны без учёта регистра (COLLATE NOCASE + *_norm)', () => {
    migrateUp(db);
    const stmts = prepareStatements(db);
    seedUser(stmts, 'Alice@Example.com');

    // email_norm UNIQUE: повторный адрес в другом регистре отклоняется
    expect(() => seedUser(stmts, 'alice@example.com')).toThrow();
    // COLLATE NOCASE: поиск по email без учёта регистра возвращает строку
    const found = stmts.getUserByEmail.get('ALICE@EXAMPLE.COM') as unknown as Row;
    expect(found).toBeTruthy();

    const userId = runInsert(stmts.insertUser, 'carol@example.com', 'carol@example.com', 'h', 't');
    stmts.insertTag.run(userId, 'Работа', 'работа');
    expect(() => stmts.insertTag.run(userId, 'РАБОТА', 'работа')).toThrow();
  });

  it('использует idx_notes_user_updated для выборки списка заметок', () => {
    migrateUp(db);
    const plan = (
      db
        .prepare(
          `EXPLAIN QUERY PLAN SELECT id FROM notes WHERE user_id = ? ORDER BY updated_at DESC`,
        )
        .all(1) as unknown as Row[]
    )
      .map((r) => String(r.detail))
      .join(' | ');
    expect(plan).toContain('idx_notes_user_updated');
  });

  it('обратима: up → down → up восстанавливает схему', () => {
    migrateUp(db);
    expect(getAppliedMigrations(db)).toHaveLength(1);

    expect(migrateDown(db)).toEqual(['001_init.sql']);
    expect(tableNames(db)).toEqual(['schema_migrations']);
    expect(getAppliedMigrations(db)).toHaveLength(0);

    expect(migrateUp(db)).toEqual(['001_init.sql']);
    expect(tableNames(db)).toContain('notes');
  });

  it('транзакция откатывает частичную запись при ошибке', () => {
    migrateUp(db);
    const stmts = prepareStatements(db);
    const t = '2026-10-13T10:00:00.000Z';

    expect(() =>
      transaction(db, () => {
        runInsert(stmts.insertUser, 'dave@example.com', 'dave@example.com', 'h', t);
        throw new Error('boom');
      }),
    ).toThrow('boom');

    expect(count(db, 'users')).toBe(0);
  });
});
