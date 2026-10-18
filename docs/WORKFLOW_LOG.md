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

## 2026-10-18 — Orchestrator: Приёмка T-06, запуск T-15

- **T-06 принят:** AbilitySystem (AbilityBase/Registry) + двойной прыжок, коммит `616cda2`, GUT **175/175, 1817 asserts** (+8 тестов). Кросс-правки `EventBus` (+`ability_acquired`), `GameState` (+`abilities`), Player/FSM/states — на контроль Guardian.
- **⚠️ Интеграционный зазор (трек до QA):** способности пока НЕ сериализуются SaveManager'ом — T-06 задокументировал контракт (`abilities: Array[String]`, schema bump + миграция). Сложу в T-26 (следующий save-интегрирующий бэкенд) либо отдельным проходом перед QA.
- **Разблокированы:** T-07/T-08/T-09 (способности), T-19 (HUD — зависимости T-18/T-06/T-10 все готовы).
- **Решение:** слот освобождён (T-06) → запуск **T-15** (зоны 2–3 «Болото»/«Горный перевал», dba) — на критическом пути боссов (T-31 ждёт T-15), параллельно с T-30 (боссы).

## 2026-10-18 — Orchestrator: Приёмка T-15, запуск T-16

- **T-15 принят:** зоны 2–3 «Болото»/«Горный перевал», коммиты `a923ea9` + `4a484df`, GUT **196/196, 2199 asserts** (+10 тестов). Туман (CanvasLayer, без шейдеров), параллакс 3 хребта, вертикальные шахты, ability-gate-заглушки (dash/wall_climb), связность зон 1↔2↔3 проверена тестом. Кросс-правок нет.
- **Разблокированы:** T-31 (боссы 3–4) — частично, ждёт T-30 (в работе) + T-16.
- **Решение:** слот освобождён (T-15) → запуск **T-16** (зоны 4–5 «Руины-храм»/«Финал», dba) — последняя зона, на критическом пути T-31/T-32, параллельно с T-30 (боссы).

## 2026-10-18 — Orchestrator: Приёмка T-30, запуск T-26

- **T-30 принят:** Boss framework + боссы 1–2 (BossBase/Arena/данные, фазы 33/66, EC-09), коммит `ef53c1c`, GUT **196/196, 2199 asserts** (+11 тестов). Кросс-правки `EventBus` (+boss-сигналы), `GameState` (+bosses_defeated/rewards/currency), `save_serializer`+`save_migrations` (schema v1→v2), `balancing` — на контроль Guardian.
- **Заметка:** T-30 поднял schema до v2; способности всё ещё не сериализуются — сложу в T-26 (вместе со смерть-состоянием/HP, schema → v3).
- **⚠️ Сериализатор — общий файл:** T-26/T-27/T-29 все модифицируют `save_serializer.gd`/`save_migrations.gd` → их запускать строго последовательно (не параллельно), каждый поднимает schema на +1.
- **Разблокированы:** T-31/T-32 — ждут T-16 (в работе).
- **Решение:** слот освобождён (T-30) → запуск **T-26** (смерть/corpse run/костёр, backend) — ядро Gothic-механики, на пути QA (T-26→T-22→T-37), параллельно с T-16 (зоны 4–5).

## 2026-10-18 — Orchestrator: Приёмка T-16, запуск T-32

- **T-16 принят:** зоны 4–5 «Руины-храм»/«Финал», коммит `6bad0f2`, GUT **218/218, 2594 asserts** (+11 тестов). Руины: загадка-рычаги + 2 источника света (жёлтый/красный), эмиссивный CanvasLayer; финал: монохром + арена + `BossSpawn` + хук `ending_requested`. Кросс-правки `zone_02_swamp.tres`/`zone_03_mountains.tres` (+входы из руин), `test_zone_02_03.gd` — на контроль Guardian.
- **Разблокированы:** T-31 (боссы 3–4), T-32 (финальный босс) — все зависимости готовы.
- **Решение:** слот освобождён (T-16) → запуск **T-32** (финальный босс, backend) — на критическом пути QA (T-37 ждёт T-32), параллельно с T-26 (смерть). T-31 — следующей волной.

## 2026-10-18 — Orchestrator: Приёмка T-26, запуск T-17

- **T-26 принят:** смерть/corpse run/костёр + HP + сериализация способностей/смерти (schema v2→v3), коммит `d4cd882`, GUT **218/218, 2594 asserts** (чистый worktree 207/207). Кросс-правки `EventBus` (+8 сигналов), `GameState` (HP/инвентарь/смерть/чекпоинт/in_combat/active_slot), `SaveManager`/`save_serializer`/`save_migrations` (v3), `Player` (урон/пропасть), `balancing` (`max_hp`), `bonfire` — на контроль Guardian.
- **Закрыт зазор:** способности теперь сериализуются (`abilities: Array[String]` + миграция v2→v3).
- **Разблокированы:** T-22 (экран смерти), T-27/T-29 (сериализатор свободен).
- **Решение:** слот освобождён (T-26) → запуск **T-17** (переходы зон + экран загрузки, backend) — инфраструктура на пути QA (T-17→T-33→T-37), параллельно с T-32 (финал). Интегрирует: fall_death_y из границ зоны (T-26 оставил INF) и переспавн corpse-узла при переходе.

## 2026-10-18 — Orchestrator: Приёмка T-32, запуск T-27

- **T-32 принят:** финальный босс (3 фазы ash_cleave/pyre_fan/last_rites) + концовка по фракции + титры, коммит `3e5c218`, GUT **225/225, 2717 asserts** (+7 тестов). Кросс-правки `zone_05_finale.tscn` (gate_on_boss_id, EndingSequence), `test_zone_04_05.gd`, `hitbox.gd` (guard) — на контроль Guardian. Сериализатор не трогал.
- **Разблокированы:** T-27 (фракции), T-31 (боссы 3–4) и остальные готовые; T-28/T-24 ждут T-27, T-33 ждёт T-17.
- **Решение:** слот освобождён (T-32) → запуск **T-27** (фракции: репутация/доступ/концовка, backend) — сериализатор свободен (schema → v4), разблокирует T-28 (NPC/диалоги) и T-24 (ремап/журнал/фракции), параллельно с T-17 (переходы).

## 2026-10-18 — Orchestrator: Приёмка T-27, запуск T-19

- **T-27 принят:** фракции (3 фракции, репутация −100…+100, пороги доступа, Δ-таблица, выбор/концовка), коммит `dec13a1`, GUT **238/238, 2840 asserts** (+13 тестов). Сериализация фракций (schema v3→v4). Кросс-правки `GameState` (+factions/chosen_faction), `EventBus` (+4 сигнала), `save_serializer`/`save_migrations`, `test_save` — на контроль Guardian.
- **Разблокированы:** T-24 (ремап/журнал/фракции), T-28 (NPC/диалоги).
- **Решение:** слот освобождён (T-27) → запуск **T-19** (HUD, frontend) — крупнейшая frontend-задача на пути QA (T-37 ждёт T-19), параллельно с T-17 (переходы).

## 2026-10-18 — Orchestrator: Приёмка T-17, запуск T-29

- **T-17 принят:** переходы зон + экран загрузки (фоновый `ResourceLoader` load, блокировка ввода EC-12, `fall_death_y` EC-03, переспавн corpse, `bootstrap()`), коммит `4649c2b`, GUT **248/248, 2937 asserts** (+10 тестов). Кросс-правки `EventBus` (+`zone_loaded`), `InputManager`/`input_buffer` (+clear), `Main.gd` (bootstrap), `zone_data.gd` (+epigraph) — на контроль Guardian.
- **Разблокированы:** T-33 (карта).
- **Решение:** слот освобождён (T-17) → запуск **T-29** (прогрессия: характеристики/очки/учителя, backend) — закрывает сериализатор (schema → v5, последний), разблокирует T-21 (инвентарь), параллельно с T-19 (HUD). T-33 не запускаю параллельно с T-19 — оба трогают `ui/hud/`.

## 2026-10-18 — Orchestrator: Приёмка T-19, запуск T-33

- **T-19 принят:** HUD (HP/выносливость/3 слота способностей/быстрые слоты/валюта/босс-бар с фазами 33-66), коммит `c1b8a69`, GUT **265/265, 3060 asserts** (+17 тестов). Кросс-правка `EventBus` (+`ability_cooldown_changed`, `ability_hint_changed`) — на контроль Guardian.
- **⚠️ Интеграционный зазор (трек до QA):** `HUD.tscn` пока НЕ инстанцирован в `Main.tscn` (T-19 намеренно отложил из-за T-17). Перед QA нужен проход сборки UI: встроить HUD + все экраны (T-20/T-21/T-22/T-23/T-24/T-33) в слои Main (HUD 10/UI 20/Overlay 40). Сложу в отдельный финальный integration-проход.
- **Разблокированы:** T-33 (карта, после T-17).
- **Решение:** слот освобождён (T-19) → запуск **T-33** (карта мира + миникарта, frontend) — на пути QA (T-37 ждёт T-33), параллельно с T-29 (прогрессия).

## 2026-10-18 — Orchestrator: Приёмка T-29, запуск T-07

- **T-29 принят:** прогрессия (характеристики/очки/уровень/XP/учителя + требования экипировки), коммит `4c63ff3`, GUT **280/280, 3294 asserts** (+13 тестов). Сериализация v4→v5 — **сериализатор закрыт полностью**. Кросс-правки `GameState` (+stats/level/xp/lp), `EventBus` (+4 сигнала), `SaveManager`, `stamina.gd`, `save_serializer`/`save_migrations` — на контроль Guardian.
- **Разблокированы:** T-21 (инвентарь).
- **Решение:** слот освобождён (T-29) → запуск **T-07** (способность Dash, backend) — ядро метроидвании, параллельно с T-33 (карта). T-08/T-09 — следующей волной (T-07/T-08 обе трогают `states/`, секвенирую).

## 2026-10-18 — Orchestrator: Приёмка T-07, запуск T-08

- **T-07 принят:** способность Dash (D_dash/T_dash, i-frames, кулдаун 0.6≤1 с, сигнал HUD `ability_cooldown_changed`), коммит `c13ebfe`, GUT **308/308, 3503 asserts** (+11 тестов). Кросс-правки `ability_registry`, `Player.gd`, `states/{dash,jump,fall,double_jump,land}`, `test_combat_hitbox`/`test_corpse_run` (выдача способности перед рывком) — на контроль Guardian.
- **Решение:** слот освобождён (T-07) → запуск **T-08** (Карабканье по стенам, backend) — третья способность, параллельно с T-33 (карта). T-09 (gates) — следующей волной.

## 2026-10-18 — Orchestrator: Приёмка T-33, запуск T-34

