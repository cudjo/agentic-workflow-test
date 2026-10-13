# PLAN — фундамент реализации «Сервис заметок»

> Владелец: **Planner** (сессия 0). Выход инициализации (дизайн-док §6.4).
> Вход: `TICKET.md` (маршрут `full`, приёмка с QA), `SPEC.md` (требования, гейт 1 утверждён),
> `DESIGN.md` (UX/UI-контракт, гейт 2 утверждён), `mockups/` (утверждённый макет «Liquid Glass»).
> Статус: зафиксирован до старта Tasker'ов. Решения здесь — контракт для реализации.

---

## 1. Резюме решения (стек)

| Слой | Выбор | Обоснование |
|---|---|---|
| **Фронтенд** | **React 18 + TypeScript + Vite** (SPA) | Скилл `react`. SPA обязателен (клиентский роутинг, guard маршрутов, live-превью markdown, состояние). Vite — быстрый dev-сервер + прод-сборка. Токены/классы из `mockups/styles.css` переносятся в приложение как контракт вёрстки. |
| **Бэкенд** | **Node.js + TypeScript + Fastify** | Скилл `typescript-node`. Единый язык с фронтом, строгие типы, Fastify даёт JSON-schema-валидацию контрактов + скорость. Node v26 уже стоит в окружении. |
| **БД** | **SQLite** (встроенный `node:sqlite`, `DatabaseSync`) | **Ключевое решение.** В окружении нет Docker и psql (проверено), а `init.sh` обязан реально подниматься на этой машине. SQLite — нулевая установка, файловая персистентность (NFR-25), синхронный API без нативных зависимостей (нет риска сборки native-модулей под Node 26 на Windows). Слой данных изолирован → PostgreSQL — drop-in замена позже (см. риски). |
| **Хеширование паролей** | **bcryptjs** (чистый JS) | Соответствует NFR-9 («bcrypt/argon2»), без native-сборки. Заменяемо на `argon2`/нативный `bcrypt` в проде. |
| **Сессии** | Cookie-сессия, opaque token (SHA-256 в БД) + CSRF double-submit | См. §4. |
| **Markdown** | `markdown-it` (рендер) + `DOMPurify` (санитайзинг по allowlist) на фронте | Raw markdown хранится как текст; XSS-защита — в единственной точке рендера (DESIGN §8). |

**Причины не брать альтернативы:**
- `go` — не установлен в окружении.
- `postgres` (Docker) — Docker/psql отсутствуют; поднятие было бы невозможным в песочнице и ломким у Tasker'ов.
- `python` — валидная альтернатива бэкенду, но единый TypeScript-стек удешевляет типы и переиспользование контрактов между фронтом/бэком.

---

## 2. Структура репозитория

```
/
  PLAN.md, TASKS.json, init.sh, init.ps1
  TICKET.md, SPEC.md, DESIGN.md          # входные артефакты (в baseline)
  mockups/                               # утверждённый макет (в baseline)
  server/                                # бэкенд (Fastify + SQLite)
    package.json, tsconfig.json, vitest.config.ts
    src/
      index.ts                           # entrypoint: config → app → listen
      app.ts                             # сборка Fastify (роуты, middleware, static)
      config.ts                          # env: PORT, DATABASE_PATH, SESSION_SECRET, COOKIE_SECURE, CORS_ORIGIN
      db/
        client.ts                        # DatabaseSync-обёртка, `node:sqlite`
        migrate.ts                       # runner: применяет migrations/*.sql по порядку (таблица schema_migrations)
        migrations/001_init.sql
      routes/
        auth.ts, notes.ts, tags.ts, health.ts
      middleware/
        auth.ts                          # парсит session-cookie → req.user, иначе 401
        csrf.ts                          # сверяет X-CSRF-Token с токеном сессии (state-changing)
        rateLimit.ts                     # in-memory limiter (login/register)
      lib/
        password.ts, sessions.ts, validation.ts, errors.ts, search.ts
      scripts/e2e-smoke.mjs              # сценарная API-проверка (для QA/смоук)
    tests/                               # vitest (unit + integration)
  web/                                   # фронтенд (React + Vite)
    package.json, vite.config.ts, tsconfig.json
    src/
      main.tsx, App.tsx, router.tsx      # react-router, guard авторизации
      styles/tokens.css, glass.css, base.css  # перенесены из mockups/styles.css (контракт)
      api/client.ts                      # fetch с credentials:include + CSRF-заголовком
      lib/markdown.ts                    # markdown-it + DOMPurify (allowlist §8)
      lib/format.ts                      # даты «13 окт, 09:20», склонение «N заметок»
      pages/Login.tsx, Register.tsx, Notes.tsx, Editor.tsx, Note.tsx, NotFound.tsx
      components/  (NoteItem, DeleteDialog, TagInput, SearchBox, Segmented, EmptyState, Skeleton, MdToolbar, Topbar …)
```

