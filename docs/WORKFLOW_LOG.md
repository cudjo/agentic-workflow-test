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

## 2026-10-18 — T-04 выполнен (tasker-backend, приёмка Orchestrator)

- **Результат:** Контроллер игрока (CharacterBody2D + FSM). Коммиты `c8f684e`, `1b91f54`. GUT **24/24 passed, 95 asserts** (было 12/23; +12 тестов T-04). Portable Godot 4.4.1: import/init/smoke — OK.
- **Артефакты:** `game/data/balance/balancing.tres` (+`BalancingParams`), `game/entities/player/` (Player.tscn/Player.gd/PlayerStateMachine.gd/states/), GUT `test_player_movement.gd`, `test_player_fsm.gd`.
- **Кросс-файловые правки (на контроль Guardian):** `autoload/EventBus.gd` (+`player_state_changed`/`stamina_changed`/`player_died`), `autoload/GameState.gd` (выносливость), `autoload/InputManager.gd` (+`capture_buffer()`), `docs/init.ps1`/`init.sh` (+`-ginclude_subdirs` — фикс ложнозелёного GUT без тестов).
- **Замечания Tasker:** `dash`/`attack`/`block` — каркасы под T-07/T-10/T-11; `t_parry`/`V_wall_slide` заведены в баланс под T-08/T-11. Чужие untracked-файлы (`game/tests/_probe.gd`, `opencode.jsonc`) не трогал — взять на заметку для уборки перед гейтом.
- **Решение:** Разблокированы T-05, T-06 (после T-05), T-10, T-26 (частично). Слот освобождён → запуск **T-10** (боевое ядро) параллельно с продолжающейся T-13.

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

## 2026-10-18 — tasker-dba: T-13 Тайлсеты и пайплайн уровней + ZoneData

