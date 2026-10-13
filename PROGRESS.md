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

---

## T-06 — Фронтенд-фундамент + auth-экраны (login/register) + guard маршрутов — tasker-frontend

**Дата:** 2026-10-13
**Стек-скилл:** `react` (компоненты/хуки/состояние/a11y/тесты)
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **Инициализация `web/` (React 18 + TypeScript + Vite):** `package.json` (скрипты `dev`, `build`
  = `tsc --noEmit && vite build`, `typecheck`, `test`/`test:watch`), `vite.config.ts` (dev 5173,
  `strictPort`, proxy `/api` и `/health` → `http://localhost:3000`; блок `test` для vitest),
  `tsconfig.json` (strict, `moduleResolution: bundler`, `jsx: react-jsx`, `verbatimModuleSyntax`,
  `noUnusedLocals/Parameters`), `index.html` (RU, `#root`), `src/main.tsx`, `src/vite-env.d.ts`.
- **Дизайн-токены и стили — прямой перенос `mockups/styles.css` с сохранением имён (DESIGN §0):**
  - `src/styles/tokens.css` — раздел 1 (все `--c-*`, `--glass-*`, `--sh-*`, `--fs-*`, `--sp-*`, `--r-*`,
    `--container`, `--topbar-h`) + token-override для `@supports not (backdrop-filter)` и
    `prefers-contrast: more`;
  - `src/styles/base.css` — mesh-фон (`body::before`, `meshDrift`), ресеты, `:focus-visible`,
    `.sr-only`, `.skip-link`, утилиты (`.container`, `.stack*`, `.row*`, `.clamp-2/3`, `.page`);
  - `src/styles/glass.css` — примитивы стекла, topbar/brand/userchip/avatar, кнопки, поля, алерты,
    бейджи, теги/чипы, segmented, результаты grid/list, empty, скелетоны, диалог, `.auth*`, `.pw-meter`,
    редактор/`.md`, адаптив (1024/900/640), fallback (`@supports not`), `prefers-contrast`,
    `prefers-reduced-motion`. Проверено: собранный CSS содержит `--glass-bg-hi/…`, `--r-lg`, `--sp-4`,
    `backdrop-filter`, `meshDrift`, `@supports not`, `prefers-reduced-motion` (contract сохранён).
- **`src/api/client.ts` — fetch-обёртка (PLAN §3.3):** `credentials: 'include'`; на state-changing
  (`POST/PATCH/PUT/DELETE`) добавляет `X-CSRF-Token` из читаемой cookie `XSRF-TOKEN`; `401` вне
  auth-эндпоинтов вызывает `notifyUnauthorized()` → редирект на `/login` с сохранением целевого URL;
  ошибки приводятся к `ApiError {status, code, message, field?, retryAfter?}` (единый контракт ошибок
  PLAN §3.2 + `Retry-After`). `authApi`: `me`/`login`/`register`/`logout`.
- **Auth-состояние:** `src/auth/AuthContext.tsx` — восстановление сессии `GET /api/auth/me` при
  монтировании (`loading → authenticated|anonymous`), `login`/`register`/`logout`, глобальный обработчик
  401 (сброс состояния + редирект с `reason: 'expired'`).
- **Router + guard:** `src/App.tsx` (маршруты `/login`, `/register`, защищённый `/notes`, `/` → `/notes`,
  `*` → NotFound), `src/router.tsx` (BrowserRouter + AuthProvider), `src/components/ProtectedRoute.tsx`
  (loading → `role=status`; anonymous → `<Navigate to="/login" state={{from}}>`; после входа возврат на
  сохранённый URL — AC-10).
- **Компоненты:** `Topbar` (brand, `userchip` с email + кнопка «Выйти» → `POST /api/auth/logout` →
  редирект `/login`, поток F), `SkipLink` (первый в tab-порядке), `AppLayout` (skip-link + Topbar + `<main>`),
  `AuthLayout` (брендовая панель `S1/S2` + карточка), `Alert` (role=alert/status), инлайн-иконки.
- **Страницы по DESIGN §2.11:** `pages/Login.tsx` — email/пароль, `novalidate`, клиентская валидация
  (email-формат, пароль непустой), ошибки под полем (`aria-invalid`/`aria-describedby`/`role=alert`),
  обобщённая ошибка «Неверные учётные данные» (AC-5), rate-limit баннер с обратным отсчётом `mm:ss` и
  блокировкой формы (AC-6), баннер «Сессия истекла» (`reason=expired`, AC-9), авто-редирект на запрошенный
  URL/`/notes` (AC-4). `pages/Register.tsx` — email/пароль/повтор, валидация ≥8 и совпадение, индикатор
  силы пароля (3 сегмента + текстовая оценка — не только цветом), дубликат → «Этот email уже зарегистрирован»
  + ошибка поля (AC-2), успех → авто-авторизация и `/notes` (AC-1). `pages/Notes.tsx` — каркас `S3`
  (заголовок + empty-state; полный список — T-08), `pages/NotFound.tsx`.
- **Тесты (vitest + @testing-library/react + user-event):** `src/__tests__/auth.test.tsx` (9 тестов).
- **`init.ps1`/`init.sh` уже рассчитаны на `web/`** (шаг `npm install` + `npm run build`) — структура
  и скрипты совпадают, правок скриптов не требовалось.

### Покрытие приёмки T-06 (тесты + live-проверка)

| Критерий | Проверка |
|---|---|
| Токены/классы совпадают с `mockups/styles.css` (DESIGN §0) | grep собранного CSS: `--glass-bg-hi/…`, `--r-lg`, `--sp-4`, `backdrop-filter`, `meshDrift`, media-условия |
| Регистрация → авто-авторизация → `/notes` (AC-1) | тест «успешная регистрация ведёт на /notes» + live `POST /register → 201`, `me → 200` |
| Дубликат email → «Этот email уже зарегистрирован» (AC-2) | тест + live `POST /register` (другой регистр) → `409 field=email` |
| Вход успех → `/notes` (AC-4) | тест + live |
| Неверные данные → обобщённая ошибка (AC-5) | тест «обобщённая ошибка» + live `401` «Неверные учётные данные» |
| Неавторизованный доступ к `/notes` → `/login`, данные не видны; возврат после входа (AC-10) | 2 теста guard + live `GET /api/auth/me → 401` |
| «Выйти» → инвалидация сессии → `/login` (AC-7/F) | тест (проверяет `X-CSRF-Token` в logout) + live `logout без CSRF → 403`, `с CSRF → 204`, `me → 401` |
| Rate-limit баннер + disabled (AC-6) | тест «429 → баннер + disabled» |

### Как проверить

```powershell
cd web
npm install
npm test          # vitest (9 тестов)
npm run build     # tsc --noEmit && vite build
npm run dev       # :5173, proxy /api -> :3000
# в другом терминале:
cd ..\server; npm start   # :3000
# e2e через Vite-proxy (внимание: системный HTTP_PROXY 127.0.0.1:9989 даёт 502 → нужен --noproxy "*"):
curl.exe --noproxy "*" -i -X POST http://localhost:5173/api/auth/register -H "Content-Type: application/json" `
  --data-binary '{"email":"e2e.t06@example.com","password":"Secret12345"}' -c "$env:TEMP\ck.txt"
curl.exe --noproxy "*" -i http://localhost:5173/api/auth/me -b "$env:TEMP\ck.txt"
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm test`: **Test Files 1 passed (1) · Tests 9 passed (9)** (guard-редирект; возврат на запрошенный URL;
  вход успех; обобщённая ошибка; rate-limit 429 + disabled; регистрация успех; дубликат 409; клиентская
  валидация без запроса; logout с CSRF-заголовком).
- `npm run build`: `tsc --noEmit` без ошибок; `vite build` → `dist/` (`index.html` 0.47 kB, CSS 33.4 kB,
  JS 183 kB).
- **Реальный прогон end-to-end через Vite dev-proxy** (`server npm start` :3000 + `web npm run dev` :5173,
  `curl.exe --noproxy "*"`):
  1. `GET http://localhost:5173/` → `200 text/html`, `<div id="root">`, `<script src="/src/main.tsx">`;
  2. `GET /notes` → `200` (SPA-fallback Vite);
  3. `POST /api/auth/register` → `201 {"user":{"id":1,"email":"e2e.t06@example.com"}}` +
     `Set-Cookie: session=…; Max-Age=604800; HttpOnly; SameSite=Lax` и `XSRF-TOKEN=…` (без HttpOnly);
  4. `GET /api/auth/me` (cookie) → `200 {"user":{…}}`;
  5. `POST /api/auth/logout` без `X-CSRF-Token` → `403` (подтверждает необходимость CSRF-заголовка, который
     шлёт `api/client.ts`); с заголовком → `204` + очищенные cookie;
  6. `GET /api/auth/me` после logout → `401`;
  7. `POST /api/auth/login` (неверный пароль) → `401` «Неверные учётные данные»;
  8. повторная регистрация того же email в другом регистре → `409` «Этот email уже зарегистрирован».
- **UI-проверка:** реальный браузер в песочнице недоступен; рендер и сценарии проверены через
  `@testing-library/react` (jsdom) по ролям/aria + реальный HTTP-обмен через Vite-прокси. Серверные логи
  прогона не содержат паролей, cookie и токенов (NFR-9/A9).
- **Грабли окружения:** системный `HTTP_PROXY=http://127.0.0.1:9989` перехватывает `curl.exe`/`localhost`
  и отдаёт `502` — для локальных проверок использовать `curl.exe --noproxy "*"`.

