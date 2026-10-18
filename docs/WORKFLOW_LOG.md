# Workflow Log — Пиксельная метроидвания Gothic

## 2026-10-14 — Orchestrator: Триаж

- **Действие:** Триаж вводной «пиксельная метроидвания на Godot в стиле Gothic»
- **Результат:** Создан `docs/TICKET.md`. Категория: gamedev/godot, маршрут: full.
- **Решение:** Делегировать Analyst для подготовки требований (`docs/SPEC.md`).
- **Следующий гейт:** Гейт 1 — утверждение требований человеком.

## 2026-10-14 — Orchestrator: Приёмка Analyst

- **Действие:** Получен результат Analyst (subagent `ses_ec8a530e5ffesJLhSNkVJpT1Le`).
- **Результат:** `docs/SPEC.md` создан (черновик, 9 user stories, acceptance criteria, core mechanics, world design, art direction, NFR, 14 edge cases, 9 открытых вопросов).
- **Решение:** Сохранены артефакты (`docs/SPEC.md`, `docs/index.md`). Ожидание человека на гейте 1.
- **Следующий гейт:** ⏳ Гейт 1 — утверждение требований человеком (Q1–Q9).

## 2026-10-14 — Гейт 1: Требования утверждены (человек)

- **Ответы Q1–Q9:**
  - Q1: Фракции и прокачка — в MVP.
  - Q2: 5 зон, 3 способности, **5 боссов**.
  - Q3: Сохранения у костров, в бою нельзя.
  - Q4: ПК (Win/Linux), железо ~2020 г.
  - Q5: Оригинальный сеттинг.
  - Q6: **Потеря всего инвентаря** с corpse run.
  - Q7: Русский + английский.
  - Q8: Свой арт + CC0.
  - Q9: Один репо.
- **Решение:** SPEC обновлён. Запуск Designer для макетов (`docs/mockups/` + `docs/DESIGN.md`).

## 2026-10-14 — Orchestrator: Приёмка Designer

- **Действие:** Получен результат Designer (subagent `ses_ec89e1715ffef57VOgWU0XngRd`).
- **Результат:**
  - `docs/mockups/` — 8 HTML-макетов: главное меню, HUD, смерть, инвентарь, костёр, деревня-бастион, index
  - `docs/DESIGN.md` — черновик: 27 цветов, шрифты, отступы, слои, анимации, 15 состояний персонажа, a11y-чеклист
- **Особые отметки Designer:**
  - Шрифт Press Start 2P (OFL) использован как заглушка — нужен свой CC0 растровый шрифт
  - Рабочее название «Пепельный Бастион» — требует утверждения
  - Разрешение выбрано 480×270 (а не 320×180) для читаемости кириллицы
  - Не нарисованы: ремап управления, полная карта, вкладки «Журнал»/«Фракции»/«Карта»
- **Решение:** Ожидание человека на гейте 2 (макеты).

## 2026-10-14 — Гейт 2: Макеты утверждены (человек)

- **Ответы:**
  - Название «Пепельный Бастион» — оставляем.
  - Недостающие макеты (ремап, карта, журнал/фракции) → в план, делать сразу в Godot.
  - Разрешение 480×270 — ок.
  - Шрифт Press Start 2P — оставляем (не для продажи).
- **Решение:** Запуск Planner для `docs/PLAN.md`, `docs/TASKS.json`, `docs/init.sh` и baseline-коммита.

## 2026-10-14 — Orchestrator: Приёмка Planner

- **Действие:** Получен результат Planner (subagent `ses_ec88b6799ffepAaB7Q3Dz477f1`).
- **Результат:**
  - `docs/PLAN.md` — архитектура (Godot 4.4+, GDScript, autoload-синглтоны, слои), 12 этапов, техрешения
  - `docs/TASKS.json` — 37 задач (T-01…T-37): devops×2, backend×20, frontend×10, dba×4, qa×1
  - `docs/init.sh` + `docs/init.ps1` — скрипты подъёма окружения
  - Baseline-коммит `f14db84`
  - Стек-скилл `godot` добавлен
- **⚠️ Предупреждение:** Godot не установлен. Нужен Godot 4.4+ до этапа 1 (T-03+).
- **Решение:** Начало реализации. Первые задачи — T-01/T-02 (инициализация Godot-проекта).

## 2026-10-14 — T-01 выполнен (tasker-devops)
- Коммит `78be26f`. Godot 4.4.1 portable, GUT 9.4.0, 10 autoload-заглушек, Main.tscn, InputMap. Верификация headless: import + quit + GUT smoke — OK.
- T-02 и T-03 разблокированы. Запуск параллельно.

