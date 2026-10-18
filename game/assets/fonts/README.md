# Шрифты UI (T-18)

Оба шрифта распространяются по SIL Open Font License 1.1; тексты лицензий —
рядом (`OFL-PressStart2P.txt`, `OFL-Tiny5.txt`).

| Файл | Шрифт | Источник | Роль |
|---|---|---|---|
| `PressStart2P-Regular.ttf` | Press Start 2P Regular | <https://github.com/google/fonts/tree/main/ofl/pressstart2p> | основной UI-шрифт (8/16/24/32 px), OFL |
| `Tiny5-Variable.ttf` | Tiny5 (variable) | <https://github.com/google/fonts/tree/main/ofl/tiny5> | fallback для символов, которых нет в Press Start 2P: `✓ □ ○ △`; OFL |

## Кириллица

DESIGN §4.2/Q8 отмечает риск «Press Start 2P без кириллицы». В актуальном
релизе Google Fonts (OFL) кириллица **есть**: метаданные объявляют subset
`cyrillic`, а cmap содержит весь диапазон U+0410–U+044F и `Ё/ё`. Это
проверяется GUT-тестом `test_press_start_2p_covers_russian_and_english`
через `Font.has_char`, а не на глаз.

Fallback-цепочка (`FontVariation.fallbacks = [Tiny5]`) всё равно включена:
она закрывает символы, которых в Press Start 2P действительно нет
(`✓`, `□`, `○`, `△`), и страхует от пропусков в редких глифах.

Импорт настроен на пиксельный рендер: `antialiasing=0`, `hinting=0`,
`subpixel_positioning=0`, `allow_system_fallback=false` — системные шрифты
не подменяют глифы, покрытие проверяемо.
