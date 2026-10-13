-- 001_init.sql — начальная схема сервиса заметок (SQLite).
-- Источник истины: PLAN.md §3.1. ANSI-совместимый SQL (drop-in замена на PostgreSQL позже, риск R1).
--
-- Соглашения:
--   * время — ISO-8601 UTC в TEXT (например 2026-10-13T19:20:31.123Z);
--   * PRAGMA foreign_keys=ON выставляется на каждом соединении в db/client.ts
--     (PRAGMA внутри транзакции — no-op, поэтому здесь не дублируется);
--   * IF NOT EXISTS делает файл переприменяемым (поверх учёта в schema_migrations);
--   * каждый шаг выполняется runner'ом в транзакции — атомарно.

CREATE TABLE IF NOT EXISTS users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  email         TEXT NOT NULL COLLATE NOCASE,       -- хранится в lowercase
  email_norm    TEXT NOT NULL UNIQUE,               -- lower(email) — уникальность без учёта регистра
  password_hash TEXT NOT NULL,                      -- bcrypt
  created_at    TEXT NOT NULL                       -- ISO-8601 UTC
);

CREATE TABLE IF NOT EXISTS sessions (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  token_hash TEXT NOT NULL UNIQUE,                  -- SHA-256(raw token); raw — только в cookie
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  csrf_token TEXT NOT NULL,                         -- random, для double-submit
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL                          -- default +7 суток, скользящее продление
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

CREATE TABLE IF NOT EXISTS notes (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title         TEXT,                               -- опц., ≤ 200
  body_markdown TEXT NOT NULL,                      -- raw markdown, ≤ 100 000
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notes_user_updated ON notes(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS tags (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,                         -- исходное написание
  name_norm  TEXT NOT NULL,                         -- lower() — для регистронезависимой уникальности
  UNIQUE (user_id, name_norm)
);

CREATE TABLE IF NOT EXISTS note_tags (
  note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  tag_id  INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
  PRIMARY KEY (note_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_note_tags_tag ON note_tags(tag_id);