- **Skills:** загружен `godot` (GDScript, TileSet/TileMapLayer, Resource, GUT, headless-проверки — профильный стек задачи). Другие skills не требовались.
- **Действие:** реализована T-13 (`docs/TASKS.json`) по PLAN §2.1/§2.3/§3.6 и DESIGN §8.6. Арт отсутствует, поэтому тайлы — программные grayscale-заглушки за тем же контрактом (16×16, source id, atlas-координаты, физические слои, Terrain Sets); цвет задаёт палитра зоны из ZoneData через `modulate`.
- **Артефакты:**
  - `world/tilesets/zone_terrain.tres` — TileSet 16×16: 4 физических слоя (solid=world 1, one-way=world 1, ladder=interactable 128, hazard=256), 2 Terrain Sets (ground/platforms) по 5 палитрам зон, 16 side-вариантов ground на зону, custom data `tile_type`/`zone_index`; atlas 256×128, 105 тайлов.
  - `world/tilesets/terrain_tiles.gd` — контракт раскладки атласа (source id, строки/столбцы, mask↔peering bits), `tests/tools/build_level_pipeline.gd` — воспроизводимый генератор заглушек (атлас → TileSet → ZoneData → шаблон сцены; исключён из экспорта).
  - `world/zones/zone_data.gd` + `zone_palette.gd`/`zone_entry_point.gd`/`zone_exit.gd` — типизированные Resource'ы: id, display_name, палитра, ambient, tileset, точки входа, выходы/связи; `validate()` проверяет целостность.
  - `data/zones/zone_template.tres` — ZoneData-шаблон (палитра зоны 1, ambient 0.42, 2 входа, 2 выхода со связями zone_02_swamp/zone_01_village).
  - `world/zones/zone_scene.gd` + `zone_template.tscn` — WorldRoot-совместимый корень (Node2D/ZoneScene): применяет ВСЕ поля ZoneData (фон, ambient, tileset всех четырёх TileMapLayer'ов, modulate палитры, пламя костра), создаёт Marker2D входов и Area2D выходов, эмитит `zone_ready` и `EventBus.zone_entered(id, display_name)`. В шаблоне — демо-раскладка solid/one-way/ladder/hazard и все 4 props.
  - `world/props/` — bonfire, chest, door, rubble (scenes + typed scripts; rubble — StaticBody2D-блок с `blocking`).
- **Проверки (portable Godot 4.4.1-stable, headless):**
  - `--headless --path game --import` — exit 0, без ошибок; PNG-атлас и `.uid` импортированы/закоммичены.
  - GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **80/80 passed, 491 asserts** (включая 29 новых тестов T-13; тесты T-03/T-04/T-10 не сломаны).
  - Чистый HEAD-коммит в отдельном worktree (без незакоммиченных файлов T-10): GUT **53/53 passed, 353 asserts**, import exit 0 — коммит самодостаточен.
  - T-13 GUT: ZoneData — все поля/валидация; TileSet — слои/terrain sets/custom data/полигоны; физика — игрок стоит на solid, падает сквозь ladder/hazard и проходит one-way снизу, приземляется сверху; hazard/ladder-слои находятся shape-запросом; solid при `scale=2` даёт коллизию в масштабе (y=22); шаблон грузится `SceneRouter.instantiate_zone`, применяет поля, создаёт входы/выходы, эмитит `zone_entered` и `exit_requested`.
  - Smoke `--headless --path game --quit-after 90` — без скрипт-ошибок/варнингов.
- **Найденные и исправленные проблемы:**
  1. Новые `class_name` не видны в `-s`-скрипте до `--import` — пайплайн разбит на «атлас → import → TileSet/сцена».
  2. `ResourceSaver` встраивал TileSet в ZoneData и сцену (дублирование 30 КБ ×3) — после сохранения ресурс перечитывается с диска, теперь `ExtResource("zone_terrain.tres")`.
  3. `ZoneScene` ссылался на глобальный `EventBus`, из-за чего не грузился в tool-режиме без autoload'ов — эмиссия через `/root/EventBus` с проверкой сигнала (в рантайме/тестах тот же autoload).
  4. Проверка масштаба подтвердила: one-way-полигон с нужной намоткой блокирует сверху и пропускает снизу; целочисленный `scale=2` даёт корректную коллизию.
- **Кросс-файловые правки (на контроль Guardian):** `autoload/EventBus.gd` (+`zone_entered` — минимальный контракт для баннера T-14/загрузки T-17), `autoload/SceneRouter.gd` (+`instantiate_zone()` — только загрузка/проверка WorldRoot-совместимости; переходы/экран загрузки остаются T-17).
- **Замечание:** в рабочем дереве параллельно присутствовали незакоммиченные файлы T-10 (combat/) и приёмочная запись T-04 — в коммит T-13 не включались; `docs/TASKS.json` и статус задачи не менялись (`pending` до QA/Guardian).
- **Коммит:** `d1e46b9` «T-13: тайлсеты, ZoneData, props и шаблон зоны». Статус остаётся `pending` — отметит QA/Guardian по гейтам.

## 2026-10-18 — T-10 выполнен (tasker-backend)

- **Skills:** загружен `godot` (GDScript, Area2D-слои, Resource-данные, GUT/headless — профильный стек боевого ядра). Другие skills не требовались.
- **Действие:** реализовано боевое ядро T-10 по PLAN §2.1/§3.1, DESIGN §7, AC-03.1/AC-03.3.
- **Реализовано:**
  - `core/combat/combat_layers.gd` — единый источник битовых слоёв, совпадает с `[layer_names]` project.godot: player_hitbox=8 → mask enemy_hurtbox=64, enemy_hitbox=16 → mask player_hurtbox=32.
  - `core/combat/damage.gd` — формула `max(min_damage, weapon_damage * combo_multiplier * damage_multiplier - defense)`; значения из `balancing.tres`; отбрасывание импульсом в CharacterBody2D; вспышка спрайта жёстко ≤ 0.1 s (AC-03.1).
  - `core/combat/hitbox.gd` / `hurtbox.gd` — Area2D: хитбокс живёт на слое атакующего, маскирует hurtbox цели, бьёт каждого один раз за шаг; hurtbox применяет knockback/вспышку и поддерживает i-frames.
  - `core/combat/stamina.gd` — трата, восстановление после задержки в покое, флаг `exhausted` (HUD «НЕТ СИЛ»); `GameState` владеет экземпляром, транслирует `stamina_changed` в EventBus, HUD читает `GameState.is_stamina_exhausted()`.
  - `core/combat/combo.gd` — 2–3 удара, окно связки в конце шага, активная фаза хитбокса по долям; длительность шага = `t_attack * attack_speed`.
  - `data/weapons/weapon_data.gd` + `light_dagger.tres`/`one_handed_sword.tres`/`two_handed_axe.tres` — 3 типа оружия (лёгкое/одноручное/двуручное) с уроном, отбрасыванием, скоростью и множителями комбо.
  - `balancing_params.gd` + `balancing.tres` — группы Combat/Stamina: damage_multiplier, min_damage, hit_flash_duration=0.08, knockback_scale, combo_link_window=0.12, combo_hit_start/end_ratio, e_dash, stamina_regen_delay/rate.
  - `Player.gd` + `Player.tscn` + `states/attack.gd` — узлы Hitbox/Hurtbox, комбо из данных оружия, связка второго удара, трата E_attack/E_block/E_roll/E_dash, восстановление в locomotion-состояниях.
- **Верификация (portable Godot 4.7.2-stable, headless):**
  - `--headless --import` — exit 0, без ошибок.
  - GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **80/80 passed, 491 asserts** (+27 тестов T-10; 24 прежних T-03/T-04 зелёные; 29 тестов T-13 тоже зелёные).
  - `docs/init.ps1` (import + smoke + GUT) — exit 0.
  - Smoke `--headless --path game --quit` — exit 0, скрипт-ошибок/варнингов нет.
  - Боевой сценарий в GUT: удар по dummy впереди — ровно одно попадание, урон по формуле, knockback в velocity цели, вспышка видна и гаснет ≤ 100 мс, E_attack списан; цель за спиной не задета; при 0 выносливости атака не стартует и флаг поднят; второй удар связывается в окне и снова тратит E_attack; dash/block тратят E_dash/E_block; комбо конфигурируется из данных оружия.
- **Найденные/исправленные проблемы:**
  - Реген выносливости в `Player._physics_process` мог «доливать» её в T-04-тесте переката — задержка 0.8 s из balancing.tres исключает ложное срабатывание; реген покрыт отдельными тестами.
  - `area_entered` мог пропустить попадание при включении мониторинга поверх цели на коротком окне удара → опрос `get_overlapping_areas()` с дедупликацией.
  - Вспышка ограничена и в `Damage.compute()/create()`, и константой `HIT_FLASH_MAX_SEC` — данные не могут нарушить AC-03.1.
- **Кросс-файловые правки (на контроль Guardian):** `autoload/GameState.gd` (Stamina-делегат, текущее оружие, `is_stamina_exhausted()`, `update_stamina()`), `data/balance/balancing_params.gd` + `.tres`, `entities/player/Player.gd`/`Player.tscn`/`states/attack.gd`. `EventBus.gd` не менялся (его правка `zone_entered` пришла из T-13): флаг HUD доступен через GameState, существующего `stamina_changed` достаточно для полосы выносливости.
- **Замечания:** `e_dash` добавлен в баланс (потребитель — T-07); `defense` в формуле — параметр под броню/врагов (T-12/T-29), пока 0; `docs/TASKS.json` и статус не менялись (`pending` до QA/Guardian). Чужие файлы (`_probe.gd`, `opencode.jsonc`, T-13-артефакты) не трогал.
- **Коммит:** `1941388` «T-10: боевое ядро — урон/выносливость/комбо».

## 2026-10-18 — Orchestrator: Приёмка T-10, запуск T-18

- **T-10 принят:** боевое ядро (урон/выносливость/комбо), GUT **80/80, 491 asserts**, коммит `1941388`. Кросс-правки `GameState`/`balancing`/`Player`/`states/attack` — на контроль Guardian.
- **T-13:** запись в журнале и коммит `d1e46b9` присутствуют, GUT 80/80; финального уведомления сессии пока не получено. По коду/тестам зависимые зоны T-14…T-16 фактически разблокированы.
- **Решение:** слот освобождён (T-10) → запуск **T-18** (тема/токены/шрифт/UI-компоненты, frontend), независима от текущих world/combat-треков. После завершения T-13 — волна зон (T-14…T-16) + T-25.

## 2026-10-18 — Orchestrator: Приёмка T-13, запуск T-25

- **T-13 принят:** тайлсеты/ZoneData/props/шаблон зоны, коммиты `d1e46b9` + `77ac4bb`, GUT 80/80 (29 тестов T-13; самодостаточность подтверждена в worktree 53/53). Кросс-правки `EventBus` (+`zone_entered`) и `SceneRouter` (+`instantiate_zone()`) — на контроль Guardian.
- **Разблокированы:** T-14…T-16 (зоны 1–5), T-17 (после T-14).
- **Решение:** слот освобождён (T-13) → запуск **T-25** (SaveManager, backend), параллельно с продолжающейся T-18. Следом — волна зон T-14…T-16 и ветка способностей (T-05/T-06).

## 2026-10-18 — Orchestrator: Приёмка T-25, запуск T-12

- **T-25 принят:** SaveManager (3 слота, SHA-256 checksum, атомарная запись, миграции v0→v1), коммит `1e95c3a`, GUT **92/92, 570 asserts** (+12 тестов). Кросс-правка `EventBus` (+`save_completed`/`save_failed`/`slot_corrupted`) — на контроль Guardian.
- **Отметка:** Tasker T-25 зафиксировал parse-error в незакоммиченных файлах параллельной T-18 (`ui/components/slot.gd`) — на чистом HEAD ошибок нет; рабочий момент параллельной разработки, на контроль при приёмке T-18.
- **Разблокированы:** T-26 (смерть), T-27 (фракции), T-29 (прогрессия); частично T-20/T-23 (ждут T-18).
- **Решение:** слот освобождён (T-25) → запуск **T-12** (враги: базовый AI + 3–4 типа, backend), параллельно с продолжающейся T-18; задача на критическом пути боссов (T-12→T-30→T-31/T-32).

## 2026-10-18 — Orchestrator: Приёмка T-18, запуск T-05

- **T-18 принят:** тема/токены (27 цветов)/шрифт/9 UI-компонентов, коммит `ede182a`, GUT **126/126, 979 asserts** (+34 теста). Кириллица закрыта: актуальный релиз Press Start 2P содержит cyrillic (проверено `has_char`) + Tiny5-fallback. Кросс-правка `Main.gd` (тема окна) — на контроль Guardian.
- **Отметка:** T-18 зафиксировал parse-error в незакоммиченном `tests/unit/test_enemy_combat_e2e.gd` параллельной T-12 — на чистом HEAD `ede182a` ошибок нет; рабочий момент, проверяется при приёмке T-12.
- **Разблокированы:** T-20 (меню), T-23 (костёр), T-36 (локализация); частично T-19/T-21/T-22/T-24 (ждут T-06/T-26/T-27/T-29).
- **Решение:** слот освобождён (T-18) → запуск **T-05** (анимации/визуал игрока, frontend) — голова серийной цепочки способностей (T-05→T-06→T-07/T-08/T-09 + T-19), параллельно с T-12 (враги).

## 2026-10-18 — Orchestrator: Приёмка T-12, запуск T-14

- **T-12 принят:** враги (AI FSM + swift/heavy/ranged/undead + спавнер), коммит `e4f12cf`, GUT **142/142, 1183 asserts** (+16 тестов). AI без navmesh — обосновано платформенными патрулями (RayCast2D + leash + watchdog). Кросс-правки `EventBus` (+`enemy_died`), `balancing` (+тайминги врагов), `Player.gd`/`Player.tscn` (Hurtbox→Hurt, группа `player`) — на контроль Guardian.
- **Разблокированы:** T-30 (боссы) — частично, ждёт T-14.
- **Решение:** слот освобождён (T-12) → запуск **T-14** (зона 1 «Деревня-бастион», dba) — параллельно с T-05 (фронт); T-14 — бутылочное горлышко для T-30 (боссы) и T-17 (переходы).

## 2026-10-18 — Orchestrator: Приёмка T-05, запуск T-06

- **T-05 принят:** анимации/визуал игрока (AnimatedSprite2D + SpriteFrames, 18 анимаций, программные заглушки 16×24 ≤16 цветов), коммит `67ae3b0`, GUT **156/156, 1648 asserts** (+14 тестов). Кросс-правки `Config.gd` (+`no_flash`), `balancing` (+`anim_*`) — на контроль Guardian.
- **Разблокированы:** T-06 (способности) — ключ к T-07/T-08/T-09 и T-19 (HUD).
- **Решение:** слот освобождён (T-05) → запуск **T-06** (AbilitySystem + двойной прыжок, backend) — параллельно с T-14 (зона 1).

## 2026-10-18 — Orchestrator: Приёмка T-14, запуск T-30

- **T-14 принят:** зона 1 «Деревня-бастион» (хаб), коммит `7ac547f`, GUT **167/167, 1760 asserts** (+11 тестов). Палитра/макет соответствуют; выход на уступ требует двойного прыжка (48 px > 32 px). Кросс-правок нет (только новые файлы в `world/zones/`, `data/zones/`, `tests/`).
- **Разблокированы:** T-17 (переходы), T-30 (боссы).
- **Решение:** слот освобождён (T-14) → запуск **T-30** (Boss framework + боссы 1–2, backend) — голова глубочайшей цепочки боссов (T-30→T-31→T-32), параллельно с T-06 (способности).

## 2026-10-18 — T-25 выполнен (tasker-backend)

- **Skills:** загружен `godot` (типизированный GDScript, autoload, FileAccess/DirAccess, HashingContext, GUT/headless — профильный стек сохранений). Другие skills не требовались.
- **Действие:** реализован SaveManager по PLAN §2.1/§3.4, AC-05.1, EC-07/EC-14.
- **Реализовано:**
  - `autoload/SaveManager.gd` — 3 слота `user://saves/slot_{1..3}.json`; API `save_slot`/`load_slot`/`read_slot`/`get_slot_metadata`/`has_slot`/`delete_slot`; ошибки диска и повреждение возвращают `false` + сигнал, без вылета; `saves_dir` переопределяется только тестами.
  - `core/save/save_serializer.gd` — заголовок `{schema_version, checksum}`, SHA-256 через `HashingContext` по сырым байтам тела; сериализуются только реально существующие поля GameState: текущая выносливость и оружие (`WeaponData.id`/`resource_path`); загрузка оружия по пути, затем по id, затем дефолт; meta `zone_id`/`zone_name`/`level`/`play_time`/`saved_at_unix` + extras для UI.
  - `core/save/save_migrations.gd` — `CURRENT_VERSION = 1`, `migrate(version, body) -> {ok, reason, body}`; v0 (плоское тело) → v1 (`state`/`meta`); сейв новее билда → `schema_too_new`; v1-тело, помеченное v0, отклоняется; в шапке файла — контракт добавления полей T-26/T-27/T-29 (сериализатор + bump версии + шаг миграции + тест).
  - `autoload/EventBus.gd` — `save_completed(slot)`, `save_failed(slot, reason)`, `slot_corrupted(slot, reason)` для подтверждения/ошибок UI (T-22/T-23).
  - `tests/unit/test_save.gd` — 12 GUT-тестов: round-trip (stamina/weapon/meta), изоляция слотов и пустой слот, подмена checksum, подмена тела, обрезанный файл, перезапись, сбой записи при сохранном старом слоте (EC-14), миграция v0, отказ для новой/неверно помеченной схемы, SHA-256 vector, невалидный номер слота.
- **Проверки (portable Godot 4.4.1-stable, headless):**
  - `--headless --path game --import` — exit 0; `SaveSerializer`/`SaveMigrations` зарегистрированы, в наших файлах ошибок нет.
  - GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **92/92 passed, 570 asserts** (80 прежних + 12 новых), exit 0.
  - Smoke `--headless --path game --quit` — exit 0, без скрипт-ошибок/варнингов.
  - `docs/init.ps1` с `GODOT_PATH` — exit 0 (import + smoke + GUT).
  - Функциональный smoke в GUT: реальная запись/чтение `user://.../slot_N.json`, проверка заголовка, восстановления, метаданных и отказа при порче; тестовый каталог изолирован и очищается.
- **Найденные/исправленные проблемы:**
  1. `JSON.parse_string` печатал engine ERROR на обрезанном файле — заменён на `JSON.parse()` (возвращает Error без выброса), EC-07 без шума в логе.
  2. Checksum считается по сырому телу, а не по повторной сериализации: `JSON.stringify` сортирует ключи, а parse/stringify чисел не гарантирует байтовое равенство — проверка не зависит от форматирования.
  3. Перезапись существующего слота через `DirAccess.rename` проверена отдельным тестом (Windows); tmp удаляется и при успехе, и при ошибке.
  4. Повреждённый `schema_version` (v1-тело как v0) больше не приводит к молчаливой потере `state` — слот отклоняется.
- **Кросс-файловые правки (на контроль Guardian):** `autoload/EventBus.gd` (+3 сигнала). `GameState.gd` не менялся — сериализуются только существующие поля.
- **Замечания:** статус T-25 — `pending` (не менял, решение QA/Guardian). HP/инвентарь/позиция/фракции/квесты появятся в T-26/T-06/T-27/T-29 по контракту миграций. В рабочем дереве параллельно T-18: import печатает parse error в untracked `ui/components/slot.gd` — чужой in-progress файл, не трогал. Чужие untracked-файлы (`ui/…`, `assets/fonts/…`, `opencode.jsonc`) не трогал.
- **Коммит:** `1e95c3a` «T-25: SaveManager — слоты/checksum/миграции/атомарная запись».
- **Чистый HEAD (отдельный worktree):** import exit 0 без ошибок, GUT **92/92, 570 asserts** — коммиты самодостаточны, untracked-файлы T-18 на прогон не влияют.

## 2026-10-18 — T-18 выполнен (tasker-frontend)

- **Skills:** загружен `godot` (тема/Theme, FontFile/FontVariation, Control/CanvasItem `_draw`, GUT/headless, a11y-фокус — профильный стек UI). Другие skills не требовались: задача не трогает БД/сеть/React.
- **Действие:** реализованы токены, тема, шрифт и базовые UI-компоненты по DESIGN §4/§6 и a11y §9.2.
- **Реализовано:**
  - `ui/theme/tokens.gd` (`UITokens`) — 27 цветов DESIGN §4.1 (26 базовых + точечный `ok #8fa77c`), 4 размера/высоты строки (8/16/24/32, 12/16/24/32), отступы `sp-1…6`, safe-margin, паддинги, границы, геометрия шкал/слотов/портретов/диалога, `TYPE_SPEED=0.022`, WCAG-хелперы `contrast_ratio`/`is_readable`.
  - `ui/theme/main_theme.tres` (генератор `tests/tools/build_ui_theme.gd`) — `FontVariation` Press Start 2P + fallback Tiny5, default 8 px, type variations `H1/H2/Title/Muted/Gold/Danger/SteelLabel`, Button/Label/RichTextLabel/Tooltip/PanelContainer стили из токенов. 9-slice панели генерируются в рантайме (`UIStyle.panel_style`, текстура 16×16, margin 6), т.к. `ImageTexture` не сериализуется в `.tres`.
  - `ui/components/`: `AshenPanel` (9-slice: solid/glass/inset/danger, заклёпки), `AshenBar` (HP/выносливость/босс, сегменты 3+1, след урона ступенями, фазы 33/66, «НЕТ СИЛ»/«КРИТИЧНО»), `AshenSlot` (6 состояний §6.2, маркер/замок/«!», dashed empty), `AshenMenuItem` (каретка, hover=фокус, активное, disabled с причиной, toggle ползунком), `AshenTab`, `AshenToast` (success/danger, ✓/«!»), `AshenDialog` (портрет 52×52, печать 22 мс/символ, ответы 2×2, тег `[Орден+1]`, disabled-причина), `AshenKbd`/`AshenPrompt` (глиф по `InputManager.active_device`, Xbox/PS/клавиатура). Фокус: золотая рамка 2 px + внутренняя gold-9 + каретка/скобки; состояние дублируется формой/знаком/числом.
  - `ui/components/showcase/ComponentShowcase.tscn` — dev-витрина: HUD-кластер, меню, инвентарь с вкладками, два диалога, тосты, подсказки; каждый компонент применён ≥ 2 раз (проверяется GUT-обходом дерева).
- **Решение по шрифту RU/EN:** известная проблема «Press Start 2P без кириллицы» **не подтвердилась для актуального релиза Google Fonts**: metadata объявляет subset `cyrillic`, cmap содержит U+0410–U+044F и `Ё/ё` (проверено разбором TTF и GUT-тестом `Font.has_char`). Основной шрифт — Press Start 2P (OFL), fallback-цепочка — Tiny5 (OFL) для символов, которых в PS2P действительно нет (`✓ □ ○ △`) и как страховка от редких пропусков. Оба `.ttf` + `.import` (с UID ресурса внутри), лицензии OFL и `assets/fonts/README.md` закоммичены; `allow_system_fallback=false`, `antialiasing=0`, `hinting=0`, `subpixel_positioning=0` — пиксельный рендер без подмены системными шрифтами.
- **Проверки (portable Godot 4.4.1-stable):**
  - `--headless --path game --import` — exit 0, ошибок нет (на чистом worktree с удалённым `.godot` тоже).
  - GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **126/126 passed, 979 asserts**, exit 0 (92 прежних + 34 новых: 14 `test_theme.gd`, 20 `test_ui_components.gd`).
  - Clean worktree HEAD `21a28db` + только файлы T-18 — тот же результат 126/126; чужие изменения T-12/T-25 не влияют.
  - Smoke `--headless --path game --quit` — exit 0; `--headless --path game res://ui/components/showcase/ComponentShowcase.tscn --quit-after 10` — без скрипт-ошибок.
  - Визуальный smoke: окно 960×540, `ComponentShowcase` — рендер без engine-ошибок; проверены состояния Slot/Bar/Tab/Dialog/Toast/Kbd, фокус-каретка, меню с причиной disabled.
- **Найденные/исправленные проблемы:**
  1. `slot.gd`: `icon` конфликтовал с нативным `Button.icon` — переименовано в `item_icon`.
  2. Сеттеры `AshenBar.value/max_value` присваивали параметр `value` вместо поля — шкалы не обновлялись; заменено на именованные параметры и прямое присваивание поля.
  3. `AshenDialog` при `instant_text` не завершал печать (guard в `_finish_typing`) — исправлено, добавлен публичный `advance_typing`/`select_answer` для тестов.
  4. `Main` + `gui/theme/custom` ломали первый `--import` на чистом клоне (тема грузила неимпортированные шрифты → ERROR). Тема назначается `Window.theme` в `Main._ready`; витрина ставит тему сама. Это устранило ошибки import и сохранило наследование темы всеми Control под Main.
  5. Disabled-причина в MenuItem рисовалась поверх строки — вынесена второй строкой, высота строки 28 px; «!»/замок/маркер слота выровнены по токенам.
- **Кросс-файловые правки (на контроль Guardian):** `game/Main.gd` (назначение темы окну). `project.godot` не изменён (отказались от `gui/theme/custom` ради чистого import). `docs/TASKS.json` и статус не менялись (`pending` до QA/Guardian).
- **Замечания:** в `docs/WORKFLOW_LOG.md` на момент записи были незакоммиченные строки Orchestrator (приёмка T-25) — они вошли в тот же коммит журнала как часть append-only истории; игровые файлы T-12/T-25 и untracked `opencode.jsonc` не трогал.
- **Коммит:** «T-18: тема, токены, шрифт и UI-компоненты».

## 2026-10-18 — T-12 выполнен (tasker-backend)

- **Skills:** загружен `godot` (типизированный GDScript, CharacterBody2D/FSM, Area2D-боёвка, Resource-данные, GUT/headless — профильный стек задачи). Другие skills не требовались.
- **Действие:** реализованы враги по TASKS T-12, PLAN §2.1/§3.1, SPEC US-03; переиспользовано боевое ядро T-10 (`CombatLayers`/`Hitbox`/`Hurtbox`/`Damage`).
- **Реализовано:**
  - `core/ai/state_machine.gd` — `EnemyStateMachine`: состояния patrol/chase/attack/hurt/death, приоритеты Death 100 > Hurt 90 > Attack 60 > Chase 50 > Patrol 0; `request_state()` только вверх по приоритету, `force_state()` — завершение атак/отшатывания; Death терминален.
  - `data/enemies/enemy_data.gd` + 4 `.tres` — HP, урон, скорости, радиусы (detect/attack/leash/preferred), тайминги патруля/атаки, размеры тел/хитбоксов, цвет заглушки, снаряд, возрождение; `is_valid()` ловит битые данные.
  - `entities/enemies/base/enemy.gd` + `enemy.tscn` — CharacterBody2D, ручная гравитация, FSM-тики, патруль с разворотом у стены/края (RayCast2D), погоня, telegraph/active/recovery атаки, hurt/death, отбрасывание с сопротивлением, poise, leash-зажим и watchdog против залипания. Реакция на урон — вспышка в том же physics-кадре (≤ 16.7 мс, лимит T-10 100 мс). Смерть: fade/squash `balancing.enemy_death_duration`, затем `EventBus.enemy_died`.
  - `base/enemy_spawner.gd/.tscn` + `enemy_spawn_entry.gd` — спавн групп из данных; точка спавна становится home (центр патруля/leash), учёт `died`, `remaining_count()`, сигнал `all_defeated`; возрождённая нежить не считается побеждённой.
  - 4 типа (сцена-наследник base + тонкий скрипт): `swift` (рывок в активной фазе), `heavy` (высокое HP/poise 8, широкий удар, супер-армор к отбрасыванию в замахе), `ranged` (держит `preferred_distance`, отступает, стреляет `enemy_projectile.tscn` через Hitbox слоя enemy_hitbox → player_hurtbox), `undead` (возрождение 1 раз с долей HP после анимации смерти).
  - Тесты: `tests/unit/test_enemy_fsm.gd` (10 тестов: чистая FSM, данные, слои, патруль у края, chase↔patrol, leash, watchdog, сцена hurt/death) и `tests/unit/test_enemy_combat_e2e.gd` (6 тестов: урон игрок→враг с вспышкой/hurt/knockback/смертью, урон враг→игрок, ranged-снаряд, poise/супер-армор heavy, revive undead, encounter из 5 врагов через EnemySpawner до `all_defeated`).
- **Выбор AI-подхода:** без NavigationAgent2D/navmesh. Уровни — простые прямые/платформенные пути (PLAN T-12), поэтому достаточно горизонтального движения + RayCast2D (край платформы и стена), leash от точки спавна и watchdog-разворота. Это детерминированно, дёшево для 5+ врагов и тестируется headless; навмеш добавил бы карты/перепекание без пользы для платформенных патрулей.
- **Проверки (portable Godot 4.7.2-stable, headless; код 4.4-совместим, без API 4.5+):**
  - `--headless --path game --import` — exit 0, ошибок/parse error нет.
  - GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **142/142 passed, 1183 asserts**, exit 0 (126 существующих T-01…T-18 + 16 новых T-12).
  - Smoke `--headless --path game --quit` — exit 0, без скрипт-ошибок.
  - Чистый HEAD `e4f12cf` в отдельном worktree (без untracked-файлов): import exit 0, GUT **142/142, 1183 asserts**, smoke exit 0.
- **Найденные/исправленные проблемы:**
  1. `EnemyData.patrol_pause` отсутствовал, хотя использовался разворотом патруля — поле добавлено в ресурс и все 4 `.tres` (тайминг патруля остаётся данными, не константой).
  2. `Hitbox._already_hit` жил между взмахами: второй удар того же врага не проходил. Добавлен `clear_hits()` при каждой активации; e2e проверяет второй удар heavy.
  3. Async `Damage.flash` при наложении попаданий/смерти мог оставить спрайт белым. У врага вспышка сделана тик-таймером (≤ `hit_flash_duration`, не дольше 100 мс) и не восстанавливает цвет во время fade смерти.
  4. Входящий урон не переводил игрока в Hurt: idle-игрока «уносило» отбросом, и враг терял цель. `Player` теперь подписан на свой Hurtbox и вызывает `apply_hurt()` (HP/блок — T-26/T-11).
  5. Ранний черновик e2e содержал duplicate `frames` (parse error, отмечен Orchestrator/T-18) — исправлено, на коммите `e4f12cf` импорт чистый.
- **Кросс-файловые правки (на контроль Guardian):** `autoload/EventBus.gd` (+`enemy_died`), `data/balance/balancing_params.gd` + `.tres` (+`enemy_death_duration`, `enemy_knockback_friction`, `enemy_stuck_timeout`), `entities/player/Player.gd` (подписка Hurtbox→Hurt), `entities/player/Player.tscn` (группа `player`). `docs/TASKS.json` и статус не менялись (`pending` до QA/Guardian).
- **Замечания:** в рабочем дереве параллельно шли T-18/T-05; чужие `ui/`, `assets/fonts/`, `opencode.jsonc` не трогал. В `docs/WORKFLOW_LOG.md` на момент записи была незакоммиченная запись Orchestrator (приёмка T-18) — вошла в коммит журнала как часть append-only истории.
- **Коммит:** `e4f12cf` «T-12: враги — базовый AI + swift/heavy/ranged/undead».

## 2026-10-18 — T-05 выполнен (tasker-frontend)

- **Skills:** загружен `godot` (GDScript, AnimatedSprite2D/SpriteFrames, Node2D, GUT/headless — профильный стек визуала игрока). Другие skills не требовались.
- **Задача:** анимации и визуал игрока (DESIGN §7, AC-02.1/02.2, AC-03.3).
- **Подход:** `AnimatedSprite2D` + кадровые анимации (DESIGN задаёт кадры/тайминги), а не `AnimationPlayer`: нет интерполяции, кадры 16×24 остаются пиксельными; замена арта — через `PlayerAnimation.frames_override` без правок логики.
- **Сделано:**
  - `entities/player/sprites/player_sprite_frames.gd` — контракт 18 анимаций (idle/run/jump_rise/jump_apex/fall/land/double_jump/dash/wall_slide/attack_1..3/block/roll/hurt/death/out_of_stamina/sit), программные заглушки 16×24 из 9 токенов `UITokens` (≤16 цветов), тайминги из `balancing.tres`.
  - `entities/player/PlayerAnimation.gd` — привязка `EventBus.player_state_changed` → анимация; апекс по `vy`, attack_1..3 по шагу комбо, idle-вариант при 0 выносливости; double jump flash steel-3 на 3 кадра; dash — 2 призрачных кадра steel-9 + холодный i-frames-вид; пыль бега; метка «Твои вещи» (gold-9) на death; hurt-вспышка отключается `Config.no_flash` (смена тона без мерцания).
  - `Player.tscn`: добавлены `Animation` + `AnimatedSprite2D`, старый программный `Visual` скрыт.
  - `tests/unit/test_player_animation.gd` — 14 GUT-тестов.
- **Кросс-правки (на контроль Guardian):** `autoload/Config.gd` (+`no_flash`/`set_no_flash`; загрузка/тумблер — T-20), `data/balance/balancing_params.gd` + `balancing.tres` (+10 `anim_*` таймингов из DESIGN §7).
- **Проверка:** Godot 4.4.1 portable. Чистый worktree `67ae3b0`: `--headless --import` exit 0; GUT **156/156 passed, 1648 asserts** (+14 новых; 142 прежних не сломаны); smoke `--headless --path game --quit` exit 0. Пользовательский smoke: Player.tscn инстанцирован, все состояния FSM → корректные анимации 16×24; PNG-лист кадров собран для визуальной проверки (вне репо).
- **Ограничения:** wall_slide/double_jump/sit — контракт/API готовы, состояния FSM появятся в T-06/T-08/T-23; арт — заглушки. Статус T-05 в `TASKS.json` — `pending` (QA/Guardian).
- **Коммит:** `67ae3b0` «T-05: анимации и визуал игрока». Untracked-файлы других сессий (`opencode.jsonc`, `world/zones/zone_banner*`, `zone_01_backdrop.gd`) не тронуты.

## 2026-10-18 — T-14 выполнен (tasker-dba)

- **Skills:** загружен `godot` (типизированный GDScript, ZoneScene/ZoneData, TileMapLayer, PointLight2D/CanvasModulate, ResourceSaver/PackedScene для генерации сцены, GUT/headless — профильный стек зоны и уровня). Другие skills не требовались.
- **Задача:** зона 1 «Деревня-бастион» (хаб) по макету `zone-village.html`, DESIGN §8.6, SPEC §5.
- **Подход:** сцена и ZoneData генерируются скриптом `tests/tools/build_zone_01.gd` на пайплайне T-13 (тот же тайлсет/пропсы/контракт ZoneScene). Арт — программные заглушки: `Backdrop` (стена-бастион с мхом, стяг, ворота с поднятой решёткой, хижина с тёплым окном, дальний замок/луна) и `Foreground` (влажная земля, лужи, мох, бочки, кромка уступа, груда завала). Цвета — токены зоны 1 из `UITokens` (`night`, `stone`, `gold`, `brown`, `green-3`, `blood`).
- **Сделано:**
  - `world/zones/zone_01_village/zone_01_village.tscn` + `data/zones/zone_01_village.tres`: корень `ZoneScene`, палитра зоны 1, ambient 0.42, тайлсет зоны 1; 3 точки входа (`start`, `from_gate`, `from_ledge`) и 2 выхода (`gate` → zone_02_swamp, `ledge` → zone_03_mountains).
  - Раскладка: пол 30×2 тайла, one-way уступ 7 тайлов на y=176 (48 px над полом), сундук-секрет на уступе, дверь-выход на уступе, завал-заглушка T-09 (`Rubble`, meta `ability_gate=double_jump`, коллизия совпадает с видимой грудой), костёр-чекпоинт `Props/Bonfire` (112, 224), маркеры `NPC_Keeper` и `Trader`, границы мира (`WorldBounds`: пол/стены/потолок).
  - Освещение: 2 факела `PointLight2D` с радиальным градиентом 180 px (радиус ≈90 px), окно хижины, костёр и холодная луна; ambient через `CanvasModulate` из ZoneData.
  - Баннер: `world/zones/zone_banner.tscn/.gd` (CanvasLayer 15, h2 16 px + «Зона 1 · Хаб», ступенчатый fade 4 шага). Подписан на `EventBus.zone_entered`, показывается один раз за вход в сцену зоны.
  - `tests/integration/test_zone_01.gd` — 11 GUT-тестов: загрузка `SceneRouter.instantiate_zone`, палитра/ambient/тайлсет, 2 факела ≈90 px, пропсы/маркеры/сундук, баннер первого входа, входы/выходы, недостижимость уступа без двойного прыжка (геометрия + физика), границы мира, триггер перехода `gate`.
- **Проверка:** Godot 4.4.1 portable. Чистый worktree `7ac547f`: `--headless --import` exit 0; GUT **167/167 passed, 1760 asserts** (156 прежних + 11 новых, 0 падений); smoke `--headless --path game --quit-after 60` exit 0; отдельный запуск сцены зоны `--headless --path . res://world/zones/zone_01_village/zone_01_village.tscn --quit-after 120` exit 0. Пользовательский smoke: рендер зоны 480×270 в OpenGL-совместимом режиме (PNG вне репо) — макет читается: стена/мох, ворота, факелы, хижина, уступ с сундуком и дверью, завал, влажный пол, баннер.
- **Ограничения:** ability gate и подсказка «Нужно: Двойной прыжок» — T-09 (здесь только физическая заглушка завала и высокий уступ); логика чекпоинта/сохранения — T-26 (здесь только prop `Bonfire` и его позиция); состояние FSM/способность двойного прыжка — T-06 (тест физики эмулирует импульсы из `balancing.tres`, порог уступа 48 px: 32 < 48 ≤ 57.6). Палитра `Platforms` = accent (gold) задаётся контрактом T-13, поэтому уступ тёплый, а не серый, как в макете. Статус T-14 в `docs/TASKS.json` не менялся (`pending` до QA/Guardian).
- **Кросс-файловые правки:** нет — только новые файлы в `world/zones/`, `data/zones/`, `tests/`. Untracked-файлы других сессий (`opencode.jsonc`, `entities/player/*` T-05) не тронуты.
- **Коммит:** `7ac547f` «T-14: зона 1 «Деревня-бастион» (хаб)». Запись журнала закоммичена отдельным коммитом `docs(WORKFLOW_LOG)` вместе с накопившимися append-only записями Orchestrator/T-05 других сессий.

## 2026-10-18 — T-06 выполнен (tasker-backend)

- **Skills:** загружен `godot` (типизированный GDScript, `Resource`/`class_name`, CharacterBody2D + FSM-состояния, Area2D-подбор, GUT/headless — профильный стек способностей). Другие skills не требовались.
- **Задача:** AbilitySystem + двойной прыжок (PLAN §2.1/§3.1/§3.3, SPEC US-02/AC-02.1).
- **Сделано:**
  - `core/abilities/ability_base.gd` — контракт `AbilityBase` (Resource): `id`, `display_name`, `description`, `activate(player) -> bool`, `deactivate(player)`, `player_flags()`. Базовая активация ставит на игроке runtime-флаг с id способности.
  - `core/abilities/ability_double_jump.gd` — `AbilityDoubleJump`: `ID=double_jump`, `AIR_JUMPS=1`, `MIN_HEIGHT_FACTOR=0.8`.
  - `core/abilities/ability_registry.gd` — `AbilityRegistry`: ленивый кеш данных из `data/abilities/*.tres`, API `get_ability/has_ability/all_ids/all` — единая точка для FSM, gates (T-09) и HUD (T-19).
  - `data/abilities/double_jump.tres` — данные способности (RU-название для подсказок).
  - `autoload/GameState.gd` — `abilities: Array[StringName]` (типизированный набор), `has_ability/add_ability/get_abilities/clear_abilities`; `add_ability` идемпотентен и эмитит `EventBus.ability_acquired`.
  - `autoload/EventBus.gd` — сигнал `ability_acquired(ability_id)`.
  - `world/props/ability_pickup.gd/.tscn` — Area2D-подбор по контакту: `GameState.add_ability` → сигнал → живой Player разблокирует поведение; точка одноразовая, скрывается, повтор не выдаёт способность.
  - `entities/player/Player.gd` — `ability_flags`, `double_jumps_used`, привязка `GameState.abilities` в `_ready` + live-подписка на сигнал, `can_double_jump()/try_double_jump()/on_landed()`, вызов `PlayerAnimation.play_double_jump()`.
  - `PlayerStateMachine` + `states/double_jump.gd` — состояние `double_jump` в воздушном тире (priority 50), импульс `get_double_jump_velocity()` (высота 0.8·H_jump = 25.6 px), вход Jump/Fall → DoubleJump через `force_state` (внутри тира, как coyote jump), выход DoubleJump → Fall на апексе.
  - `states/jump.gd`, `states/fall.gd` — попытка двойного прыжка; `states/land.gd` — сброс счётчика (`Player.on_landed()`), повтор доступен только после приземления.
  - `tests/unit/test_abilities.gd` — 8 GUT-тестов: контракт реестра, typed-набор/идемпотентность/сигнал, activate/deactivate флагов, подбор по контакту и реальная разблокировка прыжка, одноразовость pickup, отказ без способности, ровно один прыжок + высота ≥0.8·H_jump + сброс на приземлении + повтор после приземления, двойной прыжок из Fall.
- **Проверки (portable Godot 4.4.1-stable, headless; `GODOT_PATH`):**
  - Dev-worktree от `67ae3b0`: `--headless --import` exit 0; GUT **164/164, 1705 asserts** (156 прежних + 8 новых), exit 0.
  - Чистый worktree коммита `616cda2` (уже поверх T-14): import exit 0; GUT **175/175, 1817 asserts** (167 прежних + 8 новых), exit 0; единственное предупреждение чужое — inner class в `tests/integration/test_zone_01.gd` (T-14).
  - Smoke `--headless --path game --quit` — exit 0 без скрипт-ошибок; отдельные запуски `Player.tscn` и `ability_pickup.tscn` — exit 0.
  - Пользовательский smoke реальным вводом (InputEventKey SPACE через InputMap, временная сцена вне коммита): контакт с pickup → способность в `GameState` → флаг на игроке → SPACE = прыжок → второй SPACE = `double_jump`; 8/8 проверок PASS, exit 0.
- **Найденные/исправленные проблемы:**
  1. Fall→Land случается на следующем тике после `is_on_floor()` (`move_and_slide` взводит флаг позже `physics_update`) — тест сброса счётчика ждёт лишний кадр; это штатная латентность FSM, не баг кода.
  2. Состояние `double_jump` само зовёт `PlayerAnimation.play_double_jump()` (API T-05), а затем то же состояние приходит сигналом — вспышка steel-3 перезапускалась; добавлен идемпотентный guard в `PlayerAnimation._start_double_jump_flash()`.
  3. `monitoring/monitorable` нельзя менять внутри `body_entered` — в pickup переключение отложено через `set_deferred`.
  4. Потенциальная циклическая ссылка `Player` ↔ `PlayerAnimation` — ссылка на слой анимации в Player оставлена untyped, вызов через `has_method/call`.
- **Кросс-файловые правки (на контроль Guardian):** `autoload/EventBus.gd` (+1 сигнал), `autoload/GameState.gd` (+набор/API способностей), `entities/player/Player.gd`, `PlayerStateMachine.gd`, `states/{jump,fall,land}.gd`, `PlayerAnimation.gd` (guard вспышки). Новые файлы — только `core/abilities/`, `data/abilities/`, `world/props/ability_pickup.*`, `states/double_jump.gd`, `tests/unit/test_abilities.gd`.
- **Контракт для следующих задач:** T-07/T-08 — наследовать `AbilityBase`, положить `.tres` в `data/abilities/`, добавить путь в `AbilityRegistry.ABILITY_PATHS`, переопределить `activate()` с `super.activate(player)`; поведение — в Player + FSM, разблокировка живой сессии идёт через `GameState.add_ability` → `EventBus.ability_acquired`. T-09 — `GameState.has_ability(id)` + `AbilityRegistry.get_ability(id).display_name` для подсказки, `ability_acquired` для открытия gates. T-19 — `GameState.get_abilities()`, сигнал и `display_name` для слотов. T-25 — способности пока не сериализуются: добавить `abilities: Array[String]` в `state`, поднять `schema_version` и шаг миграции по контракту `save_migrations.gd`.
- **Ограничения:** гейт-подсказка и открытие завала — T-09; HUD-слоты — T-19; сейв набора способностей — T-25. Godot в системе не установлен, использован portable 4.4.1 (совместим с 4.4+). Статус T-06 в `docs/TASKS.json` не менялся (`pending` до QA/Guardian).
- **Коммит:** `616cda2` «T-06: AbilitySystem + двойной прыжок» (на `v2` поверх T-14/T-25; исходный коммит ветки `ee5a58e`, перенесён cherry-pick). Чистый worktree `616cda2` — import/GUT/smoke зелёные.
- **Примечание:** в `docs/WORKFLOW_LOG.md` на момент записи была незакоммиченная append-only запись Orchestrator (приёмка T-14) — она вошла в docs-коммит вместе с этой записью; её содержимое не правил.
