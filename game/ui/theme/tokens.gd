class_name UITokens
extends RefCounted
## UITokens — единственный источник дизайн-токенов (DESIGN §4).
##
## Компоненты и тема обязаны брать цвета/размеры/отступы/границы отсюда,
## а не хардкодить значения. Здесь же — WCAG-хелперы, которыми проверяется
## контраст 8-px текста (DESIGN §4.1, §9.1: ≥ 4.5:1).
##
## Палитра: 27 UI-цветов (DESIGN §4.1). `OK` (#8fa77c) — допустимый точечный
## акцент для «ЕСТЬ»/hitbox, не является основным цветом успеха
## (успех = steel-3 + галочка).

# ------------------------------------------------------------------------------
# §4.1 Цвета — 27 токенов
# ------------------------------------------------------------------------------

const VOID := Color("#0b0c10")          # чёрный UI-фон, обводка, вставки
const NIGHT_9 := Color("#10131c")       # фон панелей
const NIGHT := Color("#1a1f2e")         # тёмно-синий, фон ночи
const NIGHT_3 := Color("#262c3e")       # hover/выделение строки, небо
const NIGHT_5 := Color("#323a4c")       # горизонт неба
const GREEN_9 := Color("#161e14")
const GREEN := Color("#1f2a1c")
const GREEN_3 := Color("#2e3d2a")
const BROWN_9 := Color("#2a2018")
const BROWN := Color("#3b2e22")
const BROWN_3 := Color("#54402f")
const STONE_9 := Color("#303035")       # рамка по умолчанию, тень камня
const STONE := Color("#4a4a4f")
const STONE_3 := Color("#6b6b70")       # рамка панели, disabled-текст
const STONE_5 := Color("#9a9a9c")       # вторичный текст
const BONE := Color("#d6c9a8")          # основной текст
const GOLD_9 := Color("#7d5a28")        # уголки рамок, след урона
const GOLD := Color("#c08a3e")          # фокус, выбор, активное
const GOLD_3 := Color("#e0b56a")        # акцентный текст, заголовки, огонь
const BLOOD_9 := Color("#4a1a17")       # тёмная кайма
const BLOOD := Color("#7a2a24")         # заливка опасности (не текст)
const BLOOD_3 := Color("#b5483c")       # HP-бар, рамки опасности
const BLOOD_5 := Color("#cf6a5c")       # ТОЛЬКО текст 8 px опасности
const STEEL_9 := Color("#2f4350")       # туман, фон «ОК»
const STEEL := Color("#4f6b7a")         # выносливость, карта
const STEEL_3 := Color("#7f9aa8")       # холодный свет, значки, «ЕСТЬ»
const OK := Color("#8fa77c")            # точечно: «ЕСТЬ»/hitbox, не акцент

## 27 цветов по имени токена (для темы, тестов и документации).
const COLORS := {
	"void": VOID,
	"night-9": NIGHT_9,
	"night": NIGHT,
	"night-3": NIGHT_3,
	"night-5": NIGHT_5,
	"green-9": GREEN_9,
	"green": GREEN,
	"green-3": GREEN_3,
	"brown-9": BROWN_9,
	"brown": BROWN,
	"brown-3": BROWN_3,
	"stone-9": STONE_9,
	"stone": STONE,
	"stone-3": STONE_3,
	"stone-5": STONE_5,
	"bone": BONE,
	"gold-9": GOLD_9,
	"gold": GOLD,
	"gold-3": GOLD_3,
	"blood-9": BLOOD_9,
	"blood": BLOOD,
	"blood-3": BLOOD_3,
	"blood-5": BLOOD_5,
	"steel-9": STEEL_9,
	"steel": STEEL,
	"steel-3": STEEL_3,
	"ok": OK,
}

# ------------------------------------------------------------------------------
# §4.2 Типографика — 4 размера
# ------------------------------------------------------------------------------

const FONT_BODY := 8
const FONT_H2 := 16
const FONT_H1 := 24
const FONT_TITLE := 32

const LINE_BODY := 12
const LINE_H2 := 16
const LINE_H1 := 24
const LINE_TITLE := 32

const FONT_SIZES := [FONT_BODY, FONT_H2, FONT_H1, FONT_TITLE]
const LINE_HEIGHTS := [LINE_BODY, LINE_H2, LINE_H1, LINE_TITLE]

