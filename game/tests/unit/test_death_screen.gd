extends GutTest
## T-22 — экран смерти (DESIGN §6.5/§8.3, SPEC US-05, AC-05.2/05.3, EC-05).
##
## Проверяем acceptance T-22 на живой сцене `res://ui/death/DeathScreen.tscn`:
##   * первая смерть — «ОСТАЛОСЬ НА МЕСТЕ ГИБЕЛИ» (валюта, число предметов,
##     превью 5, мешок на карте); повторная — «УТРАЧЕНО НАВСЕГДА» и череп;
##   * появление через `t_death` ступенчатым fade, «Без мигания» — сразу;
##   * фокус по умолчанию на «Возродиться у костра», навигация без мыши;
##   * мини-карта ×2 (192×108, клетка 16×12) с костром и меткой гибели;
##   * возрождение вызывает `DeathHandler.respawn()` из T-26.

const SCREEN_SCENE: PackedScene = preload("res://ui/death/DeathScreen.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const ZONE: StringName = &"zone_01_village"

var screen: DeathScreen

var _saved_no_flash: bool = false
var _saved_hp: float = 0.0
var _saved_currency: int = 0
var _saved_inventory: Array[StringName] = []
var _saved_abilities: Array[StringName] = []
var _saved_death_active: bool = false
var _saved_corpse: Dictionary = {}
var _saved_respawn: Dictionary = {}
var _saved_zone: StringName = &""


func before_each() -> void:
	_saved_no_flash = Config.no_flash
	_saved_hp = GameState.hp
	_saved_currency = GameState.currency
	_saved_inventory = GameState.get_inventory()
	_saved_abilities = GameState.get_abilities()
	_saved_death_active = GameState.death_active
	_saved_corpse = GameState.get_corpse_info()
	_saved_respawn = {
		"bonfire": GameState.respawn_bonfire,
		"zone_id": GameState.respawn_zone_id,
		"position": GameState.respawn_position,
	}
	_saved_zone = GameState.current_zone_id

	Config.no_flash = false
	GameState.clear_corpse()
	GameState.death_active = false
	GameState.set_hp(GameState.hp_max)
	GameState.currency = 0
	GameState.clear_inventory()
	GameState.clear_abilities()
	GameState.restore_respawn_bonfire(&"", &"", Vector2.ZERO)
	GameState.current_zone_id = ZONE

	screen = SCREEN_SCENE.instantiate() as DeathScreen
	add_child_autofree(screen)
	await wait_process_frames(1)


func after_each() -> void:
	_free_corpses()
	Config.no_flash = _saved_no_flash
	GameState.set_hp(_saved_hp)
	GameState.currency = _saved_currency
	GameState.restore_inventory(_saved_inventory)
	GameState.restore_abilities(_saved_abilities)
	GameState.restore_death_state(
		_saved_death_active,
		bool(_saved_corpse.get("active", false)),
		StringName(str(_saved_corpse.get("zone_id", ""))),
		_saved_corpse.get("position", Vector2.ZERO),
		_saved_corpse.get("items", []),
		int(_saved_corpse.get("currency", 0)),
		bool(_saved_corpse.get("lost", false))
	)
	GameState.restore_respawn_bonfire(
		StringName(str(_saved_respawn.get("bonfire", ""))),
		StringName(str(_saved_respawn.get("zone_id", ""))),
		_saved_respawn.get("position", Vector2.ZERO)
	)
	GameState.current_zone_id = _saved_zone


# ------------------------------------------------------------------------------
# Сцена и появление через T_death
# ------------------------------------------------------------------------------

func test_scene_is_canvas_layer_40_and_starts_hidden() -> void:
	assert_true(screen is CanvasLayer, "экран смерти — CanvasLayer")
	assert_eq(screen.layer, 40, "слой 40 (DESIGN §4.4)")
	assert_false(screen.is_shown(), "до смерти экран скрыт")
	assert_false(screen.visible)


func test_death_screen_requested_shows_the_screen() -> void:
	screen.hide_screen()
	assert_false(screen.is_shown())

	EventBus.death_screen_requested.emit(_first_death_info())

	assert_true(screen.is_shown(), "сигнал T-26 показывает экран")
	assert_true(screen.visible)
	assert_eq(screen.get_title_label().text, "ТЫ ПОГИБ")
	assert_false(screen.is_lost_death())


func test_fade_is_stepped_and_follows_death_html_delays() -> void:
	screen.show_death(_first_death_info())

	assert_false(screen.is_fade_finished(), "появление идёт ступенями")
	assert_eq(screen.get_fade_alpha("title"), 0.0)
	assert_eq(screen.get_fade_alpha("panels"), 0.0)

	screen.advance_fade(0.4)
	assert_almost_eq(screen.get_fade_alpha("title"), 0.25, 0.001, "первый шаг fade")
	assert_eq(screen.get_fade_alpha("panels"), 0.0, "панели ждут своей задержки")

	screen.advance_fade(0.7)
	assert_almost_eq(screen.get_fade_alpha("title"), 1.0, 0.001, "заголовок проявился")
	assert_almost_eq(screen.get_fade_alpha("panels"), 0.25, 0.001, "ступень, не плавность")
	assert_eq(screen.get_fade_alpha("actions"), 0.0)

	screen.advance_fade(0.2)
	assert_almost_eq(screen.get_fade_alpha("panels"), 0.5, 0.001, "следующая ступень")

	screen.advance_fade(1.7)
	assert_true(screen.is_fade_finished(), "все группы проявились")
	for group: String in ["title", "panels", "actions", "warning"]:
		assert_eq(screen.get_fade_alpha(group), 1.0, "группа %s" % group)


func test_no_flash_shows_everything_immediately() -> void:
	Config.no_flash = true
	screen.show_death(_first_death_info())

	assert_true(screen.is_fade_finished(), "«Без мигания» отключает fade")
	assert_eq(screen.get_fade_alpha("title"), 1.0)
	assert_eq(screen.get_fade_alpha("panels"), 1.0)
	assert_eq(screen.get_fade_alpha("actions"), 1.0)
	assert_eq(screen.get_fade_alpha("warning"), 1.0)


# ------------------------------------------------------------------------------
# Первая смерть: AC-05.2/05.3
# ------------------------------------------------------------------------------

func test_first_death_shows_remaining_loot_and_bag_marker() -> void:
	screen.show_death(_first_death_info())

	assert_true(screen.is_shown())
	assert_false(screen.is_lost_death(), "первая смерть — corpse run")

	assert_eq(screen.get_heading_label().text, "ОСТАЛОСЬ НА МЕСТЕ ГИБЕЛИ")
	assert_eq(
		screen.get_heading_label().get_theme_color("font_color"),
		UITokens.GOLD_3,
		"заголовок остатка золотой"
	)
	assert_eq(screen.get_currency_label().text, "1 240", "валюта с разрядным пробелом")
	assert_eq(screen.get_items_label().text, "14", "число предметов")
	assert_eq(screen.get_preview_slots().size(), 5, "превью первых 5 предметов")
	assert_eq(screen.get_more_label().text, "+9", "остальные предметы — «+N»")
	assert_eq(screen.get_footnote_label().text, "Экипировка — тоже там.")
	assert_eq(
		screen.get_warning_label().text,
		"Умрёшь до подбора — вещи пропадут навсегда."
	)
	assert_eq(screen.get_legend_label().text, "Твои вещи")
	assert_string_contains(
		screen.get_subtitle_label().text,
		"Деревня-бастион",
		"подзаголовок называет зону гибели"
	)
	assert_has(_marker_kinds(), "corpse_bag", "на карте мешок «Твои вещи»")
	assert_has(_marker_kinds(), "bonfire", "на карте костёр возрождения")


func test_preview_counts_duplicates_and_keeps_item_tooltips() -> void:
	var info: Dictionary = _first_death_info()
	info["items"] = ["bone_charm", "bone_charm", "ash_shard"]
	info["items_count"] = 3
	info["preview"] = ["bone_charm", "ash_shard"]

	screen.show_death(info)
	var slots: Array[AshenSlot] = screen.get_preview_slots()
	assert_eq(slots.size(), 2)
	assert_eq(slots[0].count, 2, "дубликат показан числом")
	assert_eq(slots[0].tooltip_text, "bone_charm")
	assert_eq(slots[1].count, -1, "уникальный предмет без счётчика")
	assert_eq(screen.get_more_label().text, "+1", "непоказанный предмет — «+N»")


func test_preview_groups_stacks_like_the_mockup() -> void:
	var info: Dictionary = _first_death_info()
	info["items"] = [
		"sword", "shield", "potion", "potion", "potion",
		"herb", "herb", "herb", "herb", "herb",
		"key", "bone_charm", "ash_shard", "scroll",
	]
	info["items_count"] = 14
	info["preview"] = ["sword", "shield", "potion", "potion", "potion"]

	screen.show_death(info)
	var slots: Array[AshenSlot] = screen.get_preview_slots()
	assert_eq(slots.size(), 5, "5 типов предметов, а не 5 повторов")
	assert_eq(slots[2].count, 3, "три зелья — одна ячейка со счётчиком")
	assert_eq(slots[3].count, 5, "пять трав — одна ячейка со счётчиком")
	assert_eq(screen.get_more_label().text, "+9", "остаток предметов")


func test_currency_formatting_uses_thin_thousands() -> void:
	assert_eq(DeathScreen.format_number(1240), "1 240")
	assert_eq(DeathScreen.format_number(37), "37")
	assert_eq(DeathScreen.format_number(0), "0")
	assert_eq(DeathScreen.format_number(-12500), "-12 500")


# ------------------------------------------------------------------------------
# Повторная смерть: EC-05
# ------------------------------------------------------------------------------

func test_second_death_shows_irreversible_loss_and_skull() -> void:
	screen.show_death(_lost_death_info())

	assert_true(screen.is_lost_death(), "метка потеряна навсегда (EC-05)")
	assert_eq(screen.get_heading_label().text, "УТРАЧЕНО НАВСЕГДА")
	assert_eq(
		screen.get_heading_label().get_theme_color("font_color"),
		UITokens.BLOOD_5,
		"опасность — текстовый blood-5 (≥4.5:1)"
	)
	assert_eq(screen.get_currency_label().text, "500", "показана потерянная валюта")
	assert_eq(screen.get_items_label().text, "3", "показаны потерянные предметы")
	assert_eq(screen.get_footnote_label().text, "Вернуть уже нельзя.")
	assert_eq(
		screen.get_footnote_label().get_theme_color("font_color"),
		UITokens.BLOOD_5
	)
	assert_eq(screen.get_warning_label().text, "Прошлая потеря необратима.")
	assert_eq(screen.get_legend_label().text, "Утрачено")
	assert_eq(screen.get_subtitle_label().text, "Ты пал снова, не вернув своё")
	assert_has(_marker_kinds(), "corpse_skull", "метка на карте — череп")
	assert_has(_marker_kinds(), "bonfire", "костёр остаётся на карте")


func test_empty_info_is_safe_and_still_readable() -> void:
	screen.show_death({})

	assert_true(screen.is_shown())
	assert_eq(screen.get_heading_label().text, "ОСТАЛОСЬ НА МЕСТЕ ГИБЕЛИ")
	assert_eq(screen.get_currency_label().text, "0")
	assert_eq(screen.get_items_label().text, "0")
	assert_eq(screen.get_preview_slots().size(), 0)
	assert_eq(screen.get_more_label().text, "")


# ------------------------------------------------------------------------------
# Мини-карта ×2: T-33 + T-22
# ------------------------------------------------------------------------------

func test_death_minimap_is_double_scale_and_has_corpse_pin() -> void:
	screen.show_death(_first_death_info())

	var minimap: AshenMinimap = screen.get_minimap()
	assert_not_null(minimap)
	assert_eq(minimap.custom_minimum_size, Vector2(192, 108), "карта ×2 от 96×54")
	var renderer: MapRenderer = minimap.get_renderer()
	assert_eq(renderer.grid_size, Vector2i.ONE, "локальная карта зоны, не мир 12×9")
	assert_eq(renderer.cell_size, Vector2(192, 108), "зона целиком на карте ×2")
	assert_eq(renderer.marker_scale, 2.0, "маркеры масштабируются ×2")

	var snapshot: Dictionary = screen.get_map_snapshot()
	assert_true(snapshot.has("corpse"), "снимок карты содержит метку гибели")
	var corpse: Dictionary = snapshot.get("corpse", {})
	assert_eq(corpse.get("cell", Vector2i(-1, -1)), Vector2i.ZERO, "клетка локальной карты")
	assert_false(bool(corpse.get("lost", true)), "мешок, не череп")
	var local: Vector2 = corpse.get("local", Vector2.ZERO)
	assert_almost_eq(local.x, 300.0 / 480.0, 0.01, "метка на месте гибели")
	assert_almost_eq(local.y, 200.0 / 270.0, 0.01)

	var bonfires: Array = snapshot.get("bonfires", [])
	assert_eq(bonfires.size(), 1, "костёр зоны на карте")
	var bonfire_local: Vector2 = (bonfires[0] as Dictionary).get("local", Vector2.ZERO)
	assert_almost_eq(bonfire_local.x, 112.0 / 480.0, 0.01, "костёр в своей точке")
	assert_almost_eq(bonfire_local.y, 224.0 / 270.0, 0.01)

	var player: Dictionary = snapshot.get("player", {})
	assert_false(bool(player.get("valid", true)), "мёртвый игрок не рисуется")
	assert_has(_marker_kinds(), "bonfire", "костёр возрождения на карте")


func test_lost_minimap_uses_previous_corpse_position() -> void:
	screen.show_death(_lost_death_info())

	var corpse: Dictionary = screen.get_map_snapshot().get("corpse", {})
	assert_true(bool(corpse.get("lost", false)), "череп вместо мешка")
	var local: Vector2 = corpse.get("local", Vector2.ZERO)
	assert_almost_eq(local.x, 300.0 / 480.0, 0.01, "потерянная метка осталась на месте")
	assert_almost_eq(local.y, 200.0 / 270.0, 0.01)


# ------------------------------------------------------------------------------
# Фокус и возрождение (T-26)
# ------------------------------------------------------------------------------

func test_focus_defaults_to_respawn_and_moves_without_mouse() -> void:
	screen.show_death(_first_death_info())
	await wait_process_frames(1)

	assert_true(
		screen.get_respawn_button().has_focus(),
		"фокус по умолчанию — «Возродиться у костра»"
	)
	assert_true(screen.get_respawn_button().is_focus_visible(), "фокус виден (каретка)")
	assert_eq(screen.get_respawn_button().focus_mode, Control.FOCUS_ALL)

	screen._input(_action_event(&"ui_right"))
	assert_true(screen.get_menu_button().has_focus(), "вправо — вторая кнопка")
	screen._input(_action_event(&"ui_left"))
	assert_true(screen.get_respawn_button().has_focus(), "влево — возрождение")
	assert_eq(screen.get_menu_button().focus_mode, Control.FOCUS_ALL)


func test_respawn_calls_death_handler_and_closes_screen() -> void:
	var handler: DeathHandler = DeathHandler.new()
	add_child_autofree(handler)
	handler.set_physics_process(false)
	handler.auto_respawn = true
	GameState.death_active = true
	GameState.set_hp(0.0)
	GameState.set_respawn_bonfire(ZONE, &"hub", Vector2(112.0, 212.0))
	GameState.clear_corpse()

	watch_signals(EventBus)
	EventBus.death_screen_requested.emit(_first_death_info())
	await wait_process_frames(1)
	assert_true(screen.is_shown())
	assert_false(handler.auto_respawn, "экран берёт возрождение на себя")

	screen.respawn_now()

	assert_false(GameState.death_active, "смерть разрешена (T-26)")
	assert_almost_eq(GameState.hp, GameState.hp_max, 0.001, "полное HP после возрождения")
	assert_signal_emitted(EventBus, "player_respawned")
	assert_false(screen.is_shown(), "экран закрылся")


## Пользовательский сценарий целиком: смерть → бюджет T_death → экран →
## «Возродиться у костра» → игрок у костра с полным HP (T-26 + T-22).
func test_end_to_end_death_opens_screen_and_respawns_at_bonfire() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = Vector2(300.0, 200.0)

	var handler: DeathHandler = DeathHandler.new()
	add_child_autofree(handler)
	handler.set_physics_process(false)
	GameState.set_respawn_bonfire(ZONE, &"hub", Vector2(112.0, 212.0))
	GameState.set_hp(GameState.hp_max)
	GameState.currency = 37
	GameState.restore_inventory([&"ash_shard", &"bone_charm"])

	player.kill()
	assert_eq(handler.phase, &"dying", "бюджет t_death идёт")
	handler.tick(handler.time_left + 0.01)
	await wait_process_frames(1)

	assert_true(screen.is_shown(), "экран смерти открылся после T_death")
	assert_eq(handler.phase, &"dead", "экран ждёт решения игрока")
	assert_false(handler.auto_respawn, "авто-возрождение выключено")
	assert_eq(player.get_state_name(), &"death")
	assert_eq(screen.get_currency_label().text, "37", "валюта из corpse-метки")
	assert_eq(screen.get_items_label().text, "2", "предметы из corpse-метки")

	screen.respawn_now()

	assert_eq(handler.phase, &"idle")
	assert_eq(player.global_position, Vector2(112.0, 212.0), "игрок у костра")
	assert_eq(player.get_state_name(), &"idle", "игрок жив")
	assert_almost_eq(GameState.hp, GameState.hp_max, 0.001)
	assert_false(screen.is_shown())


func test_main_menu_action_emits_signal_and_hides() -> void:
	watch_signals(screen)
	screen.show_death(_first_death_info())
	await wait_process_frames(1)

	screen.get_menu_button().pressed.emit()

	assert_signal_emitted(screen, "main_menu_requested")
	assert_false(screen.is_shown())


# ------------------------------------------------------------------------------
# a11y: текст и не-цветовые признаки (DESIGN §9)
# ------------------------------------------------------------------------------

func test_eight_px_text_colors_pass_wcag_on_panels() -> void:
	var background: Color = UITokens.NIGHT_9
	for color: Color in [
		UITokens.GOLD_3,
		UITokens.BLOOD_5,
		UITokens.STONE_5,
		UITokens.BONE,
	]:
		assert_true(
			UITokens.is_readable(color, background),
			"%s на night-9 ≥ 4.5:1" % color.to_html()
		)


func test_layout_matches_death_mockup_and_fits_the_frame() -> void:
	screen.show_death(_first_death_info())
	await wait_process_frames(1)

	var root: Control = screen.get_root_control()
	assert_eq(root.size, Vector2(480, 270), "кадр 480×270")

	var left: Control = screen.get_left_panel()
	var right: Control = screen.get_right_panel()
	var title: Control = root.get_node("TitleBlock")
	var actions: Control = screen.get_actions()
	var warning: Control = root.get_node("Warning")
	var keys: Control = root.get_node("Keys")

	assert_eq(left.position, Vector2(24, 70), "левая панель по макету")
	assert_eq(left.size, Vector2(216, 142))
	assert_eq(right.position, Vector2(248, 70), "правая панель по макету")
	assert_eq(right.size, Vector2(208, 142))
	assert_false(left.get_global_rect().intersects(right.get_global_rect()), "панели не перекрываются")
	assert_eq(title.position, Vector2(0, 10))
	assert_eq(actions.position, Vector2(24, 220))
	assert_eq(warning.position, Vector2(24, 248))
	assert_almost_eq(keys.get_global_rect().end.x, 456.0, 0.5, "подсказка у правого края")
	assert_almost_eq(keys.get_global_rect().position.y, 225.0, 0.5)

	var frame := Rect2(Vector2.ZERO, Vector2(480, 270))
	for control: Control in [title, left, right, actions, warning, keys]:
		assert_true(
			frame.encloses(control.get_global_rect()),
			"%s внутри кадра: %s" % [control.name, control.get_global_rect()]
		)


func test_lost_state_differs_by_shape_and_text_not_only_color() -> void:
	screen.show_death(_lost_death_info())
	assert_has(_marker_kinds(), "corpse_skull", "череп — форма")
	assert_eq(screen.get_heading_label().text, "УТРАЧЕНО НАВСЕГДА", "текст")
	assert_eq(screen.get_footnote_label().text, "Вернуть уже нельзя.", "текст")


# ------------------------------------------------------------------------------
# Помощники
# ------------------------------------------------------------------------------

func _first_death_info() -> Dictionary:
	var items: Array[String] = _items(14)
	var preview: Array[String] = []
	for index: int in 5:
		preview.append(items[index])
	return {
		"active": true,
		"zone_id": String(ZONE),
		"position": Vector2(300.0, 200.0),
		"items": items,
		"items_count": items.size(),
		"preview": preview,
		"currency": 1240,
		"lost": false,
		"previous_lost": false,
		"previous": {},
		"death_position": Vector2(300.0, 200.0),
	}


## Повторная смерть: новый corpse пуст, потеряна старая метка (`previous`).
func _lost_death_info() -> Dictionary:
	var lost_items: Array[String] = _items(3)
	return {
		"active": true,
		"zone_id": String(ZONE),
		"position": Vector2(120.0, 180.0),
		"items": [],
		"items_count": 0,
		"preview": [],
		"currency": 0,
		"lost": false,
		"previous_lost": true,
		"previous": {
			"active": true,
			"zone_id": String(ZONE),
			"position": Vector2(300.0, 200.0),
			"items": lost_items,
			"items_count": lost_items.size(),
			"preview": lost_items,
			"currency": 500,
			"lost": true,
		},
		"death_position": Vector2(120.0, 180.0),
	}


func _items(count: int) -> Array[String]:
	var result: Array[String] = []
	for index: int in count:
		result.append("item_%d" % index)
	return result


func _marker_kinds() -> Array[String]:
	var kinds: Array[String] = []
	for spec: Dictionary in screen.get_minimap().get_renderer().get_marker_specs():
		kinds.append(str(spec.get("kind", "")))
	return kinds


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _free_corpses() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"corpses"):
		node.free()
