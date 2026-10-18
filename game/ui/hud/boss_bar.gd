class_name AshenBossBar
extends Control
## AshenBossBar — панель босса HUD (T-19, AC-03.4, DESIGN §6.3).
##
## Содержит:
##   * имя босса (bone) и подпись фазы «ФАЗА II / III» (stone-5);
##   * сегментную шкалу `AshenBar` вида BOSS (248×8);
##   * метки фаз на порогах из `boss_fight_started.phase_thresholds`
##     (по умолчанию — 33% / 66%, `UITokens.BOSS_PHASE_MARKS`);
##   * уведомление «ФАЗА II» по центру с подзаголовком фазы
##     (`boss_phase_changed.phase_title`).
##
## Панель скрыта вне боя: показать её может только `begin_fight()`
## (HUD вызывает его по `EventBus.boss_fight_started`), скрыть —
## `end_fight()` (по `boss_defeated` или смене зоны).
##
## Уведомление живёт `NOTICE_TIME`; `advance(delta)` публичный, чтобы тесты
## не ждали реальные таймеры (тот же приём, что `AshenBar.advance_trail`).

const NOTICE_TIME: float = 1.8
const ROMAN: Array[String] = ["I", "II", "III", "IV"]

## Высота строки имени + шкалы (имя 10 px, зазор 2 px, шкала 8 px).
const PANEL_HEIGHT: int = 22

var boss_id: StringName = &""
var display_name: String = ""
var max_hp: float = 0.0
var phase_index: int = 0
var phase_title: String = ""

var _name_label: Label
var _phase_label: Label
var _bar: AshenBar
var _phase_marks_overlay: _PhaseMarks
var _notice_panel: AshenPanel
var _notice_title: Label
var _notice_subtitle: Label
var _notice_left: float = 0.0
var _phase_marks: PackedFloat32Array = PackedFloat32Array(UITokens.BOSS_PHASE_MARKS)
var _name_key: String = ""
var _built: bool = false


func _init() -> void:
	name = "BossBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(UITokens.BAR_BOSS_SIZE.x, float(PANEL_HEIGHT))
	size = custom_minimum_size
	visible = false


func _ready() -> void:
	_ensure_built()
	visible = false
	if not Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.connect(_on_locale_changed)


func _exit_tree() -> void:
	if Locale.language_changed.is_connected(_on_locale_changed):
		Locale.language_changed.disconnect(_on_locale_changed)


# ------------------------------------------------------------------------------
# Бой (вызывает HUD по сигналам EventBus)
# ------------------------------------------------------------------------------

## Показать панель и заполнить её данными босса (AC-03.4).
## `thresholds` — пороги фаз из `BossData.get_phase_thresholds()`
## (например [0.66, 0.33]); пустой массив — метки 33/66 из токенов.
func begin_fight(
	new_boss_id: StringName,
	new_display_name: String,
	new_max_hp: float,
	thresholds: PackedFloat32Array = PackedFloat32Array()
) -> void:
	_ensure_built()
	boss_id = new_boss_id
	_name_key = "boss.%s.name" % String(new_boss_id)
	display_name = LocaleText.lookup(_name_key, new_display_name)
	max_hp = maxf(new_max_hp, 1.0)
	phase_index = 0
	phase_title = ""
	_phase_marks = (
		thresholds.duplicate() if thresholds.size() > 0
		else PackedFloat32Array(UITokens.BOSS_PHASE_MARKS)
	)
	_name_label.text = display_name
	_phase_marks_overlay.marks = _phase_marks
	_phase_marks_overlay.queue_redraw()
	_bar.set_values(max_hp, max_hp)
	_notice_left = 0.0
	_notice_panel.visible = false
	_refresh_phase_label()
	visible = true


func set_health(current: float, maximum: float) -> void:
	_ensure_built()
	if maximum > 0.0:
		max_hp = maximum
	_bar.set_values(current, maxf(max_hp, 1.0))


## Переход фазы: подпись «ФАЗА N / M» + уведомление «ФАЗА N».
func set_phase(new_phase_index: int, title: String) -> void:
	_ensure_built()
	phase_index = clampi(new_phase_index, 0, ROMAN.size() - 1)
	phase_title = title
	_refresh_phase_label()
	_show_notice(title)


func end_fight() -> void:
	boss_id = &""
	display_name = ""
	phase_title = ""
	_notice_left = 0.0
	if _notice_panel != null:
		_notice_panel.visible = false
	visible = false


