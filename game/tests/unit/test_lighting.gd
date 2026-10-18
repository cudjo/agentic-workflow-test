extends GutTest
## T-35 — освещение и атмосфера (PLAN §3.6, DESIGN §4.4/§8.7/§9.1/§9.3,
## SPEC US-07/AC-07.1).
##
## Проверяем:
##   * ambient 0.26–0.5 (мир) / 0.78 (меню) и зоны T-13/T-16 в этих границах;
##   * постеризацию/дизеринг Байера 4×4 (без плавных градиентов) и 6–8 ступеней;
##   * z-order: мир → emissive 1 → post 2 → HUD 10 (DESIGN §4.4);
##   * эмиссивный слой вне CanvasModulate (пламя/окна не затемняются);
##   * режим «Читаемость силуэтов»: контур героя + виньетка 0 (AC-07.1);
##   * режим «Без мигания»: нет мерцания света и вспышек урона (≤3/с всегда).

const POSTERIZE_SHADER: Shader = preload("res://assets/shaders/posterize.gdshader")
const DITHER_SHADER: Shader = preload("res://assets/shaders/dither_light.gdshader")
const OUTLINE_SHADER: Shader = preload("res://assets/shaders/silhouette_outline.gdshader")
const RIG_SCENE: PackedScene = preload("res://world/lighting/lighting_rig.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player/Player.tscn")
const ZONE_01_SCENE: String = "res://world/zones/zone_01_village/zone_01_village.tscn"
const ZONE_DATA_PATHS: Array[String] = [
	"res://data/zones/zone_01_village.tres",
	"res://data/zones/zone_02_swamp.tres",
	"res://data/zones/zone_03_mountains.tres",
	"res://data/zones/zone_04_ruins.tres",
	"res://data/zones/zone_05_finale.tres",
]

var _saved_no_flash: bool = false
var _saved_readability: bool = false


func before_each() -> void:
	_saved_no_flash = Config.no_flash
	_saved_readability = Config.silhouette_readability
	Config.set_no_flash(false)
	Config.set_silhouette_readability(false)


func after_each() -> void:
	Config.set_no_flash(_saved_no_flash)
	Config.set_silhouette_readability(_saved_readability)


# ------------------------------------------------------------------------------
# Ambient / профиль
# ------------------------------------------------------------------------------

func test_ambient_limits_match_design_8_7() -> void:
	assert_almost_eq(LightingProfile.AMBIENT_MIN, 0.26, 0.001)
	assert_almost_eq(LightingProfile.AMBIENT_MAX, 0.5, 0.001)
	assert_almost_eq(LightingProfile.AMBIENT_MENU, 0.78, 0.001)

	assert_almost_eq(LightingProfile.world_ambient(0.0), 0.26, 0.001, "too dark -> 0.26")
	assert_almost_eq(LightingProfile.world_ambient(0.42), 0.42, 0.001, "in range kept")
	assert_almost_eq(LightingProfile.world_ambient(0.9), 0.5, 0.001, "too bright -> 0.5")


func test_menu_profile_is_bright_0_78() -> void:
	var profile := LightingProfile.menu_profile()
	assert_true(profile.menu_mode)
	assert_almost_eq(profile.effective_ambient(), 0.78, 0.001)
	assert_almost_eq(profile.vignette_strength(), 0.0, 0.001, "menus have no vignette")


func test_every_zone_ambient_is_within_dark_atmosphere_range() -> void:
	for path: String in ZONE_DATA_PATHS:
		var data := load(path) as ZoneData
		assert_not_null(data, "%s loads" % path)
		if data == null:
			continue
		assert_between(
			data.ambient_level,
			LightingProfile.AMBIENT_MIN,
			LightingProfile.AMBIENT_MAX,
			"%s ambient stays inside DESIGN §8.7" % path
		)
		assert_almost_eq(
			LightingProfile.from_zone(data).effective_ambient(),
			data.ambient_level,
			0.001,
			"%s profile keeps the zone ambient" % path
		)


func test_dither_levels_are_quantized_to_six_eight_steps() -> void:
	assert_eq(LightingProfile.levels_for(0), 6)
	assert_eq(LightingProfile.levels_for(7), 7)
	assert_eq(LightingProfile.levels_for(9), 8)


