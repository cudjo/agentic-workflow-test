class_name PlayerAnimation
extends Node2D
## PlayerAnimation — визуальная привязка FSM игрока к анимациям (T-05, DESIGN §7).
##
## Ничего не решает про физику/бой: слушает `EventBus.player_state_changed` и
## проигрывает соответствующий набор `AnimatedSprite2D`, добавляет визуальные
## признаки (вспышка double jump, шлейф dash, пыль бега, метка «Твои вещи»).
##
## Подход: `AnimatedSprite2D` + кадровые анимации, потому что DESIGN §7 задаёт
## именно кадры и тайминги (6–12 кадров на действие), а пиксель-арт 16×24 не
## требует интерполяции `AnimationPlayer`. Кадры — `PlayerSpriteFrames`
## (программные заглушки), заменяемые через `frames_override` без правок логики.
##
## a11y: при `Config.no_flash` вспышка урона заменяется спокойной сменой тона
## без мерцания (DESIGN §7/§9.3).

signal animation_changed(animation: StringName)

## Соответствие состояний FSM (T-04) и анимаций контракта.
## `jump` уточняется в `tick()` (подъём/апекс), `attack` — по шагу комбо.
const STATE_TO_ANIMATION := {
	&"idle": PlayerSpriteFrames.ANIM_IDLE,
	&"run": PlayerSpriteFrames.ANIM_RUN,
	&"jump": PlayerSpriteFrames.ANIM_JUMP_RISE,
	&"fall": PlayerSpriteFrames.ANIM_FALL,
	&"wall_slide": PlayerSpriteFrames.ANIM_WALL_SLIDE,
	# Wall kick — отталкивание от стены; визуально это прыжок (T-08).
	&"wall_kick": PlayerSpriteFrames.ANIM_JUMP_RISE,
	&"land": PlayerSpriteFrames.ANIM_LAND,
	&"attack": PlayerSpriteFrames.ANIM_ATTACK_1,
	&"block": PlayerSpriteFrames.ANIM_BLOCK,
	&"roll": PlayerSpriteFrames.ANIM_ROLL,
	&"dash": PlayerSpriteFrames.ANIM_DASH,
	&"hurt": PlayerSpriteFrames.ANIM_HURT,
	&"death": PlayerSpriteFrames.ANIM_DEATH,
	# Состояния будущих задач (T-23): контракт уже готов.
	&"double_jump": PlayerSpriteFrames.ANIM_DOUBLE_JUMP,
	&"out_of_stamina": PlayerSpriteFrames.ANIM_OUT_OF_STAMINA,
	&"sit": PlayerSpriteFrames.ANIM_SIT,
}

## |vy|, ниже которого прыжок считается апексом (DESIGN §7: «|vy| мало»).
const APEX_VELOCITY: float = 20.0
## Шлейф dash: 2 «призрачных» кадра steel-9 (DESIGN §7).
const DASH_GHOST_COUNT: int = 2
const DASH_GHOST_LIFETIME: float = 0.12
## Вспышка double jump: 2–3 кадра steel-3 (DESIGN §7).
const DOUBLE_JUMP_FLASH_FRAMES: int = 3
## Вспышка урона без «без мигания»: один короткий кадр ≤ 100 мс (AC-03.1).
const HURT_FLASH_TIME: float = 0.06
const DUST_LIFETIME: float = 0.25

## Готовый SpriteFrames настоящего арта; null → программные заглушки.
@export var frames_override: SpriteFrames

@onready var sprite: AnimatedSprite2D = $Sprite

## Текущая проигрываемая анимация (контракт PlayerSpriteFrames).
var current_animation: StringName = &""
## Счётчики для тестов/отладки визуальных признаков.
var dash_ghost_count: int = 0
var dust_spawn_count: int = 0

var _player: Player
var _state: StringName = &""
var _tint_left: float = 0.0
var _is_double_jump_flash: bool = false
var _dash_ghosts: Array[Sprite2D] = []
var _dust_timer: float = 0.0
var _death_marker: Sprite2D
## T-35: материал контура силуэта (AC-07.1). Всегда назначен, контур
## включается только режимом «Читаемость силуэтов» (Config).
var _outline_material: ShaderMaterial


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("PlayerAnimation: parent must be Player")
		return
	if sprite == null:
		push_error("PlayerAnimation: AnimatedSprite2D child 'Sprite' is missing")
		return
	sprite.sprite_frames = (
		frames_override
		if frames_override != null
		else PlayerSpriteFrames.build(_get_balance(), _get_attack_speed())
	)
	sprite.offset = Vector2(0.0, -2.0)
	_setup_silhouette_outline()
	EventBus.player_state_changed.connect(_on_player_state_changed)
	Config.visual_accessibility_changed.connect(_apply_silhouette_outline)
	_play(PlayerSpriteFrames.ANIM_IDLE)


## T-35: контур силуэта по shader'у, материал общий для всех кадров.
func _setup_silhouette_outline() -> void:
	_outline_material = SilhouetteOutline.create_material()
	sprite.material = _outline_material
	_apply_silhouette_outline()