- **T-33 принят:** карта мира + миникарта (ZoneRoom/посещённость/WorldMapModel/MapRenderer/AshenMinimap), коммиты `e226a45` + `811c0ef`, GUT **308/308, 3503 asserts** (+17 тестов). Кросс-правки `SceneRouter` (visited_zones), `zone_data.gd`/`zone_exit.gd`/`zone_room.gd`, 5 `data/zones/*.tres`, `HUD.gd`, `minimap.gd`, `Main.tscn`, `project.godot` (action `map`) — на контроль Guardian.
- **⚠️ Зазор (трек до QA):** посещённые зоны не сериализуются (после загрузки карта знает только текущую зону; `restore_visited_zones` готов). Сложу в финальный integration/QA-проход.
- **Решение:** слот освобождён (T-33) → запуск **T-34** (AudioManager, backend) — атмосфера US-07 на пути QA (T-37 ждёт T-34), параллельно с T-08 (стены). T-09 запущу после T-08 (forward-ref на `wall_climb.tres`).

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

## 2026-10-18 — T-30 выполнен (tasker-backend)

- **Skills:** загружен `godot` (Reason: типизированный GDScript, `Resource`/`class_name`, CharacterBody2D + EnemyStateMachine, Area2D hitbox/hurtbox, `tres`-данные, GUT/headless). Другие skills не требовались: задача не затрагивает React/PostgreSQL/Docker/Go/Python.
- **Задача:** T-30 «Boss framework + боссы 1–2» (PLAN §2.1/§3.1, SPEC US-03/AC-03.4/EC-09, TASKS T-30). Статус TASKS не менялся (pending до QA/Guardian).
- **Контракт фаз:** `BossData` + `BossPhaseData` (`data/bosses/*.tres`): 2–3 фазы, `hp_threshold_ratio` 1.0 / 0.66 / 0.33 (`BossData.PHASE_TWO_THRESHOLD`/`PHASE_THREE_THRESHOLD`, параметризованы по фазам). `BossBase` при переходе меняет `pattern_id`, скорость/тайминги/урон/размер хитбокса, эмитит `EventBus.boss_phase_changed(boss_id, index, title)` — `title` = «ФАЗА II»/«ФАЗА III» для HUD T-19 (AC-03.4). Дополнительно: `boss_fight_started`, `boss_health_changed`, `boss_defeated`, `boss_reward_granted`.
- **Контракт награды/EC-09:** при смерти `BossBase` вызывает `GameState.mark_boss_defeated(id)` + `GameState.queue_boss_reward(id, zone_id, reward_id, gold)`. Если игрок жив — награда выдаётся сразу (`claim_boss_reward`, +`currency`, событие); если мёртв — остаётся в `boss_rewards_pending` и выдаётся `BossArena` при следующем входе в зону (`claim_pending_boss_rewards(zone_id)`). Флаг и очередь персистятся SaveManager (schema v1→v2); арена при загруженном флаге не спавнит босса и открывает барьеры.
- **Арена:** `BossArena` (`boss_base/boss_arena.gd`): вход игрока через `Trigger` закрывает `StaticBody2D`-барьеры группы `arena_barrier` (слой world), ограничивает босса `arena_bounds`; после победы открывает выходы. Сцены: `zone_01/boss_arena_zone_01.tscn`, `zone_02/boss_arena_zone_02.tscn` (программные заглушки через `_draw`, без внешнего арта).
- **Боссы:** `Zone01Boss` — ближний (`cleave` → `lunge` → `frenzy`, рывки/ускорение по фазам); `Zone02Boss` — дальний/вызовы (`bolt` → `volley` 3 снаряда → `summon` 2 снаряда + призывы, держит `preferred_distance`, лимит 4 живых вызова, призывы убираются со смертью). Снаряды — `EnemyProjectile`, призывы — `Enemy` (переиспользование T-10/T-12).
- **Файлы:** `data/bosses/` (3 скрипта + 2 `.tres`), `entities/bosses/boss_base/`, `entities/bosses/zone_01/`, `entities/bosses/zone_02/`, `tests/unit/test_boss.gd` (11 тестов).
- **Кросс-файловые правки (на контроль Guardian):** `autoload/EventBus.gd` (+5 boss-сигналов), `autoload/GameState.gd` (+boss/currency API), `core/save/save_serializer.gd` (+boss-поля), `core/save/save_migrations.gd` (CURRENT_VERSION 1→2, `_v1_to_v2`), `data/balance/balancing_params.gd`/`balancing.tres` (`boss_death_duration`, `boss_phase_transition_time`), `tests/unit/test_save.gd` (жёстко зашитая `schema_version:1` заменена на `SaveMigrations.CURRENT_VERSION`).
- **Evidence (portable Godot 4.4.1-stable, headless, `GODOT_PATH`):**
  - Базовая линия HEAD до задачи: GUT 175/175, 1817 asserts.
  - Чистый worktree коммита `ef53c1c`: `--headless --import` exit 0 (без script/parse errors); GUT `-gdir=res://tests -ginclude_subdirs` — **186/186 passed, 1992 asserts** (175 базовых + 11 новых, 0 падений).
  - Smoke `--headless --path game --quit` exit 0; отдельные арены `zone_01`/`zone_02` с `--quit-after 120` exit 0.
  - FPS long-fight (600 physics-кадров, фаза III zone_02 с призывами/снарядами): `Performance.TIME_PHYSICS_PROCESS` p95 = **0.00773 s** (< 1/60 = 0.01667 s), first100 = 0.00504 s, last100 = 0.00533 s — деградации нет.
  - Совмещённая проверка на текущем HEAD `a923ea9` (T-30 + T-15): GUT **196/196, 2198 asserts** — зоны 2–3 не сломаны.
- **Ограничения/далее:** арены — самостоятельные сцены; встраивание в `zone_01_village` (T-14) и `zone_02_swamp` (T-15) — при интеграции T-15/T-17, сцена готова к instance. Награда — золото/очередь (предметы/очки — T-29); HUD-панель — T-19 (сигналы готовы). Арт — заглушки. Независимые приёмка QA и ревью Guardian не выполнялись Tasker'ом.

## 2026-10-18 — T-15 выполнен (tasker-dba)

- **Skills:** загружен `godot` (типизированный GDScript, `Resource`/`class_name`, TileMapLayer, CanvasLayer/Control `_draw`, PointLight2D/CanvasModulate, PackedScene/ResourceSaver-генератор, GUT/headless — профильный стек зон и визуала). Другие skills не требовались: задача не затрагивает React/PostgreSQL/Docker/Go/Python.
- **Задача:** T-15 «Зоны 2–3 „Болото“ и „Горный перевал“» (TASKS T-15, DESIGN §8.6, SPEC §4.1/§5, PLAN §2.1/§2.3/§3.6). Статус TASKS не менялся (`pending` до QA/Guardian).
- **Подход:** генератор `tests/tools/build_zones_02_03.gd` на пайплайне T-13 по образцу T-14: `ZoneScene` + `ZoneData`, общий `zone_terrain.tres` (строки зон 2/3 — индексы 1 и 2), props `bonfire`/`chest`/`rubble`, баннер, `WorldBounds`. Арт — программные заглушки в палитрах зон; туман и параллакс — лёгкие скрипты без шейдеров/партиклов.
- **Зона 2 «Болото» (`zone_02_swamp`):** палитра `green-9` (небо), `brown` (земля), `gold-9` (акцент/пламя), `steel-9` (вода hazard), ambient 0.36. Backdrop: мутное небо, мёртвые деревья, мох, топь, болотные огни; Foreground: камыш, ряска, пузыри. Туман `zone_02_fog.gd`: CanvasLayer 4, 2 полупрозрачных покрывала + 5 мягких клубов на радиальном градиенте, дрейф в `_process` (7 узлов, без аллокаций). Hazard-вода двумя плёсами (колонки 8–12, 16–18, ряд 13) поверх пола. Костёр (96, 224), сундук за dash-gate на карнизе.
- **Зона 3 «Горный перевал» (`zone_03_mountains`):** палитра `night-9`, `steel` (порода), `steel-3` (холодный акцент/лёд), `stone-5` (hazard-шипы), `bone` (снег), ambient 0.36. Параллакс `zone_03_parallax.gd`: 3 хребта (scroll_factors 0.08/0.18/0.32, реакция на `Camera2D`, без камеры — ветровой дрейф), непрерывная снеговая кромка, 18 штрихов ветра; Foreground — 26 снежинок и позёмка. Две вертикальные шахты (центральная под wall climb: стены 11/14, верхняя полка; вторая — камин 20/24), костёр (96, 224) с тёплым пламенем `gold-3` через `zone_03_scene.gd` (наследник `ZoneScene`; accent остаётся холодным).
- **Связность (сверено с T-14):** `village.gate → zone_02_swamp/west_gate`; `zone_02_swamp.west_gate → zone_01_village/from_gate`; `zone_02_swamp.east_gate ↔ zone_03_mountains.north_pass`; `zone_03_mountains.south_ledge → zone_01_village/from_ledge`; `village.ledge → zone_03_mountains/south_ledge`. В зоне 1 нет входа `east_gate` (это расхождение шаблона T-13), поэтому обратный путь болота ведёт в существующий `from_gate`, а гор — в `from_ledge`. Тест обходит все выходы всех трёх зон и проверяет существование целевой зоны и точки входа.
- **Ability gates (SPEC §4.1, заглушки T-09):** болото — `Props/DashGate` (`Rubble`, meta `ability_gate=dash`, `future_gate=T-09`) на карнизе с сундуком; горы — `Props/WallClimbGate` (`wall_climb`) у входа в шахту и `Props/DashGate` (`dash`) на карнизе. Родные зоны dash/wall climb — зона 2, поэтому оба «чужих» применения в зоне 3 закрывают критерий «способность вне родной зоны». Над dash-карнизами добавлены сплошные козырьки (ряд 7), чтобы препятствие нельзя было перепрыгнуть.
- **Тесты:** `tests/integration/test_zone_02_03.gd` — 10 GUT-тестов: загрузка через `SceneRouter`, палитры/ambient/пламя, связность всех входов-выходов, туман (слой, клубы, дрейф) и hazard-вода, параллакс (слои, камера, ветер, снег), вертикальные шахты, ability gates (native + foreign), входы/выходы/костры/границы, сигнал перехода, headless-бюджет 60 кадров < 1 с.
- **Evidence (portable Godot 4.4.1-stable, headless, `GODOT_PATH`):**
  - Базовая линия HEAD `ef53c1c` (T-30): GUT 186/186, 1992 asserts.
  - Чистый worktree коммита `4a484df`: `--headless --import` exit 0; GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **196/196 passed, 2199 asserts** (186 базовых + 10 новых, 0 падений); отдельный прогон нового файла — 10/10, 207 asserts.
  - Smoke `--headless --path game --quit` exit 0; отдельные сцены `zone_02_swamp.tscn` и `zone_03_mountains.tscn` с `--quit-after 120` — exit 0, без скрипт-ошибок.
  - Визуальный smoke: окно 480×270, OpenGL-совместимый рендер обеих зон в PNG (вне репо) — читаются палитры, мягкий туман и его дрейф, три слоя хребтов со снегом, штрихи ветра, шахты, костры, hazard-вода.
