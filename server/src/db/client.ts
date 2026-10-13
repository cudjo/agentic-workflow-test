/**
 * db/client.ts — тонкая обёртка над встроенным `node:sqlite` (DatabaseSync).
 *
 * Роль (PLAN §2): изолировать SQL-слой, чтобы позже заменить SQLite на PostgreSQL (риск R1).
 * Здесь: открытие соединения с корректными PRAGMA, набор подготовленных statements
 * и помощник транзакций. Бизнес-логика (валидация, ownership, поиск) живёт в T-02..T-05.
 *
 * Соглашения:
 *   * время — ISO-8601 UTC (`nowIso()`), хранится в TEXT (PLAN §3.1);
 *   * `PRAGMA foreign_keys=ON` — на каждом соединении (иначе каскады молча не работают);
 *   * все операции записи, затрагивающие >1 таблицу, — в `transaction()` (NFR-26/27).
 */
import { DatabaseSync, type StatementSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname, isAbsolute, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));

/** Путь по умолчанию: `server/data/app.db` (относительно корня пакета `server/`). */
export const DEFAULT_DB_PATH = resolve(MODULE_DIR, '..', '..', 'data', 'app.db');

/** Текущее время в формате ISO-8601 UTC — единственный формат времени в схеме. */
export function nowIso(): string {
  return new Date().toISOString();
}

/**
 * Разрешает путь к файлу БД: явный аргумент → env `DATABASE_PATH` → `server/data/app.db`.
 * `:memory:` (in-memory БД) возвращается как есть.
 */
export function resolveDatabasePath(explicit?: string): string {
  const raw = explicit ?? process.env.DATABASE_PATH ?? DEFAULT_DB_PATH;
  if (raw === ':memory:' || raw === '') return raw === '' ? DEFAULT_DB_PATH : raw;
  return isAbsolute(raw) ? raw : resolve(process.cwd(), raw);
}

/**
 * Открывает соединение (создаёт каталог для файла БД при необходимости) и применяет PRAGMA.
 * Вызывающий обязан закрыть соединение (`db.close()`).
 */
export function openDatabase(dbPath?: string): DatabaseSync {
  const path = resolveDatabasePath(dbPath);
  if (path !== ':memory:') {
    mkdirSync(dirname(path), { recursive: true });
  }
  const db = new DatabaseSync(path);
  // FK-каскады обязательны (acceptance T-01); PRAGMA действует в рамках соединения.
  db.exec('PRAGMA foreign_keys = ON');
  db.exec('PRAGMA busy_timeout = 5000');
  if (path !== ':memory:') {
    // WAL — параллельные чтения при едином писателе (однопроцессный деплой, PLAN R4).
    db.exec('PRAGMA journal_mode = WAL');
  }
  return db;
}

/**
 * Выполняет `fn` в транзакции. Вложенные вызовы не поддерживаются — используйте одну
 * транзакцию на логическую операцию. При ошибке выполняется откат и ошибка пробрасывается.
 */
export function transaction<T>(db: DatabaseSync, fn: () => T): T {
  db.exec('BEGIN');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (error) {
    try {
      db.exec('ROLLBACK');
    } catch {
      // соединение уже могло откатиться — не маскируем исходную ошибку
    }
    throw error;
  }
}

/**
 * Подготовленные statements для основных таблиц схемы (§3.1).
 * Имена — контракт для роутов/сервисов (T-02..T-05); SQL остаётся ANSI-совместимым.
 */
export function prepareStatements(db: DatabaseSync) {
  return {
    // ---- users ----
    insertUser: db.prepare(
      `INSERT INTO users (email, email_norm, password_hash, created_at)
       VALUES (?, ?, ?, ?)`,
    ),
    getUserById: db.prepare(
      `SELECT id, email, email_norm, password_hash, created_at FROM users WHERE id = ?`,
    ),
    getUserByEmail: db.prepare(
      `SELECT id, email, email_norm, password_hash, created_at FROM users WHERE email = ?`,
    ),
    deleteUser: db.prepare(`DELETE FROM users WHERE id = ?`),

    // ---- sessions ----
    insertSession: db.prepare(
      `INSERT INTO sessions (token_hash, user_id, csrf_token, created_at, expires_at)
       VALUES (?, ?, ?, ?, ?)`,
    ),
    getSessionByTokenHash: db.prepare(
      `SELECT id, token_hash, user_id, csrf_token, created_at, expires_at
       FROM sessions WHERE token_hash = ?`,
    ),
    touchSession: db.prepare(`UPDATE sessions SET expires_at = ? WHERE id = ?`),
    deleteSessionByTokenHash: db.prepare(`DELETE FROM sessions WHERE token_hash = ?`),
    deleteExpiredSessions: db.prepare(`DELETE FROM sessions WHERE expires_at <= ?`),

    // ---- notes ----
    insertNote: db.prepare(
      `INSERT INTO notes (user_id, title, body_markdown, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?)`,
    ),
    getNoteById: db.prepare(
      `SELECT id, user_id, title, body_markdown, created_at, updated_at
       FROM notes WHERE id = ? AND user_id = ?`,
    ),
    listNotesByUser: db.prepare(
      `SELECT id, user_id, title, body_markdown, created_at, updated_at
       FROM notes WHERE user_id = ? ORDER BY updated_at DESC, id DESC`,
    ),
    updateNote: db.prepare(
      `UPDATE notes SET title = ?, body_markdown = ?, updated_at = ?
       WHERE id = ? AND user_id = ?`,
    ),
    deleteNote: db.prepare(`DELETE FROM notes WHERE id = ? AND user_id = ?`),

    // ---- tags ----
    insertTag: db.prepare(
      `INSERT INTO tags (user_id, name, name_norm) VALUES (?, ?, ?)`,
    ),
    getTagByUserAndNorm: db.prepare(
      `SELECT id, user_id, name, name_norm FROM tags WHERE user_id = ? AND name_norm = ?`,
    ),
    listTagsByUser: db.prepare(
      `SELECT t.id AS id, t.name AS name, COUNT(nt.note_id) AS count
       FROM tags t LEFT JOIN note_tags nt ON nt.tag_id = t.id
       WHERE t.user_id = ?
       GROUP BY t.id, t.name
       ORDER BY t.name COLLATE NOCASE ASC`,
    ),
    deleteTag: db.prepare(`DELETE FROM tags WHERE id = ? AND user_id = ?`),

    // ---- note_tags ----
    linkNoteTag: db.prepare(`INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?, ?)`),
    unlinkNoteTagsByNote: db.prepare(`DELETE FROM note_tags WHERE note_id = ?`),
    getTagsForNote: db.prepare(
      `SELECT t.name AS name FROM tags t
       JOIN note_tags nt ON nt.tag_id = t.id
       WHERE nt.note_id = ?
       ORDER BY t.name COLLATE NOCASE ASC`,
    ),
  };
}

export type Statements = ReturnType<typeof prepareStatements>;

/**
 * Значение, допустимое к биндингу в SQLite.
 * (В `node:sqlite` тип `SQLInputValue` не экспортирован — объявляем совместимый здесь.)
 */
export type SqlValue = null | number | bigint | string | Uint8Array;

/** Выполняет anonymous-statement и возвращает `lastInsertRowid` как number. */
export function runInsert(stmt: StatementSync, ...params: SqlValue[]): number {
  const result = stmt.run(...params);
  return Number(result.lastInsertRowid);
}