func _apply_silhouette_outline() -> void:
	SilhouetteOutline.set_enabled(_outline_material, Config.silhouette_readability)


func _process(delta: float) -> void:
	tick(delta)


## Один шаг визуала; публичный, чтобы GUT-тесты шли детерминированно.
func tick(delta: float) -> void:
	if _player == null or sprite == null:
		return
	sprite.flip_h = _player.facing < 0
	_update_animation_for_motion()
	_tick_tint(delta)
	_tick_dust(delta)


# ------------------------------------------------------------------------------
# Public API (FSM events + будущие способности/костёр)
# ------------------------------------------------------------------------------

## Текущая анимация (StringName из контракта).
func get_current_animation() -> StringName:
	return current_animation


## Активна ли короткая вспышка double jump (steel-3, 2–3 кадра).
func is_double_jump_flash_active() -> bool:
	return _is_double_jump_flash and _tint_left > 0.0


## Активна ли вспышка урона. В режиме «без мигания» всегда false.
func is_flash_active() -> bool:
	return _tint_left > 0.0 and not Config.no_flash


## Материал контура силуэта (T-35, AC-07.1) — для тестов/отладки.
func get_outline_material() -> ShaderMaterial:
	return _outline_material


## Включён ли 1-px контур (режим «Читаемость силуэтов»).
func is_silhouette_outline_enabled() -> bool:
	return SilhouetteOutline.is_enabled(_outline_material)


## Живые «призрачные» кадры шлейфа dash.
func get_dash_ghosts() -> Array[Sprite2D]:
	var alive: Array[Sprite2D] = []
	for ghost: Sprite2D in _dash_ghosts:
		if is_instance_valid(ghost):
			alive.append(ghost)
	return alive


## Метка «Твои вещи» на месте гибели создана?
func has_death_marker() -> bool:
	return _death_marker != null and is_instance_valid(_death_marker)


## Убирает метку (возрождение у костра, T-26).
func clear_death_marker() -> void:
	if has_death_marker():
		_death_marker.queue_free()
	_death_marker = null


## Посадить героя у костра (T-23) и вернуть в idle.
func play_sit() -> void:
	_state = &"sit"
	_play(PlayerSpriteFrames.ANIM_SIT)


func play_idle() -> void:
	_state = &"idle"
	_play(PlayerSpriteFrames.ANIM_IDLE)


## Публичный вход для двойного прыжка (T-06), если он не эмитит состояние.
func play_double_jump() -> void:
	_on_player_state_changed(&"double_jump")


# ------------------------------------------------------------------------------
# State -> animation
# ------------------------------------------------------------------------------

func _on_player_state_changed(state_name: StringName) -> void:
	_state = state_name
	var animation: StringName = STATE_TO_ANIMATION.get(state_name, &"")
	if animation == &"":
		return
	if state_name == &"jump":
		animation = _air_animation()
	elif state_name == &"attack":
		animation = _attack_animation()
	elif state_name == &"idle":
		animation = _idle_animation()
	_play(animation)

	match state_name:
		&"double_jump":
			_start_double_jump_flash()
		&"dash":
			_start_dash()
		&"hurt":
			_start_hurt()
		&"death":
			_spawn_death_marker()
		&"run":
			_dust_timer = 0.0


func _update_animation_for_motion() -> void:
	match _state:
		&"jump":
			_play(_air_animation())
		&"attack":
			_play(_attack_animation())
		&"idle":
			_play(_idle_animation())


func _air_animation() -> StringName:
	if absf(_player.velocity.y) <= APEX_VELOCITY:
		return PlayerSpriteFrames.ANIM_JUMP_APEX
	return PlayerSpriteFrames.ANIM_JUMP_RISE


func _attack_animation() -> StringName:
	var step: int = 0
	if _player.combo != null:
		step = clampi(_player.combo.step_index, 0, 2)
	match step:
		1:
			return PlayerSpriteFrames.ANIM_ATTACK_2
		2:
			return PlayerSpriteFrames.ANIM_ATTACK_3
		_:
			return PlayerSpriteFrames.ANIM_ATTACK_1


## AC-03.3: при нуле выносливости в покое показываем idle-вариант «тяжело дышит».
func _idle_animation() -> StringName:
	if GameState.is_stamina_exhausted():
		return PlayerSpriteFrames.ANIM_OUT_OF_STAMINA
	return PlayerSpriteFrames.ANIM_IDLE


func _play(animation: StringName) -> void:
	if sprite == null or animation == &"":
		return
	if current_animation == animation and sprite.is_playing():
		return
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation):
		return
	_sync_attack_speed(animation)
	current_animation = animation
	sprite.play(animation)
	animation_changed.emit(animation)


# ------------------------------------------------------------------------------
# Visual cues
# ------------------------------------------------------------------------------