## Шрифт макетов: Press Start 2P (OFL), кириллица + латиница.
const FONT_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"
## Fallback-шрифт (OFL): символы, которых нет в Press Start 2P (✓ □ ○ △).
const FONT_FALLBACK_PATH := "res://assets/fonts/Tiny5-Variable.ttf"
const THEME_PATH := "res://ui/theme/main_theme.tres"

# ------------------------------------------------------------------------------
# §4.3 Отступы и размеры
# ------------------------------------------------------------------------------

const SP_1 := 2
const SP_2 := 4
const SP_3 := 8
const SP_4 := 12
const SP_5 := 16
const SP_6 := 24
const SPACING := [SP_1, SP_2, SP_3, SP_4, SP_5, SP_6]

const SAFE_MARGIN := 8
const PANEL_PADDING := 6
const PANEL_PADDING_DIALOG := 8

const BORDER_PANEL := 2
const BORDER_INNER := 1
const BORDER_SLOT := 2
const BORDER_BAR := 1
const BORDER_FOCUS := 2
const RIVET_SIZE := 3
const FOCUS_ARM := 4
const SLOT_BADGE := 7
const SLOT_LOCK_SIZE := Vector2(9, 10)
const TOGGLE_TRACK := Vector2(14, 6)
const TOGGLE_KNOB := 6
const GLASS_ALPHA := 0.82
const BAR_HIGHLIGHT := Color(1, 1, 1, 0.16)

const ICON := 12
const SLOT_HUD := 22
const SLOT_INV := 28
const SLOT_GAP := 1

const BAR_SEGMENT := 3
const BAR_SEGMENT_GAP := 1
const BAR_HP_SIZE := Vector2(112, 10)
const BAR_STAMINA_SIZE := Vector2(96, 8)
const BAR_BOSS_SIZE := Vector2(248, 8)
const BOSS_PHASE_MARKS := [0.33, 0.66]
const HP_CRITICAL_RATIO := 0.25

const PORTRAIT_HUD := 28
const PORTRAIT_DIALOG := 52
const MINIMAP_SIZE := Vector2(96, 54)
const MINIMAP_ROOM := Vector2(8, 6)

const ROW_MENU_H2 := 24
const ROW_MENU_BODY := 16
const TAB_HEIGHT := 18
const KBD_HEIGHT := 12
const TOAST_MIN_HEIGHT := 16
const HIT_TARGET := 16
const DIALOG_SIZE := Vector2(464, 96)
const DIALOG_TEXT_WIDTH := 380

# ------------------------------------------------------------------------------
# §4.5 Движение
# ------------------------------------------------------------------------------

const TYPE_SPEED := 0.022          # 1 символ / 22 мс (≈45 зн/с)
const FADE_STEPS := 4
const FADE_TIME := 0.8
const BLINK_HZ := 1.0
const MAX_FLASHES_PER_SEC := 3
const DAMAGE_TRAIL_STEP := 0.06

# ------------------------------------------------------------------------------
# Хелперы
# ------------------------------------------------------------------------------

## Именованный цвет токена; возвращает MAGENTA для неизвестного имени, чтобы
## ошибка была заметна в рантайме.
static func color(token_name: String) -> Color:
	return COLORS.get(token_name, Color.MAGENTA)


## Относительная яркость sRGB по WCAG 2.1.
static func relative_luminance(c: Color) -> float:
	var r: float = _linearize(c.r)
	var g: float = _linearize(c.g)
	var b: float = _linearize(c.b)
	return 0.2126 * r + 0.7152 * g + 0.0722 * b


## Контраст по WCAG 2.1: (L1 + 0.05) / (L2 + 0.05), 1.0…21.0.
static func contrast_ratio(a: Color, b: Color) -> float:
	var la: float = relative_luminance(a)
	var lb: float = relative_luminance(b)
	var lighter: float = maxf(la, lb)
	var darker: float = minf(la, lb)
	return (lighter + 0.05) / (darker + 0.05)


## true, если 8-px текст этим цветом на фоне `background` проходит WCAG AA.
static func is_readable(fg: Color, background: Color, minimum: float = 4.5) -> bool:
	return contrast_ratio(fg, background) >= minimum


static func _linearize(channel: float) -> float:
	if channel <= 0.03928:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)