Порты: **бэкенд 3000**, **фронтенд-dev 5173** (Vite proxy `/api` → `:3000`). В проде Fastify раздаёт собранный `web/dist` сам (однопроцессный деплой, T-12).

---

## 3. Контракты

### 3.1 Схема БД (SQLite, `server/src/db/migrations/001_init.sql`)

```sql
CREATE TABLE users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  email         TEXT NOT NULL COLLATE NOCASE,       -- хранится в lowercase
  email_norm    TEXT NOT NULL UNIQUE,               -- lower(email) — уникальность без учёта регистра
  password_hash TEXT NOT NULL,                      -- bcrypt
  created_at    TEXT NOT NULL                       -- ISO-8601 UTC
);

CREATE TABLE sessions (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  token_hash TEXT NOT NULL UNIQUE,                  -- SHA-256(raw token); raw — только в cookie
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  csrf_token TEXT NOT NULL,                         -- random, для double-submit
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL                          -- default +7 суток, скользящее продление
);
CREATE INDEX idx_sessions_user ON sessions(user_id);

CREATE TABLE notes (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title         TEXT,                               -- опц., ≤ 200
  body_markdown TEXT NOT NULL,                      -- raw markdown, ≤ 100 000
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
CREATE INDEX idx_notes_user_updated ON notes(user_id, updated_at DESC);

CREATE TABLE tags (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,                         -- исходное написание
  name_norm  TEXT NOT NULL,                         -- lower() — для регистронезависимой уникальности
  UNIQUE (user_id, name_norm)
);

CREATE TABLE note_tags (
  note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  tag_id  INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
  PRIMARY KEY (note_id, tag_id)
);
CREATE INDEX idx_note_tags_tag ON note_tags(tag_id);
```

- Время — ISO-8601 UTC (TEXT). Сортировка — `updated_at DESC` (Q-S3).
- Каскады: удаление пользователя → заметки/сессии/теги; удаление заметки → note_tags; осиротевшие теги без заметок чистятся (T-05).
- Все операции записи — в транзакции (`BEGIN`/`COMMIT`), обновление заметки с тегами атомарно (NFR-26/27).

### 3.2 REST API (базовый путь `/api`)

Общий формат: JSON, ошибки — `{ "error": { "code", "message", "field?" } }`. Коды: 400/401/404/409/422/429/500.

**Auth**
| Метод/путь | Тело запроса | Ответ | Примечания |
|---|---|---|---|
| `POST /api/auth/register` | `{email, password}` | `201 {user}` + cookie | 409 занят, 422 валидация (email-формат, пароль ≥ 8) |
| `POST /api/auth/login` | `{email, password}` | `200 {user}` + cookie | 401 обобщённо; 429 rate-limit (~5/15 мин) |
| `POST /api/auth/logout` | — | `204` | инвалидация сессии, очистка cookie |
| `GET /api/auth/me` | — | `200 {user}` / `401` | для восстановления сессии и guard'а |

`user = { id, email }`.

**Notes** (все требуют авторизации; только свои — иначе `404`, Q-A7)
| Метод/путь | Параметры/тело | Ответ |
|---|---|---|
| `GET /api/notes?q=&tag=` | `q` подстрочный поиск, `tag` фильтр (имя тега); комбинируются по «И» | `200 {items: Note[], total}` |
| `POST /api/notes` | `{title?, bodyMarkdown, tags: string[]}` | `201 Note`; 422 если пустая (нет title и нет текста) |
| `GET /api/notes/:id` | — | `200 Note` / `404` |
| `PATCH /api/notes/:id` | частично `{title?, bodyMarkdown?, tags?}` | `200 Note` |
| `DELETE /api/notes/:id` | — | `204` / `404` |

`Note = { id, title, bodyMarkdown, tags: string[], createdAt, updatedAt }` (теги — как массив строк исходного написания, отсортированы).

**Tags**
| Метод/путь | Ответ |
|---|---|
| `GET /api/tags` | `200 {items: [{name, count}]}` — теги пользователя со счётчиком заметок (для чипов-фильтров и `datalist`) |

**Прочее**: `GET /health` → `200 {ok:true}` (без авторизации).

Валидация на сервере (NFR-7): заголовок ≤ 200, тело ≤ 100 000, теги ≤ 20 шт., длина тега ≤ 50, email-формат, пароль ≥ 8. Теги триммируются, пустые отбрасываются, дубликаты (регистронезависимо) схлопываются с сохранением первого написания (Q-T2).