## Холодная вспышка double jump на 2–3 кадра (steel-3). Не зависит от no_flash:
## это не мерцание урона, а одиночная вспышка способности.
## T-06: FSM вызывает `play_double_jump()` на входе в состояние, после чего
## то же состояние приходит сигналом — активную вспышку не перезапускаем.
func _start_double_jump_flash() -> void:
	if _is_double_jump_flash and _tint_left > 0.0:
		return
	var speed: float = 1.0
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(
		PlayerSpriteFrames.ANIM_DOUBLE_JUMP
	):
		speed = maxf(
			sprite.sprite_frames.get_animation_speed(PlayerSpriteFrames.ANIM_DOUBLE_JUMP),
			1.0
		)
	_tint_left = float(DOUBLE_JUMP_FLASH_FRAMES) / speed
	_is_double_jump_flash = true
	sprite.modulate = UITokens.STEEL_3


## Hurt: вспышка спрайта; при Config.no_flash — смена тона без мерцания.
func _start_hurt() -> void:
	_is_double_jump_flash = false
	if Config.no_flash:
		_tint_left = _get_balance().t_hurt
		sprite.modulate = UITokens.BLOOD_5
	else:
		_tint_left = HURT_FLASH_TIME
		sprite.modulate = UITokens.BONE


## Dash: 2 призрачных кадра steel-9 + холодный i-frames-вид (без мерцания).
func _start_dash() -> void:
	_is_double_jump_flash = false
	_tint_left = _get_balance().t_dash
	sprite.modulate = UITokens.STEEL_3
	_dash_ghosts.clear()
	for index: int in DASH_GHOST_COUNT:
		_spawn_dash_ghost(index)


func _spawn_dash_ghost(index: int) -> void:
	if sprite.sprite_frames == null:
		return
	var texture: Texture2D = sprite.sprite_frames.get_frame_texture(
		sprite.animation, sprite.frame
	)
	if texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.top_level = true
	ghost.texture = texture
	ghost.offset = sprite.offset
	ghost.flip_h = sprite.flip_h
	ghost.modulate = Color(UITokens.STEEL_9, 0.55)
	ghost.z_index = -1
	add_child(ghost)
	ghost.global_position = _player.global_position - Vector2(
		float(_player.facing) * (4.0 + 5.0 * float(index)), 0.0
	)
	var tween: Tween = ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, DASH_GHOST_LIFETIME)
	tween.tween_callback(ghost.queue_free)
	_dash_ghosts.append(ghost)
	dash_ghost_count += 1


## Пыль/брызги от шагов на влажной земле во время бега.
func _tick_dust(delta: float) -> void:
	if _state != &"run":
		_dust_timer = 0.0
		return
	_dust_timer += delta
	var interval: float = _get_balance().anim_dust_interval
	if _dust_timer < interval:
		return
	_dust_timer -= interval
	_spawn_dust()


func _spawn_dust() -> void:
	var particle := Sprite2D.new()
	particle.top_level = true
	particle.texture = PlayerSpriteFrames.make_particle_texture(PlayerSpriteFrames.C_DUST)
	particle.z_index = -1
	add_child(particle)
	particle.global_position = _player.global_position + Vector2(
		-float(_player.facing) * 3.0, 9.0
	)
	var tween: Tween = particle.create_tween()
	tween.tween_property(particle, "modulate:a", 0.0, DUST_LIFETIME)
	tween.parallel().tween_property(particle, "position:y", particle.position.y - 3.0, DUST_LIFETIME)
	tween.tween_callback(particle.queue_free)
	dust_spawn_count += 1


## Метка «Твои вещи»: мешок с золотым ореолом на месте гибели (DESIGN §7).
func _spawn_death_marker() -> void:
	if has_death_marker():
		return
	_death_marker = Sprite2D.new()
	_death_marker.top_level = true
	_death_marker.texture = PlayerSpriteFrames.build_death_marker_texture()
	_death_marker.z_index = -1
	add_child(_death_marker)
	_death_marker.global_position = _player.global_position + Vector2(0.0, 8.0)


func _tick_tint(delta: float) -> void:
	if _tint_left <= 0.0:
		return
	_tint_left -= delta
	if _tint_left > 0.0:
		return
	_tint_left = 0.0
	_is_double_jump_flash = false
	if sprite != null:
		sprite.modulate = Color.WHITE


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

## Замах/удар/возврат должны совпадать с длительностью шага комбо (T-10).
func _sync_attack_speed(animation: StringName) -> void:
	if not String(animation).begins_with("attack_"):
		return
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation):
		return
	var count: int = PlayerSpriteFrames.FRAME_COUNTS.get(animation, 0)
	if count <= 0:
		return
	var step: float = maxf(_get_balance().t_attack * _get_attack_speed(), 0.001)
	sprite.sprite_frames.set_animation_speed(animation, float(count) / step)


func _get_balance() -> BalancingParams:
	if _player != null and _player.balance != null:
		return _player.balance
	return load("res://data/balance/balancing.tres") as BalancingParams


func _get_attack_speed() -> float:
	if _player == null:
		return 1.0
	var weapon: WeaponData = _player.get_weapon()
	return weapon.attack_speed if weapon != null else 1.0