- **Найденные/исправленные проблемы:**
  1. Туман из прямоугольных `ColorRect` выглядел «плитами» — заменён на `TextureRect` с радиальным градиентом (мягкие клубы) + равномерные покрывала; по-прежнему 7 узлов.
  2. Снег хребтов рисовался хеш-точками 2×2 и читался пунктиром — заменён на непрерывную 1-px кромку (ближний слой `bone`, средний `stone-5`).
  3. Dash-препятствия можно было перепрыгнуть — добавлены сплошные козырьки над карнизами (32 px просвета, завал высотой 16–24 px).
  4. Низкая видимость болота при ambient 0.30 делала сцену почти чёрной — ambient поднят до 0.36, «слепоту» создаёт туман, а не потеря деталей.
  5. Верхние полки шахт были сплошными тайлами — wall climb вёл в тупик; заменены на one-way платформы (T-13), сквозь которые карабкающийся выходит наверх.
  6. Обратные ссылки в шаблон T-13 (`east_gate` для деревни) не соответствуют фактическим входам T-14 — использованы `from_gate`/`from_ledge`.
- **Кросс-файловые правки:** нет — только новые файлы в `world/zones/zone_02_swamp/`, `world/zones/zone_03_mountains/`, `data/zones/`, `tests/`. `ZoneScene`, `ZoneData`, тайлсет и props T-13 не менялись; `docs/TASKS.json` не трогал.
- **Ограничения:** физика/логика dash и wall climb — T-07/T-08, сам gate и подсказка «Нужно: …» — T-09; чекпоинт-сохранение костров — T-26; полноценный перф-пасс с рендером — T-37 (здесь headless-замер и визуальный smoke). Арт — заглушки. Независимые приёмка QA и ревью Guardian не выполнялись Tasker'ом.
- **Коммит:** `a923ea9` «T-15: зоны 2–3 «Болото» и «Горный перевал»» + `4a484df` «T-15: one-way полки шахт — карабканье не ведёт в тупик» (фикс по итогам визуального smoke). Запись журнала идёт отдельным docs-коммитом; в него входят уже лежавшие в рабочем дереве незакоммиченные append-only записи Orchestrator (запуск T-15) и T-30 — их содержимое не правил.

## 2026-10-18 — T-26 выполнен (tasker-backend)

- **Skills:** загружен `godot` (типизированный GDScript, autoload/GameState, CharacterBody2D + FSM, Area2D-подбор, Node/`_physics_process`-таймер, Resource-данные, FileAccess/JSON-сериализация, GUT/headless — профильный стек смерти/сохранений). Другие skills не требовались: задача не затрагивает React/PostgreSQL/Docker/Go/Python.
- **Задача:** T-26 «Смерть, corpse run и чекпоинты-костры» (TASKS T-26; PLAN §2.1/§3.1/§3.4; SPEC US-05, AC-05.2/05.3, EC-01/03/04/05/06). Статус TASKS не менялся (`pending` до QA/Guardian).
- **HP и смерть:** в `BalancingParams`/`balancing.tres` добавлен `max_hp = 100` (единый источник); `GameState.hp`/`hp_max`, `damage_hp`/`set_hp`/`reset_hp`, сигнал `EventBus.player_health_changed`. `Player.apply_damage()` уменьшает HP и при HP ≤ 0 вызывает существующий `kill()` → FSM `death` (немедленное прерывание рывка/прыжка, EC-01); блок/парирование T-11 могут отменить урон до этого вызова.
- **DeathHandler** (`core/death/death_handler.gd`): по `EventBus.player_died` сразу выкладывает инвентарь+валюту в `GameState.drop_corpse()`, ставит `death_active`, пишет death-автосейв в активный слот и держит бюджет `t_death`. По истечении — `EventBus.death_screen_requested(info)` (хук T-22) и возрождение у последнего костра с полным HP (`GameState.reset_hp`, `Player.reset_player`). `auto_respawn=false` позволяет T-22 ждать кнопку «Возродиться». EC-04: загрузка сейва с `death_active` разрешается как обычная смерть (`save_loaded`/`_ready` → `resolve_pending_death`), без отката потери.
- **Corpse run** (`world/props/corpse.gd/.tscn`): Area2D-мешок `gold-9`, подбор по контакту с игроком; позиция/предметы/валюта живут в `GameState` и переживают сейв. Узел спавнится после возрождения, чтобы мёртвое тело на месте гибели не подобрало метку само. EC-05: повторная смерть до подбора очищает старую метку, эмитит `corpse_lost`, старый узел становится черепом (`mark_lost`), подбор невозможен; новая метка содержит только новую добычу.
- **Костёр** (`world/props/bonfire.gd/.tscn`): Area2D-контакт делает костёр чекпоинтом (`GameState.set_respawn_bonfire`, id `zone_id/bonfire_id`, позиция со `respawn_offset`); `save_to_slot()` — единственная точка сохранения, `GameState.in_combat` блокирует запись и эмитит `EventBus.save_failed(slot, "in_combat")` (EC-06). `zone_id` выводится из родительской `ZoneScene`.
- **EC-03:** у `Player` появился `fall_death_y` (по умолчанию `INF`, включает T-17 из границ зоны) и `_check_fall_death()`: падение за границу наносит полный урон (`hp_max`) в обход i-frames рывка.
- **Сериализация (schema v2 → v3):** `SaveSerializer` пишет `state.hp`, `inventory`, `abilities` (как `Array[String]`), `death_active`, `death_corpse_active`, `death_zone_id`, `death_position` (`{x,y}`), `death_items`, `death_currency`, `death_lost`, `respawn_bonfire` (id зоны/костра), `respawn_zone_id`, `respawn_position`; `apply_state` восстанавливает их через API GameState (способности — через `restore_abilities` → `add_ability` → живой Player получает `ability_acquired`). `SaveMigrations.CURRENT_VERSION = 3`, добавлен `_v2_to_v3`: старые сейвы получают полное HP из `balancing.tres`, пустые инвентарь/способности, отсутствие смерти/метки и пустой чекпоинт. `SaveManager` запоминает `GameState.active_slot` и эмитит `EventBus.save_loaded`.
- **Тесты:** новый `tests/unit/test_corpse_run.gd` — 9 GUT-тестов: HP/летальный урон; сброс лута на месте гибели + бюджет `t_death` + возрождение у костра; смерть в рывке и в воздухе (EC-01); подбор по контакту (AC-05.3); необратимая потеря при повторной смерти (EC-05); пропасть = полный урон в обход i-frames (EC-03); костёр-чекпоинт и запрет сохранения в бою (EC-06); контакт с костром; выход в бюджете смерти → загрузка = обычная смерть (EC-04). В `test_save.gd` добавлены round-trip HP/инвентаря/способностей/смерти/чекпоинта и миграция v2→v3; существующие тесты используют `SaveMigrations.CURRENT_VERSION`.
- **Evidence (portable Godot 4.7.2-stable, headless; код 4.4-совместим):**
  - Базовая линия до задачи: `--headless --import` exit 0; GUT **196/196, 2199 asserts**.
  - Чистый worktree коммита `d4cd882`: `--headless --import` exit 0 (без script/parse errors); GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **207/207 passed, 2337 asserts** (196 базовых + 2 новых в test_save + 9 новых corpse-run, 0 падений); smoke `--headless --path game --quit` exit 0; `res://Main.tscn --quit-after 60` exit 0.
  - Полный прогон в общем рабочем дереве на момент записи дополнительно видел untracked-тест параллельной T-16 (`test_zone_04_05.gd`) с 1 падением в её визуальном тесте — к файлам T-26 отношения не имеет; мой коммит проверен изолированно в чистом worktree.
- **Найденные/исправленные проблемы:**
  1. Мёртвое тело на месте гибели мгновенно подбирало corpse-метку по контакту → узел Corpse спавнится только после возрождения (и после `resolve_pending_death` при загрузке); состояние метки при этом персистится сразу при смерти (EC-04).
  2. При повторной смерти `DeathHandler._corpse_node` продолжал указывать на старую метку, и новая не спавнилась → ссылка сбрасывается в `begin_death`, старый узел остаётся черепом.
  3. Corpse-узлы в GUT накапливались между тестами (динамические дети не входят в `add_child_autofree`) → тест-хелпер чистит группу `corpses` в before/after_each.
  4. Round-trip corpse-содержимого в `test_save` изначально ожидал не то, что реально переносится `drop_corpse` → тест приведён к фактическому контракту (drop забирает весь текущий инвентарь).
- **Кросс-файловые правки (на контроль Guardian):** `autoload/EventBus.gd` (+8 сигналов: HP, respawn, death screen, corpse drop/lost/collect, checkpoint, combat, save_loaded), `autoload/GameState.gd` (HP/инвентарь/смерть/чекпоинт/бой/активный слот/текущая зона), `autoload/SaveManager.gd` (active_slot + `save_loaded`), `core/save/save_serializer.gd`/`save_migrations.gd` (schema v3), `entities/player/Player.gd` (урон/HP/смерть/пропасть), `data/balance/balancing_params.gd` + `.tres` (`max_hp`), `world/props/bonfire.gd/.tscn` (чекпоинт/сохранение), `tests/unit/test_save.gd`.
- **Ограничения/далее:** `fall_death_y` по умолчанию `INF` — привязка к границам зоны за T-17 (иначе пропасть не активна в реальной сцене); `FallLimit`/hazard-тайлы не менялись. `in_combat` пока никто не выставляет из AI — выставит T-12/T-23 (API и блокировка готовы). Экран смерти — только сигнал-хук (T-22); узел `Corpse` после смены зоны переспавнится по `zone_entered`, полноценное управление зонами — T-17. Death-автосейв пишется только если игрок уже сохранялся/загружался (есть `active_slot`). Коррекция отношения Guardian/QA не проводилась.
- **Коммит:** `d4cd882` «T-26: смерть, corpse run, костёр + сериализация HP/способностей» + отдельный `docs(WORKFLOW_LOG): T-26 — evidence`. В docs-коммит вошли уже лежавшие в рабочем дереве незакоммиченные append-only записи Orchestrator (приёмка T-15/T-30, запуск T-16/T-26) — их содержимое не правил; файлы параллельной T-16 (зоны 4–5) не трогал.

## 2026-10-18 — T-16 выполнен (tasker-dba)