Поиск (Q-S1/Q-S2): подстрочный, регистронезависимый, по `title` + `body_markdown` (исходный markdown), спецсимволы — как литералы (экранирование `%`/`_`), реализуется `LOWER() LIKE LOWER(?) ESCAPE '\'` + комбинация с `tag` через `EXISTS`.

### 3.3 Как фронтенд получает данные

`web/src/api/client.ts` — тонкая обёртка над `fetch` с `credentials: 'include'` (cookie). State-changing-запросы добавляют заголовок `X-CSRF-Token` из cookie `XSRF-TOKEN`. На `401` → сброс состояния и редирект на `/login` с сохранением целевого URL (DESIGN §1.2 поток B). Вид «плитки/список» — `localStorage["notes.view"] ∈ {grid,list}`, дефолт `grid` (только клиент, Q5a).

---

## 4. Модель безопасности

1. **Пароли** — bcrypt (cost 10) через `bcryptjs`; в ответах/логах никогда (NFR-9, A9).
2. **Сессии** — cookie `session` = opaque token (`crypto.randomBytes(32).base64url`), в БД — SHA-256 токена (токен не подписывается — секрет окружения не требуется, §4.7); флаги `HttpOnly`, `Secure` (когда `COOKIE_SECURE=true`, дефолт в prod; в локальном HTTP — выкл), `SameSite=Lax`, `Path=/`, срок 7 суток со скользящим продлением (Q-A3/Q-A4). Logout удаляет запись сессии.
3. **CSRF** (NFR-11, AC-15): double-submit — сервер выдаёт `csrf_token` в сессии и продублированный читаемый cookie `XSRF-TOKEN` (`SameSite=Lax`); клиент шлёт `X-CSRF-Token` на `POST/PATCH/DELETE`; middleware сверяет равенство с токеном сессии. Плюс `SameSite=Lax` как первый рубеж.
4. **Ownership** (NFR-6, AC-11…14): каждая операция с заметкой фильтруется `WHERE user_id = :uid`; чужой/несуществующий ресурс → `404` (не раскрывая существование, Q-A7).
5. **XSS** (NFR-5, AC-45…47): raw markdown хранится как текст (на сервере не рендерится в HTML); рендер только на клиенте через `markdown-it` → `DOMPurify` по allowlist (§8: `strong,em,code,pre,ul,ol,li,blockquote,h2–h4,a,hr,table,thead,tbody,tr,th,td,p`; `script/iframe/style/on*/javascript:` вырезаются, элемент вне allowlist — как текст). Один рендерер `.md` для превью (S4) и просмотра (S5) — AC-31. Теги/заголовки — только текстовые узлы (без `innerHTML`, AC-47).
6. **Rate limiting** (NFR-12, AC-6): in-memory лимитер на вход/регистрацию (ключ `ip+email`, ~5 неудач / 15 мин → 429 с `retryAfter`). Допустимо для однопроцессного деплоя; при горизонтальном масштабировании — внешнее хранилище (риск §5).
7. **Секреты** (NFR-8): значения — только env (`.env`, в `.gitignore`); в репозитории — `.env.example`. `SESSION_SECRET` **необязателен**: сессии — opaque-токен без подписи (п. 2), CSRF — сверка `csrf_token` (п. 3), поэтому секрет для целостности сессии не нужен; если задан в окружении — просто переносится в конфиг (совместимость с деплоем).

---

## 5. Риски и митигация

| # | Риск | Митигация |
|---|---|---|
| R1 | **SQLite vs PostgreSQL.** В проде/масштабе SQLite уступает Postgres (конкурентная запись, полнотекстовый поиск). | Слой `db/client.ts` изолирует SQL; схема ANSI-совместима; поиск на сотнях заметок (NFR-4) укладывается в `LIKE`. Переход на Postgres — отдельная задача (docker-скилл), не блокирует MVP. **Развилка для человека: если нужен PostgreSQL сразу — требуются Docker/psql в окружении.** |
| R2 | **Node 26 + native-модули** (bcrypt/argon2/better-sqlite3) могут требовать сборки на Windows. | Выбраны чистый JS (`bcryptjs`) и встроенный `node:sqlite` — нулевые native-зависимости. |
| R3 | **Cookie `Secure` в локальном HTTP.** На `http://localhost` cookie с `Secure` не отправляется. | Флаг управляется `COOKIE_SECURE` (false в dev, true в prod за TLS). |
| R4 | **Rate-limit в памяти** не разделяется между процессами/перезапусками. | Допустимо для однопроцессного деплоя; задокументировано как ограничение (T-12). |
| R5 | **Дрейф вёрстки от макета** (токены/классы). | `web/src/styles` — прямой перенос `mockups/styles.css`; имена классов/токенов — контракт (DESIGN §0); T-11 — финальный a11y/responsive-пас против макета. |
| R6 | **Расхождение превью/просмотра markdown** (AC-31). | Один `lib/markdown.ts` для обоих экранов (T-07), тест на идентичность рендера. |
| R7 | **Нет Docker в окружении** → нельзя проверить T-12 (контейнеризация) в этой песочнице. | T-12 верифицируется без Docker (прод-сборка + однопроцессный запуск Fastify со статикой); Dockerfile — как необязательный артефакт, проверяется в CI/вручную. |
| R8 | **Нет bash в окружении** (только PowerShell). | `init.sh` — канонический (Linux/CI/Git Bash); `init.ps1` — рабочий скрипт этой Windows-машины. Оба делают одно и то же. |

