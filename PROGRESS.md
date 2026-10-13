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

---

## T-02 — Каркас бэкенда (Fastify + конфиг + health + ошибки) — tasker-backend

**Дата:** 2026-10-13
**Стек-скилл:** `typescript-node`
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **`server/src/config.ts`** — конфиг из env (PLAN §2, §4.7): `PORT` (дефолт 3000), `HOST` (127.0.0.1),
  `DATABASE_PATH` (дефолт `server/data/app.db` из `db/client.ts`), `SESSION_SECRET`, `COOKIE_SECURE`
  (дефолт `false` в dev, `true` в проде), `CORS_ORIGIN` (дефолт `http://localhost:5173`), `LOG_LEVEL`.
  Валидация порта/булевых флагов; секрет `SESSION_SECRET` **не** имеет значения в коде — в проде
  обязателен (иначе `MissingSecretError`, NFR-8), в dev/test генерируется эфемерный.
- **`server/src/lib/errors.ts`** — единый контракт ошибок `{error:{code,message,field?}}` (PLAN §3.2):
  класс `AppError(statusCode, code, message, {field?})`, `errorBody()`, `toHttpError()` (маппинг
  неизвестных исключений; для 5xx — обобщённое `INTERNAL` без деталей/stack, NFR-9).
- **`server/src/routes/health.ts`** — `GET /health → 200 {ok:true}` (без авторизации).
- **`server/src/app.ts`** — `buildApp()`: Fastify-инстанс, декораторы `config`/`db`/`stmts`
  (`openDatabase()` + `prepareStatements()` из T-01, закрытие соединения в `onClose`),
  `@fastify/cors` (`origin=CORS_ORIGIN`, `credentials:true`, `allowedHeaders:[Content-Type,X-CSRF-Token]`),
  `setNotFoundHandler` → 404 JSON, `setErrorHandler` → ответ в каноническом формате + серверный лог.
  Логгер pino с `redact` (`REDACT_PATHS`: `password*`/`token`/`csrf*`/`cookie`/`authorization`/`set-cookie`,
  censor `[redacted]`). `buildApp` не вызывает `listen`. При старте идемпотентно применяет миграции
  (`migrateUp`, опция `autoMigrate`, дефолт `true`) — сервер поднимается на чистой БД.
- **`server/src/index.ts`** — entrypoint: `loadConfig()` → `buildApp()` → `listen()` + graceful shutdown
  по SIGINT/SIGTERM. `buildApp` импортирует `db/migrate.ts` (T-01) для автоприменения схемы.
- **`server/package.json`** — зависимости `fastify ^5.6`, `@fastify/cors ^11.1`; скрипты `dev`
  (`tsx watch src/index.ts`), `start`.
- **Тесты:** `server/tests/app.test.ts` (12 тестов) — конфиг (дефолты/env/обязательный секрет в проде),
  `/health`, CORS (простой + preflight с `X-CSRF-Token`), 404 JSON, `AppError` → статус/код/field,
  500 без stack/деталей, редактирование лога, `errorBody`.

### Как проверить

```powershell
cd server
npm install
npm run typecheck        # tsc --noEmit
npm test                 # vitest
npm start                # :3000 (или npm run dev — watch)
# в другом терминале:
curl.exe -i http://127.0.0.1:3000/health
curl.exe -i http://127.0.0.1:3000/nope
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm run typecheck`: без ошибок (exit 0).
- `npm test`: **Test Files 2 passed (2) · Tests 21 passed (21)** (12 новых T-02 + 9 из T-01).
- Реальный запуск `npm start` (tsx, порт 3000) + `curl.exe`:
  - `GET /health` → `200 {"ok":true}`;
  - `GET /health` с `Origin: http://localhost:5173` → `Access-Control-Allow-Origin: http://localhost:5173`,
    `Access-Control-Allow-Credentials: true`;
  - preflight `OPTIONS /health` → `204` с `Access-Control-Allow-Headers: Content-Type, X-CSRF-Token`;
  - `GET /nope` → `404 {"error":{"code":"NOT_FOUND","message":"Маршрут GET /nope не найден"}}`.
- Лог сервера (pino) проверен: только `method/url/statusCode/responseTime`, без cookie, паролей,
  токенов и тел запросов (NFR-9/A9); 500-й путь отдаёт `INTERNAL` без stack, полный `err` — только в лог.

### Артефакты

`server/src/config.ts`, `server/src/lib/errors.ts`, `server/src/routes/health.ts`, `server/src/app.ts`,
`server/src/index.ts`, `server/tests/app.test.ts`, обновлён `server/package.json` (+`package-lock.json`)

**Коммит:** `6d38555` — `feat(T-02): каркас Fastify (config, /health, CORS, единый формат ошибок, логгер без секретов)`

### Заметки для следующих задач

- **T-03+**: `app.decorate('db')` / `app.decorate('stmts')` / `app.decorate('config')` доступны в роутах;
  ошибки бросать через `AppError(422|401|404|409|429, code, message, {field})` — формат ответа
  централизован в `app.ts`. Cookie-флаги — из `app.config` (`cookieSecure`, `sessionSecret`).
- CSRF-заголовок уже разрешён в CORS (`X-CSRF-Token`); при добавлении cookie-ответов
  `Set-Cookie` автоматически редактируется логгером.
- Тесты с `:memory:`-БД: `buildApp` сам применяет миграции; для изоляции передавайте свой `db`.