## Ступенчатый таймер уведомления (тесты вызывают вручную).
func advance(delta: float) -> void:
	if _notice_left <= 0.0:
		return
	_notice_left = maxf(_notice_left - delta, 0.0)
	if _notice_left <= 0.0 and _notice_panel != null:
		_notice_panel.visible = false


# ------------------------------------------------------------------------------
# Запросы (HUD, тесты, QA)
# ------------------------------------------------------------------------------

func is_fight_visible() -> bool:
	return visible


func is_notice_visible() -> bool:
	return _notice_panel != null and _notice_panel.visible


## Текст уведомления без подзаголовка: «ФАЗА II».
func get_notice_text() -> String:
	return _notice_title.text if _notice_title != null else ""


func get_notice_subtitle() -> String:
	return _notice_subtitle.text if _notice_subtitle != null else ""


func get_phase_text() -> String:
	return _phase_label.text if _phase_label != null else ""


func get_phase_marks() -> PackedFloat32Array:
	return _phase_marks.duplicate()


func get_phase_count() -> int:
	return _phase_marks.size() + 1


func get_bar() -> AshenBar:
	return _bar


func get_name_text() -> String:
	return _name_label.text if _name_label != null else ""


# ------------------------------------------------------------------------------
# Построение
# ------------------------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true

	_name_label = _make_label("", UITokens.BONE, HORIZONTAL_ALIGNMENT_LEFT)
	_name_label.position = Vector2.ZERO
	_name_label.size = Vector2(170, 10)
	add_child(_name_label)

	_phase_label = _make_label("", UITokens.STONE_5, HORIZONTAL_ALIGNMENT_RIGHT)
	_phase_label.position = Vector2(170, 0)
	_phase_label.size = Vector2(78, 10)
	add_child(_phase_label)

	_bar = AshenBar.new()
	_bar.kind = AshenBar.Kind.BOSS
	_bar.position = Vector2(0, 12)
	_bar.size = UITokens.BAR_BOSS_SIZE
	add_child(_bar)

	# Метки фаз из данных босса поверх шкалы (33 % / 66 % по умолчанию).
	_phase_marks_overlay = _PhaseMarks.new()
	_phase_marks_overlay.position = _bar.position
	_phase_marks_overlay.size = _bar.size
	_phase_marks_overlay.marks = _phase_marks
	add_child(_phase_marks_overlay)

	_notice_panel = AshenPanel.new()
	_notice_panel.variant = UIStyle.PanelVariant.SOLID
	_notice_panel.padding = UITokens.SP_2
	_notice_panel.custom_minimum_size = Vector2(156, 40)
	_notice_panel.position = Vector2(46, -52)
	_notice_panel.size = Vector2(156, 40)
	_notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notice_panel)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", UITokens.SP_1)
	_notice_panel.add_child(column)

	_notice_title = _make_label("", UITokens.GOLD_3, HORIZONTAL_ALIGNMENT_CENTER, UITokens.FONT_H2)
	column.add_child(_notice_title)

	_notice_subtitle = _make_label("", UITokens.BLOOD_5, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_notice_subtitle)

	_notice_panel.visible = false


func _refresh_phase_label() -> void:
	if _phase_label == null:
		return
	_phase_label.text = tr("ui.hud.phase_of") % [
		_phase_at(phase_index),
		_phase_at(maxi(get_phase_count() - 1, 0)),
	]


func _show_notice(title: String) -> void:
	_notice_title.text = tr("ui.hud.phase") % _phase_at(phase_index)
	_notice_subtitle.text = tr(title) if not title.is_empty() else ""
	_notice_panel.visible = true
	_notice_left = NOTICE_TIME


func _on_locale_changed(_code: String) -> void:
	if boss_id != &"":
		display_name = LocaleText.lookup(_name_key, display_name)
		_name_label.text = display_name
	_refresh_phase_label()
	if is_notice_visible() and not phase_title.is_empty():
		_notice_subtitle.text = tr(phase_title)


func _phase_at(index: int) -> String:
	return ROMAN[clampi(index, 0, ROMAN.size() - 1)]


func _make_label(
	text: String,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	font_size: int = UITokens.FONT_BODY
) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIStyle.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# Тень void 1 px — читаемость 8-px текста поверх сцены (DESIGN §9.1).
	label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## Метки порогов фаз из данных босса (по умолчанию 33 % / 66 %).
class _PhaseMarks extends Control:

	var marks: PackedFloat32Array = PackedFloat32Array()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		for mark: float in marks:
			var x: float = floor(size.x * clampf(mark, 0.0, 1.0))
			draw_rect(Rect2(x, 0.0, 2.0, size.y), UITokens.VOID)