- **Skills:** загружен `godot` (типизированный GDScript, `Resource`/`class_name`, TileMapLayer, CanvasLayer/Node2D `_draw`, PointLight2D/CanvasModulate, PackedScene/ResourceSaver, GUT/headless — профильный стек зон и загадки). Другие skills не требовались: задача не про React/PostgreSQL/Docker/Go/Python.
- **Задача:** T-16 «Зоны 4–5 „Руины-храм“ и „Финал“» (TASKS T-16, DESIGN §8.6/§8.7, SPEC §5/US-04, PLAN §2.1/§2.3/§3.6). Статус в TASKS не менял (`pending` до QA/Guardian).
- **Зона 4 «Руины-храм»:** палитра `brown-3` (фон), `brown` (камень), `gold` (акцент), `blood` (hazard) + `gold-9`/`blood-3` в свете; ambient 0.26 с тёплым сдвигом (R>G>B, `zone_04_scene.gd`) — «до 0.26 у костра» (DESIGN §8.7). Гнетущая тишина: ровно два PointLight2D — жёлтый `gold-9` над костром (энергия 1.35, радиус 78 px) и красный `blood-3` над алтарём (1.2, 58 px). Эмиссивный жёлто-красный отсвет из проломов крыши вынесен на CanvasLayer 1 (`zone_04_glow.gd`), поэтому не затемняется CanvasModulate и виден при ambient 0.26. Костёр (чекпоинт) — внутри храма (288, 224); загадка-проход: 3 контактных рычага (`world/props/lever.gd`) с целевым состоянием [вкл, выкл, вкл] и `SealedGate` (`world/props/sealed_gate.gd`) в проёме стены; выход `to_finale` — за дверью. Входы: `from_swamp` (болото), `from_mountains` (верхний уступ), `from_finale` (до двери, чтобы повторная загрузка не запирала игрока); выходы: `to_swamp`, `to_mountains`, `to_finale`.
- **Зона 5 «Финал»:** почти монохром — `void`, `stone-9`, `stone-5` (+ `stone` в арте), единственный хроматический акцент `blood-3` (палитра hazard, 3 трещины в backdrop, 2 искры, 1 рунный свет). Пустая арена `Arena` с `BossSpawn` (360, 224) и `get_arena_bounds()` = Rect2(24, 40, 432, 184) — контракт для T-32; барьеров/босса нет (`is_empty()`). Точка выхода в концовку: `EndingExit` (Area2D) + `Marker2D` `ending_exit` + сигнал `ending_requested(faction_id, zone_id, ending_id)`; фракция читается из `FactionManager` защищённо (`has_method`, заглушка T-27 → `&""`), `gate_on_boss_id` пуст и включается T-32. Декор — два неблокирующих обломка монолитов (`Props/`). Выход `to_ruins`.
- **Связность:** `zone_04_ruins ↔ zone_02_swamp` (`to_ruins` 456,144 ↔ `from_ruins` 440,150), `zone_04_ruins ↔ zone_03_mountains` (`to_ruins` 392,48 ↔ `from_ruins` 376,54), `zone_04_ruins ↔ zone_05_finale` (`to_finale` 468,214 ↔ `from_ruins` 32,214) и обратный `to_ruins` 12,214 → `from_finale` 320,214. Тест обходит граф от хаба и проверяет все адреса.
- **Артефакты:** `world/zones/zone_04_ruins/` (сцена, scene/backdrop/foreground/glow/puzzle, .uid), `world/zones/zone_05_finale/` (сцена, backdrop/foreground/arena/ending_hook, .uid), `data/zones/zone_04_ruins.tres`, `zone_05_finale.tres`, `world/props/lever.*`, `world/props/sealed_gate.*`, `tests/integration/test_zone_04_05.gd` (11 тестов / 241 assert). Генератор: `tests/tools/build_zones_04_05.gd` + раннер-сцена `build_zones_04_05.tscn` (запуск `godot --headless --path game res://tests/tools/build_zones_04_05.tscn`).
- **Evidence (portable Godot 4.4.1-stable, clean worktree `6bad0f2`, `GODOT_PATH`):** `--headless --import` exit 0; GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **218/218 passed, 2594 asserts**, 0 падений; smoke `--headless --path game --quit` exit 0; `zone_04_ruins.tscn` и `zone_05_finale.tscn` с `--quit-after 120` — exit 0 без script-ошибок. Визуальный smoke (non-headless, OpenGL, 480×270 PNG): видны жёлтый столб `gold-9` над костром и красный `blood-3` над алтарём руин, четыре ступени и рычаги; финал — серая шахта/монолиты, `blood-3`-руна арены и трещины. Скриншоты — временные (`%TEMP%\opencode\t16_zone4_final.png`, `t16_zone5.png`), в репозиторий не добавлены.
- **Найденные/исправленные проблемы:** (1) шаги к верхнему входу были по 32 px при `h_jump = 32` — заменены на 16-px ступени (4 ряда); (2) дверь стояла на 368 и наполовину в стене (ячейка 23 = 368–384) — перенесена в 376 по центру проёма; (3) при ambient 0.26 руины читались почти чёрными — добавлен эмиссивный CanvasLayer-отсвет (DESIGN §8.7) и усилены локальные источники; (4) `-s`-запуск генератора не видит autoload-имена (после T-26 `bonfire.gd` использует `GameState`) — генератор запускается через сцену-раннер; (5) `assert_almost_eq` для Vector2 в тесте заменён на `assert_eq`.
- **Кросс-файловые правки:** `data/zones/zone_02_swamp.tres` и `zone_03_mountains.tres` (+1 entry `from_ruins`, +1 exit `to_ruins` — обратные связи), `tests/integration/test_zone_02_03.gd` (в словарь графа добавлены зоны 4–5). `ZoneScene`/`ZoneData`/`Props` T-13, сцены T-14/T-15 и `docs/TASKS.json` не менялись; файлы T-30 (`entities/bosses/`, `data/bosses/`) не тронуты.
- **Ограничения:** сама концовка/финальная последовательность — T-32; реализация `FactionManager` — T-27; босс, барьеры и триггер арены — T-32; ability gates — T-09; полноценный перф-пасс — T-37. Арт — программные заглушки. Независимые приёмка QA и ревью Guardian Tasker'ом не выполнялись.
- **Коммит:** `6bad0f2` «T-16: зоны 4–5 «Руины-храм» и «Финал»»; запись журнала — отдельным docs-коммитом (в него входит уже лежавшая в рабочем дереве append-only запись Orchestrator о запуске T-16, её содержимое не правил).

## 2026-10-18 — T-32 выполнен (tasker-backend)

- **Skills:** загружен `godot` (типизированный GDScript, `BossBase`/`Resource`/`.tres`, `CharacterBody2D`/`Area2D`, Control/UI-компоненты T-18, GUT/headless — профильный стек задачи). Другие skills не требовались: нет React/PostgreSQL/Docker/Go/Python-контекста.
- **Задача:** T-32 «Босс 5 (финал)» (TASKS T-32; PLAN §2.1/§3.1; SPEC US-03/AC-03.4, US-06; T-30 framework + T-16 арена). Статус в TASKS не менялся (`pending` до QA/Guardian).
- **Босс:** `Zone05Boss` (`entities/bosses/zone_05/`) на `BossBase`; данные `data/bosses/zone_05_boss.tres`: 3 фазы `ash_cleave` → `pyre_fan` → `last_rites`, пороги 66/33 из `BossData` (параметризованы). Нарастающая сложность: урон 10→13→17, скорость 44→56→72, кулдаун 1.5→1.15→0.85, телеграф 0.5→0.38→0.28; II — ближний удар + веер 3 снарядов, III — 5 снарядов + 2 призыва «эха». HP 360, награда `sovereign_crown` 300 золота; EC-09 через `GameState.mark_boss_defeated`/`queue_boss_reward`.
- **Арена:** `zone_05_arena.gd` — спавн в `BossSpawn` (ноги на полу), `Trigger` + два физических барьера, `GameState.in_combat` (EC-06); `EndingExit.gate_on_boss_id = zone_05_sovereign`, выход разблокируется после победы (проверка по `GameState`), барьеры открываются. Повторный вход после победы: босс не появляется, отложенная награда добирается (EC-09).
- **Концовка:** `ui/ending/` — `EndingText` + `EndingCatalog` (нейтральная при заглушке `FactionManager`, отдельные эпилоги для фракций, безопасное чтение `has_method`/поля), `EndingScreen` на `AshenPanel`/`AshenMenuItem`/`AshenPrompt`/`UITokens`, `CreditsScreen`, `EndingSequence` (ступенчатое затемнение → концовка → титры, отключение физики игрока). Сигнал хука T-16 `ending_requested` подключён.
- **Кросс-файловые правки:** `world/zones/zone_05_finale/zone_05_finale.tscn` (gate + `EndingSequence`), `tests/integration/test_zone_04_05.gd` (ожидания T-16 «арена пуста» заменены контрактом T-32), `core/combat/hitbox.gd` (guard `not monitoring` — устранён runtime-error `get_overlapping_areas` при гонке deferred-деактивации).
- **Evidence (чистый worktree, коммит `3e5c218`, portable Godot 4.4.1):** `--headless --import` exit 0; GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **225/225 passed, 2717 asserts, 0 падений** (+7 тестов T-32); smoke `--headless --path game --quit` exit 0; smoke `res://world/zones/zone_05_finale/zone_05_finale.tscn --quit-after 120` exit 0 без script-ошибок. E2E в GUT: вход в арену → 3 фазы → победа → концовка (нейтральная при заглушке) → титры; отдельные тесты — зависимость текста от фракции и EC-09.
- **Ограничения:** T-27 (`FactionManager`) и T-19 (HUD-панель босса) ещё не реализованы — фракционная концовка проверена через каталог/последовательность, HUD получает события фаз, но панель появится в T-19. Арт — программные заглушки. Независимая приёмка QA и ревью Guardian не заменяются этим smoke.
- **Коммит:** `3e5c218` «T-32: финальный босс + концовка по фракции». Запись журнала оставлена некоммиченной: в рабочем дереве параллельно есть незакоммиченные правки Orchestrator/T-17.

## 2026-10-18 — T-17 выполнен (tasker-backend)