# ------------------------------------------------------------------------------
# Шейдеры
# ------------------------------------------------------------------------------

func test_shaders_exist_and_declare_required_uniforms() -> void:
	assert_not_null(POSTERIZE_SHADER)
	assert_not_null(DITHER_SHADER)
	assert_not_null(OUTLINE_SHADER)

	var posterize_code: String = POSTERIZE_SHADER.code
	assert_string_contains(posterize_code, "uniform int levels")
	assert_string_contains(posterize_code, "uniform float dither_strength")
	assert_string_contains(posterize_code, "uniform float vignette_strength")
	assert_string_contains(posterize_code, "bayer4")
	assert_string_contains(posterize_code, "hint_screen_texture")

	var dither_code: String = DITHER_SHADER.code
	assert_string_contains(dither_code, "uniform vec4 glow_color")
	assert_string_contains(dither_code, "uniform float radius_px")
	assert_string_contains(dither_code, "uniform int steps")
	assert_string_contains(dither_code, "bayer4")

	var outline_code: String = OUTLINE_SHADER.code
	assert_string_contains(outline_code, "uniform bool enabled")
	assert_string_contains(outline_code, "uniform vec4 outline_color")
	assert_string_contains(outline_code, "rim_strength")


func test_bayer_4x4_is_stepped_without_smooth_gradients() -> void:
	# DESIGN §8.7: дизеринг Байера 4×4; границы ступеней — floor, не smoothstep.
	for shader: Shader in [POSTERIZE_SHADER, DITHER_SHADER]:
		assert_string_contains(shader.code, "floor")
		assert_string_contains(shader.code, "mod(pixel, 2.0)")
		assert_string_contains(shader.code, "16.0")
		assert_false(shader.code.contains("smoothstep"), "no smooth gradients/neon")
		assert_false(shader.code.contains("mix(color, color, 0.5)"))


# ------------------------------------------------------------------------------
# LightingRig: слои, виньетка, меню
# ------------------------------------------------------------------------------

func _spawn_rig(profile: LightingProfile = null) -> LightingRig:
	var rig := RIG_SCENE.instantiate() as LightingRig
	assert_not_null(rig, "lighting_rig.tscn has a LightingRig root")
	if rig == null:
		return null
	rig.auto_register_zone_lights = false
	rig.profile = profile
	add_child_autofree(rig)
	rig.set_process(false)
	return rig


func test_lighting_layers_match_design_z_order() -> void:
	var rig := _spawn_rig()
	if rig == null:
		return
	await wait_frames(1)

	var emissive := rig.get_emissive_layer()
	var post := rig.get_post_layer()
	assert_not_null(emissive)
	assert_not_null(post)
	assert_eq(emissive.layer, LightingRig.EMISSIVE_LAYER, "emissive/light layer = 1")
	assert_eq(post.layer, LightingRig.POST_LAYER, "post-process layer = 2")
	assert_lt(emissive.layer, post.layer, "world -> lights -> post")
	assert_lt(post.layer, LightingRig.HUD_LAYER, "lighting stays below HUD=10 (DESIGN §4.4)")
	assert_not_null(rig.get_post_material(), "screen ColorRect has a ShaderMaterial")
	if rig.get_post_material() != null:
		assert_eq(rig.get_post_material().shader, POSTERIZE_SHADER)


func test_menu_rig_creates_its_own_0_78_ambient() -> void:
	var rig := _spawn_rig(LightingProfile.menu_profile())
	if rig == null:
		return
	await wait_frames(1)
	var ambient := rig.get_node_or_null("Ambient") as CanvasModulate
	assert_not_null(ambient, "menu gets a CanvasModulate 0.78")
	if ambient != null:
		assert_almost_eq(ambient.color.r, 0.78, 0.001)
	assert_almost_eq(rig.get_ambient_level(), 0.78, 0.001)


func test_world_rig_does_not_add_second_canvas_modulate() -> void:
	var rig := _spawn_rig()
	if rig == null:
		return
	await wait_frames(1)
	assert_null(
		rig.get_node_or_null("Ambient"),
		"zone ambient stays on ZoneScene/Ambient (one CanvasModulate per canvas)"
	)