---

## 6. Окружение и команды

### 6.1 Подъём (`init.sh` / `init.ps1`)

1. Проверка инструментов: `node ≥ 22` (нужен `node:sqlite`), `npm`.
2. `npm install` в `server/` и `web/`.
3. `npm run migrate` в `server/` (применяет `migrations/*.sql` к `server/data/app.db`).
4. Проверка: `npm run test` (vitest, в T-01+ появится), `npm run build` (web).
5. Печать стартовых команд (dev: `npm run dev` в обоих; прод: `npm run build && npm start` в server).

### 6.2 Локальный запуск (dev)

```bash
# терминал 1 — бэкенд
cd server && npm run dev          # :3000
# терминал 2 — фронтенд
cd web && npm run dev             # :5173 (proxy /api → :3000)
```

### 6.3 Общая e2e-проверка (что гоняет QA, NFR-28)

Скрипт `server/scripts/e2e-smoke.mjs` (fetch, cookies, CSRF) — сценарий пользователя по SPEC NFR-28:
`регистрация → me → создание заметки с тегами → список → поиск по тексту → фильтр по тегу (и комбинированно) → переключение вида (клиент) → редактирование → удаление → logout` + **изоляция**: второй пользователь не видит заметок первого, доступ к чужой заметке по id → 404.

Запуск: `node server/scripts/e2e-smoke.mjs` (против `http://localhost:3000`). Дополнительно QA проходит UI-сценарий в браузере (маршрут full): регистрация → список → создание → markdown-превью → переключение вида → поиск/фильтр → редактирование → удаление → выход; плюс ручная проверка a11y (§5 DESIGN) и адаптивности (брейкпоинты 1280/1024/860/640).

---

## 7. Декомпозиция

См. `TASKS.json` (12 задач). Порядок: **БД (T-01) → бэкенд (T-02→T-05) → фронтенд (T-06→T-11, частично параллельно) → деплой (T-12)**.
Параллельность: T-06 (фронт-фундамент+auth) стартует после T-03; T-07 (рендерер) после T-06; T-08 (список) после T-05+T-06; T-09 (редактор) после T-05+T-07; T-10 (просмотр) после T-07+T-08; T-11 (a11y/responsive) после T-08..T-10; T-12 (деплой) после T-05+T-11.

Стек-скиллы (ровно один на задачу): T-01 — `postgres` (SQL-дисциплина; реализация SQLite через `node:sqlite`), T-02..T-05 — `typescript-node`, T-06..T-11 — `react`, T-12 — `docker`.

Общие критерии SPEC (AC-1…AC-47, NFR-*) проверяются QA **после** всех задач (гейт приёмки), а не внутри отдельной задачи.

---

## 8. Открытые вопросы к человеку (не блокируют старт)

1. **БД**: подтвердить SQLite для MVP (PostgreSQL требует Docker/psql, которых нет в окружении). См. R1.
2. DESIGN §12 (не блокируют): горячие клавиши toolbar в MVP? поведение toolbar на мобильном? счётчики у чипов тегов? сортировка в UI? формат дат «сегодня/вчера»?
3. Локаль интерфейса — русская (Q13), подтвердить.
4. Git-identity для коммитов агентов: имя/email (сейчас не настроены — baseline делаю с локальным `Planner Agent <planner@agentic-workflow.local>`).

---

## 9. Definition of Done (для Orchestrator)

- `init.sh`/`init.ps1` поднимают окружение и завершаются 0 на чистой Windows-машине.
- `server/scripts/e2e-smoke.mjs` проходит полный сценарий NFR-28.
- Все задачи `TASKS.json` в `done`; общие критерии SPEC закрыты QA (гейт приёмки); `REVIEW.md` + PR (гейт 3) перед merge.