- **Skills:** загружен `godot` (типизированный GDScript, autoload/сигналы, `ResourceLoader.load_threaded_request`, CanvasLayer/Control, `PackedScene`, GUT/headless — профильный стек переходов зон и экрана загрузки). Другие skills не требовались: задача не затрагивает React/PostgreSQL/Docker/Go/Python.
- **Задача:** T-17 «Переходы зон и экран загрузки» (TASKS T-17; PLAN §2.1/§2.2/§2.3/§3.2; SPEC US-04/AC-04.1, EC-03/EC-12; DESIGN §5/§6.6). Статус в TASKS не менялся (`pending` до QA/Guardian).
- **SceneRouter:** полный переход — `change_zone(zone_id, entry_id)`, `ResourceLoader.load_threaded_request` + поллинг `load_threaded_get_status` в `_process`, бюджет `LOAD_TIMEOUT = 3.0` с, минимальный показ экрана 0.05 с. Заменяется только `WorldRoot`: старая зона снимается с дерева и освобождается, новая инстанцируется; HUD/UI/Toasts/Overlay не трогаются. Игрок один на забег: переносится между зонами, ставится на `ZoneEntryPoint.position` из ZoneData, `reset_player()` и `fall_death_y` из нижней границы `WorldBounds` (EC-03). Сигнал `transition_started/finished/failed`, `last_load_seconds` для evidence. `bootstrap()` — синхронный первый вход из `Main.gd` (инициализация мира, а не переход; все дальнейшие переходы — фоновые). `reset()` — новая игра/тесты. Контракт T-13 `instantiate_zone()` сохранён.
- **Экран загрузки:** `ui/loading/LoadingScreen.tscn/.gd` — CanvasLayer 40, чёрный фон `void`, название зоны h2 `gold-3`, эпиграф из `ZoneData.epigraph`, спиннер 4 шага (`FADE_TIME/4`, ровно один lit). Ввод во время показа игнорируется по EC-12: физика игрока выключена SceneRouter'ом, буфер `InputManager` очищается, события поглощаются `LoadingScreen._input` до конца загрузки.
- **Corpse run:** метка гибели из `GameState` переспавнивается при входе в её зону; при выходе узел освобождается вместе с зоной, при повторном входе появляется снова. Дубликат с `DeathHandler` (его `zone_entered`-хук) исключён проверкой существующего узла в той же точке.
- **Сигнал для T-34:** в `EventBus` добавлен `zone_loaded(zone_id, display_name)` — эмитится после скрытия экрана и расстановки игрока; AudioManager подпишется для кроссфейда музыки (AC-07.2). `zone_entered` из ZoneScene сохранён как есть.
- **Кросс-файловые правки:** `autoload/EventBus.gd` (+`zone_loaded`), `autoload/InputManager.gd` + `core/input/input_buffer.gd` (`clear_buffered_input()`/`clear()` — EC-12), `Main.gd` (bootstrap), `world/zones/zone_data.gd` (+`epigraph`) и 5 `data/zones/*.tres` (тексты эпиграфов). Файлы T-32 (`entities/bosses/zone_05/`, `ui/ending/`, `data/bosses/`) и `tests/_probe.gd` не трогались.
- **Evidence (чистый worktree от коммита `4649c2b`, portable Godot 4.4.1-stable, `GODOT_PATH`):** `--headless --import` exit 0 без ошибок; GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **248/248 passed, 2937 asserts, 0 падений** (+10 тестов `test_scene_router.gd`: переход туда/обратно, экран/ввод, fall-лимит, corpse, `zone_loaded`, выход-триггер, 10 переходов без утечек узлов, bootstrap, битая зона); smoke `--headless --path game --quit` exit 0 без ERROR/script-ошибок; `--quit-after 120` exit 0. Повторный полный прогон на том же коммите — 248/248 (первый прогон дал единственное падение известной флаки `test_boss` по 95-му перцентилю физики при параллельно работающем чужом Godot-процессе; отдельно `test_boss` — 11/11).
- **E2E/smoke как пользователь:** временный `SceneTree`-скрипт на реальном `Main.tscn`: boot `zone_01_village` → игрок (100, 214) → `change_zone(zone_02_swamp, west_gate)`: `active=true`, `input_locked=true`, экран виден, физика игрока off → после загрузки зона `zone_02_swamp`, игрок (32, 214), `load_s=0.054`, `fall_y=270.0`, ввод разблокирован, экран скрыт → обратно `zone_01_village/from_gate`, игрок (245, 214), `zones=1`, `players=1`. Локальный рендер LoadingScreen (OpenGL, 480×270, `%TEMP%\opencode\t17_loading.png`): чёрный фон, золотое «БОЛОТО», эпиграф, 4-шаговый спиннер.
- **Найденное/исправленное:** (1) `EventBus.zone_entered` эмитится в `ZoneScene._ready` — старую зону нужно снимать с дерева до `add_child` новой, иначе `DeathHandler` спавнит corpse в старой зоне; (2) при показе экрана в том же кадре, что и `add_child`, `@onready`-узлы ещё не разрешены — LoadingScreen разрешает их лениво; (3) выход рядом с точкой входа давал мгновенный обратный переход — добавлен `EXIT_GRACE_TIME = 0.25 с`; (4) мгновенный headless `--quit` обрывал threaded-загрузку стартовой зоны — первый вход сделан синхронным `bootstrap()` (переходы остались фоновыми); (5) `fall_death_y` после `bootstrap` застывал из-за выключенного `_process` — grace-таймер включает обработку.
- **Ограничения:** камера/следование за игроком не входят в T-17 (HUD/камера T-19); загрузка идёт через threaded-запрос, но при мгновенном выходе процесса отмена потока — забота движка; арт экрана/спиннера — программные примитивы по макету. Осталась одна известная флака вне задачи: `test_boss.test_long_boss_fight_stays_within_60hz_physics_budget` в общем прогоне на загруженной машине (в чистом прогоне и отдельно — зелёный; код боссов не менялся). Независимая приёмка QA и ревью Guardian не заменяются этим smoke.
- **Коммит:** `4649c2b` «T-17: переходы зон + экран загрузки». Запись журнала оставлена некоммиченной: в рабочем дереве параллельно лежат незакоммиченные записи Orchestrator/T-27/T-32.

## 2026-10-18 — T-27 выполнен (tasker-backend)

- **Skills:** загружен `godot` (типизированный GDScript, autoload/`GameState`, `Resource`/`class_name`/`.tres`, сигналы `EventBus`, сериализация `FileAccess`/JSON/schema-миграции, GUT/headless — профильный стек задачи). Другие skills не требовались: React/PostgreSQL/Docker/Go/Python-контекста нет.
- **Задача:** T-27 «Фракции: репутация, доступ, квесты, концовка» (TASKS T-27; PLAN §2.1/§2.2/§3.4; SPEC US-06, AC-06.1/06.2, EC-11). Статус в `docs/TASKS.json` не менялся (`pending` до QA/Guardian).
- **Данные:** `data/factions/faction_data.gd` + 3 `.tres` — `order` («Орден Пепла», порог 10), `free` («Вольные Марки», порог 0), `ash` («Культ Пепла», порог 5). В ресурсе: имя/ключ локализации/лор/цвет, шкала −100…+100, порог доступа, шаблоны причин отказа (территория/торговец/квест), `alternative_faction_id` (EC-11), Δ-таблица `reputation_events` (квесты `quest_*` и действия `action_*`) и список квестов. В коде фракций/порогов/чисел нет — только загрузка и валидация (`is_valid`: пустые id, дубликаты, порог вне шкалы, нулевые Δ).
- **FactionManager:** реестр с детерминированным порядком id; геттеры репутации/имени/лора/цвета/таблицы; `set_reputation` с clamp и сигналами, `add_reputation`; `apply_reputation_event`/`complete_quest` — применяет Δ ко всем фракциям и возвращает `{faction_id, delta, value, reaction, access_granted}` (AC-06.1). Доступ: `can_enter_territory`/`can_trade`/`can_access`, полный `get_access_info` с `reason`, порогом, текущей репутацией и альтернативой; квесты — `get_quest_owner`/`get_faction_quests`/`get_quest_access` (`available`, `reason`, `alternative_faction_id`, `alternative_allowed`, конкретный `alternative_quest_id`) (AC-06.2, EC-11). Реакция NPC — `hostile/wary/neutral/friendly/trusted` по смещению от порога. Выбор/концовка — `choose_faction`, `get_selected_faction` (явный выбор или `&""`), `get_ending_faction_id` (выбор, иначе лучшая фракция с положительной репутацией), `get_best_faction`.
- **Состояние/сейв (schema v4):** состояние — `GameState.factions` (id → int) и `GameState.chosen_faction` (`restore_factions`/`reset_factions`); `SaveSerializer` пишет `state.factions` и `state.chosen_faction`, применяет их через `restore_factions`; `SaveMigrations.CURRENT_VERSION = 4`, шаг `_v3_to_v4` даёт дефолты `{}`/`""`, существующие поля не меняет. T-25-контракт (checksum, атомарность) не тронут.
- **Сигналы (`EventBus`):** `faction_reputation_changed(faction_id, value)` (T-24), `faction_access_changed(faction_id, granted)`, `faction_quest_completed(quest_id, faction_id, delta, reaction)` (T-28), `faction_chosen(faction_id, display_name)` (T-32). Коммит содержит только этот блок: незакоммиченный `zone_loaded` параллельной T-17 в рабочем дереве оставлен как есть.
- **Контракт для T-28:** перед выдачей — `get_quest_access(quest_id)` (объяснение + альтернатива), завершение — `complete_quest(quest_id)`; торговец — `can_trade(faction_id)`/`get_access_info(..., TRADER).reason`, территория — `can_enter_territory`/`TERRITORY`; реакцию NPC брать из `get_npc_reaction` или сигнала `faction_quest_completed`. **T-24:** `get_faction_ids/name/lore/color`, `get_reputations`, `get_reputation_table`, `get_access_info` + сигналы для вкладки «Фракции». **T-32:** `get_selected_faction()` — стабильный id выбора (пусто → нейтральная концовка), `get_faction_name()` — имя для эпилога; `get_ending_faction_id()` доступен как fallback «лучшая фракция», но текущий T-32 читает `get_selected_faction` первым.
- **Тесты:** `tests/unit/test_factions.gd` — 11 тестов: реестр/валидность данных, Δ-таблица, изменение репутации квестом + сигналы/реакция/доступ (AC-06.1), шкала реакции NPC, отказ территории и торговца с причиной (AC-06.2), пересечение порога, альтернатива через союзную фракцию и её закрытие (EC-11), выбор/лучшая фракция для концовки (US-06), clamp, restore/reset, неизвестная фракция. `test_save.gd` — +2 теста (v3→v4 дефолты, round-trip `factions`/`chosen_faction`) и обновлённый v2→current.
- **Evidence (portable Godot 4.7.2-stable, headless):** исходный HEAD `3e5c218` — GUT **225/225, 2717 asserts**; чистый worktree на коммите `dec13a1` — `--headless --import` exit 0 без script/parse-ошибок, GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **238/238 passed, 2840 asserts, 0 падений** (+13 тестов), smoke `--headless --path game --quit` exit 0, `res://Main.tscn --quit-after 60` exit 0 без ERROR. В рабочем дереве вместе с незакоммиченной T-17 — **247/247, 2929 asserts** (интеграция с `SceneRouter`/`LoadingScreen`).
- **Найденное/исправленное:** при первой правке `save_migrations.gd` функция `_default_max_hp` осталась на одной строке с телом — импорт дал Parse Error; исправлено до коммита, повторный `--import` чистый. Других регрессий не найдено.
- **Кросс-файловые правки:** `autoload/GameState.gd` (+60 строк: `factions`, `chosen_faction`, 4 метода), `autoload/EventBus.gd` (+4 сигнала), `core/save/save_serializer.gd` (+поля/хелпер), `core/save/save_migrations.gd` (v4), `tests/unit/test_save.gd`. `FactionManager.gd`, `data/factions/`, `tests/unit/test_factions.gd` — новые/свои. `docs/TASKS.json`, `test_final_boss.gd`, `ui/ending/`, T-17-файлы и `tests/_probe.gd` не менялись.
- **Ограничения:** квестовой системы/NPC-сущностей ещё нет (T-28) — доступ и Δ проверены API-тестами, не сценарным диалогом; мир не содержит триггеров территории/торговцев (их подключает T-28/T-24); выбор фракции не блокируется после первого раза (UI решает); текущая концовка T-32 использует явный выбор, «лучшая фракция» — отдельный API. Независимая приёмка QA и ревью Guardian не заменяются этим smoke.
- **Коммит:** `dec13a1` «T-27: фракции — репутация/доступ/концовка + сериализация v4». Запись журнала оставлена некоммиченной: в рабочем дереве параллельно лежат незакоммиченные записи Orchestrator/T-17/T-32.



## 2026-10-18 — T-19 выполнен (tasker-frontend)