func test_readability_mode_removes_vignette() -> void:
	var rig := _spawn_rig()
	if rig == null:
		return
	await wait_frames(1)

	Config.set_silhouette_readability(false)
	assert_true(rig.is_vignette_active(), "default atmosphere has a light vignette")
	assert_gt(rig.get_vignette_strength(), 0.0)

	Config.set_silhouette_readability(true)
	assert_false(rig.is_vignette_active(), "readability mode removes the vignette")
	assert_almost_eq(rig.get_vignette_strength(), 0.0, 0.001)
	var shader_material := rig.get_post_material()
	assert_not_null(shader_material)
	if shader_material != null:
		assert_almost_eq(
			float(shader_material.get_shader_parameter(&"vignette_strength")),
			0.0,
			0.001,
			"shader uniform is updated too"
		)


# ------------------------------------------------------------------------------
# Эмиссивные объекты
# ------------------------------------------------------------------------------

func test_emissive_glow_lives_on_separate_canvas_layer() -> void:
	var rig := _spawn_rig()
	if rig == null:
		return
	await wait_frames(1)

	var glow := rig.spawn_emissive_glow(Vector2(100.0, 120.0), UITokens.GOLD, 20.0)
	assert_not_null(glow)
	assert_eq(glow.get_parent(), rig.get_emissive_layer(), "glow is on the emissive layer")
	assert_not_null(glow.get_glow_material())
	if glow.get_glow_material() != null:
		assert_eq(glow.get_glow_material().shader, DITHER_SHADER)
		assert_eq(
			int(glow.get_glow_material().get_shader_parameter(&"steps")),
			LightingProfile.DITHER_LEVELS_MIN,
			"6-stepped radial falloff, no smooth gradient"
		)
	# CanvasLayer 1 — отдельный canvas: CanvasModulate зоны (canvas 0) не действует.
	assert_true(glow.get_parent() is CanvasLayer)
	assert_eq((glow.get_parent() as CanvasLayer).layer, LightingRig.EMISSIVE_LAYER)


func test_zone_scene_installs_lighting_without_touching_ambient() -> void:
	var zone := SceneRouter.instantiate_zone(ZONE_01_SCENE)
	assert_not_null(zone)
	if zone == null:
		return
	add_child_autofree(zone)
	await wait_frames(1)

	var ambient := zone.get_node("Ambient") as CanvasModulate
	assert_not_null(ambient)
	assert_almost_eq(
		ambient.color.r,
		zone.zone_data.ambient_level,
		0.001,
		"T-13 ambient is preserved by T-35"
	)

	var rig := zone.get_node_or_null("LightingRig") as LightingRig
	assert_not_null(rig, "ZoneScene installs the lighting rig")
	if rig == null:
		return
	assert_eq(rig.get_emissive_layer().layer, LightingRig.EMISSIVE_LAYER)
	assert_eq(rig.get_post_layer().layer, LightingRig.POST_LAYER)
	assert_gte(rig.get_registered_light_count(), 1, "zone point lights are registered")
	assert_gte(
		rig.get_emissive_layer().get_child_count(),
		1,
		"warm torches/windows get emissive cores"
	)


# ------------------------------------------------------------------------------
# «Без мигания»: flicker и вспышки
# ------------------------------------------------------------------------------

func test_flame_flicker_is_stepped_three_frames() -> void:
	assert_almost_eq(LightingProfile.flame_multiplier(0.0), 1.0, 0.001)
	assert_almost_eq(LightingProfile.flame_multiplier(0.14), 1.05, 0.001)
	assert_almost_eq(LightingProfile.flame_multiplier(0.28), 0.95, 0.001)
	assert_almost_eq(LightingProfile.flame_multiplier(0.42), 1.0, 0.001, "3-frame loop")


func test_no_flash_disables_light_flicker() -> void:
	var rig := _spawn_rig()
	if rig == null:
		return
	await wait_frames(1)

	var light := PointLight2D.new()
	light.energy = 1.0
	add_child_autofree(light)
	rig.register_light(light)

	assert_almost_eq(rig.flicker_multiplier(0.14), 1.05, 0.001)
	rig.tick(0.14)
	assert_almost_eq(light.energy, 1.05, 0.001, "torch energy flickers by ±5%")

	Config.set_no_flash(true)
	assert_almost_eq(rig.flicker_multiplier(0.28), 1.0, 0.001)
	rig.tick(0.14)
	assert_almost_eq(light.energy, 1.0, 0.001, "no flicker in no-flash mode")