### Артефакты

`web/package.json`, `web/package-lock.json`, `web/vite.config.ts`, `web/tsconfig.json`, `web/index.html`,
`web/src/vite-env.d.ts`, `web/src/main.tsx`, `web/src/router.tsx`, `web/src/App.tsx`,
`web/src/styles/{tokens,base,glass}.css`, `web/src/api/client.ts`, `web/src/lib/{format,validation}.ts`,
`web/src/auth/AuthContext.tsx`,
`web/src/components/{Topbar,AppLayout,AuthLayout,ProtectedRoute,Alert,SkipLink,icons}.tsx`,
`web/src/pages/{Login,Register,Notes,NotFound}.tsx`, `web/src/setupTests.ts`,
`web/src/__tests__/auth.test.tsx`

**Коммит:** `feat(T-06): фронтенд-фундамент web/ (Vite+React+TS), токены/glass-стили, api/client, router+guard, Topbar, Login/Register`
(хеш — `git log --oneline -1`)

### Заметки для следующих задач

- **T-07/T-08/T-09/T-10:** фундамент готов. Использовать `apiRequest<T>()`/`ApiError` из
  `src/api/client.ts` (сам добавит CSRF и обработает 401); `useAuth()` даёт `user/status/login/register/logout`;
  защищённые страницы добавляются вложенным `<Route>` под `<ProtectedRoute>` + `<AppLayout>` в `src/App.tsx`.
  Стили/утилиты уже перенесены (`.results--grid/--list`, `.note-item*`, `.segmented`, `.search`, `.md`,
  `.editor-*`, `.modal`, `.empty`, `.skeleton`, `.tag`, `.chip`) — классы совпадают с макетом.
- **T-08:** `pages/Notes.tsx` сейчас — каркас (заголовок + empty-state без CTA); заменить на полный `S3`
  (плитки/список, поиск `?q=`, чипы тегов `?tag=`, `localStorage notes.view`, DeleteDialog, скелетоны/ошибки).
- **T-11 (a11y):** базовые aria-паттерны форм/guard/topbar уже есть (`aria-invalid`/`aria-describedby`/
  `role=alert`, `skip-link`, `aria-busy` на submit); кросс-экранный пас — после T-08..T-10.
- **T-12:** `web/dist` — цель прод-раздачи Fastify (SPA-fallback). `npm run build` в `web/` собирает
  статику; в `init.ps1`/`init.sh` шаг сборки выполняется автоматически.
- **Dev-грабли:** Vite `strictPort: true` (5173 занят → падать, а не менять порт); при проверках
  `curl.exe`/браузерных проксях учитывать системный `HTTP_PROXY` (см. выше).

---

## T-07 — Markdown-рендерер с санитизацией (общий для превью и просмотра) — tasker-frontend

**Дата:** 2026-10-13
**Стек-скилл:** `react` (компоненты/состояние/a11y/тесты)
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **`web/src/lib/markdown.ts` (новый)** — единый рендерер `markdown → безопасный HTML`, один на всё
  приложение (превью S4, T-09 — и просмотр S5, T-10; AC-31).
  - Конвейер **`markdown-it` → `DOMPurify`** по allowlist (DESIGN §8, PLAN §4.5, NFR-5):
    `strong, em, code, pre, ul, ol, li, blockquote, h2, h3, h4, a, hr, table, thead, tbody, tr, th, td, p`.
    Экспорт `ALLOWED_TAGS` (контракт) и `renderMarkdown(md: string): string`.
  - `markdown-it` настроен `html: true` (сырой HTML проходит через санитайзер), `linkify: true`,
    `breaks/typographer: false`. DOMPurify: `ALLOWED_TAGS` + `ALLOWED_ATTR` (`href,title,target,rel`),
    `ALLOW_DATA_ATTR/ALLOW_ARIA_ATTR: false`, безопасные схемы URI по умолчанию DOMPurify.
    `script`/`iframe`/`style` (+ их содержимое) и `on*`-обработчики **вырезаются**, `javascript:` в `href`
    блокируется; элемент вне allowlist разворачивается — текст остаётся, элемент не рендерится
    (`<b>текст</b>` → «текст», AC-46).
  - **Сдвиг заголовков +1 с ограничением `h4`:** markdown `#` → `h2`, `##` → `h3`, `###`/`####` → `h4`.
    В статье не появляется второй `h1` (DESIGN §5.4: `h1` — заголовок заметки) и не выходим за allowlist
    (`h2–h4`).
  - **Ссылки:** DOMPurify-хук `afterSanitizeAttributes` вешает `target="_blank"` +
    `rel="noopener noreferrer"` на каждый `<a>` (защита от reverse tabnabbing).
  - Пустой/нестроковый ввод → `''`; битый/незакрытый markdown не роняет рендер (E8/E9).
- **Стили `.md`** — проверены в `web/src/styles/glass.css` (§T-06): уже полностью соответствуют
  DESIGN §2.13/§3.5 — `max-width: 72ch`, `font-size: 16px`, `line-height: 1.7` (`--lh-relaxed`),
  `h2..h4`, `pre` тёмный (`rgb(15 23 42 / .9)` + светлый текст), `code`-плашка, `table` с фоном,
  `blockquote`, `hr`, списки, ссылки. **Правок не потребовалось** — контракт сохранён.
- **Зависимости `web/`:** добавлены `markdown-it ^15.0.2`, `dompurify ^3.4.17` (+ devDep
  `@types/markdown-it`).
- **Тесты:** `web/src/__tests__/markdown.test.ts` (28 тестов).

### Покрытие приёмки T-07 (тесты + e2e)

| Критерий | Проверка |
|---|---|
| AC-45/NFR-5: `<script>`/`on*`/`javascript:`/`iframe`/`style` не исполняется, опасное вырезано | 6 тестов + e2e (script/iframe/style → `""`, `onerror`/`onclick` вырезаны, href `javascript:` не создаётся) |
| AC-46: `<b>текст</b>` как текст → детерминированный рендер по allowlist | 3 теста + e2e (`<b>текст</b>` → `<p>текст</p>`, без `<b>`) |
| E8/E9: битый/незакрытый markdown не ломает | 10 параметризованных кейсов + длинный/юникод-ввод |
| AC-31: один рендерер даёт идентичный HTML для превью и просмотра; тест на совпадение | 2 теста (идентичность + идемпотентность) |
| allowlist совпадает с DESIGN §8 | тест на точный состав `ALLOWED_TAGS` |
| `<a>` → `rel="noopener noreferrer"` + `target="_blank"` | тест + e2e |
| заголовки начинаются с `h2`, `h1` не выводится (DESIGN §5.4) | тест + e2e (`# H1` → `<h2>`) |

### Как проверить

```powershell
cd web
npm install
npm test          # vitest (28 новых T-07 + 9 T-06)
npm run build     # tsc --noEmit && vite build
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm test`: **Test Files 2 passed (2) · Tests 37 passed (37)** = 9 существующих (T-06) + 28 новых T-07.
- `npm run build`: `tsc --noEmit` без ошибок; `vite build` → `dist/` (CSS 33.41 kB, JS 183.14 kB).
  `markdown.ts` пока не импортируется страницами (подключат T-09/T-10) — в текущий бандл не входит,
  но типизируется `tsc` и покрыт тестами.
- **E2E (реальный модуль в DOM, jsdom через `vite-node`, временный скрипт удалён):** все кейсы как
  пользователь:
  - `# H1` → `<h2>H1</h2>`; `**bold**`/`*em*`/`` `code` ``/списки/цитата/таблица — корректно;
  - `<script>window.__pwned=1</script>` → вырезан, `window.__pwned === undefined`;
  - `<img onerror=…>`, `<iframe>`, `<style>` → `""` (вырезаны целиком);
  - `[click](javascript:…)` → ссылка не создаётся; `<a href="javascript:…">` → `href` снят (`null`),
    остаются безопасные `target`/`rel`;
  - `<b>текст</b>` → `<p>текст</p>`;
  - в каждом выводе: `script=0 iframe=0 style=0 onAttrs=0`; ссылки: `target="_blank" rel="noopener noreferrer"`.
- **UI-проверка:** реальный браузер в песочнице недоступен (как в T-06); поведение санитайзера проверено
  в DOM (jsdom) — эквивалент того, что видит пользователь, включая неисполнение опасного кода.

### Артефакты

`web/src/lib/markdown.ts` (новый), `web/src/__tests__/markdown.test.ts` (новый),
`web/package.json` (+`package-lock.json`): `markdown-it`, `dompurify`, `@types/markdown-it`

**Коммит:** `feat(T-07): markdown-рендерер (markdown-it + DOMPurify по allowlist) — единый для превью и просмотра`
(хеш — `git log --oneline -1`)

### Заметки для следующих задач

- **T-09 (превью) / T-10 (просмотр):** импортировать `renderMarkdown` из `src/lib/markdown.ts` и вставлять
  результат одним способом (напр. `<article className="md" dangerouslySetInnerHTML={{__html: renderMarkdown(bodyMarkdown)}} />`).
  Тот же вызов на обоих экранах гарантирует AC-31 (тест на идентичность уже есть). Теги/заголовок заметки —
  только текстовые узлы React (не через `renderMarkdown`), т.к. AC-47/NFR-14.
- **Заголовки:** рендерер сам сдвигает markdown-заголовки к `h2+`, поэтому страница может держать
  единственный `<h1>` (заголовок заметки) без доп. обработки.