- **Skills:** загружен `godot` (типизированный GDScript, CanvasLayer/Control, `AshenBar`/`AshenSlot`/`AshenPanel`/`AshenKbd`/`AshenPrompt` из T-18, сигналы `EventBus`, GUT/headless, рендер 480×270 — профильный стек HUD). Другие skills не требовались: React/PostgreSQL/Docker/Go/Python-контекста в задаче нет.
- **Задача:** T-19 «HUD» (TASKS T-19; PLAN §2.3 — CanvasLayer 10; DESIGN §6.3/§9; макет `docs/mockups/hud.html`). Статус в `docs/TASKS.json` не менялся (`pending` до QA/Guardian).
- **Реализация:** `ui/hud/HUD.tscn` + `HUD.gd` (CanvasLayer 10, раскладка в 480×270 с safe-зоной 8 px): портрет и уровень (`УР7`, поле-заглушка T-29), HP `AshenBar` с числом и следом урона, выносливость, 3 слота способностей (`double_jump`/`dash`/`wall_climb`; закрытые — замок + приглушённая программная иконка), полоса кулдауна снизу слота, 4 быстрых слота-заглушки с клавишами 1–4, панель валюты (`1 240`) и очков обучения (`ОП 3`), название зоны, мини-карта-заглушка (комнаты/проход/замок/метка игрока), контекстная подсказка `AshenPrompt` (глиф по `InputManager.active_device`), подсказка «Нужно: …» с замком, панель босса. HP<25 % — мигание 1 Гц ступенями + подпись «КРИТИЧНО» + ступенчатая кайма 3/6/9 px по краю; `Config.no_flash` отключает мигание, оставляя статичную кайму. 0 выносливости — «!» + «НЕТ СИЛ» (AC-03.3).
- **Панель босса (`boss_bar.gd`):** `begin_fight`/`set_health`/`set_phase`/`end_fight`; имя, подпись «ФАЗА II / III», `AshenBar` BOSS (248×8), метки фаз из `boss_fight_started.phase_thresholds` (33/66 %) поверх шкалы, уведомление «ФАЗА II» + подзаголовок из `boss_phase_changed.phase_title`; вне боя скрыта. Подписки: `boss_fight_started`, `boss_health_changed`, `boss_phase_changed`, `boss_defeated`, `zone_entered` (сброс при переходе).
- **Контракты заглушек:** T-07 — `EventBus.ability_cooldown_changed(ability_id, remaining, duration)` или `hud.start_ability_cooldown(&"dash", c_dash)`; T-09 — `EventBus.ability_hint_changed(ability_id, required)` или `hud.show_ability_hint(id)`/`hide_ability_hint()` (после получения способности подсказка гаснет сама); T-29 — `hud.set_level(n)`/`set_training_points(n)`, а при появлении `GameState.level`/`GameState.training_points` HUD подхватывает их поллингом; T-33 — `hud.set_minimap_data({"player_room": Vector2i, ...})`, неизвестные/битые поля игнорируются, `_MinimapStub` заменяется на `minimap.gd` с сохранением API; T-21 — `hud.set_quick_slot(index, item_id, count, icon)`. Валюта (`GameState.currency`, сигнала нет) обновляется поллингом каждый кадр; HP/выносливость/способности — сигналами `player_health_changed`/`stamina_changed`/`ability_acquired` + полный ресинк на `save_loaded`/`player_respawned`.
- **Тесты:** `tests/unit/test_hud.gd` — 17 тестов, 123 assert: слой/кадр/safe-зона всех элементов, HP и критическое состояние (мигание + «Без мигания»), выносливость 0 и «НЕТ СИЛ», замок/иконка/открытие способности, кулдаун dash (полоса, сигнал T-07), быстрые слоты, валюта/очки/уровень, зона и мини-карта, глифы клавиатура→Xbox→клавиатура (EC-08), ability hint API + сигнал T-09 + автогашение, босс (скрыт вне боя, HP, метки 33/66, «ФАЗА II», автоскрытие уведомления, победа), скрытие подсказки в бою, контраст токенов.
- **Evidence (чистый worktree от коммита `c1b8a69`, portable Godot 4.4.1-stable):** `--headless --import` exit 0 без ошибок; GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **265/265 passed, 3060 asserts, 0 падений** (+17 тестов T-19); smoke `--headless --path game --quit` exit 0; smoke `res://ui/hud/HUD.tscn --quit-after 60` exit 0; в логах нет ERROR/SCRIPT ERROR. Локальный рендер (OpenGL, 480×270): `%TEMP%\opencode\t19_hud_normal.png` (HP 74/100, выносливость, closed/open слоты, зона, мини-карта, «Нужно: РЫВОК», подсказка E, быстрые слоты, кошелёк) и `t19_hud_boss.png` (HP 20/100 + «КРИТИЧНО» + кайма, «НЕТ СИЛ», панель босса с «ФАЗА II» и метками 33/66, скрытая подсказка).
- **Найденное/исправленное:** (1) Root Control с full-rect anchors + явный `size` давал удвоенный размер (960×540) и ломал правые/нижние привязки — установка `size` убрана, layout считается от viewport; (2) минимальный размер панели кошелька (94×42) выталкивал её за safe-зону — панель расширена до 96×44, тест safe-зоны зелёный; (3) `PANEL_MARGIN` ошибочно брался из `UITokens` вместо `UIStyle` — исправлено на этапе импорта.
- **Кросс-файловые правки:** `autoload/EventBus.gd` (+2 сигнала-контракта `ability_cooldown_changed`, `ability_hint_changed` с документацией; HUD подключается к ним через `has_signal`, поэтому совместим и без них). `docs/TASKS.json`, `Main.gd`/`Main.tscn`, `ui/loading/`, `autoload/SceneRouter.gd`, файлы T-29 (`core/progression/`, `data/balance/`, `entities/npc/`) и untracked `opencode.jsonc`/`tests/_probe.gd` не трогались.
- **Ограничения:** `HUD.tscn` ещё не инстанцирован в `Main.tscn` (пустой слой `HUD` оставлен сборке/интеграции, чтобы не пересекаться с T-17); источники кулдауна/подсказки — T-07/T-09, очки/уровень — T-29, мини-карта — T-33; арт портрета/иконок — программные заглушки. При прогоне в рабочем дереве один раз упал известный перф-тест `test_boss` (95-й перцентиль физики 22–27 мс) — в чистом worktree тот же тест зелёный (265/265). Независимые приёмка QA и ревью Guardian Tasker'ом не выполнялись.
- **Коммит:** `c1b8a69` «T-19: HUD — HP/выносливость/способности/босс-бар». Запись журнала оставлена некоммиченной: в рабочем дереве параллельно лежат незакоммиченные записи Orchestrator/T-17/T-27/T-32 и правки T-29.

## 2026-10-18 — T-29 выполнен (tasker-backend)

- **Skills:** загружен `godot` (типизированный GDScript, `Resource`/`class_name`/`.tres`, autoload/`GameState`, сигналы `EventBus`, schema-миграции `SaveSerializer`/`SaveMigrations`, GUT/headless — профильный стек задачи). Другие skills не требовались: React/PostgreSQL/Docker/Go/Python-контекста нет.
- **Задача:** T-29 «Прогрессия: характеристики, очки обучения, учителя» (TASKS T-29; PLAN §2.1/§3.4; SPEC US-08, AC-08.1/08.2). Статус в `docs/TASKS.json` не менялся (`pending` до QA/Guardian).
- **Данные:** `data/balance/progression_data.gd` + `progression.tres`: 4 характеристики (сила/ловкость/выносливость/здоровье), старт 5, максимум 20, строго растущие таблицы стоимости шагов (1, 2, 3 … 20), накопительные пороги XP (100 … 3250), 2 очка обучения за уровень, XP за врагов/квесты, требования экипировки (`light_dagger` — ловкость 8, `two_handed_axe` — сила 9). `TeacherData` + 3 учителя (`quartermaster` — сила, `huntress` — ловкость, `elder` — здоровье) с навыками, стоимостью и предусловиями. Все `.tres` валидируются (`is_valid`) до рантайма.
- **Ядро:** `core/progression/progression_rules.gd` — цена шага, XP→уровень, начисление очков, `check_requirements` (+ reason с требуемым/текущим значением), требования экипировки. `equipment_requirements.gd` — чистый контракт `{stat_id: min}` для T-21: `met`/`missing`/`reason` («НЕТ · ещё N» берётся из `deficit`). `entities/npc/teacher.gd` — тренировка +1 за очки (AC-08.1), карточка/покупка навыка с предусловиями (AC-08.2), `get_interact_info()` для диалога T-28.
- **GameState:** `stats`, `learning_points`, `level`, `xp`; `train_stat`, `add_xp`, `award_quest_xp`, `spend_learning_points`, `get_equipment_info`; опыт за врагов начисляется автоматически по `EventBus.enemy_died` (таблица `enemy_xp`); здоровье повышает max HP, выносливость — max stamina; алиас `training_points` для HUD T-19.
- **Сигналы (`EventBus`):** `stat_changed(stat_id, value, next_cost)`, `learning_points_changed(points)`, `level_changed(level, points_awarded)`, `xp_changed(current_xp, xp_to_next)`.
- **Сериализация (schema v5):** `state.stats`, `state.learning_points`, `state.level`, `state.xp`; `SaveMigrations.CURRENT_VERSION = 5`, шаг `_v4_to_v5` (стартовые stats из `progression.tres`, 0 LP, уровень 1, 0 XP), `SaveSerializer.apply_state` применяет прогрессию до HP/выносливости; `SaveManager` подставляет `level` в метаданные слота, если вызывающий не передал его явно.
- **Контракт для T-21:** `GameState.get_equipment_info(item_id)` → `{item_id, requirements, met, missing: [{stat_id, required, current, deficit}], reason}`; `GameState.check_requirements({stat_id: min})` — для навыков/предметов; `get_stat_name`/`get_stat_ids`. **T-19:** `GameState.level`/`learning_points` (+алиас `training_points`) и сигналы. **T-28:** `Teacher.get_interact_info()`, `train()`, `get_skill_info(id)`, `learn_skill(id)`; опыт квеста — `GameState.award_quest_xp(id)`.
- **Тесты:** `tests/unit/test_progression.gd` — 13 тестов, 185 asserts: данные/таблицы, +1 и рост стоимости (AC-08.1), отказ без очков/на максимуме, учитель, XP/уровни/очки, XP за врагов/квесты, блокировка навыка с требуемым значением (AC-08.2), успешное изучение, требования экипировки для T-21, HP/выносливость, валидация restore/сигналы. `test_save.gd` — +2 теста (v4→v5 дефолты, round-trip прогрессии) и обновлённые v2/v3→current.
- **Evidence (чистый worktree `4c63ff3`, portable Godot 4.4.1-stable, `GODOT_PATH`):** `--headless --import` exit 0 без script/parse-ошибок; GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **280/280 passed, 3294 asserts, 0 падений** (+13 T-29 и +2 test_save к базовым 265); smoke `--headless --path game --quit` exit 0; `res://Main.tscn --quit-after 120` exit 0 без ERROR/script-ошибок. Промежуточный прогон дал единственное падение известной флаки `test_boss` (p95 физики 0.0176 с), изолированно `test_boss` — 11/11 (p95 0.0099 с); повторный полный прогон чистый. Smoke как пользователь (headless-сцена на чистом worktree): учитель повысил силу 5→6→7 (стоимость 1→2→3), `iron_guard` заблокирован с «ТРЕБУЕТСЯ: СИЛА 10 (у вас 7); ВЫНОСЛИВОСТЬ 7 (у вас 5)», после strength 10/endurance 7 изучен, топор требует силу 9, save/load восстановил stats 9/7/6/8, LP 5, уровень 3, XP 300, HP-max 115.
- **Найденное/исправленное:** (1) стартовая сила 5 делала дефолтный меч «непригодным» — требования меча убраны, требования остались у тяжёлого топора и кинжала; (2) `GameState.hp_max`/`stamina_max` стали производными от характеристик — restore прогрессии вынесен до восстановления HP/выносливости, иначе clamp терял бонус; (3) `Stamina` получил `set_maximum(value, grant_delta)`, чтобы повышение выносливости не сбрасывало текущее значение; (4) слот-метаданные писали уровень 0 — `SaveManager` берёт `GameState.level`, если level не передан.
- **Кросс-файловые правки:** `autoload/GameState.gd` (+прогрессия/экипировка/XP), `autoload/EventBus.gd` (+4 сигнала), `autoload/SaveManager.gd` (level в метаданных), `core/combat/stamina.gd` (`set_maximum`), `core/save/save_serializer.gd`/`save_migrations.gd` (v5), `tests/unit/test_save.gd`. Новые: `core/progression/`, `data/balance/progression*`, `data/balance/teacher_data.gd`, `data/balance/teachers/`, `entities/npc/teacher.gd`, `tests/unit/test_progression.gd`. `docs/TASKS.json`, `ui/`, T-19/T-33-файлы и `opencode.jsonc` не трогались.
- **Ограничения:** сцены/диалоги учителей — T-28 (учитель пока класс без `.tscn`, данные и API готовы); экран инвентаря — T-21 (контракт `get_equipment_info` покрыт тестами); квестовой системы нет — `award_quest_xp` вызывает T-28; арт/локализация имён — заглушки до T-36. Независимые приёмка QA и ревью Guardian Tasker'ом не выполнялись.
- **Коммит:** `4c63ff3` «T-29: прогрессия — характеристики/очки/учителя + сериализация v5». Запись журнала оставлена некоммиченной: в рабочем дереве параллельно идут правки T-33 (`SceneRouter`, zone data, `ui/map`, `ui/hud`).

