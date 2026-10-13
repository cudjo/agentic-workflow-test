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

---

## T-04 — CRUD заметок с ownership-проверкой — tasker-backend

**Дата:** 2026-10-13
**Стек-скилл:** `typescript-node`
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **`server/src/lib/notes.ts`** — доменные правила заметок (без HTTP):
  `Note`/`NoteRow` (контракт PLAN §3.2), `toNote()`, лимиты `MAX_TITLE_LENGTH=200` /
  `MAX_BODY_LENGTH=100000`, `EMPTY_NOTE_MESSAGE`, `NOTE_NOT_FOUND_MESSAGE`, `noteNotFound()`,
  `parseNoteInput()` (POST), `parseNotePatch()` (PATCH, только переданные поля),
  `parseTags()` (тримминг, отбрасывание пустых, дедуп без учёта регистра с сохранением первого
  написания — Q-T2), `assertNoteNotEmpty()` (AC-17/E1).
  Семантика `title`: `undefined`/`null`/пробельная строка → `null` («заголовка нет»);
  отсутствие текста → `''` (колонка `body_markdown NOT NULL`).
- **`server/src/routes/notes.ts`** — HTTP-слой (`preHandler: requireAuth` на всех роутах):
  `GET /api/notes` → `200 {items, total}` (порядок `updated_at DESC`, AC-13/Q-S3),
  `POST /api/notes` → `201 Note`, `GET /api/notes/:id` → `200 Note`/`404`,
  `PATCH /api/notes/:id` (частично) → `200 Note`, `DELETE /api/notes/:id` → `204`.
  **Ownership:** каждый доступ к заметке идёт через `getNoteById`/`deleteNote` с
  `WHERE user_id = :uid`; чужой и несуществующий id неразличимы (404 `NOT_FOUND`,
  сообщение «Заметка не найдена», Q-A7/AC-11..14). Нечисловой/неположительный `:id` → тоже 404.
  **Транзакции (NFR-26):** создание/обновление (вместе со связями тегов) и удаление — в `transaction()`.
  **Теги (T-04 база):** `tags[]` принимаются, нормализуются и сохраняются в `note_tags`
  (переиспользование тега пользователя по `name_norm`), в ответе — массив строк исходного написания.
  Лимиты (≤20 шт., ≤50 символов), `GET /api/tags`, поиск/фильтр и чистка осиротевших тегов — **T-05**.
- **`server/src/app.ts`** — `notesRoutes` зарегистрирован после `authRoutes` (порядок обработчиков
  ошибок/404 не менялся — кастомный формат наследуется, см. грабли T-03).
- **Тесты:** `server/tests/notes.test.ts` (30 тестов, `app.inject`, tmp-файл БД на каждый тест).

### Решения по неоднозначностям (зафиксировано для QA/T-05)

| Вопрос | Решение |
|---|---|
| `tags` в T-04 | **Хранятся уже сейчас** (нормализация + `note_tags`), т.к. контракт `Note.tags` обязателен;
  лимиты/`/api/tags`/поиск — T-05. Осиротевшие теги после снятия/удаления не чистятся (зона T-05). |
| PATCH с пустым телом | `422 VALIDATION_ERROR` «Укажите хотя бы одно поле для обновления» (явная ошибка вместо
  молчаливого no-op). `tags: []` — валидное поле (очистка тегов), не пустое тело. |
| PATCH, делающий заметку пустой | `422` (`title` → `null` + текст пустой) — то же правило, что и при создании (AC-17/E1). |
| `updatedAt` при PATCH только тегов | Обновляется (тег — часть заметки), заметка поднимается наверх списка. |
| Ответ списка | `{items, total}` по PLAN §3.2 (`total` = число своих заметок). |
| Ошибка не найденной заметки | Одно сообщение и код для чужой/несуществующей/битой `:id` (без раскрытия, Q-A7). |

### Как проверить

