# T-24 — ремап, журнал, фракции, выбор фракции: журнал действий

## 2026-10-18 — Tasker (frontend)

- **Skills:** загружен `godot` — типизированный GDScript 4.4, `CanvasLayer`/`Control`/`Button`,
  тема и токены T-18, autoload-контракты T-03/T-27/T-28, GUT/headless и проверка кадра 480×270.
  Другие стек-скиллы не требовались: задача целиком в Godot UI + существующих данных.
- **Задача:** T-24 (TASKS.json; PLAN §5; DESIGN §6/§9; AC-01.3, AC-06.2, US-06). Статус в
  `docs/TASKS.json` не менялся — приёмка за QA/Guardian.
- **Сделано:**
  - `game/ui/remap/Remap.tscn` + `Remap.gd` — игровые действия из `InputMap` (без `ui_*`),
    захват следующего события (клавиша/кнопка геймпада), замена привязок того же типа с
    сохранением второй половины пары, `InputManager.remap_action()` → `user://settings.cfg`,
    сброс `InputManager.reset_to_defaults()`, дубли подсвечиваются «! ДУБЛЬ» + tooltip +
    именем конфликтующего действия. Список в две колонки: 10 действий помещаются в 480×270.
  - `game/ui/journal/Journal.tscn` + `Journal.gd` — вкладки «КВЕСТЫ»/«СОБЫТИЯ»
    (`Tab`/`Shift+Tab`/`LB`/`RB`), активные и завершённые квесты отдельными разделами
    (`Journal.get_quest_entries`), события (`Journal.get_events`), детали/описание,
    пустые состояния DESIGN §6.6, реактивность по `journal_changed`.
  - `game/ui/factions/Factions.tscn` + `Factions.gd` — список фракций с репутацией и
    статусом доступа словом (`ОТКР`/`ЗАКР`), вкладка «СПИСОК» (лор, репутация, порог,
    причина отказа, альтернатива EC-11) и «ДОСТУП» (территория/торговец/квесты; причина
    выбранного ограничения целиком, доступна с клавиатуры строками `AshenMenuItem`).
  - `game/ui/factions/FactionChoice.tscn` + `FactionChoice.gd` — экран присяги: список
    фракций, репутация, статус доступа, влияние на концовку; двухшаговое подтверждение
    (`Enter/A` на строке → «Присягнуть» → `confirm_choice()`), фиксация через
    `FactionManager.choose_faction()`, сигнал `choice_made`, отмена `Esc/B` без выбора.
    Открывается сюжетным `EventBus.faction_choice_requested(reason)` или `open()`.
  - `game/ui/components/tab_bar.gd` — `AshenTabBar`: вкладки T-18, переключение
    `Tab`/`Shift+Tab` и raw `LB`/`RB` (9/10), событие помечается обработанным.
- **Кросс-файловые правки:** `game/Main.tscn` — 4 экрана инстансированы в слой UI и скрыты;
  `game/autoload/EventBus.gd` — добавлен `faction_choice_requested(reason)` (US-06).
- **Тесты:** `game/tests/unit/test_remap_journal_factions.gd` — 19 тестов / 138 assert:
  список действий и фильтр `ui_*`, применение и запись `KEY_F` в `settings.cfg`, сохранение
  кнопки геймпада, конфликт дублей текстом, сброс к дефолтам, захват/отмена, вкладки
  `Tab`/`LB`/`RB`, активные/завершённые квесты, события, реактивность журнала, пустые
  состояния, репутация/порог/причина/альтернатива, доступ по трём видам, сюжетное
  открытие выбора, фиксация выбора и отмена.
- **Evidence (чистый worktree HEAD T-24, portable Godot 4.4.1-stable):**
  `--headless --import` exit 0 без script/parse-ошибок; полный GUT
  `-gdir=res://tests -ginclude_subdirs -gexit` — **477/477 passed, 4959 asserts, 0 failing**
  (458 базовых + 19 T-24; известный флейк T-30 на этом прогоне не проявился); targeted
  T-24 — 19/19; smoke `--headless --path game --quit-after 180` exit 0 без SCRIPT ERROR.
  Визуальный smoke 480×270: `%TEMP%\opencode\t24_journal_quests.png`,
  `t24_journal_events.png`, `t24_factions_list.png`, `t24_factions_access.png`,
  `t24_remap.png`, `t24_remap_capture.png`, `t24_choice.png`.
- **Найденные/исправленные проблемы:** (1) `AshenMenuItem._ready()` сбрасывает `tooltip_text` —
  подсказки строк ставятся после `add_child`; (2) фактическая высота строки `AshenMenuItem` —
  23 px (шрифт), а не 16, из-за чего 11 действий не помещались в колонку — список ремапа
  переведён в `GridContainer` 2×N; (3) префиксы состояний рисовались без пробела — добавлен
  хвостовой пробел; (4) подсказки обрезались по краю панели — перенесены в футер/укорочены;
  (5) полный текст доступа не влезал в панель — причины разнесены по фокусируемым строкам
  «территория/торговец/квесты»; (6) D-pad и клавиша «влево» выглядели одинаково — `D←/D→`
  и `ST←/ST→`; (7) экран выбора показывал лор и причину, обрезая их — оставлены только
  репутация/порог/доступ/влияние, полный лор и причина — на вкладке «Фракции».
