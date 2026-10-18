class_name PlayerSpriteFrames
extends RefCounted
## PlayerSpriteFrames — контракт кадров игрока и программные заглушки (T-05).
##
## Спрайт 16×24, ≤ 16 цветов (DESIGN §7, SPEC §6.1). Кадры генерируются в
## памяти детерминированно, чтобы вся сцена/логика работали до появления арта.
## Замена на настоящий арт — передать готовый `SpriteFrames` в
## `PlayerAnimation.frames_override` (или заменить реализацию `build()`),
## логика FSM и имена анимаций при этом не меняются.
##
## Цвета берутся только из токенов `UITokens` (DESIGN §4.1). Палитра заглушки
## — 9 цветов, что укладывается в лимит 16.

const SIZE := Vector2i(16, 24)
const MAX_COLORS: int = 16

## Полный набор анимаций из DESIGN §7 (+ wall_slide/out_of_stamina/sit).
const ANIM_IDLE: StringName = &"idle"
const ANIM_RUN: StringName = &"run"
const ANIM_JUMP_RISE: StringName = &"jump_rise"
const ANIM_JUMP_APEX: StringName = &"jump_apex"
const ANIM_FALL: StringName = &"fall"
const ANIM_LAND: StringName = &"land"
const ANIM_DOUBLE_JUMP: StringName = &"double_jump"
const ANIM_DASH: StringName = &"dash"
const ANIM_WALL_SLIDE: StringName = &"wall_slide"
const ANIM_ATTACK_1: StringName = &"attack_1"
const ANIM_ATTACK_2: StringName = &"attack_2"
const ANIM_ATTACK_3: StringName = &"attack_3"
const ANIM_BLOCK: StringName = &"block"
const ANIM_ROLL: StringName = &"roll"
const ANIM_HURT: StringName = &"hurt"
const ANIM_DEATH: StringName = &"death"
const ANIM_OUT_OF_STAMINA: StringName = &"out_of_stamina"
const ANIM_SIT: StringName = &"sit"

## Анимации, которые зациклены (DESIGN §7: «цикл»); остальные играются один раз.
const LOOPING: Array[StringName] = [
	ANIM_IDLE,
	ANIM_RUN,
	ANIM_JUMP_RISE,
	ANIM_JUMP_APEX,
	ANIM_FALL,
	ANIM_WALL_SLIDE,
	ANIM_BLOCK,
	ANIM_OUT_OF_STAMINA,
	ANIM_SIT,
]

## Количество кадров по DESIGN §7.
const FRAME_COUNTS := {
	ANIM_IDLE: 6,
	ANIM_RUN: 8,
	ANIM_JUMP_RISE: 2,
	ANIM_JUMP_APEX: 2,
	ANIM_FALL: 2,
	ANIM_LAND: 3,
	ANIM_DOUBLE_JUMP: 6,
	ANIM_DASH: 4,
	ANIM_WALL_SLIDE: 2,
	ANIM_ATTACK_1: 6,
	ANIM_ATTACK_2: 6,
	ANIM_ATTACK_3: 8,
	ANIM_BLOCK: 2,
	ANIM_ROLL: 6,
	ANIM_HURT: 2,
	ANIM_DEATH: 10,
	ANIM_OUT_OF_STAMINA: 4,
	ANIM_SIT: 4,
}

# ------------------------------------------------------------------------------
# Палитра заглушки (9 цветов из токенов)
# ------------------------------------------------------------------------------
const C_OUTLINE := UITokens.VOID
const C_CLOAK := UITokens.STEEL_9
const C_BODY := UITokens.STEEL
const C_HIGHLIGHT := UITokens.STEEL_3
const C_SKIN := UITokens.BONE
const C_WEAPON := UITokens.GOLD_3
const C_SHIELD := UITokens.STEEL_3
const C_DUST := UITokens.BROWN_3
const C_MARKER := UITokens.GOLD_9
const C_MARKER_BAG := UITokens.BROWN