```powershell
cd server
npm test          # vitest (все файлы)
npm run typecheck # tsc --noEmit
npm start         # :3000
# реальный прогон: register → create → list → patch → delete → me (curl, cookie-jar + X-CSRF-Token)
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm test`: **Test Files 4 passed (4) · Tests 81 passed (81)** = 51 существующих (T-01..T-03) + 30 новых T-04.
- `npm run typecheck`: без ошибок (exit 0).
- **Реальный прогон** (`npm start`, `NODE_ENV=production`, порт 3111, `curl.exe`, cookie-jar, два пользователя):
  1. `POST /api/auth/register` alice → `201`; `GET /api/auth/me` → `200`;
  2. `POST /api/notes` `{title, bodyMarkdown, tags:[" Work ","work","Home"]}` + `X-CSRF-Token` →
     `201 {"id":1,...,"tags":["Home","Work"],...}` (дедуп `Work`/`work` — сохранилось первое написание);
  3. `POST /api/notes` без `X-CSRF-Token` → `403 FORBIDDEN field=x-csrf-token`;
  4. пустая заметка `{"title":"   "}` → `422 VALIDATION_ERROR` с сообщением;
  5. `GET /api/notes` → `200 {items:[note], total:1}`;
  6. `PATCH /api/notes/1 {title, tags:["home"]}` → `200`, `updatedAt` вырос, `tags:["Home"]`;
  7. bob: `GET`/`PATCH`/`DELETE /api/notes/1` → все `404 NOT_FOUND`; список bob `{items:[],total:0}`;
     заметка alice после атак не изменилась (`200`, тот же `updatedAt`);
  8. **рестарт сервера** → `GET /api/notes` alice → `200`, `total:2` (обе заметки, включая PATCH-правку) — NFR-25;
  9. `DELETE /api/notes/1` → `204` без тела, затем `GET` → `404`;
  10. `POST /api/auth/logout` → `204`, `GET /api/auth/me` → `401`;
  11. юникод round-trip: заметка «Привет мир» с тегами `Робота`/`работа` → ответ
      `{"title":"Привет мир","bodyMarkdown":"**жирный** текст","tags":["Home","Работа"]}` — данные целы,
      дедуп регистронезависим с сохранением первого написания (Q-T2);
  12. **логи:** паролей, cookie, CSRF/сессионных токенов и тел запросов нет (NFR-9/A9).
- Дефектов в процессе не найдено; правок вне T-04 (кроме регистрации роутера) нет.

### Артефакты

`server/src/lib/notes.ts`, `server/src/routes/notes.ts`, `server/tests/notes.test.ts`,
`server/src/app.ts` (+2 строки: импорт и `register(notesRoutes)`)

**Коммит:** `feat(T-04): CRUD заметок с ownership-проверкой (404 на чужой id, транзакции, теги базово)`
(хеш — `git log --oneline -1`)

### Заметки для следующих задач

- **T-05:** statements уже готовы: `getTagByUserAndNorm` / `insertTag` / `linkNoteTag` /
  `unlinkNoteTagsByNote` / `getTagsForNote` / `listTagsByUser`; в `routes/notes.ts` —
  готовый `replaceNoteTags(app, userId, noteId, names)` (замена набора в транзакции) и
  `parseTags()` в `lib/notes.ts` — лимиты (≤20/≤50) и `GET /api/tags` добавляются туда/в новый
  `routes/tags.ts`. `name_norm` считается в JS (`toLowerCase()`), т.к. SQLite `lower()` не знает
  кириллицу. Поиск (`?q=&tag=`) — `GET /api/notes` в этом же файле, контракт `{items, total}` сохранён.
- **T-08/T-09:** PATCH возвращает полный `Note` (фронт может обновлять состояние без доп. GET);
  `tags: []` — валидный способ очистить теги; пустой PATCH → `422` (не отправлять пустое тело).
- Типизация `node:sqlite`: `stmt.all()` возвращает `Record<string, SQLOutputValue>[]`, поэтому
  приведение к строковым типам требует `as unknown as T[]` (иначе `tsc` падает) — см. `noteTags()`,
  `listNotesByUser`.
- Предупреждение по окружению: `curl.exe -o $null` в PowerShell 5.1 создаёт файл с именем `--max-time`
  (пустой аргумент); в скриптах использовать `-o NUL`.

---

## T-05 — Теги (many-to-many) + серверный поиск/фильтр — tasker-backend

**Дата:** 2026-10-13
**Стек-скилл:** `typescript-node`
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **`server/src/lib/notes.ts`** — лимиты тегов Q-T3 в `parseTags()`: константы
  `MAX_TAGS_PER_NOTE = 20`, `MAX_TAG_LENGTH = 50`. Тег длиннее 50 → `422 VALIDATION_ERROR
  field=tags`; после тримминга/дедупа более 20 уникальных тегов → `422 field=tags`. Пустой/
  пробельный тег по-прежнему отбрасывается (AC-33/36/T1), дубликат в другом регистре схлопывается
  с сохранением первого написания (Q-T2/AC-37). Лимит количества считается по результату
  дедупликации (тому, что реально сохранится). Спецсимволы/юникод в теле тега допустимы (T4).