- **Стили:** класс `.md` (glass.css) уже покрывает вёрстку markdown — отдельные стили не нужны.
  Блок `.md-raw` — демонстрационный (в продукте не используется).

---

## T-08 — Экран списка заметок: плитки/список, поиск, фильтр, empty-state, удаление — tasker-frontend

**Дата:** 2026-10-13
**Стек-скилл:** `react` (компоненты/состояние/a11y/тесты)
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **`web/src/api/notes.ts` (новый)** — тонкие обёртки над `apiRequest` из `client.ts`
  (CSRF/401 берутся оттуда): `notesApi.list({q, tag})` → `GET /api/notes?q=&tag=` (`{items,total}`),
  `notesApi.remove(id)` → `DELETE /api/notes/:id` (204), `tagsApi.list()` → `GET /api/tags`
  (`{items:[{name,count}]}`). Типы `Note` (`title: string | null`), `TagCount`.
- **`web/src/lib/view.ts` (новый)** — предпочтение вида: `loadView()` / `saveView()`,
  ключ `notes.view ∈ {grid,list}`, дефолт **grid**, повреждённое/отсутствующее значение → grid
  (AC-25/AC-27). Доступ к `localStorage` защищён try/catch (приватный режим не роняет экран).
- **`web/src/lib/note-text.ts` (новый)** — производные тексты: `toPlainText(markdown)` (plain-text
  выжимка **без рендера** — снимает markdown-разметку, ссылки → текст, блоки кода → содержимое) и
  `noteTitle(note)` — `title` либо первая непустая строка текста (E3).
- **`web/src/lib/format.ts`** — добавлены `formatNoteDate(iso)` → «13 окт, 09:20» (DESIGN §2.1/§9) и
  `formatNotesCount(n)` — склонение «N заметка/заметки/заметок» (§2.6).
- **`web/src/components/icons.tsx`** — добавлены инлайн-SVG (все `aria-hidden`/`focusable=false`):
  `SearchIcon, CloseIcon, GridIcon, ListIcon, PlusIcon, PencilIcon, TrashIcon, FileTextIcon, RefreshIcon`.
- **Компоненты (новые):**
  - `NoteItem.tsx` — **один DOM** (`li.note-item`) на плитку и строку (раскладку задаёт контейнер
    `results--grid`/`results--list`, AC-24/AC-26): заголовок `clamp-2` (для пустого — из первой строки
    текста), фрагмент `clamp-3` plain-text, теги как текст (или «Без тегов»), `<time dateTime=…>`,
    действия «Редактировать»/«Удалить» — всегда видимы, с контекстными `aria-label`.
  - `Segmented.tsx` — `role="group"` + `aria-label`, кнопки `aria-pressed`, `ArrowLeft/ArrowRight`
    переносят фокус и выбирают вид, скрытый `role="status"` «Текущий вид: плитки/список» (NFR-16).
  - `SearchBox.tsx` — debounce 300 ms (серверный поиск, NFR-4), sr-only label `for="q"`, `type="search"`,
    `aria-describedby` → регион результатов, кнопка `.search__clear` (только при непустом тексте)
    возвращает фокус в поле; внешний сброс синхронизирует поле.
  - `TagFilter.tsx` — чипы-фильтры из `GET /api/tags` со счётчиками (`chip__count`, `aria-hidden`),
    toggle `aria-pressed`, контейнер `role="group" aria-labelledby`; подпись «Фильтры не применены» /
    «Активен фильтр: {tag}» / «Активен поиск» и «Сбросить».
  - `EmptyState.tsx` — два варианта: **A** «Пока ни одной заметки» + CTA «Создать заметку» (`Link`
    на `/notes/new` — маршрут редактора T-09), **B** «Ничего не найдено» + «Сбросить поиск и фильтры»
    (возвращает фокус в поиск). Ровно один вариант решает страница.
  - `Skeleton.tsx` — `NoteListSkeleton`: 3 плитки-скелетона в `results--grid` (форма будущей раскладки),
    контейнер `aria-hidden` + скрытый `role="status"` «Загрузка заметок…» (спиннеров нет).
  - `DeleteDialog.tsx` — нативный `<dialog>.showModal()` (fallback на `open`-атрибут), `aria-labelledby`/
    `aria-describedby`, фокус на «Отмена», Esc/backdrop = отмена; подтверждение — через `onConfirm`.
- **`web/src/pages/Notes.tsx` (переписан)** — полный `S3`: заголовок «Мои заметки» + «Сортировка: сначала
  обновлённые» + CTA; панель поиска/вида/фильтров; регион результатов `role="status" aria-live="polite"`
  («{N} … — все заметки / по фильтру»); комбинирование q+tag по «И» (сервер); при повторных запросах
  скелетоны **не** показываются (сохраняется предыдущий результат, §4.2.1); empty-state A/B по правилу
  «есть ли активные фильтры»; удаление — оптимистичное (заметка исчезает без перезагрузки, `DELETE` в фоне,
  при ошибке — алерт и перечитка, E17); ошибка загрузки — `.alert--error` с «Повторить» и «Выйти и войти снова».
- **`web/src/setupTests.ts`** — добавлен минимальный polyfill `localStorage` (jsdom под Node 26 не предоставляет
  его без `--localstorage-file`); после каждого теста чистится localStorage. Инфраструктурная правка, кода
  продукта не касается.
- **Тесты:** `web/src/__tests__/notes.test.tsx` (18 тестов, `@testing-library/react`: реальный `App` +
  `AuthProvider` + `MemoryRouter`, мок `fetch` с серверной фильтрацией по `?q=&tag=`).

### Покрытие приёмки T-08 (тесты + e2e)

| Критерий | Проверка |
|---|---|
| Список отображает свои заметки; заголовок/фрагмент/теги/дата | 2 теста + e2e `GET /api/notes` |
| Переключение плитки↔список мгновенно, состав/порядок неизменны (AC-24/26) | тест (сравнение `textContent` всех `li` до/после) + ArrowLeft/Right |
| Вид в `localStorage notes.view`, дефолт grid, восстановление, повреждённое → grid (AC-25/27) | 3 теста |
| Поиск (debounce 300 ms, серверный `?q=`) (AC-39/43) | тест + e2e `?q=борщ` |
| Чип тега фильтрует, toggle `aria-pressed` (`?tag=`) (AC-40/41) | тест + e2e `?tag=работа` |
| q+tag по «И»; «Сбросить» возвращает все (AC-41/43) | 3 теста + e2e (совпадение и пустое пересечение) |
| Empty-state A + CTA (AC-23/E12) / B + «Сбросить» (AC-42) | 2 теста + e2e (пустой список) |
| Удаление: подтверждение без перезагрузки; отмена не меняет; удаление последней → empty A (AC-21/22, E14) | 3 теста + e2e `DELETE` → 204, total 3→2→0 |
| Загрузка — скелетоны; ошибка — alert с «Повторить» (§4.2) | 2 теста |

### Как проверить

```powershell
cd web
npm install
npm test          # vitest: 55 тестов (9 T-06 + 28 T-07 + 18 T-08)
npm run build     # tsc --noEmit && vite build
# e2e-data-path (S3 использует те же эндпоинты):
cd ..\server; $env:PORT='3311'; $env:DATABASE_PATH="$env:TEMP\notes.db"; npm start
# затем — сценарий register → 3 заметки → list/q/tag/q+tag/tags → DELETE (см. журнал T-08)
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm test`: **Test Files 3 passed (3) · Tests 55 passed (55)** = 9 (T-06) + 28 (T-07) + 18 новых T-08.
- `npm run build`: `tsc --noEmit` без ошибок; `vite build` → `dist/` (`index.html` 0.47 kB, CSS 33.41 kB,
  JS 196.16 kB).
- **E2E data-path** (`npm start`, порт 3311, tmp-БД, Node `fetch` с cookie-jar + `X-CSRF-Token`):
  **13/13 PASS** — register 201; 3 заметки; list `total=3` (заметка без `title` → `null`, теги массивом);
  `?q=борщ` → 1; `?tag=работа` → 1; q+tag совпадение → 1, пустое пересечение → 0; `/api/tags` со счётчиками;
  `DELETE` → 204, `total` 3→2→0 (последняя → пустой список).
- **UI-проверка:** реальный браузер в песочнице недоступен (как T-06/T-07) — поведение экрана проверено
  интеграционными тестами, которые рендерят **реальный `App`** с настоящими компонентами/роутером/контекстом
  и мок-`fetch`, отвечающим как сервер; a11y проверяется через роли/имена/aria-атрибуты, вид — по классам
  контейнера.
- **UI-наблюдение:** в DOM два CTA «Создать заметку» (в шапке и в empty-state A) — оба ведут на маршрут
  редактора `/notes/new` (появится в T-09); таргеты проверены в тестах по `data-empty-*`.

### Артефакты

`web/src/api/notes.ts` (новый), `web/src/lib/view.ts` (новый), `web/src/lib/note-text.ts` (новый),
`web/src/lib/format.ts`, `web/src/components/icons.tsx`, `web/src/components/{NoteItem,Segmented,SearchBox,
TagFilter,EmptyState,Skeleton,DeleteDialog}.tsx` (новые), `web/src/pages/Notes.tsx`,
`web/src/setupTests.ts`, `web/src/__tests__/notes.test.tsx` (новый)

**Коммит:** `feat(T-08): экран списка заметок (плитки/список, поиск, теги-фильтры, empty-state, удаление)`
(хеш — `git log --oneline -1`)