- **Ограничения/зазоры:** Journal и Factions в `Main.tscn` инстансированы, но пока не имеют
  собственной клавиши открытия (нет действия `journal`; вход — публичный `open()` из меню/паузы,
  T-20); Remap открывается `open()` из настроек T-20; FactionChoice доступен по сюжетному
  сигналу. Сам выбор фракции живёт в `GameState.chosen_faction` и уже сериализуется сейвом
  (T-25/T-27), отдельного сохранения в экране нет.
- **Параллельность:** не тронуты `game/project.godot` (inventory-action T-21),
  `ui/inventory/`, `tests/unit/test_inventory.gd`, `opencode.jsonc` и `docs/WORKFLOW_LOG.md`.
  Изменены только пути T-24 + `Main.tscn` + `EventBus.gd`.

## 2026-10-19 — Tasker (frontend): Fix-2 (QA-блокеры 5–8)

- **Skills:** загружен `godot` — правки GDScript/`CanvasLayer`/`Control`, InputMap,
  масштаб UI и headless GUT/QA. Другие стек-скиллы не нужны: фронтенд Godot + существующие
  autoload-контракты; `N/A` для внешних стеков.
- **Задача:** `docs/QA.md` блокеры 5, 6, 7, 8; DESIGN §9.6 п.6; TASKS T-20/T-24. Статусы в
  `docs/TASKS.json` не менялись. Чистый worktree `fix2-nav-a11y`, коммит Fix-2.
- **Сделано:**
  1. **Ремап (B5):** `Settings.gd` — строка «Управление» больше не `disabled`, без причины
     «T-24»; `MainMenu.gd` инстансирует `Remap.tscn`, `_on_remap_requested()` скрывает
     настройки и вызывает `Remap.open()`, `closed` возвращает в настройки с фокусом;
     закрытие меню/переход в MAIN закрывает ремап. `Remap.ACTION_ORDER` дополнен
     `inventory`/`journal`/`factions`.
  2. **Журнал/фракции (B6):** в `project.godot` добавлены InputMap-действия `journal`
     (`N` / L3) и `factions` (`F` / R3); `Journal._input`/`Factions._input` открывают и
     закрывают экраны по этим действиям, блокируются при паузе другой модалки и при
     видимых `dialogue_ui`/`campfire_ui` (не ломают существующую навигацию).
  3. **A11y п.6 (B7):** `WorldMap` — колонка зон расширена (кнопка 160 px, доступно 146 px)
     при сохранении 480×270, карта/детали сдвинуты на 184; `HUD.apply_ui_scale()` реагирует
     на `Config.ui_scale` (шрифт 8→12 при 150 %, геометрия подписей/кошелька/подсказки/босса),
     `ui_scale_changed` подключён; `DeathScreen` присваивает `_coins_row_label`/`_items_row_label`
     и `_retranslate()` сделан null-safe.
  4. **AC-02.4 (B8):** `AbilityHint` считает экранный clamp панели (canvas transform) и
     сдвигает текст/иконку/рамку внутрь 480×270 с отступом 2 px.
- **Кросс-файловые правки:** `game/assets/locale/{ru,en}.csv` + регенерированные
  `.translation` (подписи новых действий ремапа, убран текст «T-24»);
  `game/tests/unit/test_menu.gd` — устаревший тест «ремап disabled до T-24» заменён на
  проверку открытия `Remap` и возврата в настройки. `world/zones/`, `entities/bosses/`,
  `Main.gd`, `autoload/` не тронуты.
- **Evidence (portable Godot 4.4.1-stable, этот worktree):**
  - `--headless --import`: без script/parse-ошибок (known RID leaks at exit).
  - Полный GUT `-gdir=res://tests -ginclude_subdirs -gexit`: **518/518 passed, 7060 asserts,
    0 failing** (exit code 1 только из-за известных RID/resource leak at exit).
  - `qa_a11y.tscn`: **105 PASS / 1 FAIL**; единственный fail — контур врагов (D10, вне Fix-2).
    Новые PASS: `переполнение панелей RU/150%`, `EN/150%`, `масштаб UI 150% применяется к HUD —
    шрифт HUD 8 → 12 px`; runtime-ошибок `DeathScreen._retranslate` нет.
  - `qa_e2e.tscn` на чистом `user://saves`: **83 PASS / 7 FAIL** — ровно исходные блокеры
    B1–B4 (способности/враги/видимость арен/эмиттер фракций), вне Fix-2; меню/навигация PASS.
  - Smoke `Main.tscn`: `journal open=true paused=true` → `closed paused=false`,
    `factions open=true paused=true` → `closed paused=false`; ремап из настроек
    `open=true`, после закрытия настройки снова видимы.
  - Probe 480×270: EN `1. BASTION VILLAGE` — 144 px при доступных 146; подсказка
    `Нужно: ДВОЙНОЙ ПРЫЖОК` — правый край 478 < 480; DeathScreen RU `[Монеты, Предметы]`,
    EN `[Coins, Items]` без ошибок.
- **Ограничения:** визуальный рендер (скриншоты) не снимался — проверка headless + геометрия
  Control; независимые QA/Guardian не заменяются этим smoke.
