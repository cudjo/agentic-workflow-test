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

---

## T-03 — Аутентификация: register/login/logout/me, сессии, CSRF, rate-limit — tasker-backend

**Дата:** 2026-10-13
**Стек-скилл:** `typescript-node`
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)
**Контекст:** задача была частично реализована прерванной сессией (не закоммичена). Реализация
осмотрена, дополнена, покрыта тестами и проверена end-to-end; рабочий код не переписывался.

### Что сделано

- **Осмотрена и подтверждена частичная реализация** (из прошлой сессии): `routes/auth.ts`,
  `middleware/auth.ts` (`attachSession`/`requireAuth`), `middleware/csrf.ts` (`csrfGuard`),
  `middleware/rateLimit.ts` (лимитер `ip+email`, окно 15 мин / 5 неудач), `lib/password.ts`
  (bcryptjs cost 10 + `DUMMY_PASSWORD_HASH` для выравнивания времени), `lib/sessions.ts`
  (opaque `randomBytes(32).base64url`, SHA-256 в БД, cookie-утилиты, `touchSession`),
  `lib/validation.ts` (email-формат, пароль ≥ 8, `field` в ошибке). Соответствие PLAN §4/§3.2 —
  полное; переписывать было нечего.
- **Исправлен найденный дефект в `server/src/app.ts`**: `setErrorHandler`/`setNotFoundHandler`
  регистрировались ПОСЛЕ `app.register(authRoutes)`. Fastify инкапсулирует обработчики — дочерний
  контекст роутов не наследовал кастомный обработчик, и ошибки из `routes/auth.ts` и из хуков
  (`requireAuth` → 401, `csrfGuard` → 403, `tooManyRequests` → 429, `assertValidCredentials` → 422)
  уходили в дефолтный формат Fastify `{statusCode,error,message}`, ломая контракт
  `{error:{code,message,field?}}` (PLAN §3.2). Обработчики перенесены до регистрации плагинов —
  контракт восстановлен.
- **Дописаны тесты** `server/tests/auth.test.ts` (30 тестов, vitest, `app.inject`): свой tmp-файл БД
  на каждый тест (`mkdtempSync` + удаление каталога в `afterEach`), cookie-помощники, проверки
  атрибутов `Set-Cookie`, состояния БД и ответов.
- Бизнес-логика auth **не менялась** — только порядок регистрации обработчиков в `app.ts`.

### Покрытие приёмки T-03 (тесты + live-проверка)

| Критерий | Проверка |
|---|---|
| register → 201 + cookie; me → `{user:{id,email}}`; logout → 204; повторный me → 401 | 4 теста + live |
| дубликат email в разном регистре → 409 `field=email`; слабый пароль/невалидный email → 422 `field` | 6 тестов + live |
| login неверный → 401 обобщённо; 6-я неудача → 429 + `Retry-After` | 6 тестов + live |
| state-changing без `X-CSRF-Token` → 403; с корректным → проходит | 7 тестов + live |
| истёкшая/удалённая сессия → 401 | 4 теста |

Дополнительно: raw-токен не хранится в БД (только SHA-256), `session` — HttpOnly, `XSRF-TOKEN` —
читаемый, скользящее продление сессии, сброс счётчика лимита после успешного входа, отсутствие
секретов в ответах.

### Как проверить

```powershell
cd server
npm install
npm test          # vitest (все файлы)
npm run typecheck # tsc --noEmit
npm start         # :3000 (DATABASE_PATH по умолчанию server/data/app.db)
```

### Результаты проверок (13.10.2026, Node v26, Windows)

- `npm test`: **Test Files 3 passed (3) · Tests 51 passed (51)** = 21 существующих (T-01/T-02) + 30 новых.
- `npm run typecheck`: без ошибок.
- **Реальный прогон** (`npm start`, порт 3000, `curl.exe`, cookie-jar в tmp-каталоге) — все ожидаемые коды:
  1. `POST /api/auth/register` → `201`, тело `{"user":{"id":1,"email":"e2e.user@example.com"}}`,
     `Set-Cookie: session=…; Max-Age=604800; HttpOnly; SameSite=Lax` и
     `Set-Cookie: XSRF-TOKEN=…; Max-Age=604800; SameSite=Lax` (без HttpOnly);
  2. `GET /api/auth/me` (cookie) → `200 {"user":{"id":1,"email":"e2e.user@example.com"}}`;
  3. `POST /api/auth/login` (неверный пароль) → `401 {"error":{"code":"UNAUTHORIZED","message":"Неверные учётные данные"}}`;
  4. `POST /api/auth/logout` без `X-CSRF-Token` → `403 field=x-csrf-token`; сессия сохраняется (`me` → `200`);
  5. `POST /api/auth/logout` с корректным `X-CSRF-Token` → `204` + очищенные cookie (`Max-Age=0`); `me` → `401`;
  6. повторная регистрация того же email в другом регистре → `409 field=email`;
  7. 6 неудачных входов (тот же ip+email): попытки 1–5 → `401`, 6-я → `429` + `Retry-After: 900`.
- **Логи (NFR-9/A9):** только `method/url/statusCode/responseTime` и коды ошибок; тел запросов, cookie,
  паролей и токенов нет (проверено поиском по логу реального прогона).

### Артефакты

`server/src/routes/auth.ts`, `server/src/middleware/auth.ts`, `server/src/middleware/csrf.ts`,
`server/src/middleware/rateLimit.ts`, `server/src/lib/password.ts`, `server/src/lib/sessions.ts`,
`server/src/lib/validation.ts`, `server/src/app.ts` (порядок обработчиков), `server/tests/auth.test.ts`,
`server/package.json` (+`package-lock.json`, `bcryptjs`)

**Коммит:** `feat(T-03): аутентификация (register/login/logout/me, сессии, CSRF, rate-limit)`
(хеш — `git log --oneline -1`; задача коммитится одним коммитом)

### Заметки для следующих задач

- **T-04+**: в защищённых роутах использовать `preHandler: requireAuth` — заполняет `request.user = {id,email}`;
  ownership-фильтр по `request.user.id`. В `app.ts` показан рабочий порядок: обработчики ошибок/404 —
  ДО `register(роут-плагины)`, иначе кастомный формат ошибок не наследуется (инкапсуляция Fastify).
- **State-changing роуты** (`POST/PATCH/DELETE`) автоматически проходят через `csrfGuard` при наличии
  сессии — фронтенд (T-06) обязан слать `X-CSRF-Token` из cookie `XSRF-TOKEN`. `POST /api/auth/logout`
  уже защищён CSRF.
- **Rate-limit** in-memory и per-app (перезапуск сбрасывает) — ограничение для однопроцессного деплоя
  (PLAN R4, документируется в T-12).
- **Валидация тела** реализована в `lib/validation.ts` (не JSON-schema): даёт стабильный `422` с `field`,
  соответствующий контракту PLAN §3.2.