### Заметки для следующих задач

- **T-09 (редактор):** маршрут `/notes/new` (CTA из empty-state A и шапки S3) и `/notes/:id/edit` (кнопка
  «Редактировать» в `NoteItem`) уже зашиты ссылками — нужно добавить их в `App.tsx`; `notesApi` расширить
  `create/update`. `TagInput` — `datalist` из `tagsApi.list()`.
- **T-10 (просмотр):** `NoteItem` ссылается на `/notes/:id` (заголовок и «кликабельная» карточка через
  растянутый `::after`); `DeleteDialog` переиспользуется без изменений.
- **T-11 (a11y):** segmented (group/aria-pressed/Arrow), поиск (sr-only label/clear), чипы (group/aria-pressed),
  диалог (native/aria-labelledby/autofocus), регион результатов (`role=status aria-live`) уже реализованы —
  остаётся сквозной пас (фокус-ловушка, контраст, брейкпоинты).
- **T-12:** сборка `web/dist` (JS 196 kB) — цель прод-раздачи; маршруты `/notes/new` и `/notes/:id(/edit)`
  добавятся в T-09/T-10, SPA-fallback обязателен.
- **Dev-грабли:** jsdom под Node 26 не даёт `localStorage` — в `setupTests.ts` добавлен polyfill; если тесты
  будут переноситься в другой раннер с нативным Storage, polyfill безвреден (используется только при отсутствии).

---

## T-09 — Экран редактора: заголовок, теги, markdown, toolbar, live-превью, сохранение — tasker-frontend

