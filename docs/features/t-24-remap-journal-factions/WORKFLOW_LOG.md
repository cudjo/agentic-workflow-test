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