## 2026-10-18 — T-33 выполнен (tasker-frontend)

- **Skills:** загружен `godot` (типизированный GDScript, `Resource`/`class_name`/`.tres`, CanvasLayer/Control `_draw`, `AshenPanel`/`AshenMenuItem`/`AshenPrompt` из T-18, `EventBus`/autoload, GUT/headless, пиксельный рендер 480×270 — профильный стек карты/UI). Другие skills не требовались: React/PostgreSQL/Docker/Go/Python-контекста нет.
- **Задача:** T-33 «Полная карта мира и миникарта» (TASKS T-33; PLAN §5 — недостающий макет; SPEC US-04/AC-04.2; DESIGN §4.3/§5). Статус в `docs/TASKS.json` не менялся (`pending` до QA/Guardian).
- **Данные (из ZoneData, не хардкод в UI):** новый `ZoneRoom` (`id`, `grid_position` в сетке 12×9, `world_rect` 480×270); `ZoneData.map_rooms`/`map_bonfires` (+валидация комнат/костров), `ZoneExit.required_ability`. В 5 `.tres` заданы клетки: деревня (1,6), болото (4,6), горы (7,6), руины (7,3), финал (10,3), костры — из мировых координат сцен; `zone_template` получил комнату-образец. Закрытые проходы помечены на той стороне, где реальный забор: деревня/уступ — `double_jump`, болото→руины — `dash`, горы→руины — `wall_climb`.
- **Посещённость:** `SceneRouter.visited_zone_ids` + сигнал `zone_visited`, `mark_zone_visited`/`get_visited_zone_ids`/`restore_visited_zones`/`reset_visited_zones`; зона отмечается в `_apply_zone` и по `EventBus.zone_loaded` (идемпотентно), `reset()` очищает. Карта не хранит своего геймплейного состояния.
- **Модель:** `ui/map/world_map_model.gd` — чистая `WorldMapModel`: читает `data/zones/*.tres` (шаблон исключён), строит снимок `{rooms, links, gates, bonfires, player, player_room}` из посещённых зон, текущей зоны/позиции и набора способностей. Скрытая информация — ровно один уровень: комната непосещённой зоны не раскрывается, но проход к ней виден маркером; закрытый проход несёт `required_ability`, замок и не раскрывает имя цели. Связи дедуплицируются по паре зон.
- **UI:** `ui/map/WorldMap.tscn`/`WorldMap.gd` — CanvasLayer 20, затемнение, панель посещённых зон (`AshenMenuItem`, видимый фокус), карта `MapRenderer` (клетка 23×17), детали «ТЕКУЩАЯ/ПОСЕЩЕНА · КОСТЁР · ЗАКРЫТО: <способность>», легенда «ЗАМОК/ОГОНЁК/РОМБ». Открытие/закрытие — новое действие `map` (M / BACK геймпада) и `ui_cancel`, пауза мира; навигация ↑/↓/←/→ без мыши, Enter не уходит в мир. `MapRenderer` общий с миникартой: посещённые — заливка+контур, текущая — двойная золотая рамка+метка игрока, костёр — форма огонька, закрытый проход — замок+иконка способности; сетка неизведанных клеток видна на полной карте.
- **Миникарта:** `ui/hud/minimap.gd` (`AshenMinimap`, 96×54, комнаты 8×6, без подписей) заменила `_MinimapStub` T-19 с сохранением API `set_minimap_data`/`get_minimap_data`/`get_minimap`/`panel`; HUD сам синхронизирует тот же снимок по `visited_zone_ids` + `GameState.current_zone_id` + позиции игрока + способностям, внешний `set_minimap_data({...})` остаётся override до пустого словаря.
- **Тесты:** `tests/unit/test_map.gd` — 17 тестов, 136 asserts: 5 зон/уникальные клетки/валидность `.tres`, скрытие непосещённых и маркер прохода, способность/замок/открытие после получения, костры, дедупликация связей, текущая зона и клетка игрока, совпадение снимков HUD↔полной карты, геометрия 96×54/8×6, открытие/закрытие `map`/`ui_cancel`, навигация с фокусом, текст деталей/легенда, трекинг `zone_loaded`/restore.
- **Evidence (портативный Godot 4.4.1-stable, чистые worktree):** `e226a45` (T-33 до T-07) — `--headless --import` exit 0, GUT **297/297, 3430 asserts** (280 базовых + 17 T-33); финальный `811c0ef` (поверх T-07) — import exit 0, GUT **308/308, 3503 asserts**, 0 падений; smoke `--headless --path game --quit` exit 0; `--quit-after 120` exit 0 без ERROR; `docs/init.ps1` с `GODOT_PATH` на `_console.exe` — exit 0, GUT **308/308, 3507 asserts**. В рабочем дереве один полный прогон дал известную флаки `test_boss` (p95 физики 0.0201 с), изолированно `test_boss` — 11/11. Smoke-сцена Main→карта (чистый worktree `e226a45`): зона 1 открывается (1 комната, 2 маркера, костёр), закрывается `ui_cancel`, переход в болото даёт 2 зоны/2 комнаты/1 связь. Локальный рендер 480×270: `%TEMP%\opencode\t33_map_all.png` (5 зон, связи, замок «КАРАБКАНЬЕ», текущая зона, костры, детали), `t33_map_two.png`, `t33_hud.png`/`t33_hud2.png` и `t33_minimap_zoom2.png` (миникарта 96×54: комнаты, костры, замки не закрывают комнату, метка).
- **Найденное/исправленное:** (1) в ZoneData не было данных карты — добавлены `ZoneRoom`/`map_rooms`/`map_bonfires`/`required_ability` с валидацией, иначе карта была бы хардкодом; (2) `MapRenderer` под full-rect anchors ругался на `size` в `_ready` — установка размера убрана, размер задаёт `custom_minimum_size`; (3) порядок зон сделан географическим (по клеткам), а не по id — список карты читается сверху вниз; (4) пустое поле карты заполнено сеткой клеток, иначе 5 комнат терялись; (5) `ability_display_name` HUD переведён на общий `WorldMapModel.ability_label`, чтобы подписи замков и слотов совпадали.
- **Кросс-файловые правки:** `autoload/SceneRouter.gd` (+посещённые зоны), `world/zones/zone_data.gd`/`zone_exit.gd`/`zone_room.gd`, `data/zones/zone_01…05.tres` + `zone_template.tres`, `ui/hud/HUD.gd`/`minimap.gd`, `Main.tscn` (инстанс карты), `project.godot` (действие `map`), новые `ui/map/*`, `tests/unit/test_map.gd`. Файлы T-29/T-07 (`core/progression/`, `core/save/`, `data/balance/`, `entities/npc/`, `core/abilities/`, `Player.gd`), `docs/TASKS.json`, `tests/_probe.gd`, `opencode.jsonc` не трогались.
- **Ограничения:** посещённые зоны пока не входят в сейв-схему T-25 (`SceneRouter` даёт `restore_visited_zones` для будущей интеграции) — после загрузки карта знает только текущую зону; комнаты — по одной на зону (сцена зоны 480×270), модель читает первую `map_rooms` (массив в данных допускает расширение, мультикомнатная раскладка не реализована); пауза карты отключается в QA через `WorldMap.pause_on_open`; арт/локализация подписей — заглушки до T-36. Независимые приёмка QA и ревью Guardian Tasker'ом не выполнялись.
- **Коммит:** `e226a45` «T-33: полная карта мира + миникарта» + `811c0ef` «T-33: маркеры прохода на миникарте не закрывают комнату» (после T-07). Запись журнала оставлена некоммиченной: в рабочем дереве параллельно лежат незакоммиченные записи Orchestrator/T-29.

## 2026-10-18 — T-07 выполнен (tasker-backend)

