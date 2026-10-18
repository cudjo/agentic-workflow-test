# T-36 — локализация RU/EN: журнал действий

## 2026-10-18 — Tasker (frontend)

- **Skills:** загружен `godot` — GDScript 4.4+, `TranslationServer`/CSV-переводы,
  `Control`/`Label`/`Button`, тема и пиксельный UI 480×270, GUT/headless и
  локальный рендер кадра. Другие стек-скиллы не требовались (задача целиком в
  Godot UI + данные); `react`/`postgres`/`go`/`python`/`docker` — N/A.
- **Задача:** T-36 «Локализация RU/EN» (TASKS.json; PLAN §3.5; DESIGN §9.6
  п.6, §9.4). Статус в `docs/TASKS.json` не менялся — приёмка за QA/Guardian.
- **Сделано:**
  - `game/assets/locale/ru.csv` + `en.csv` — 415 ключей (`ui.*`, `faction.*`,
    `zone.*`, `ability.*`, `boss.*`, `enemy.*`, `weapon.*`, `npc.*`). Переводы
    подключены в `project.godot` → `internationalization/locale/translations`
    (сгенерированные `*.translation`, источник — CSV).
  - `game/autoload/Locale.gd` — `TranslationServer.set_locale` из
    `Config.language`, сигнал `language_changed`, `translate_key/format_key`,
    `bind()/bind_tooltip()` с автоматическим обновлением привязанных подписей,
    статические `LocaleText.translate_for/current/lookup` для данных.
  - Весь UI переведён на `tr(key)`: меню, настройки, сохранения, HUD,
    босс-бар, инвентарь, смерть, костёр, карта, ремап, журнал, фракции,
    выбор фракции, диалоги, загрузка, концовка, титры, витрина компонентов.
    Локальные `_t(ru,en)` T-20 удалены; в `ui/**/*.gd` не осталось строковых
    литералов с кириллицей (проверяется тестом).
  - Мгновенное переключение: экраны слушают `Locale.language_changed` и
    пересобирают вычисляемый текст; привязанные подписи/подсказки обновляются
    централизованно, без перезапуска и пересоздания сцен.
  - Данные: `FactionData.get_display_name/get_lore/...`, `BossData.get_display_name`,
    `ZoneData.get_display_name/get_epigraph`, `WorldMapModel.ability_label`,
    `AudioManager`-субтитры — через CSV-ключи с откатом на исходный текст.
    Диалоги/квесты не дублированы — используются их готовые RU/EN поля.
  - Переполнение: EN-строки смерти/концовки/фракций укорочены и подобраны под
    480×270; заголовок концовки уменьшен до `FONT_H2`, чтобы длинное имя
    фракции помещалось.
- **Тесты:** `game/tests/unit/test_locale.gd` — 10 тестов: совпадение наборов
  ключей CSV, непустые RU/EN-переводы, `TranslationServer`/`Locale`,
  мгновенное обновление `Label` и живого `MainMenu`/HUD, локализация данных
  (фракции/зоны/концовки/карточки костра), `translate_for`, отсутствие
  кириллических литералов в `ui/**/*.gd`.
  Обновлены две проверки, сравнивавшие отображаемый текст с константой-ключом:
  `test_campfire.gd` и `test_remap_journal_factions.gd` теперь сравнивают с
  `tr(CONST)`.
- **Evidence (чистый worktree коммита T-36, portable Godot 4.4.1, из `game/`):**
  - `--headless --import` — без script/parse-ошибок и без ошибок загрузки
    переводов (сгенерированные `.translation` лежат рядом с CSV и в коммите).
  - GUT `-gdir=res://tests -ginclude_subdirs -gexit` — **510/510 passed,
    6936 asserts, 0 failing** (487 базовых + T-11 + 10 T-36; известный
    флейк `test_boss` по 95-му перцентилю физики при повторном прогоне зелёный).
  - Smoke `--headless --path game --quit-after 180` — без SCRIPT ERROR.
  - Локальный рендер 480×270: `%TEMP%\opencode\t36_shots\` — 16 экранов ×
    {ru,en} × {100%,150%}: menu, settings, saves, hud, inventory, death,
    campfire, factions, choice, journal, map, remap, dialogue, loading,
    ending, credits; обрезки текста не обнаружено после правок.
- **Найденные/исправленные проблемы:** (1) CSV-импорт Godot ожидает в
  `project.godot` пути сгенерированных `.translation`, а не `.csv`;
  (2) многострочные значения (лор фракций, тексты концовок) требуют корректного
  CSV-экранирования — генератор исправлен; (3) `AudioManager` хранил ключи в
  субтитрах — перевод перенесён в `_emit_subtitle`; (4) `Campfire` показывал
  ключи в тостах — `_show_danger/_show_info` переводят централизованно;
  (5) EN-предупреждение смерти и подпись экипировки не помещались — укорочены;
  (6) заголовок концовки обрезался на длинных именах — `FONT_H2`;
  (7) `Remap` не знал действия `inventory` — добавлен ключ.
- **Кросс-файловые правки:** `game/project.godot` (секция
  `internationalization`; импортированные `*.translation` лежат рядом с CSV),
  `game/autoload/{AudioManager,FactionManager,SceneRouter}.gd`,
  `game/data/{factions,bosses}/*_data.gd`,
  `game/entities/npc/{teacher,trader_npc,dialogue_npc}.gd`,
  `game/world/zones/{zone_data,zone_scene,zone_banner}.gd`,
  `game/world/props/{AbilityHint,bonfire}.gd`,
  `game/core/progression/equipment_requirements.gd`,
  `game/entities/bosses/boss_base/boss_base.gd`. `docs/TASKS.json`, чужие
  `core/combat/`, `entities/player/states/block.gd`, `opencode.jsonc` не
  трогались.
- **Ограничения:** экран загрузки/баннер зоны получают уже локализованное имя
  из `ZoneData` на момент показа (переключение языка в этот момент не
  перерисовывает транзиентный экран); длинный список действий в `Remap`
  по-прежнему прокручивается, как в T-24; независимая приёмка QA/Guardian не
  проводилась.