**Дата:** 2026-10-13
**Стек-скилл:** `react` (компоненты/хуки/состояние/a11y/тесты)
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **`web/src/lib/editor.ts` (новый)** — чистые функции toolbar (DESIGN §2.7), независимые от DOM:
  `applyPrefix` (построчно, снимает прежний маркер блока `#…`/`- ` / `1. ` / `> ` — повторное нажатие
  **не дублирует**; пустые строки внутри выделения не размечаются; нумерованный список нумеруется с 1),
  `applyWrap` (`**…**`, `*…*`, `` `…` ``, toggle — повторный вызов снимает обёртку), `applyCodeBlock`
  (ограждение ``` до/после), `applyLink` (`[выделение](https://)`), диспетчер `applyToolbarOp`.
  Все возвращают `{value, selectionStart, selectionEnd}`.
- **`web/src/components/MdToolbar.tsx` (новый)** — `role="toolbar"` + `aria-label` + `aria-describedby`
  (sr-only подсказка), 4 группы `role="group"` (Заголовки, Начертание, Списки, Блоки и ссылки),
  `role="separator" aria-orientation="vertical"`, у кнопок `aria-label` + `title` + `aria-keyshortcuts`,
  глифы `aria-hidden`; `data-md-prefix/insert/block/link` — контракт разметки. Вставка учитывает выделение
  textarea; при клике мышью фокус возвращается в textarea, при активации с клавиатуры — остаётся на кнопке
  (флаг захватывается на `mousedown`); выделение применяется в `useLayoutEffect` после перерисовки.
- **`web/src/components/TagInput.tsx` (новый)** — чипы `.tag--removable` с кнопкой `aria-label="Убрать тег «…»"`
  и «призрачным» инпутом внутри `.input`: Enter/запятая добавляют, пустые и дубликаты без учёта регистра
  отбрасываются, лимиты **≤20 тегов** / **≤50 символов** с сообщением («Не больше 20 тегов» /
  «Тег длиннее 50 символов», `aria-invalid`, `role=alert`); подсказки — `datalist`. `addTag()` экспортируется
  и покрыт unit-тестами.
- **`web/src/components/UnsavedDialog.tsx` (новый)** — нативный `<dialog>` «Есть несохранённые изменения»
  (§4.2.8): «Остаться в редакторе» (`autofocus`), «Выйти без сохранения», «Сохранить и выйти»;
  Esc/backdrop = остаться.
- **`web/src/pages/Editor.tsx` (новый)** — `S4` для `/notes/new` и `/notes/:id/edit`:
  - заголовок `.input` (`maxlength=200`, подпись «Заголовок — необязательно», хинт E3);
  - `TagInput` + `datalist` из `GET /api/tags`;
  - textarea `.md-input` (`maxlength=100000`, счётчик «{N} / 100 000», sr-only label «Текст заметки в markdown»);
  - **live-сплит** `.editor-grid` (≥1025px по CSS) с `renderMarkdown` (T-07) в `.md-preview`;
    на ≤1024px CSS показывает `.editor-tabs` (`role=tablist`) и скрывает одну панель по
    `data-editor-mode`; ArrowLeft/Right переключают (roving tabindex). Панели — `role=tabpanel aria-labelledby`;
  - **явное сохранение**: пустая (нет заголовка и текста) → запрет с сообщением «Заметка пустая» (без запроса);
    иначе `POST /api/notes` (создание) / `PATCH /api/notes/:id` (редактирование); статус в шапке
    «Сохранено {время}» (`role=status`) / «● Есть несохранённые изменения»; ошибка → `.alert--error`
    «Не удалось сохранить», текст не теряется, статус не «сохранено»;
  - **диалог ухода** при несохранённых правках (кнопка «Отмена», ссылка «← Мои заметки») + `beforeunload`;
  - загрузка заметки для редактирования (`GET /api/notes/:id`), 404 → «Не удалось загрузить заметку».
- **`web/src/api/notes.ts`** — добавлены `get`, `create`, `update` и тип `NoteInput`.
- **`web/src/components/icons.tsx`** — `EyeIcon`, `SaveIcon`.
- **`web/src/App.tsx`** — маршруты `/notes/new` и `/notes/:id/edit` (под `ProtectedRoute` + `AppLayout`).
- **Тесты:** `editor-lib.test.ts` (16), `tag-input.test.tsx` (7), `editor.test.tsx` (18) — 41 новый.

### Покрытие приёмки T-09 (тесты + e2e)

| Критерий | Проверка |
|---|---|
| Создание (заголовок+текст+теги) → POST, персистентно (AC-16/AC-33) | тест (тело запроса) + e2e POST→GET→PATCH→GET |
| Пустая заметка → запрет с сообщением (AC-17/E1) | тест (POST не отправляется) + e2e 422 |
| Markdown хранится raw; превью рендерит (AC-28/AC-29) | тест (raw значение + `<strong>`/`<h2>`) |
| Toolbar: префикс/обёртка/блок/ссылка, без дублей, по выделению (§2.7) | 16 unit (lib) + 4 интеграционных |
| Сплит ≥1025 / табы ≤1024 (AC-30/NFR-23) | 2 теста (`data-editor-mode`, tablist/Arrow) |
| Несохранённые → предупреждение (AC-20/E10) | 3 теста (диалог «остаться»/«выйти»/«сохранить и выйти» + beforeunload) |
| Ошибка сохранения не теряет текст (E17) | тест (500 → текст на месте, статус не «сохранено») |
| Загрузка/редактирование заметки (PATCH) | 3 теста + e2e |

### Как проверить

```powershell
cd web
npm install
npm test          # vitest: 96 тестов (9 T-06 + 28 T-07 + 18 T-08 + 41 T-09)
npm run build     # tsc --noEmit && vite build
# e2e-data-path:
cd ..\server; $env:PORT='3411'; $env:DATABASE_PATH="$env:TEMP\t09-notes.db"; npm start
# сценарий: register → POST /api/notes (raw markdown + теги) → GET:id → PATCH → GET (персистентно)
#           → пустая → 422 → POST без CSRF → 403
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm test`: **Test Files 6 passed (6) · Tests 96 passed (96)** = 55 существующих (T-06..T-08) + 41 новых T-09
  (16 `editor-lib` + 7 `tag-input` + 18 `editor`).
- `npm run build`: `tsc --noEmit` без ошибок; `vite build` → `dist/` (CSS 33.41 kB, JS 344.89 kB).
- **E2E data-path** (`npm start`, порт 3411, tmp-БД, Node `fetch` с cookie-jar + `X-CSRF-Token`):
  **13/13 PASS** — register 201; POST заметки (raw markdown + теги) 201; `bodyMarkdown` сохранён как raw;
  теги сохранены (сервер сортирует → `["планы","работа"]`); `GET /api/notes/:id` → идентичный markdown;
  PATCH 200 и поля применены; повторный GET — изменения персистентны; пустая заметка → 422 с сообщением;
  POST без `X-CSRF-Token` → 403.
- **UI-проверка:** реальный браузер в песочнице недоступен (как T-06..T-08) — экран проверен
  интеграционными тестами, рендерящими **реальный `App`** с настоящим роутером/контекстом и мок-`fetch`,
  отвечающим как сервер; a11y — через роли/имена/aria (toolbar/группы/табы/диалог/статусы).

### Артефакты

`web/src/lib/editor.ts` (новый), `web/src/components/{MdToolbar,TagInput,UnsavedDialog}.tsx` (новые),
`web/src/pages/Editor.tsx` (новый), `web/src/__tests__/{editor-lib.test.ts,editor.test.tsx,tag-input.test.tsx}`
(новые), `web/src/api/notes.ts`, `web/src/components/icons.tsx`, `web/src/App.tsx`

**Коммит:** `feat(T-09): экран редактора (заголовок, теги, markdown, toolbar, live-превью, сохранение)`

### Заметки для следующих задач

- **T-10 (просмотр S5):** рендерер `renderMarkdown` уже подключён в Editor (превью) — на S5 использовать
  тот же вызов для идентичного HTML (AC-31). `notesApi.get(id)` готов. В Editor после создания заметки
  происходит `navigate('/notes/:id/edit', {replace})` — когда появится S5, можно вернуть переход на
  `/notes/:id` после сохранения (DESIGN поток C).
- **T-11 (a11y):** toolbar (toolbar/group/separator, aria-keyshortcuts), табы (roving tabindex/Arrow),
  поле тегов (label + aria-invalid + role=alert), статусы сохранения (`role=status`), диалог ухода
  (native dialog, autofocus, Esc) — реализованы; остаётся сквозной пас (фокус-ловушка, контраст, брейкпоинты).
- **T-12:** сборка `web/dist` (JS 344.89 kB) — цель прод-раздачи; SPA-fallback обязателен для
  `/notes/new` и `/notes/:id/edit`.
- **Инвариант сервера для QA:** `PATCH` возвращает полный `Note`; теги сортируются — сравнение наборов
  тегов на клиенте сделано регистро-/порядко-независимым (`sameTags`), поэтому ложных «несохранённых».

---

## T-10 — Экран просмотра заметки (S5) + 404 — tasker-frontend

**Дата:** 2026-10-13
**Стек-скилл:** `react` (компоненты/состояние/a11y/тесты)
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **`web/src/pages/Note.tsx` (новый)** — экран `S5` для маршрута `/notes/:id`:
  - **загрузка заметки** `GET /api/notes/:id` (через `notesApi.get`, CSRF/401-обработка — в `api/client.ts`);
    состояние `loading` → **скелетон статьи** (`NoteArticleSkeleton`, без спиннеров, §4.2.1);
  - **рендер markdown** тем же `renderMarkdown` (T-07), что и превью редактора, в
    `<article className="md article-body" dangerouslySetInnerHTML>` — идентичный HTML превью/просмотра (AC-31);
  - **один `h1` на страницу** = заголовок заметки (`noteTitle`, T-08: для заметки без заголовка — первая
    строка текста, иначе «Без названия»). Markdown-заголовки начинаются с `h2` (рендерер T-07 сдвигает
    `#` → `h2`, DESIGN §5.4); внутри `article` узлов `h1` нет;
  - **мета**: «Обновлена <time>8 окт 2026, 20:15</time>», «Создана <time>1 окт 2026</time>» и размер
    («1 284 символа») — `formatNoteDateFull` / `formatNoteDateOnly` / `formatCharsCount` из `lib/format.ts`;
  - **теги — текстовые узлы React** (`.tag > .tag__label`), не `innerHTML` — HTML-подобные символы
    экранируются и не исполняются (AC-47/NFR-14); пустой набор → «Без тегов»;
  - **действия**: «Редактировать» → `/notes/:id/edit`, «Удалить» → переиспользует `DeleteDialog`
    (native `<dialog>`, Esc/отмена = без изменений); после подтверждения `DELETE /api/notes/:id` и
    **возврат к списку** `/notes` (AC-21/E13); при ошибке удаления — `.alert--error` «Не удалось удалить»,
    фокус возвращается на кнопку (§4.2.3); ссылка **«← Мои заметки»** → `/notes`;
  - **«Заметка не найдена»** для `404`/чужого/нечислового id (Q-A7, AC-11): сервер не отличает чужую от
    несуществующей — данные не раскрываются (`article.md` не рендерится), есть ссылка «К моим заметкам».
    Прочие ошибки загрузки → `.alert--error` «Не удалось загрузить заметку» + «Повторить».
- **`web/src/lib/format.ts`** — добавлены `formatNoteDateFull` («8 окт 2026, 20:15»),
  `formatNoteDateOnly` («1 окт 2026») и `formatCharsCount` («1 284 символа», группировка + склонение).
- **`web/src/components/Skeleton.tsx`** — добавлен `NoteArticleSkeleton`: скелетон статьи (заголовок +
  строки-абзацы), контейнер `aria-hidden` + скрытый `role="status"` «Загрузка заметки…».
- **`web/src/components/icons.tsx`** — добавлена `ClockIcon` (мета-иконка, `aria-hidden`/`focusable=false`).
- **`web/src/App.tsx`** — маршрут `/notes/:id` (`<Note />`) под `ProtectedRoute` + `AppLayout`
  (статический `/notes/new` ранжируется выше параметрического — конфликта нет).
- **Тесты:** `web/src/__tests__/note.test.tsx` (8 тестов, реальный `App` + `AuthProvider` + `MemoryRouter`,
  мок-`fetch` как сервер).

### Покрытие приёмки T-10 (тесты + браузерный e2e)

| Критерий | Проверка |
|---|---|
| Открытие показывает отрендеренный markdown и сохранённое содержимое (AC-11/AC-18/AC-31) | тест + e2e (strong/h2/список, нет сырых `**`) |
| Чужой/несуществующий id → «Заметка не найдена», без раскрытия (AC-11/Q-A7) | тест (404) + e2e (`/notes/999999`) |
| Теги/заголовок как текст, HTML-подобные символы не исполняются (AC-47/NFR-14) | тест (`<script>`/`<b>`/`<img onerror>` в тегах и заголовке) + e2e |
| Удаление из просмотра → подтверждение → возврат к списку (AC-21/E13) | 2 теста (подтверждение/отмена) + e2e (dialog → `/notes`) |
| Один h1 на страницу; markdown-заголовки с h2 (DESIGN §5.4) | тест + e2e (`#` → h2, h1 в статье нет) |

### Как проверить

```powershell
cd web
npm install
npm test          # vitest: 104 теста (96 существующих + 8 T-10)
npm run build     # tsc --noEmit && vite build
# e2e-data-path (S5 ходит в те же эндпоинты):
cd ..\server; $env:PORT='3000'; $env:DATABASE_PATH="$env:TEMP\t10-notes.db"; npm start
# затем register → POST /api/notes → GET /api/notes/:id → DELETE
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm test`: **Test Files 7 passed (7) · Tests 104 passed (104)** = 96 существующих (T-06..T-09) + 8 новых T-10.
- `npm run build`: `tsc --noEmit` без ошибок; `vite build` → `dist/` (`index.html` 0.47 kB, CSS 33.41 kB,
  JS 350.15 kB).
- **Браузерный E2E (реальный Edge/Chromium, headless, CDP) — 9/9 PASS** через полный стек
  (Vite dev :5173 → прокси → Fastify :3000, реальная сессия-cookie + CSRF):
  1. `/notes/:id` открывается, заголовок заметки отображается;
  2. на странице ровно **один `h1`** = заголовок заметки;
  3. markdown отрендерен: `<strong>B-tree</strong>`, `<h2>Когда какой индекс</h2>`, список; сырых `**` нет;
  4. внутри `article.md` узлов `h1` нет (заголовки начинаются с `h2`);
  5. мета-дата в формате «8 окт 2026, 20:15» (`<time datetime>`);
  6. теги — текст: `<b>сырой</b> тег` показан как текст, узлов `script/b/img` в регионе тегов нет;
  7. `/notes/999999` → «Заметка не найдена», `article.md` отсутствует;
  8. «Удалить» открывает диалог «Удалить заметку?» (`dialog.open === true`);
  9. после подтверждения — `DELETE /api/notes/:id` → 204 и возврат на `/notes` («Мои заметки»).
- **Логи сервера:** только `method/url/statusCode/responseTime`, без паролей/cookie/токенов и тел (NFR-9/A9).
- **Грабли окружения (для QA/DevOps):** Chrome отсутствует, но Edge есть
  (`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`) — работает как Chromium/CDP; MCP
  `chrome-devtools` ищет строго `chrome.exe`, поэтому браузерный прогон сделан прямым CDP-скриптом в Edge.

### Артефакты

`web/src/pages/Note.tsx` (новый), `web/src/__tests__/note.test.tsx` (новый), `web/src/App.tsx`,
`web/src/lib/format.ts`, `web/src/components/Skeleton.tsx`, `web/src/components/icons.tsx`

**Коммит:** `feat(T-10): экран просмотра заметки (S5) — рендер markdown, мета, теги-текст, удаление и 404`
(хеш — `git log --oneline -1`)

### Заметки для следующих задач

- **T-11 (a11y):** на S5 — один `h1`, ссылки/кнопки с текстом-именем, `<time datetime>`, скелетон с
  `role="status"`, «Заметка не найдена» — `.empty` с заголовком/текстом; остаётся сквозной пас
  (фокус-ловушка диалога, контраст/брейкпоинты).
- **T-12:** маршрут `/notes/:id` теперь часть SPA — SPA-fallback обязателен и для него (JS-бандл 350 kB).
- **Поток C (DESIGN §1.2):** после сохранения в редакторе `Editor.tsx` пока уводит на `/notes/:id/edit`
  (`replace`); возврат на S5 (`/notes/:id`) — небольшая доработка Editor, вне объёма T-10 (не менялся).
- **`formatCharsCount`** использует неразрывный пробел (`\u00a0`) для группировки разрядов — учитывать при
  сравнении строк в тестах.

---

## T-11 — Доступность и адаптивность (кросс-экранный пас) — tasker-frontend

**Дата:** 2026-10-13
**Стек-скилл:** `react` (компоненты/состояние/a11y/тесты)
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано (исправления)

| # | Найдено | Исправление | Файл |
|---|---|---|---|
| 1 | Диалоги **не возвращали фокус** инициатору; `Esc` не обрабатывался, если окружение не умеет нативное закрытие | Общий хук `useModalDialog(open, ref, onEscape)`: `showModal()` + фокус на «безопасном» действии, `Esc` = безопасное действие (единообразно в браузере и jsdom), при закрытии `close()` + **возврат фокуса инициатору** (NFR-15/§5.3) | `components/useModalDialog.ts` (новый), `DeleteDialog.tsx`, `UnsavedDialog.tsx` |
| 2 | `aria-describedby` поиска указывал на `#result-status`, которого в DOM не было в состоянии загрузки/ошибки (битая IDREF) | Живой регион результатов рендерится **всегда**, текст — в состоянии `ready` (DESIGN §2.4/§2.6, NFR-16/20) | `pages/Notes.tsx` |
| 3 | `aria-label` на `div` без роли (теги заметки) не объявлялся | `role="group" aria-label="Теги заметки"` | `pages/Note.tsx` |
| 4 | Экран 404/ошибки заметки был **без `h1`**; ошибка дублировала текст алерта | `h1` «Заметка не найдена» (`.empty__title`), `h1` «Не удалось загрузить заметку» + алерт «Сервер не ответил» | `pages/Note.tsx` |
| 5 | `aria-label` на `span`-бейдже «🛡 через санитайзер» (не объявляется) и эмодзи в имени | Эмодзи — `aria-hidden`, текст несёт смысл | `pages/Editor.tsx` |
| 6 | **Lighthouse `heading-order`**: заметка, начинающаяся с `##`, рендерилась как `h3` → пропуск уровня `h1`→`h3` | Нормализация уровней заголовков: **минимальный** уровень заметки → `h2` (было: жёсткий сдвиг +1), пропуска уровней нет, верх — `h4` (DESIGN §5.4, AC-31 сохраняется: рендерер один и тот же) | `lib/markdown.ts` |
| 7 | Правило `≤860px` (`snippet: none`, `tags: 140px`) стояло **до** блока `≤1024px` и было мёртвым (`max-width: 180px` перебивал) | Блок `≤860px` перенесён после `≤1024px`; инвариант зафиксирован тестом | `styles/glass.css` |
| 8 | **≤640px поиск растягивался на 260px по высоте** (`flex: 1 1 260px` в колоночном toolbar работает по вертикали) — найдено рендером в браузере | `.toolbar .search { flex: 0 0 auto; width: 100% }` на ≤640px | `styles/glass.css` |
| 9 | Фильтр-бар на ≤640px не перестраивался в столбик (§3.10) | `.filterbar` в колонку, спейсер скрыт, «Сбросить» по левому краю | `styles/glass.css` |
| 10 | `.md-input` 14px на мобильном → iOS зумит страницу при фокусе (§5.6) | ≤640px: `.md-input { font-size: var(--fs-16) }` (на десктопе по DESIGN §2.13 остаётся 14px) | `styles/glass.css` |
| 11 | Подпись состояния фильтров — `--c-text-3` при 12px (нарушение правила §5.1.3) | `small muted` (13px, `--c-text-2`), остаётся не-live-подписью (§2.6) | `components/TagFilter.tsx` |

**Подтверждено без изменений** (контракт уже соответствовал DESIGN §5.2/§5.3):
segmented (`role=group`/`aria-pressed`/скрытый `role=status`), поиск (sr-only label, `type=search`,
`autocomplete=off`), чипы (`group`/`aria-pressed`/`aria-hidden` счётчик), toolbar (`toolbar`/`group`/
`separator`/`aria-label`+`title`+`aria-keyshortcuts`, глифы `aria-hidden`), табы редактора
(`tablist`/`tab`/`aria-controls`/roving `tabindex`/Arrow), диалоги (`aria-labelledby`/`describedby`,
`autofocus` на безопасном действии), формы (`aria-invalid`/`aria-describedby`/`role=alert`,
фокус на алерте/первом невалидном поле), `skip-link` первым в tab-порядке, иконки
(`aria-hidden`/`focusable=false`), контраст токенов (§5.1), fallback `@supports not (backdrop-filter)`,
`prefers-contrast: more`, `prefers-reduced-motion` в токенах/стекле.

### Тесты (витest + @testing-library/react): +32 (было 104 → стало 136 → 137)

- `src/__tests__/a11y.test.tsx` (20 тестов) — сквозной a11y-контракт по экранам:
  Login/Register (один `h1`, skip-link первым, `aria-invalid`/`aria-describedby`/`role=alert`,
  фокус на алерте/первом невалидном поле, сила пароля не только цветом);
  Notes (segmented-семантика, живые регионы поиска и результатов, чипы, контекстные `aria-label`
  иконок-кнопок, empty-state, диалог: aria-связи + autofocus + `Esc` + возврат фокуса,
  **Tab-обход 60 шагов без залипания и циклический**); Editor (`h1`, toolbar/группы/разделители,
  табы + Arrow + roving tabindex, поле тегов + `role=alert` на лимите, статусы, диалог несохранённых
  правок с `Esc` и возвратом фокуса); Note (один `h1`, группа тегов, диалог, 404/ошибка с заголовком,
  порядок заголовков без пропуска уровней).
- `src/__tests__/a11y-css.test.ts` (13 тестов) — статический CSS-контракт (jsdom не считает раскладку):
  брейкпоинты 1024/900/860/640, 16px у инпутов и `.md-input` на мобильном, порядок media-блоков
  (каскад), `prefers-reduced-motion`, `prefers-contrast: more` (значения токенов), fallback
  `@supports not (backdrop-filter)`, кольцо фокуса, отсутствие `contain: paint`, blur только на
  контейнере списка, плотности стекла `.98/.95/.97/.92` и базовые `.84/.68/.58/.42`.

### Покрытие приёмки T-11

| Критерий | Проверка |
|---|---|
| Полный Tab/Shift+Tab без «залипания»; диалоги `Esc` + возврат фокуса (NFR-15) | тест (60 табов, цикличность, без повторов) + **реальный браузер**: обход `/notes` и `/notes/new` по шагам, `Esc` в обоих диалогах, фокус вернулся на «Удалить заметку «…»» и «Отмена» |
| Переключатель вида и поиск/фильтр: семантика/имена (NFR-16) | тест + a11y-дерево Chrome (`button "Плитки" pressed`, `searchbox "Поиск по заметкам" description="5 заметок — все заметки"`, чипы `aria-pressed`) |
| Иконки-кнопки с `aria-label`; ошибки форм `role=alert`+`aria-invalid`+`aria-describedby` (NFR-17/19) | тесты + проверка «нет кнопок без имени / все `svg` `aria-hidden`» на 7 экранах |
| Контраст AA, видимый фокус, результаты/empty-state читаются (NFR-18/20) | Lighthouse **Accessibility 100** на `/notes`, `/notes/new`, `/login`, `/register`, `/notes/:id`; контраст — по замерам Design-токенов §5.1 |
| `prefers-reduced-motion` (mesh/shimmer/hover), `prefers-contrast`, fallback `@supports` (§5.5) | **CDP-эмуляция в реальном Chrome**: mesh `animation: none`, shimmer `1.6s infinite → 1e-05s/1`, hover `translateY(-2px) → none`, `--glass-bg-hi .84 → .98`, `--c-text-2 #3d4a5e → #2b3648`, `@supports not (…)` с `.96/.94/.95/.9` объявлен |
| Адаптив 1280/1024/860/640 (NFR-21..24) | **реальный рендер** (Chrome, CDP `resize_page`): 1280 → 4 плитки, 1024 → 3, 860 → 2, 640 → 1; список: фрагмент скрыт ≤860, теги 300→180→140→100%; сплит→табы на ≤1024 (панель по `data-editor-mode`, Arrow), toolbar 30×30 на ≤640; формы: брендовая панель скрыта ≤1024, инпуты 16px, карточка 430px; горизонтального скролла нет ни на одной ширине |

### Как проверить

```powershell
cd web
npm install
npm test          # vitest: 137 тестов (104 существующих + 33 T-11)
npm run build     # tsc --noEmit && vite build
# браузерная проверка (реальный Chrome/CDP или MCP chrome-devtools):
cd ..\server; $env:PORT='3000'; $env:DATABASE_PATH="$env:TEMP\t11-notes.db"; npm start
cd ..\web;    npm run dev      # :5173 → proxy /api → :3000
# далее: register → 3+ заметки → resize 1280/1024/860/640 → Lighthouse (snapshot) → Tab/Esc
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm test`: **Test Files 9 passed (9) · Tests 137 passed (137)** = 104 существующих (T-06..T-10) + 33 новых.
- `npm run build`: `tsc --noEmit` без ошибок; `vite build` → `dist/` (CSS 33.68 kB, JS 351.15 kB).
- **Браузерный e2e (реальный Chrome + MCP `chrome-devtools`, полный стек Vite :5173 → Fastify :3000,
  реальная сессия + CSRF), 7 экранов**:
  - ровно один `h1` и один `<main>` на каждом экране; `skip-link` первым (кроме служебного 404-роута
    вне `AppLayout`); кнопок без доступного имени — 0; `svg` без `aria-hidden` — 0; ошибок в консоли нет
    (только dev-warning React Router о future-флагах);
  - **Lighthouse Accessibility: `/notes` 100, `/notes/new` 100, `/login` 100, `/register` 100,
    `/notes/:id` 98 → после нормализации заголовков 100** (failures после правки — только SEO
    `meta-description`/`robots.txt` и agentic-browsing `llms.txt`, вне a11y);
  - клавиатура `/notes`: `skip-link → бренд → Выйти → Создать заметку → поиск → Плитки → Список →
    5 чипов → Сбросить → заметка → Редактировать → Удалить`, далее цикл; `Enter` на «Удалить…» открывает
    диалог с фокусом внутри («Отмена»), `Esc` закрывает и возвращает фокус на инициатора, заметка на месте;
  - клавиатура `/notes/new`: `… → Отмена/Сохранить → заголовок → теги → [таб «Редактор» на ≤1024] →
    11 кнопок toolbar → textarea`; на 1280 табы скрыты (`display:none`) и в tab-порядке отсутствуют;
  - адаптив: разметка/плитки/список/сплит-табы/формы — см. таблицу приёмки (ширины 1280/1024/860/640,
    измерены `getComputedStyle` и габариты узлов; горизонтального скролла нет);
  - скриншоты `/notes` 1280 (4 плитки — плитки/список), 640 (1 колонка, столбик фильтров) и
    `/notes/:id/edit` 1024 (табы) просмотрены: вёрстка целая, стекло/контраст не поплыли.
- **Найденные дефекты** — все 11 из таблицы выше; #7/#8/#9/#10 найдены **только** реальным рендером
  (jsdom раскладку не считает) — подтверждение ценности браузерного гейта.
- **Грабли окружения (для QA/DevOps):** `resize_page(640)` даёт `innerWidth = 642` (окно + 2px) —
  для попадания в media-условие `≤640px` запрашивать 638 (аналогично 858/1022);
  MCP `emulate` не умеет `prefers-reduced-motion`/`prefers-contrast` — использован прямой CDP
  (`Emulation.setEmulatedMedia`) в headless Chrome с временными скриптами (удалены).

### Артефакты

`web/src/components/useModalDialog.ts` (новый), `web/src/components/{DeleteDialog,UnsavedDialog,TagFilter}.tsx`,
`web/src/pages/{Notes,Note,Editor}.tsx`, `web/src/lib/markdown.ts`, `web/src/styles/glass.css`,
`web/src/__tests__/a11y.test.tsx` (новый), `web/src/__tests__/a11y-css.test.ts` (новый),
`web/package.json`/`package-lock.json` (`@types/node` для чтения CSS в тесте), `web/tsconfig.json` (types: node)

**Коммит:** `1996858` — `feat(T-11): сквозной пас доступности и адаптивности (фокус диалогов + Esc, aria-контракт, prefers-*, брейкпоинты)`

### Заметки для следующих задач

- **T-12 (deploy):** сборка `web/dist` (JS 351 kB) — цель прод-раздачи; новые маршруты не добавлялись,
  но SPA-fallback обязателен для `/notes`, `/notes/new`, `/notes/:id`, `/notes/:id/edit`.
- **QA:** браузерный гейт обязателен — `jsdom` не считает раскладку, и 4 из 11 дефектов T-11
  (высота поиска на 640, мёртвое правило ≤860, сплит-табы, font-size поля markdown) видны только в рендере.
  Для проверок ширины учитывать `+2px` у `resize_page`.
- **`renderMarkdown`** нормализует **минимальный** уровень заголовка заметки к `h2` (не жёсткий +1):
  заметка без `#` теперь даёт `h2`, а не `h3` (иначе Lighthouse `heading-order` и пропуск уровня).
  Тест T-07 («заголовки начинаются с h2») остаётся зелёным — сдвиг +1 сохраняется для заметок с `#`.
- **Диалоги:** вся механика (показ, `Esc`, возврат фокуса) — в `useModalDialog`; новые диалоги
  подключать через него, а не дублировать `showModal`.
- **Мобильная типографика:** `.md-input` — 14px по §2.13, но 16px на ≤640px (антизум iOS, §5.6);
  при снижении альфы стекла или смене размеров инпутов — повторный замер контраста (DESIGN §5.1.5).

---

## T-12 — Прод-сборка и однопроцессный деплой (+ Docker-артефакты) — tasker-devops

**Дата:** 2026-10-13
**Стек-скилл:** `docker` (multi-stage, минимизация образа, секреты вне образа, healthcheck, e2e-проверка)
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **Раздача SPA из Fastify — `server/src/lib/spa.ts` (новый).** Однопроцессный деплой: тот же
  Fastify отдаёт и API (`/api`, `/health`), и собранный `web/dist`.
  - `registerStatic(app, staticDir)` — `@fastify/static ^10` (совместим с Fastify 5): отдаёт
    `index.html` и хэшированные ассеты; `index.html` — `Cache-Control: no-cache`, `/assets/*` —
    `public, max-age=31536000, immutable`. Регистрируется только при наличии `index.html`
    (иначе сервер API-only — dev/tests).
  - `isSpaNavigation(request)` — SPA-fallback только для **GET/HEAD**, вне `/api` и `/health`
    и при `Accept: text/html`. Проверка `Accept` отделяет переходы браузера (SPA) от
    fetch/asset-запросов (`Accept: */*`), поэтому неизвестный API-роут и отсутствующий ассет
    остаются **JSON-404** — контракт T-02 (`/nope → 404 JSON`) не нарушен.
  - `resolveSpaIndex`/`isApiPath` — чистые хелперы (тестируются юнит).
- **`server/src/app.ts`** — новый опшн `buildApp({ staticDir })` (по умолчанию `config.staticDir`,
  `null` — отключить); `registerStatic` вызывается после CORS до роутов; `setNotFoundHandler`
  отдаёт `index.html` для навигации (SPA-fallback) либо JSON-404 как прежде; при старте логируется
  `{staticDir, spaEnabled}`.
- **`server/src/config.ts`** — env `STATIC_DIR` + `DEFAULT_STATIC_DIR` (`web/dist` относительно корня
  репозитория). Существующие env (`PORT`, `DATABASE_PATH`, `SESSION_SECRET`, `COOKIE_SECURE`,
  `CORS_ORIGIN`, `HOST`) без изменений.
- **npm-скрипты prod — `server/package.json`:** `build:web` (`npm --prefix ../web run build`),
  `serve` (`build:web && start`), `smoke` (`node scripts/e2e-smoke.mjs`); `start` = `tsx src/index.ts`
  (прод-запуск). `@fastify/static` добавлен в `dependencies`; `tsx` перенесён в `dependencies`
  (сервер запускается из TS напрямую) — образ может ставить `npm ci --omit=dev`.
- **`server/scripts/e2e-smoke.mjs` (новый)** — полный сценарный smoke NFR-28 (PLAN §6.3) по реальному
  HTTP с cookie-jar и `X-CSRF-Token` (double-submit): health → SPA тем же процессом → регистрация →
  me → CSRF-guard → создание заметки с тегами → список → поиск по тексту (регистронезависимо) →
  фильтр по тегу → комбинированно (и пустое пересечение) → `/api/tags` → редактирование →
  персистентность → **изоляция** (B не видит/не меняет заметки A; чужой id → 404) → удаление →
  logout. Печатает `✓/✗` по шагам, exit 0/1.
- **`.env.example` (корень)** — все env (PORT/HOST/DATABASE_PATH/STATIC_DIR/SESSION_SECRET/
  COOKIE_SECURE/CORS_ORIGIN/LOG_LEVEL) с пояснениями; секрет — пустой. Реальный `.env` в
  `.gitignore` (NFR-8).
- **Docker (опциональные артефакты, PLAN R7):** `Dockerfile` (multi-stage: `web-build` →
  `server-deps --omit=dev` → `runtime`; `USER node`, `VOLUME /data`, `HEALTHCHECK` GET /health,
  `CMD node --import tsx src/index.ts`), `docker-compose.yml` (сервис `notes`, том `notes-data` для
  SQLite, `SESSION_SECRET` обязателен из окружения — `:?`), `.dockerignore` (исключает
  node_modules/dist/.env/данные). Секреты в образ/репозиторий не попадают.

### Как проверить

```powershell
# прод-сборка + однопроцессный запуск (API + SPA в одном процессе)
cd server
npm run build:web                     # tsc --noEmit && vite build -> web/dist
$env:NODE_ENV='production'; $env:SESSION_SECRET='<32+ символа>'; $env:PORT='3000'
$env:DATABASE_PATH="$env:TEMP\notes.db"
npm start                             # http://localhost:3000 (SPA + /api + /health)
# в другом терминале:
node server/scripts/e2e-smoke.mjs     # NFR-28: 28 проверок
```

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm run build:web`: `tsc --noEmit` без ошибок; `vite build` → `web/dist` (`index.html` 0.47 kB,
  CSS 33.68 kB, JS 351.15 kB).
- **Прод-запуск** (`NODE_ENV=production`, `PORT=3000`, `SESSION_SECRET`, tmp `DATABASE_PATH`) —
  лог старта `{staticDir: ...\web\dist, spaEnabled: true}`; реальные запросы:
  - `GET /health` → `200 {"ok":true}`;
  - `GET /` с `Accept: text/html` → `200 text/html`, `Cache-Control: no-cache`, ссылки на
    `/assets/index-*.js|.css`;
  - `GET /assets/index-Cexs2Nkf.js` → `200 application/javascript`, `Cache-Control: public,
    max-age=31536000, immutable` (355 478 B);
  - `GET /nope` (без `Accept: text/html`) → `404 application/json` (контракт T-02 сохранён).
- **`node server/scripts/e2e-smoke.mjs` против реального прод-сервера: 28/28 PASS** (полный сценарий
  NFR-28, включая изоляцию пользователей и 403 без CSRF).
- **env-конфиг** (второй инстанс `PORT=3212`, `COOKIE_SECURE=true`, `DATABASE_PATH=...\t12-env-prod.db`):
  `GET /health` на `:3212` → `200`; `POST /api/auth/register` → `201` + `Set-Cookie: session=…;
  HttpOnly; **Secure**; SameSite=Lax` и `XSRF-TOKEN=…; **Secure**`; файл БД создан по указанному
  `DATABASE_PATH`. Все три переменные применяются.
- `npm test`: **Test Files 6 passed (6) · Tests 121 passed (121)** = 110 существующих (T-01..T-05) +
  11 новых `spa.test.ts`; `npm run typecheck` — без ошибок.
- **Секреты (NFR-8):** `.env` отсутствует и в `.gitignore`; `git grep` по реальным секретам пуст
  (единственное совпадение `SESSION_SECRET=` — фикстура теста T-02, проверяющая отсутствие утечки);
  `.env.example` — без значений. В коммит секреты не попадают.
- **Docker:** CLI в песочнице отсутствует (подтверждено: `docker` не найден) → контейнер не
  собирался (PLAN R7). Артефакты созданы и проверены статически: все `COPY`-источники существуют,
  стадии `web-build → server-deps → runtime`, есть `HEALTHCHECK`/`CMD`/`USER node`; compose
  содержит сервис, том для SQLite и обязательный `SESSION_SECRET`. Вместо Docker проверен
  **тот же runtime-путь** (`node --import tsx src/index.ts` = `CMD` образа) — однопроцессный запуск
  с раздачей SPA прошёл.
- **Ограничения (документировано, PLAN R4/R7):** rate-limit — in-memory, per-process (сбрасывается
  при перезапуске; горизонтальное масштабирование потребует внешнего хранилища); SQLite — единый
  писатель (том `/data`); контейнерная сборка/запуск не проверены в песочнице — проверяются в CI.

### Артефакты

`server/src/lib/spa.ts` (новый), `server/src/app.ts`, `server/src/config.ts`,
`server/package.json` (+`package-lock.json`: `@fastify/static`, `tsx` → dependencies),
`server/tests/spa.test.ts` (новый), `server/scripts/e2e-smoke.mjs` (новый),
`.env.example` (новый), `Dockerfile` (новый), `docker-compose.yml` (новый), `.dockerignore` (новый)

**Коммит:** `feat(T-12): прод-сборка и однопроцессный деплой (SPA+API в Fastify), e2e-smoke NFR-28, Docker-артефакты`

### Заметки для следующих задач

- **QA:** `server/scripts/e2e-smoke.mjs` — быстрый API-гейт (28 проверок); UI-гейт (браузер) — по
  PLAN §6.3. Для прод-режима важна проверка `Accept: text/html`: навигация отдаёт SPA, fetch/asset —
  JSON; без сборки (`web/dist` нет) сервер работает API-only.
- **DevOps/CI:** образ собирается из корня репозитория (`docker build -t notes-service:local .`);
  `SESSION_SECRET` — только из окружения (в образ/репозиторий не попадает); том `/data` — для SQLite.
- **Прод-гейт (человек):** любой деплой в прод — ручной апрув; агентам доступно тест-окружение.

---

## Fixpack по ревью Guardian (REVIEW.md, замечания #1, #2) — tasker-backend

**Дата:** 2026-10-13
**Статус задачи в `TASKS.json`:** не менялся (ставит конвейер по гейтам)

### Что сделано

- **#1 «`SESSION_SECRET` обязателен в prod, но не используется» → выбран вариант (a): обязательность снята.**
  - `server/src/config.ts`: `Config.sessionSecret` стал опциональным (`sessionSecret?: string`), значение —
    простой passthrough из env (если задано), что задокументировано в JSDoc поля (сессии — opaque
    `randomBytes(32)` + SHA-256 в БД, подпись не нужна; CSRF — `timingSafeEqual`). Удалены генерация
    эфемерного секрета и `MissingSecretError` (в коде больше нет висячего класса/`throw`) — «ложное
    ожидание» убрано полностью, формат сессий и публичное поведение API не менялись.
  - Тесты: `server/tests/app.test.ts` — «падает без `SESSION_SECRET` в проде» заменён на
    «не требует `SESSION_SECRET` в проде» (prod-конфиг грузится, `sessionSecret === undefined`);
    в тесте дефолтов `sessionSecret` проверяется как `undefined`. Импорт `MissingSecretError` убран.
  - Docs: `PLAN.md` §4 (пп. 2, 7), `.env.example` — уточнено, что секрет не участвует в целостности
    сессии и необязателен в любом режиме.
- **#2 «`.env.example`: `NODE_ENV=production` + `COOKIE_SECURE=false`» → прод-дефолт безопасен (NFR-10).**
  - `.env.example`: `COOKIE_SECURE=true`; комментарии переписаны (дефолт в коде: `true` в production,
    `false` в dev/test; для локального запуска прод-сборки по HTTP нужно явно `false`), убрано устаревшее
    «ОБЯЗАТЕЛЕН в production» про `SESSION_SECRET`.
  - `server/src/config.ts`: дефолт `cookieSecure = parseBool(env.COOKIE_SECURE, isProduction)` задокументирован
    как безопасный прод-дефолт; явный `COOKIE_SECURE` по-прежнему перекрывает (нужно для локального HTTP).
  - Тест добавлен: prod без `COOKIE_SECURE` → `cookieSecure === true`; test/development → `false`;
    явный `COOKIE_SECURE=false` в prod → `false`.

### Результаты проверок (13.10.2026, Node v26.11.1, Windows)

- `npm run typecheck` (server): без ошибок.
- `npm test` (server): **Test Files 6 passed (6) · Tests 122 passed (122)** (было 121: −1 устаревший
  про обязательный секрет, +2 новых покрытия правок).
- **E2E по реальному HTTP** (прод-режим, `NODE_ENV=production`, `PORT=3393`, tmp `DATABASE_PATH`,
  **без** `SESSION_SECRET` и **без** `COOKIE_SECURE`): сервер поднялся (`Server listening`, `spaEnabled: true`)
  — фатальной ошибки нет; `POST /api/auth/register` → `201 Created` +
  `Set-Cookie: session=…; HttpOnly; **Secure**; SameSite=Lax` и `XSRF-TOKEN=…; **Secure**`;
  `GET /health` → `200 {"ok":true}`.
- Остаточное (вне scope правки, не блокирует): `docker-compose.yml` всё ещё требует `SESSION_SECRET`
  через `:?` — это лишь обязательная передача переменной в контейнер, конфиг её игнорирует.

### Артефакты

`server/src/config.ts`, `server/tests/app.test.ts`, `.env.example`, `PLAN.md` (§4), `PROGRESS.md`

**Коммит:** `fix(review): SESSION_SECRET необязателен (opaque-сессии) + безопасный Cookie Secure по умолчанию в prod`

---

## 14.10.2026 — DevOps-правка: `docker-compose.yml` больше не требует `SESSION_SECRET`

**Задача:** T-12 (остаточный пункт из review `aaa314b`, см. §13 выше). Точечная правка `docker-compose.yml`.

### Проблема

После фикса `aaa314b` конфиг (`server/src/config.ts`) полностью игнорирует `SESSION_SECRET`
(сессии — opaque `randomBytes(32)` + SHA-256 в БД; CSRF — `timingSafeEqual`), но compose объявлял
переменную через `:?` — обязательную интерполяцию. `docker compose up --build` без заданного в
окружении/.env `SESSION_SECRET` падал бы ещё до старта контейнера («required variable … is missing»),
хотя приложение секрет не использует.

### Что сделано

- **`docker-compose.yml`:** удалена строка `SESSION_SECRET: ${SESSION_SECRET:?…}` из блока
  `environment` — переменная мертва (конфигом не читается), её проброс не нужен; вместо неё короткий
  комментарий, почему она не передаётся. Заголовочный комментарий переписан: больше не инструктирует
  генерировать/задавать `SESSION_SECRET` перед `docker compose up` (теперь достаточно одной команды);
  прод-гейт (ручной апрув) на месте.
- **Обоснование выбора:** удаление, а не `${SESSION_SECRET:-}`, — в compose не остаётся ни одного
  `${…}`, значит нет и необязательного проброса неиспользуемой переменной и предупреждений
  интерполяции; `.env.example` уже описывает `SESSION_SECRET` как опциональный, правки не требуются.

### Результаты проверок (14.10.2026, Node v26.11.1, Windows; Docker в песочнице отсутствует — PLAN R7)

- **Статическая корректность YAML:** `js-yaml` разобрал файл без ошибок → `YAML OK`;
  `services: [notes]`, `volumes: [notes-data]`, `environment` содержит 8 ключей
  (NODE_ENV/HOST/PORT/DATABASE_PATH/STATIC_DIR/COOKIE_SECURE/CORS_ORIGIN/LOG_LEVEL),
  `SESSION_SECRET` отсутствует (проверка `'SESSION_SECRET' in env` → `false`, exit 0).
- **Обязательные переменные:** `grep` по `:?` во всех `*.yml` → совпадений нет; `grep` по `${` в
  `docker-compose.yml` → пусто, т.е. необъявленных/обязательных интерполяций не осталось.
- Docker не запускался (CLI недоступен, PLAN R7) — проверка статическая, как и предписано.

### Артефакты

`docker-compose.yml`, `PROGRESS.md`

**Коммит:** `fix(devops): docker-compose больше не требует SESSION_SECRET (мёртвая env, opaque-сессии)`