const PLACEHOLDER_COLORS: Array[Color] = [
	C_OUTLINE,
	C_CLOAK,
	C_BODY,
	C_HIGHLIGHT,
	C_SKIN,
	C_WEAPON,
	C_SHIELD,
	C_DUST,
	C_MARKER,
]


## Имена всех анимаций контракта (для тестов/реального арта).
static func animation_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for anim_name: StringName in FRAME_COUNTS.keys():
		names.append(anim_name)
	return names


## Собирает SpriteFrames из заглушек. Скорости кадров берутся из
## `balancing.tres`; `attack_speed` — множитель скорости удара оружия.
static func build(
	balance: BalancingParams,
	attack_speed: float = 1.0
) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var attack_step: float = maxf(balance.t_attack * attack_speed, 0.001)
	var specs := {
		ANIM_IDLE: _spec(balance.anim_idle_frame, true),
		ANIM_RUN: _spec(balance.anim_run_frame, true),
		ANIM_JUMP_RISE: _spec(balance.anim_air_frame, true),
		ANIM_JUMP_APEX: _spec(balance.anim_apex_frame, true),
		ANIM_FALL: _spec(balance.anim_air_frame, true),
		ANIM_LAND: _spec(balance.t_land, false, FRAME_COUNTS[ANIM_LAND]),
		ANIM_DOUBLE_JUMP: _spec(
			balance.anim_double_jump_time, false, FRAME_COUNTS[ANIM_DOUBLE_JUMP]
		),
		ANIM_DASH: _spec(balance.t_dash, false, FRAME_COUNTS[ANIM_DASH]),
		ANIM_WALL_SLIDE: _spec(balance.anim_air_frame, true),
		ANIM_ATTACK_1: _spec(attack_step, false, FRAME_COUNTS[ANIM_ATTACK_1]),
		ANIM_ATTACK_2: _spec(attack_step, false, FRAME_COUNTS[ANIM_ATTACK_2]),
		ANIM_ATTACK_3: _spec(attack_step, false, FRAME_COUNTS[ANIM_ATTACK_3]),
		ANIM_BLOCK: _spec(balance.anim_block_frame, true),
		ANIM_ROLL: _spec(balance.t_roll, false, FRAME_COUNTS[ANIM_ROLL]),
		ANIM_HURT: _spec(balance.t_hurt, false, FRAME_COUNTS[ANIM_HURT]),
		ANIM_DEATH: _spec(balance.anim_death_frame, true),
		ANIM_OUT_OF_STAMINA: _spec(balance.anim_out_of_stamina_frame, true),
		ANIM_SIT: _spec(balance.anim_sit_frame, true),
	}
	for anim_name: StringName in specs.keys():
		var spec: Dictionary = specs[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, spec["fps"])
		frames.set_animation_loop(anim_name, LOOPING.has(anim_name))
		var count: int = FRAME_COUNTS[anim_name]
		for index: int in count:
			frames.add_frame(
				anim_name,
				_build_frame(anim_name, index, count),
				1.0
			)
	return frames


## 2×2 частица пыли/брызг (цвет из токенов).
static func make_particle_texture(color: Color, size: int = 2) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


## Метка «Твои вещи» на месте гибели: мешок с золотым ореолом (gold-9).
## 12×12, рисуется над телом; T-26 может использовать её как иконку corpse.
static func build_death_marker_texture() -> ImageTexture:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	# Золотой ореол/рамка (gold-9).
	_rect(image, 1, 3, 10, 1, C_MARKER)
	_rect(image, 1, 8, 10, 1, C_MARKER)
	_rect(image, 1, 3, 1, 6, C_MARKER)
	_rect(image, 10, 3, 1, 6, C_MARKER)
	# Мешок (brown) и завязка.
	_rect(image, 3, 5, 6, 5, C_MARKER_BAG)
	_rect(image, 5, 4, 2, 1, C_MARKER)
	_rect(image, 4, 5, 1, 1, C_MARKER)
	_rect(image, 7, 5, 1, 1, C_MARKER)
	return ImageTexture.create_from_image(image)


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