## 2026-10-14 — T-02 выполнен (tasker-devops)
- CI: `.github/workflows/ci.yml` (test + export), `game/export_presets.cfg` (Win/Linux release).
- ⚠️ Экспорт-шаблоны 4.4.1 ещё докачиваются; пресеты проверены парсингом.

## 2026-10-14 — T-03 выполнен (tasker-backend)
- Коммит `b806feb`. InputManager.gd, input_buffer.gd, ремап, coyote time, device_changed.
- GUT: 12/12 passed, 23 asserts.
- T-04 разблокирован.

## 2026-10-14 — Planner: План, декомпозиция, инициализация

- **Действие:** Проанализированы `docs/SPEC.md` (гейт 1), `docs/DESIGN.md` и `docs/mockups/` (гейт 2), состояние репозитория. Подготовлены артефакты инициализации.
- **Артефакты:**
  - `docs/PLAN.md` — архитектура Godot-проекта (`game/`), структура папок, autoload'ы, ключевые техрешения (физика/тайминги, ввод, способности, сохранения/checksum, смерть, локализация, освещение), этапы реализации, параллелизм, Zero Dead Config, риски, DoD.
  - `docs/TASKS.json` — 37 задач T-01…T-37 (init → игрок/ввод → способности → бой → зоны → UI/HUD → сохранения/смерть → фракции/NPC → боссы → карта → звук/атмосфера → локализация → QA) с acceptance-критериями, `dependsOn`, ролью (`assignee`) и стеком (`godot`). Граф — DAG, без искусственных зависимостей, проверен на циклы.
  - `docs/init.sh` + `docs/init.ps1` — идемпотентный подъём окружения: проверка рантайма Godot (`GODOT_PATH`/PATH/стандартные пути), подготовка `game/`, импорт ресурсов, headless smoke, прогон GUT. Отсутствие Godot — предупреждение, не ошибка.
  - `docs/index.md` — обновлён (статусы, артефакты, стек).
  - Стек-скилл `godot` добавлен в `~/.config/opencode/skills/godot/SKILL.md` (профильного навыка для GDScript в окружении не было).
