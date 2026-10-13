# PROGRESS — журнал задач (append-only)

Формат записи: задача → что сделано → как проверить → результат тестов → коммит.
Статус задач в `TASKS.json` Tasker'ы не меняют — его ставят QA/Guardian по зелёным гейтам.

---

## T-01 — Схема БД и runner миграций (SQLite) — tasker-dba

**Дата:** 2026-10-13
**Стек-скилл:** `postgres` (загружен ради дисциплины реляционного моделирования: нормализация,
ограничения, индексы, транзакции, FK-каскады; реализация — SQLite через `node:sqlite`, SQL ANSI-совместим
для будущей замены на PostgreSQL, PLAN R1)
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **Схема:** `server/src/db/migrations/001_init.sql` — ровно по PLAN §3.1: `users`, `sessions`, `notes`,
  `tags`, `note_tags` + индексы `idx_sessions_user`, `idx_notes_user_updated(user_id, updated_at DESC)`,
  `idx_note_tags_tag(tag_id)` + FK-каскады (`users → sessions/notes/tags` ON DELETE CASCADE,
  `notes/tags → note_tags` ON DELETE CASCADE). Время — ISO-8601 UTC в `TEXT`.
  `email TEXT COLLATE NOCASE` + `email_norm TEXT UNIQUE`; `tags UNIQUE(user_id, name_norm)`.
  SQL идемпотентен (`IF NOT EXISTS`).
- **Обратимость:** `server/src/db/migrations/001_init.down.sql` — откат в обратном порядке зависимостей.
- **Соединение:** `server/src/db/client.ts` — `node:sqlite` `DatabaseSync`, `PRAGMA foreign_keys=ON`,
  `busy_timeout`, WAL (файловая БД), дефолтный путь `server/data/app.db` (`DATABASE_PATH`), `nowIso()`,
  `transaction(db, fn)` (BEGIN/COMMIT/ROLLBACK), `prepareStatements(db)` — подготовленные statements
  для users/sessions/notes/tags/note_tags, помощник `runInsert()`.
- **Runner:** `server/src/db/migrate.ts` — учёт в таблице `schema_migrations(id, name, applied_at)`,
  применение `migrations/*.sql` по порядку имён, каждая миграция в транзакции (DDL + запись версии атомарно),
  идемпотентность, `--down [--steps N]`, `--status`, `--db <path>`.
- **Пакет `server/`:** `package.json` (скрипты `migrate`, `migrate:down`, `migrate:status`, `typecheck`,
  `test`, `test:watch`; devDeps: typescript, vitest, tsx, @types/node), `tsconfig.json` (NodeNext, strict),
  `vitest.config.ts`.
- **Тесты:** `server/tests/db.test.ts` (9 тестов).

### Как проверить

```powershell
cd server
npm install
npm run migrate          # создаёт server/data/app.db
npm run migrate          # повторно: «схема актуальна» — идемпотентно
npm run migrate:status
npm run migrate:down     # откат (обратимость)
npm run migrate          # повторное применение
npm test                 # vitest
npm run typecheck        # tsc --noEmit
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm run migrate` (пустая БД): `применено 1 — 001_init.sql`; создан `server/data/app.db` (65536 B).
- `npm run migrate` (повтор): `схема актуальна, применять нечего` — без ошибок и дублей.
- Инспекция файла БД: tables `note_tags, notes, schema_migrations, sessions, tags, users`;
  indexes `idx_note_tags_tag, idx_notes_user_updated, idx_sessions_user`;
  `PRAGMA foreign_keys = 1`; `journal_mode = wal`;
  DDL индекса: `CREATE INDEX idx_notes_user_updated ON notes(user_id, updated_at DESC)`.
- `npm run migrate:down` → таблицы схемы удалены, `schema_migrations` пуста; `npm run migrate` возвращает
  схему — обратимость подтверждена end-to-end.
- `npm test`: **Test Files 1 passed (1) · Tests 9 passed (9)** (idempotency, insert/read, каскады
  user→notes/sessions/tags и note→note_tags, регистронезависимая уникальность email/тегов,
  использование `idx_notes_user_updated` через EXPLAIN QUERY PLAN, откат транзакции, up→down→up).
- `npm run typecheck`: без ошибок.
- `init.ps1` (корень): exit code 0, шаг миграций выполняется, `web/` корректно пропускается (T-02/T-06).

### Артефакты

`server/package.json`, `server/package-lock.json`, `server/tsconfig.json`, `server/vitest.config.ts`,
`server/src/db/client.ts`, `server/src/db/migrate.ts`, `server/src/db/migrations/001_init.sql`,
`server/src/db/migrations/001_init.down.sql`, `server/tests/db.test.ts`

### Заметки для следующих задач

- `T-02`: `DATABASE_PATH` из env читается в `resolveDatabasePath()`; `openDatabase()`/`prepareStatements()`/
  `transaction()` — точки подключения. `PRAGMA foreign_keys=ON` уже включён на соединении.
- `T-05`: `listTagsByUser` уже отдаёт `{name, count}`; `linkNoteTag` — `INSERT OR IGNORE`;
  осиротевшие теги после удаления заметки не чистятся (по PLAN — зона T-05).
- Миграции только добавлять новыми файлами `NNN_*.sql` (+ парный `NNN_*.down.sql`) — `001_init.sql` не править.