static func _spec(seconds: float, per_frame: bool, frame_count: int = 1) -> Dictionary:
	var safe_seconds: float = maxf(seconds, 0.001)
	return {
		"fps": (1.0 / safe_seconds) if per_frame else (float(frame_count) / safe_seconds),
	}


static func _build_frame(anim_name: StringName, index: int, count: int) -> ImageTexture:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_draw_figure(image, anim_name, index, count)
	return ImageTexture.create_from_image(image)


static func _pose(anim_name: StringName, index: int, count: int) -> Dictionary:
	# top/body_h задают торс; ноги идут до линии пола (y = 22).
	var pose: Dictionary = {
		"top": 7,
		"body_h": 10,
		"dx": 0,
		"leg_l": 0,
		"leg_r": 0,
		"head_dx": 0,
		"head_dy": 0,
		"arm": true,
		"shield": false,
		"weapon": Rect2i(),
		"flat": false,
	}
	match anim_name:
		ANIM_IDLE:
			var bob: int = 1 if index >= count / 2 else 0
			pose["top"] = 7 + bob
			pose["body_h"] = 10 - bob
		ANIM_OUT_OF_STAMINA:
			var breathe: int = 1 if index % 2 == 1 else 0
			pose["top"] = 10 + breathe
			pose["body_h"] = 7 - breathe
			pose["dx"] = -1
		ANIM_SIT:
			pose["top"] = 12
			pose["body_h"] = 6
			pose["leg_l"] = 2
			pose["leg_r"] = 3
		ANIM_RUN:
			var step: Array[int] = [0, 1, 2, 3, 2, 1, 0, -1]
			pose["top"] = 6
			pose["body_h"] = 10
			pose["dx"] = 1
			pose["leg_l"] = step[index % step.size()]
			pose["leg_r"] = -step[index % step.size()]
			pose["head_dy"] = 1
		ANIM_JUMP_RISE:
			pose["top"] = 5
			pose["body_h"] = 12
			pose["dx"] = 1
		ANIM_JUMP_APEX:
			pose["top"] = 8
			pose["body_h"] = 9
			pose["leg_l"] = 1
			pose["leg_r"] = -1
		ANIM_FALL:
			pose["top"] = 6
			pose["body_h"] = 10
			pose["arm"] = false
		ANIM_LAND:
			var crouch: int = 1 if index == 1 else 0
			pose["top"] = 8 + crouch
			pose["body_h"] = 8 - crouch
			pose["leg_l"] = -1
			pose["leg_r"] = 1
		ANIM_DOUBLE_JUMP:
			var tuck: int = 2 if index < 2 else 0
			pose["top"] = 9 - tuck
			pose["body_h"] = 8 + tuck
			pose["leg_l"] = 1
			pose["leg_r"] = -1
		ANIM_DASH:
			pose["top"] = 8
			pose["body_h"] = 10
			pose["dx"] = 3
			pose["leg_l"] = 1
			pose["leg_r"] = -1
			pose["weapon"] = Rect2i(9, 9, 6, 2)
		ANIM_WALL_SLIDE:
			pose["top"] = 7
			pose["body_h"] = 11
			pose["arm"] = false
			pose["weapon"] = Rect2i(1, 8, 2, 6)
		ANIM_ATTACK_1:
			_attack_pose(pose, index, 6, false)
		ANIM_ATTACK_2:
			_attack_pose(pose, index, 6, true)
		ANIM_ATTACK_3:
			_attack_pose(pose, index, 8, false)
		ANIM_BLOCK:
			pose["top"] = 8
			pose["body_h"] = 9
			pose["shield"] = true
			pose["weapon"] = Rect2i(2, 10, 2, 5)
		ANIM_ROLL:
			var ball: int = index % 3
			pose["top"] = 13 + (1 if ball == 2 else 0)
			pose["body_h"] = 6
			pose["dx"] = ball
			pose["head_dx"] = 2
			pose["head_dy"] = -1
			pose["leg_l"] = 1
			pose["leg_r"] = -1
		ANIM_HURT:
			pose["top"] = 7
			pose["body_h"] = 10
			pose["dx"] = -1
			pose["head_dx"] = -1
		ANIM_DEATH:
			var progress: float = float(index) / float(maxi(count - 1, 1))
			pose["top"] = 7 + int(round(9.0 * progress))
			pose["body_h"] = 10 - int(round(6.0 * progress))
			pose["head_dy"] = int(round(4.0 * progress))
			pose["leg_l"] = int(round(2.0 * progress))
			pose["leg_r"] = -int(round(2.0 * progress))
			pose["flat"] = index == count - 1
	return pose