- **`server/src/lib/search.ts`** (новый, PLAN §2) — поиск/фильтр (`q`/`tag`):
  `normalizeForSearch` (Unicode `toLowerCase`), `escapeLikePattern` (экранирование `\`, `%`, `_` —
  литералы, S1), `toLikePattern`, `parseNotesFilter` (пустые `q`/`tag` → нет фильтра, S4) и
  `registerSearchFunctions` — регистрирует на соединении SQL-функцию **`search_norm`** из JS.
- **`server/src/db/client.ts`** — `prepareStatements()` регистрирует `search_norm`; новый statement
  `listNotesFiltered` (один подготовленный запрос под все комбинации через `? IS NULL`): поиск
  `search_norm(COALESCE(title,'')) LIKE ? ESCAPE '\' OR search_norm(body_markdown) LIKE ? ESCAPE '\'`
  + фильтр тега через `EXISTS` с `t.user_id = notes.user_id` (AC-44/S7), комбинация «И» (AC-41),
  порядок `updated_at DESC, id DESC` (Q-S3). `listTagsByUser` дополнен `HAVING COUNT(nt.note_id) > 0`
  (без заметок не возвращается). Новый statement `deleteOrphanTagsForUser` (T6).
- **`server/src/routes/tags.ts`** (новый) — `GET /api/tags` (`preHandler: requireAuth`) →
  `200 {items:[{name,count}]}`, только теги текущего пользователя (`WHERE t.user_id = ?`, Q-T4/AC-44).
- **`server/src/routes/notes.ts`** — `GET /api/notes` принимает `?q=&tag=` через `parseNotesFilter` и
  `listNotesFiltered`; `replaceNoteTags()` и `DELETE` вызывают `deleteOrphanTagsForUser()` в той же
  транзакции — теги без заметок удаляются, битых ссылок `note_tags` не остаётся (T6).
- **`server/src/app.ts`** — зарегистрирован `tagsRoutes` (после `notesRoutes`; порядок обработчиков
  ошибок/404 не менялся).
- **Тесты:** `server/tests/tags.test.ts` (29 тестов).

### Как реализован регистронезависимый поиск с кириллицей

SQLite-функции `LOWER()`/`COLLATE NOCASE` работают **только с ASCII** — проверено: заметка с текстом
`ПРИВЕТ` не находится запросом `lower(body) LIKE lower('%ПРИВЕТ%')`. Поэтому при `prepareStatements()`
на соединении регистрируется JS-функция `search_norm` (`DatabaseSync.function`, `deterministic`),
внутри — `String(value).toLowerCase()` (Unicode-aware). SQL сравнивает **нормализованную копию**
колонки с **нормализованным в JS** паттерном:

```sql
search_norm(COALESCE(title,'')) LIKE ? ESCAPE '\' OR search_norm(body_markdown) LIKE ? ESCAPE '\'
-- ? = '%' || escapeLikePattern(q.toLowerCase()) || '%'
```

Это тот же приём, что в T-04 для `tags.name_norm`/`users.email_norm` (нормализация регистра в JS):
без миграции и бэкфилла, работает и для уже существующих строк, и для кириллицы, при этом спецсимволы
LIKE остаются литералами. Для PostgreSQL замена прозрачна: там `lower()` юникод-корректен, поэтому
`search_norm(...)` меняется на `lower(...)` (SQL ANSI-совместим, риск R1).

### Принятые решения по неоднозначностям

| Вопрос | Решение |
|---|---|
| Лимит ≤ 20 тегов | Считается по количеству **уникальных** тегов после тримминга/дедупа (то, что сохранится). |
| Длина тега ≤ 50 | В символах JS (`.length`); проверяется до дедупликации. |
| Пустой `q`/`tag` | Отсутствие фильтра (S4); непереданный, `null` и `''` эквивалентны; `tag` триммится. |
| Спецсимволы поиска | `%`, `_`, `\` экранируются и трактуются как литералы (S1); `*`, `#` и markdown-синтаксис — обычный текст (S3). |
| Фильтр по тегу | Сопоставление по `name_norm` (регистронезависимо), в пределах `t.user_id = notes.user_id`. |

### Как проверить

```powershell
cd server
npm test          # vitest (все файлы)
npm run typecheck # tsc --noEmit
npm start         # :3000
# реальный прогон: register → POST/PATCH с тегами → лимиты → q/tag/q+tag → /api/tags →
# изоляция второго пользователя → DELETE (чистка orphan-тегов) — curl, cookie-jar + X-CSRF-Token
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm test`: **Test Files 5 passed (5) · Tests 110 passed (110)** = 81 существующих (T-01..T-04) + 29 новых T-05.
- `npm run typecheck`: без ошибок (exit 0).
- **Реальный прогон** (`npm start`, `NODE_ENV=production`, порт 3211, tmp-БД, `curl.exe`, два пользователя):
  1. `POST /api/auth/register` alice/bob → `201`;
  2. `POST /api/notes {tags:[" Work ","work","Home","Работа","работа","","   "]}`
     → `201 tags:["Home","Work","Работа"]` — тримминг, отбрасывание пустых, регистронезависимый дедуп
     с сохранением первого написания (кириллица в т.ч., Q-T2);
  3. 21 тег → `422 {"field":"tags","message":"К заметке можно добавить не более 20 тегов"}`;
      тег из 51 символа → `422 "Тег не должен превышать 50 символов"`;
  4. `GET /api/tags` alice → `{"items":[{"name":"Home","count":2},{"name":"Work","count":1},{"name":"Работа","count":1}]}`;
  5. `GET /api/notes?q=javascript` → `total:1` (по заголовку/телу, регистронезависимо);
  6. `GET /api/notes?q=ПРИВЕТ` у alice → `total:0` (эта заметка у bob — изоляция AC-44/S7),
     у bob `?q=common` → его заметка;
  7. `?q=%` → только заметки с литералом `%` (`total:2`, wildcard не срабатывает — S1);
  8. `?tag=home` → `total:2`; `?q=100%&tag=work` → `total:1` (пересечение «И» — AC-41); `?q=` → все (S4);
  9. `GET /api/tags` bob → только `shared` (приватность Q-T4);
  10. `DELETE /api/notes/1` → `204`; после — `GET /api/tags` alice → `{"items":[{"name":"Home","count":1}]}`
      (осиротевшие `Work`/`Работа` удалены — T6); `GET /api/tags` без сессии → `401`;
  11. логи: только `method/url/statusCode`, без паролей/cookie/токенов и тел (NFR-9/A9).
- Дефектов в процессе не найдено.

### Артефакты

`server/src/lib/search.ts` (новый), `server/src/routes/tags.ts` (новый),
`server/src/lib/notes.ts`, `server/src/db/client.ts`, `server/src/routes/notes.ts`,
`server/src/app.ts`, `server/tests/tags.test.ts`

**Коммит:** `feat(T-05): теги (лимиты, /api/tags, чистка orphan) + серверный поиск/фильтр q/tag`
(хеш — `git log --oneline -1`)

### Заметки для следующих задач

- **T-08/T-09 (фронт):** `GET /api/tags` отдаёт `{items:[{name,count}]}` — готово для чипов-фильтров и
  `datalist`; серверный поиск — `GET /api/notes?q=&tag=` (debounce на клиенте, Q-S4); `q`/`tag`
  комбинируются по «И»; пустые значения (в т.ч. `q=`) → без фильтра.
- **T-12 (deploy/smoke):** сценарий `e2e-smoke.mjs` может опираться на `/api/notes?q=&tag=` и `/api/tags`.
- Кириллица в поиске работает через JS-функцию `search_norm` (регистрируется в `prepareStatements`);
  если БД открывается внешним соединением — использовать `prepareStatements(db)`/`buildApp`
  (они регистрируют функцию), либо вызвать `registerSearchFunctions(db)` из `lib/search.ts`.
- **PowerShell 5.1 грабли (для QA e2e):** `.ps1` с юникодом читается как ANSI — сохранять с UTF-8 BOM;
  JSON-тела с кириллицей передавать в `curl.exe` через `--data-binary @file` (UTF-8 без BOM), иначе
  native-аргументы кодируются в ANSI; `Del`/`del` — алиас `Remove-Item`, не использовать как имя функции.