- **Недостающие макеты** (решение гейта 2): ремап управления, полная карта, вкладки «Журнал»/«Фракции», экран выбора фракции — включены как задачи и реализуются напрямую в Godot (T-24, T-33).
- **Проверки:** `docs/TASKS.json` — валидный JSON, 37 задач, все `dependsOn` разрешаются, циклов нет; `docs/init.ps1` выполнен (exit 0, Godot отсутствует в окружении — предупреждение). `bash` в окружении недоступен, `init.sh` не запускался (зеркало `init.ps1`).
- **Риск для исполнения:** Godot 4.x не установлен (`C:\Program Files\Godot\Godot.exe` отсутствует) — требуется установить рантайм/задать `GODOT_PATH` до этапа 1 (T-03+).
- **Решение:** Baseline-коммит артефактов; передача Orchestrator для запуска задач.
- **Следующий гейт:** Реализация задач (Tasker'ы) → QA (T-37) → Гейт 3 (Merge).

## 2026-10-14 — tasker-devops: T-01 Каркас Godot-проекта и настройки рендера

- **Действие:** Реализована задача T-01 (`docs/TASKS.json`) по PLAN §2.1/§2.2/§2.3 и DESIGN §4.4.
- **Артефакты:**
  - `game/project.godot` — 480×270, stretch viewport/integer/keep, nearest-фильтр, физика 60 Гц, GL Compatibility, 10 autoload'ов в порядке PLAN §2.2 (EventBus → Config → Locale → InputManager → AudioManager → GameState → FactionManager → Journal → SaveManager → SceneRouter), InputMap (move_left/right/up/down, jump, attack, block, roll, dash, interact — клавиатура+геймпад; ui_* — навигация меню), слои 2D-физики задокументированы. Только используемые ключи (Zero Dead Config).
  - `game/Main.tscn` + `game/Main.gd` — WorldRoot + CanvasLayer'ы HUD=10, UI=20, Toasts=30, Overlay=40.
  - `game/autoload/*.gd` — 10 типизированных заглушек с документацией (ссылки на задачи-потребители).
  - `game/icon.svg`, `.gitignore` (корневой) и `game/.gitignore` (`.godot/`, `*.tmp`).
  - Полное дерево каталогов PLAN §2.1 (core/, entities/, world/, ui/, assets/, data/, tests/ — с `.gitkeep`).
  - `game/addons/gut/` — GUT v9.4.0 вендорен (последний релиз без требования Godot 4.5; совместим с целевыми 4.4/4.5).
  - Сгенерированы и закоммичены `.uid`/`.import` (Godot 4.4 требует их в репозитории).
- **Проверки (Godot 4.4.1-stable, portable в temp, headless):**
  - `--headless --import` — exit 0, без ошибок; `game/.godot/` создан; docs/ не сканируется (вне корня проекта `game/`).
  - `--headless --quit` — exit 0, Main.tscn загружается без ошибок.
  - Скрипт-проверка: настройки рендера/физики, порядок autoload'ов (ProjectSettings + runtime-дети root), все действия InputMap, структура Main.tscn (WorldRoot + слои 10/20/30/40) — `T01_VERIFY_OK`; временный скрипт удалён.
  - GUT smoke: `-s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` — exit 0 (0 тестов), команда CI (T-02) валидна.
- **Примечания:** Godot в окружении не установлен — каркас проверен portable-сборкой 4.4.1 во временном каталоге (в систему не устанавливался); `docs/init.ps1` найдёт Godot через `GODOT_PATH`. Статус задачи остаётся `pending` — отметит QA/Guardian по гейтам.
- **Следующий шаг:** T-02 (CI + export_presets) — разблокирована.

## 2026-10-14 — tasker-devops: T-02 CI и экспорт-пресеты (Windows/Linux)

- **Артефакты:**
  - `.github/workflows/ci.yml` — джоба `test` (кэш Godot portable → `--headless --import` → GUT `-gdir=res://tests -ginclude_subdirs -gexit`) и джоба `export` (needs: test; шаблоны 4.4.1 из официального `.tpz` в `~/.local/share/godot/export_templates/4.4.1.stable/` → импорт → `--export-release "Windows Desktop"` и `"Linux"` → проверка артефактов → upload). Godot — portable-сборка через `GODOT_PATH` (конвенция `docs/init.*`); шаблоны и редактор кэшируются по версии. Триггеры: push (main, v2) + все PR; concurrency-cancel.
  - `game/export_presets.cfg` — пресеты «Windows Desktop» (`build/windows/AshenBastion.exe`) и «Linux» (`build/linux/AshenBastion.x86_64`): release-режим, `debug/export_console_wrapper=0`, PCK встроен (`embed_pck=true`), `exclude_filter="addons/gut/*,tests/*"` (GUT и тесты не попадают в поставку), `application/modify_resources=false` (rcedit недоступен headless без wine — иначе предупреждение сборки; иконка/название берутся из project.godot в рантайме).
  - `game/.gitignore` — добавлен `build/` (артефакты экспорта не коммитятся).
- **Проверки (Godot 4.4.1-stable portable, headless, эквивалент шагов CI):**
  - `--headless --import` — exit 0. GUT — exit 0. `actionlint` по workflow — exit 0.
  - Экспорт-шаблоны 4.4.1 скачаны (1150 МБ .tpz) и установлены в стандартный каталог → `--export-release "Windows Desktop"` — exit 0, без ошибок/предупреждений (93 МБ exe, PCK встроен); `--export-release "Linux"` — exit 0 (66.5 МБ, ELF-магия валидна). Smoke exe: `AshenBastion.exe --headless --quit` — exit 0.
  - Оба экспорта запускались на текущем рабочем дереве, включающем незакоммиченную реализацию InputManager из параллельной T-03.
- **Найденные и исправленные проблемы:**
  1. `game/autoload/InputManager.gd` (файл T-03, изменён параллельно): `class_name InputManager` конфликтовал с именем autoload («Class "InputManager" hides an autoload singleton») — скрипт не компилировался, экспорт падал. Убрал `class_name` (канон для autoload); `game/tests/unit/test_input_manager.gd` переключён на `preload("res://autoload/InputManager.gd")` как тип. ⚠️ Встречные правки чужих файлов — на контроль Guardian.
  2. export_presets.cfg: многострочные `ssh_remote_deploy/run_script|cleanup_script` с неэкранированными внутренними кавычками ломали парсер ConfigFile (ключ `[preset.1]` «съедался» → пресет Linux не загружался, «Invalid export preset name»). Экранировано как делает редактор Godot (`\"`). Проверено дампом ConfigFile: оба пресета читаются.
  3. GUT без `-ginclude_subdirs` молча гоняет 0 тестов при тестах в `tests/unit/` (exit 0 — ложный зелёный). В CI добавлен флаг.
  4. Godot не создаёт каталоги экспорта → в CI добавлен `mkdir -p game/build/{windows,linux}`.
- **Известное, вне скоупа T-02:** тест T-03 `test_device_changed_keyboard_event` падает (сигнал `device_changed` не эмитится при событии клавиатуры) — поведенческая логика InputManager, домен tasker-backend (T-03 в работе). CI-инфраструктура к этому готова.
- **Коммит:** T-02-артефакты + минимальные кросс-фиксы (п.1) + файлы `game/core/input/input_buffer.gd` и `game/tests/unit/test_input_*.gd` параллельной T-03 — включены в коммит, т.к. закоммиченный `InputManager.gd` ссылается на глобальный класс `InputBuffer` (без них HEAD не компилируется). Статус задачи остаётся `pending` — отметит QA/Guardian.

## 2026-10-14 — tasker-backend: T-03 InputSystem

- **Действие:** Реализована задача T-03 (`docs/TASKS.json`) — полноценный автозагрузчик `game/autoload/InputManager.gd`.
- **Артефакты:**
  - `game/core/input/input_buffer.gd` — класс `InputBuffer` (150 мс окно), API `press`/`is_pressed`/`just_pressed`/`get_buffer_time`.
  - `game/autoload/InputManager.gd` — unified `is_pressed`/`just_pressed` с учётом буфера, `press_buffered`, coyote-time helpers (`start_coyote_time`, `is_coyote_time_available`, `consume_coyote_time`, `just_pressed_or_coyote`, 0.1 с), `get_action_strength` для аналогового ввода, ремап действий через `InputMap`, сохранение/загрузка в `user://settings.cfg` (атомарная запись temp → rename), `reset_to_defaults`, определение активного устройства (keyboard/xbox/playstation/gamepad) и сигнал `device_changed`. Ключи не хардкодятся.
  - `game/tests/unit/test_input_buffer.gd` — 6 GUT-тестов на буфер.
  - `game/tests/unit/test_input_manager.gd` — 6 GUT-тестов: персистентность ремапа, сброс к дефолтам, coyote-time, `just_pressed_or_coyote`, переключение устройства keyboard/gamepad.
  - `game/addons/gut/gut_loader.gd` — кросс-фикс совместимости с Godot 4.7: fallback на `false`, если настройка `debug/gdscript/warnings/exclude_addons` отсутствует (в 4.7 заменена на `directory_rules`).
- **Проверки (локально Godot 4.7.2-stable portable, headless):**
  - GUT: `-gdir=res://tests/unit -ginclude_subdirs -gexit` — **12/12 тестов passed**, 23 asserts.
  - Smoke-запуск проекта `--headless --path game` — стартует без ошибок/скрипт-ошибок.
- **Найденные и исправленные проблемы:**
  - `test_device_changed_keyboard_event` падал, т.к. `active_device` по умолчанию уже `keyboard`; сигнал не эмитился. Исправлено: в тесте устанавливается `DEVICE_GENERIC` перед эмитацией клавиатурного события.
  - `remap_action` принимает `Array[InputEvent]`; передача `[new_jump]` вызывала ошибку typed array — исправлено явным приведением `var events: Array[InputEvent] = [new_jump]`.
- **Коммит:** `b806feb` «T-03: InputSystem — буфер ввода, ремап, устройства, coyote-time». Статус задачи остаётся `pending` — отметит QA/Guardian по гейтам.

## 2026-10-18 — Orchestrator: Продолжение реализации (checkpoint/resume)

- **Действие:** Возобновление после паузы. Сверено состояние по журналу и `docs/TASKS.json`.
- **Состояние:** T-01/T-02/T-03 выполнены (артефакты + коммиты `78be26f`, `b806feb`; статусы `pending` до зелёных гейтов). Гейты 1 и 2 пройдены человеком.
- **Готовые к запуску задачи (dependsOn выполнены):** T-04 (игрок), T-13 (тайлсеты), T-18 (тема), T-25 (сейвы), T-34 (аудио). Проверено: пересечений по файлам между ними нет.
- **Решение:** Запуск первой волны из 2 фоновых задач параллельно — **T-04** (backend: контроллер игрока + FSM, критический путь этапов 1–3) и **T-13** (dba: тайлсеты/ZoneData, фундамент зон этапа 4).
- **Следующие волны:** T-18 + T-25, затем T-34; далее строго по графу зависимостей (T-05/T-06/T-10 после T-04; T-14…T-16 после T-13; и т.д.).
- **Примечание по окружению:** Godot в системе не установлен — Tasker'ы используют portable-сборку (4.4.x/4.7.x) во временном каталоге через `GODOT_PATH` (конвенция `docs/init.*`, см. логи T-01/T-03).

## 2026-10-18 — T-04 выполнен (tasker-backend)

- **Skills:** загружен `godot` (GDScript, CharacterBody2D, FSM, GUT — профильный стек задачи). Другие skills не требовались.
- **Действие:** реализован контроллер игрока и FSM по PLAN §2.1/§3.1–3.2, DESIGN §7.
- **Реализовано:**
  - `data/balance/balancing.tres` + `BalancingParams` — единый источник: V_walk=90, H_jump=32, t_apex=0.35 (vy0≈182.86, g≈522.45 — выводятся формулами), H_double-фактор, D/T/C_dash, V_wall_slide, T_parry, E_attack/E_block/E_roll, t_attack/t_hurt/t_land/t_death, v_roll и окно i-frames переката (0.07–0.35 s = кадры 2–5).
  - `entities/player/Player.tscn` — CharacterBody2D, хитбокс 10×20 (RectangleShape2D), слой player/mask world, программная заглушка 16×24, дочерний `StateMachine`.
  - `entities/player/Player.gd` — ручная гравитация velocity-Verlet (высота прыжка H_jump без дрейфа), движение V_walk, прыжок/перекат/атака/блок/dash через `InputManager` (без дублирования InputMap), coyote-time, буфер, facing, `is_invulnerable()`, `apply_hurt()/kill()`.
  - `PlayerStateMachine.gd` + `states/` (idle, run, jump, fall, land, attack, block, roll, dash, hurt, death): `request_state()` пропускает только строго высший приоритет, `force_state()` — жизненный цикл внутри тира. Порядок: Death 100 > Hurt 90 > Roll/Dash 80 > Attack/Block 60 > Jump/Fall 50 > Land 30 > Run 10 > Idle 0.
  - `GameState`: выносливость (stamina_max из balancing.tres, `try_spend_stamina`/`restore_stamina`/`reset_stamina`); `EventBus`: `player_state_changed`, `stamina_changed`, `player_died`.
- **Верификация (portable Godot 4.4.1):**
  - `--headless --import` — OK, без ошибок.
  - `docs/init.ps1` (import + smoke + GUT) — OK.
  - GUT: **24/24 passed, 95 asserts** (было 12/23; +12 тестов T-04, 0 падений). Покрыто: значения из balancing.tres, старт движения за 1 кадр, высота прыжка ±1 px, jump→fall→land, idle↔run, attack/block, приоритеты Hurt/Death/Roll, i-frames переката (кадры 2–5) и списание E_roll один раз, отказ переката без выносливости.
  - Smoke `--headless --path game --quit` — OK, скрипт-ошибок/варнингов нет.
- **Найденные и исправленные проблемы:**
  - Ручной вызов `_physics_process()` из GUT использует idle-delta (0.15 s) для `move_and_slide()`, из-за чего высота прыжка была 237 px. Тесты переведены на реальные `await physics_frame` (60 Hz).
  - Гравитация половинными шагами до/после state-update давала Euler-сумму и апекс 33.6 px (пре-шаг затирался импульсом прыжка). Полушаг перенесён после state-update → velocity-Verlet, апекс в пределах ±1 px.
  - `block` буферизовался как одноразовое действие и «залипал» после отпускания; убран из буфера (блок — удерживаемое действие).
  - `docs/init.ps1` / `init.sh` запускали GUT без `-ginclude_subdirs` → «Nothing was run» с кодом 0. Добавлен флаг; init теперь реально прогоняет 24 теста.
- **Кросс-файловые правки:** `autoload/EventBus.gd` (3 сигнала), `autoload/GameState.gd` (выносливость), `autoload/InputManager.gd` (`capture_buffer()` — арминг 150-мс буфера по физическому нажатию), `docs/init.ps1`, `docs/init.sh`.
- **Замечание для следующих задач:** состояние `dash` реализовано как задел (D_dash/T_dash, i-frames), но ещё не гейтится способностью — это T-07; `attack`/`block` — каркас без хитбоксов/парирования (T-10/T-11); `t_parry`/`v_wall_slide` заведены в баланс под T-08/T-11.
- **Коммит:** `c8f684e` «T-04: контроллер игрока + FSM». Статус задачи остаётся `pending` — отметит QA/Guardian по гейтам.