- **Skills:** загружен `godot` (типизированный GDScript, `Resource`/`class_name`/`.tres`, FSM игрока, `EventBus`, GUT на реальных 60 Hz physics-кадрах — профильный стек задачи). Другие skills не требовались: React/PostgreSQL/Docker/Go/Python-контекста нет.
- **Задача:** T-07 «Способность Dash» (TASKS T-07; PLAN §3.1 — `D_dash=48`, `T_dash=0.15`, `C_dash=0.6`; §3.3; SPEC US-02/AC-02.2). Статус в `docs/TASKS.json` не менялся (`pending` до QA/Guardian).
- **Контракт способности:** `core/abilities/ability_dash.gd` (`AbilityDash extends AbilityBase`, `ID=&"dash"`, `DISPLAY_NAME="Рывок"`, `MAX_COOLDOWN_SEC=1.0` для AC-02.2) + `data/abilities/dash.tres`; путь добавлен в `AbilityRegistry.ABILITY_PATHS`, поэтому T-09 (gates) и T-19 (слот) видят RU-имя и данные без хардкода.
- **Поведение:** `entities/player/states/dash.gd` — скорость `D_dash/T_dash` на всё время `T_dash`, i-frames на весь рывок, кулдаун `C_dash` стартует при входе. Гейт способности двойной: вход через `Player.try_dash()` (GameState + кулдаун + выносливость `E_dash`) и defence-in-depth в состоянии (без `GameState.has_ability(&"dash")` состояние не даёт i-frames и выходит на первом тике). Рывок доступен на земле (idle/run/land) и в воздухе (jump/fall/double_jump) — воздушные состояния получили вызов `try_dash()`.
- **Кулдаун/HUD:** `C_dash` берётся из `balancing.tres` и зажимается `AbilityDash.MAX_COOLDOWN_SEC` (≤1 с); остаток тикает по physics-кадрам в `Player._physics_process`, сбрасывается при возрождении (`reset_player`). `EventBus.ability_cooldown_changed(&"dash", remaining, duration)` эмитится на старте, каждый тик и с remaining=0 — контракт T-19 уже покрыт `test_hud`; нажатие в кулдауне не «съедается» из 150-мс буфера (проверки идут до `just_pressed`).
- **Тесты:** новый `tests/unit/test_ability_dash.gd` — 11 тестов, 73 asserts: контракт реестра/флаги, значения из `balancing.tres` и `C_dash ≤ 1 с`, отказ без способности (в т.ч. без i-frames при `force_state`), дистанция `D_dash` за `T_dash` (=9 тиков, 48 px), i-frames на каждом кадре, проход сквозь ловушку без урона vs тот же trap наносит урон вне i-frames, кулдаун блокирует второй рывок/тратит выносливость один раз, сигнал старта и завершения для HUD, рывок из Jump и Fall.
- **Evidence (чистый worktree `c13ebfe`, portable Godot 4.4.1-stable, `GODOT_PATH`):** `--headless --import` exit 0 без script/parse-ошибок; GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **308/308 passed, 3503 asserts, 0 падений** (+11 T-07 к базовым 297); smoke `--headless --path game --quit` exit 0; `res://Main.tscn --quit-after 120` exit 0 без ERROR. Пользовательский сценарий (headless-сцена на чистом worktree, реальный `Player.tscn` + trap-`Hitbox`): idle → dash state, i-frames=true, cooldown=0.600 → 9 тиков/48.00 px, HP 100→100 сквозь ловушку → готовность через 0.6 с, последнее событие `[&"dash", 0.0, 0.6]`.
- **Найденное/исправленное:** (1) без способности `force_state(&"dash")` больше не даёт рывок/i-frames — два старых теста использовали dash как «механику без гейта»; в `test_combat_hitbox` и `test_corpse_run` добавлена выдача способности перед рывком (проверяемый смысл тестов сохранён); (2) кулдаун стартует в `enter()`, а не в `try_dash()`, поэтому принудительные переходы тоже не обходят его; (3) при отказе в кулдауне нажатие остаётся в буфере, но `C_dash` (0.6 с) больше 150 мс — второй рывок не срабатывает сам.
- **Кросс-файловые правки:** `core/abilities/ability_registry.gd` (+dash), `entities/player/Player.gd` (+гейт/кулдаун/сброс), `entities/player/states/dash.gd` (гейт + кулдаун), `states/jump.gd`/`fall.gd`/`double_jump.gd`/`land.gd` (+воздушный/наземный dash), `tests/unit/test_combat_hitbox.gd`, `tests/unit/test_corpse_run.gd`. Новые: `core/abilities/ability_dash.gd` (+`.uid`), `data/abilities/dash.tres`, `tests/unit/test_ability_dash.gd` (+`.uid`). `docs/TASKS.json`, `ui/` (T-19/T-33), `tests/_probe.gd`, `opencode.jsonc` не трогались.
- **Ограничения:** HUD-полоса кулдауна — потребление сигнала T-19 (проверено `test_hud`); анимация/шлейф dash — T-05 (использует `player_state_changed`); выдача dash в мире — через общий `ability_pickup` из T-06 (данные готовы); в рабочем дереве полный прогон один раз дал известную флаки `test_boss` (p95 физики 0.022 с), в чистом worktree 308/308. Независимые приёмка QA и ревью Guardian Tasker'ом не выполнялись.
- **Коммит:** `c13ebfe` «T-07: способность Dash + кулдаун». Запись журнала оставлена некоммиченной: в рабочем дереве параллельно лежат незакоммиченные записи Orchestrator/T-19/T-29/T-33.

## 2026-10-18 — T-08 выполнен (tasker-backend)

- **Skills:** загружен `godot` (типизированный GDScript, `Resource`/`class_name`/`.tres`, FSM игрока и приоритеты, `CharacterBody2D`/`is_on_wall`/`get_wall_normal`, GUT на реальных 60 Hz physics-кадрах — профильный стек задачи). Другие skills не требовались: React/PostgreSQL/Docker/Go/Python-контекста нет.
- **Задача:** T-08 «Способность Карабканье по стенам» (TASKS T-08; PLAN §3.1 — `V_wall_slide=40`; §3.3 — slide + wall kick; SPEC US-02/AC-02.3). Статус в `docs/TASKS.json` не менялся (`pending` до QA/Guardian).
- **Контракт способности:** `core/abilities/ability_wall_climb.gd` (`AbilityWallClimb extends AbilityBase`, `ID=&"wall_climb"`, `DISPLAY_NAME="Карабканье по стенам"`, хелперы `wall_dir_from_normal()`/`is_holding_into_wall()`) + `data/abilities/wall_climb.tres`; путь добавлен в `AbilityRegistry.ABILITY_PATHS`, поэтому ability gates (T-09), HUD (T-19) и карта (T-33) видят RU-имя и данные без хардкода. Флаг `wall_climb` ставится базовым `activate()`.
- **Скольжение (AC-02.3):** `states/wall_slide.gd` — вход только из `fall` через `Player.try_wall_slide()`: способность получена, игрок в воздухе, касается вертикальной стены (`is_on_wall` + нормаль) и удерживает направление в её сторону. Скорость падения ограничена `V_wall_slide`; гравитация в состоянии применяется вручную (`uses_gravity() = false`), иначе общий тик `Player._physics_process` добавлял бы скорость сверх предела. Отпускание направления/потеря стены/приземление выходят в `fall`/`land`; рывок T-07 остаётся более приоритетным прерыванием.
- **Wall kick:** `states/wall_kick.gd` + `Player.try_wall_kick()`: прыжок у стены даёт горизонтальный импульс `V_wall_kick` в сторону, противоположную стене, и обычный вертикальный импульс. Импульс удерживается `T_wall_kick_lock`, иначе удержание направления в стену сразу гасило бы отталкивание; после локка возвращается управление, на апексе — `fall`. Новые параметры `v_wall_kick=130`, `t_wall_kick_lock=0.18` добавлены в `data/balance/balancing_params.gd` и `balancing.tres` (единственный источник значений).
- **Гейт способности:** без `GameState.has_ability(&"wall_climb")` удержание невозможно (проверка в `Player.can_wall_slide()`); в `wall_slide` есть defence-in-depth — при принудительном `force_state` состояние выходит на первом physics-тике без удержания.
- **Анимация:** `PlayerAnimation.STATE_TO_ANIMATION` — `wall_slide` использует готовый контракт `PlayerSpriteFrames.ANIM_WALL_SLIDE` из T-05, `wall_kick` — `jump_rise` (отдельного арта в DESIGN §7 нет; визуально это прыжок). Дубликат ключа `wall_slide` при добавлении убран.
- **Тесты:** новый `tests/unit/test_ability_wall_climb.gd` — 12 тестов, 68 asserts: контракт реестра/флаги, значения из `balancing.tres`, хелперы направления, отсутствие удержания без способности, defence-in-depth при `force_state`, предел `V_wall_slide` по velocity и по смещению за кадр, сход со стены при отпускании направления, wall kick вправо/влево (знак и величина импульса, подъём, фактическое движение от стены), удержание импульса на время локка и возврат управления, переход `wall_kick → fall` на апексе.
- **Evidence (портативный Godot 4.4.1-stable, `GODOT_PATH`):** рабочий каталог — `--headless --import` exit 0, GUT `-gdir=res://tests -ginclude_subdirs -gexit` **320/320 passed, 3575 asserts** (+12 T-08 к базовым 308), smoke `--headless --path game --quit` exit 0, `res://Main.tscn --quit-after 120` exit 0, сцена зоны 3 (`zone_03_mountains`) `--quit-after 120` exit 0 без ERROR. Чистый worktree коммита `d93f774`: import exit 0, GUT **320/320, 3575 asserts**; первый прогон дал известную флаки `test_boss` (p95 физики 0.02113 с), изолированно `test_boss` — 11/11, повторный полный прогон — 320/320; smoke/Main exit 0.
- **Найденное/исправленное:** (1) состояния `wall_slide` из T-04 в дереве не существовало (был только задел в описании/анимационном контракте) — создано вместе с `wall_kick`; (2) общий тик гравитации обходил бы `V_wall_slide` — состояние отключает общую гравитацию и считает свою с потолком; (3) wall kick в состоянии `jump` был бы погашен удержанием направления (jump.enter/physics_update перезаписывают `velocity.x`) — вынесен в отдельное состояние с локом импульса, без повторного вертикального импульса jump; (4) добавление `wall_kick` потребовало маппинга анимации и убрало дубликат `wall_slide` в `STATE_TO_ANIMATION`; (5) в GUT сигнал `physics_frame` приходит до `_physics_process`, поэтому тест принудительного состояния ждёт смены состояния с guard ≤2 кадра (по факту — один physics-тик).
- **Кросс-файловые правки:** `core/abilities/ability_registry.gd` (+wall_climb), `data/balance/balancing_params.gd`/`balancing.tres` (+`v_wall_kick`/`t_wall_kick_lock`), `entities/player/Player.gd` (+гейт/направление стены/wall kick), `PlayerAnimation.gd` (+wall_kick, чистка дубликата), `PlayerStateMachine.gd` (+2 состояния), `states/fall.gd` (+вход в wall_slide). Новые: `core/abilities/ability_wall_climb.gd` (+`.uid`), `data/abilities/wall_climb.tres`, `states/wall_slide.gd`/`wall_kick.gd` (+`.uid`), `tests/unit/test_ability_wall_climb.gd` (+`.uid`). `docs/TASKS.json`, `ui/` (T-33), `tests/_probe.gd`, `opencode.jsonc` не трогались.
- **Ограничения:** «карабканье» реализовано как slide + wall kick по SPEC §4.1/AC-02.3 — подъёма вверх по стене нет; направление стены берётся из коллизий `CharacterBody2D`, без отдельных RayCast; отдельного арта wall kick нет (заглушка `jump_rise`); начисление способности в мире — через общий `ability_pickup` T-06 и данные. Независимые приёмка QA и ревью Guardian Tasker'ом не выполнялись.
- **Коммит:** `d93f774` «T-08: способность Карабканье по стенам + wall kick»; запись журнала — отдельным docs-коммитом. В рабочем дереве параллельно появились незакоммиченные изменения другой сессии (T-34: `Main.tscn`, `AudioManager.gd`, `Config.gd`, `ui/components/toast_host.gd`) и `opencode.jsonc` — не трогал.