static func _attack_pose(pose: Dictionary, index: int, count: int, low_start: bool) -> void:
	pose["top"] = 7
	pose["body_h"] = 10
	var windup: bool = index < 2
	var hit: bool = index >= 2 and index < 4
	if count == 8:
		windup = index < 3
		hit = index >= 3 and index < 6
	if windup:
		pose["weapon"] = Rect2i(10, 1 if not low_start else 14, 2, 6)
	elif hit:
		pose["weapon"] = Rect2i(10, 9, 6, 2)
	else:
		pose["weapon"] = Rect2i(8, 14, 5, 2)


static func _draw_figure(image: Image, anim_name: StringName, index: int, count: int) -> void:
	var pose := _pose(anim_name, index, count)
	var top: int = pose["top"]
	var body_h: int = pose["body_h"]
	var dx: int = pose["dx"]
	if pose["flat"]:
		# Финальный кадр смерти: тело лежит (16×6), голова сбоку.
		_rect(image, 2, 16, 10, 4, C_BODY)
		_rect(image, 2, 16, 10, 1, C_HIGHLIGHT)
		_rect(image, 12, 16, 3, 3, C_SKIN)
		return
	# Плащ за спиной.
	_rect(image, 3 + dx, top, 2, body_h, C_CLOAK)
	# Ноги до линии пола.
	var leg_top: int = top + body_h
	var leg_h: int = maxi(22 - leg_top, 1)
	_rect(image, 5 + dx + int(pose["leg_l"]), leg_top, 2, leg_h, C_BODY)
	_rect(image, 9 + dx + int(pose["leg_r"]), leg_top, 2, leg_h, C_BODY)
	# Торс + холодный блик.
	_rect(image, 4 + dx, top, 7, body_h, C_BODY)
	_rect(image, 4 + dx, top, 1, body_h, C_HIGHLIGHT)
	# Рука.
	if pose["arm"]:
		_rect(image, 10 + dx, top + 2, 1, maxi(body_h - 3, 1), C_HIGHLIGHT)
	# Голова.
	var head_x: int = 5 + dx + int(pose["head_dx"])
	var head_y: int = top - 5 + int(pose["head_dy"])
	_rect(image, head_x, head_y, 6, 5, C_SKIN)
	_rect(image, head_x + 2, head_y, 2, 1, C_CLOAK)
	_rect(image, head_x + 4, head_y + 2, 1, 1, C_OUTLINE)
	# Щит перед собой.
	if pose["shield"]:
		_rect(image, 11 + dx, top + 2, 2, 7, C_SHIELD)
	# Оружие (кадр удара/замаха).
	var weapon: Rect2i = pose["weapon"]
	if weapon.size.x > 0:
		_rect(image, weapon.position.x + dx, weapon.position.y, weapon.size.x, weapon.size.y, C_WEAPON)


static func _rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var clipped := Rect2i(x, y, w, h).intersection(Rect2i(Vector2i.ZERO, SIZE))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	image.fill_rect(clipped, color)