func test_emissive_glow_does_not_pulse_in_no_flash_mode() -> void:
	var glow := EmissiveGlow.new()
	glow.configure(UITokens.GOLD_3, 20.0, true)
	add_child_autofree(glow)
	await wait_frames(1)

	glow.tick(0.14)
	assert_almost_eq(glow.get_flicker_multiplier(), 1.05, 0.001)

	Config.set_no_flash(true)
	glow.tick(0.14)
	assert_almost_eq(glow.get_flicker_multiplier(), 1.0, 0.001, "steady flame")
	assert_almost_eq(
		float(glow.get_glow_material().get_shader_parameter(&"radius_px")),
		glow.radius_px,
		0.001,
		"radius stays constant"
	)


func test_flash_governor_allows_three_flashes_per_second() -> void:
	var governor := FlashGovernor.new()
	assert_true(governor.try_flash(10.0))
	assert_true(governor.try_flash(10.1))
	assert_true(governor.try_flash(10.2))
	assert_false(governor.try_flash(10.3), "fourth flash in the window is dropped")
	assert_eq(governor.count(10.3), FlashGovernor.MAX_FLASHES_PER_SEC)
	assert_true(governor.try_flash(11.01), "old flashes leave the sliding window")


func test_damage_flash_is_disabled_by_no_flash() -> void:
	var sprite := ColorRect.new()
	sprite.modulate = UITokens.BONE
	add_child_autofree(sprite)

	Config.set_no_flash(true)
	Damage.create(1.0).flash(sprite)
	assert_eq(sprite.modulate, UITokens.BONE, "no white flash in no-flash mode")

	Config.set_no_flash(false)
	Damage.create(1.0).flash(sprite)
	assert_eq(sprite.modulate, Damage.FLASH_COLOR, "flash still works in normal mode")


func test_hurtbox_caps_damage_flashes_per_second() -> void:
	var body := Node2D.new()
	add_child_autofree(body)
	var visual := ColorRect.new()
	body.add_child(visual)
	var hurtbox := Hurtbox.new()
	hurtbox.flash_target_path = NodePath("../ColorRect")
	body.add_child(hurtbox)
	await wait_frames(1)

	for index in 5:
		hurtbox.receive_damage(Damage.create(float(index + 1)))

	assert_eq(hurtbox.hit_count, 5, "damage is still applied to every hit")
	assert_eq(
		hurtbox.flash_applied_count,
		FlashGovernor.MAX_FLASHES_PER_SEC,
		"only 3 flashes per second"
	)


func test_hurtbox_shows_no_flash_at_all_in_no_flash_mode() -> void:
	var body := Node2D.new()
	add_child_autofree(body)
	var visual := ColorRect.new()
	body.add_child(visual)
	var hurtbox := Hurtbox.new()
	hurtbox.flash_target_path = NodePath("../ColorRect")
	body.add_child(hurtbox)
	await wait_frames(1)

	Config.set_no_flash(true)
	hurtbox.receive_damage(Damage.create(5.0))
	assert_eq(hurtbox.flash_applied_count, 0, "no damage flashes")
	assert_eq(visual.modulate, Color.WHITE, "visual is untouched")


# ------------------------------------------------------------------------------
# Читаемость силуэта героя (AC-07.1)
# ------------------------------------------------------------------------------

func test_player_outline_follows_readability_mode() -> void:
	GameState.reset_stamina()
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await wait_frames(2)

	var animation := player.get_node("Animation") as PlayerAnimation
	assert_not_null(animation)
	if animation == null:
		return
	var material := animation.get_outline_material()
	assert_not_null(material, "player sprite has the silhouette shader")
	if material == null:
		return
	assert_eq(material.shader, OUTLINE_SHADER)
	assert_false(animation.is_silhouette_outline_enabled(), "off by default")

	Config.set_silhouette_readability(true)
	assert_true(animation.is_silhouette_outline_enabled(), "readability enables the contour")
	assert_gt(
		float(material.get_shader_parameter(&"rim_strength")),
		0.0,
		"default rim-light keeps the silhouette visible (AC-07.1)"
	)

	Config.set_silhouette_readability(false)
	assert_false(animation.is_silhouette_outline_enabled())
