# QA — независимая приёмка фичи «Сервис заметок»

> Владелец: **QA**. Выход гейта приёмки (дизайн-док §6.6, маршрут `full`).
> Вход: реализация T-01…T-12 (коммит `5184948`), `SPEC.md`, `DESIGN.md`, `PLAN.md` §6.3, `TASKS.json`, `PROGRESS.md`.
> Метод: независимый прогон — прод-сервер (Fastify, один процесс API + SPA), реальный браузер (Chrome via chrome-devtools MCP), отдельные API-проверки, рестарт сервера.

## 1. Scope / окружение

| Параметр | Значение |
|---|---|
| Фича | «Сервис заметок»: auth + CRUD + теги + поиск/фильтр + markdown-превью + 2 вида списка |
| Коммит | `5184948` (HEAD), T-01…T-12 done |
| ОС / Node | Windows, Node v26.11.1, npm 11.20.0 |
| Прод-режим | NODE_ENV=production, PORT=3000, SESSION_SECRET (env), Secure-cookie |
| Браузер | Google Chrome через MCP chrome-devtools |

## 2. Команды воспроизведения

```powershell
cd server; npm run build:web
$env:NODE_ENV='production'; $env:SESSION_SECRET='...'; $env:PORT='3000'
$env:DATABASE_PATH="$env:TEMP\opencode\qa-notes.db"; npm start
node server/scripts/e2e-smoke.mjs
# UI — Chrome по http://127.0.0.1:3000
```

## 3. e2e-smoke.mjs (NFR-28)

**PASS — 28/28**, exit 0. Покрыто: health, SPA тем же процессом, register/cookie/me, CSRF-403, заметка с тегами, список, поиск (регистронезависимо), фильтр по тегу, комбинация, /api/tags, PATCH+персистентность, изоляция B (пустой список, 404 на чужой GET/PATCH/DELETE), DELETE+404, logout+me→401.

## 4. UI-сценарий (Chrome, как пользователь)

| # | Шаг | Результат |
|---|---|---|
| 1 | Guard /notes → /login | PASS |
| 2 | Регистрация → авто-вход | PASS |
| 3 | Empty-state A | PASS |
| 4 | Создание заметки (заголовок+2 тега+markdown) | PASS |
| 5 | Markdown-превью (h2/strong/ul) | PASS |
| 6 | Сохранение → «Сохранено …» | PASS |
| 7 | Диалог несохранённых правок | PASS |
| 8 | Карточка/строка, теги, дата | PASS |
| 9 | Переключение вида + localStorage + reload | PASS |
| 10 | Поиск по тексту (debounce) | PASS |
| 11 | Фильтр по тегу | PASS |
| 12 | q+tag (пусто) → empty-state B | PASS |
| 13 | Сброс фильтров | PASS |
| 14 | Просмотр S5 (один h1, article.md) | PASS |
| 15 | XSS-санитизация | PASS |
| 16 | Удаление: отмена/Esc/подтверждение | PASS |
| 17 | Выход | PASS |
| 18 | Изоляция 2-го пользователя | PASS |
| 19 | Empty-заметка в UI → алерт | PASS |
| 20 | Rate-limit в UI (6-я → баннер+disabled) | PASS |
| 21 | Responsive (1400 split / 640 tabs) | PASS |
| 22 | Console | PASS (0 ошибок) |

## 5. Независимые API-проверки

40/40 по существу. Auth (register/me/409/422/401 обобщённо/logout), CSRF-403, cookie-флаги (session HttpOnly+SameSite=Lax+Secure; XSRF-TOKEN читаемый), валидация заметок (422, пустая, только заголовок/только текст), теги (trim/дедуп/лимиты 20/50), поиск/фильтр (подстрочный, регистронезависимый с кириллицей, `%` как литерал, q+tag «И»), ownership (404, B пуст), rate-limit (429+Retry-After 900), пароли bcrypt, логи без секретов.

## 6. Трассировка AC (SPEC)

AC-1..AC-8, AC-10..AC-18, AC-19..AC-33, AC-35..AC-47 — ✅ PASS. Частично/не проверено: **AC-9** (истечение сессии), **AC-34** (смена набора тегов в UI — покрыто тестами T-09), **NFR-1/3/4** (нагрузка 200–500).

## 7. Расхождения SPEC/DESIGN ↔ факт

1. **Навигация после создания заметки (MINOR, не блокер).** После создания Editor делает `navigate('/notes/:id/edit', {replace})` — остаётся в редакторе, а не возвращается на S5/S3 (DESIGN §1.2 Поток C). Задокументировано Tasker'ом T-09/T-10.
2. `favicon.ico` → 404 (informational).
3. Два CTA «Создать заметку» на S3 (шапка + empty-state) — не дефект.

## 8. Fail / воспроизведение

**Функциональных fail нет.** Единственный красный пункт первичного прогона — ошибка собственного ассерта QA (`total>=6` при фактических 5 заметках), не продуктовая регрессия.

## 9. Вердикт

**ГОТОВО к Guardian.** Fail: 0. Не проверено: AC-9, AC-34 (UI), NFR-1/3/4 (нагрузка). Минорное расхождение п.7.1 — не блокер.
