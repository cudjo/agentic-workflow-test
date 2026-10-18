class_name BossHazard
extends Node2D
## BossHazard — зона опасности окружения на арене босса (T-31).
##
## Паттерны боссов зон 3–4 используют механику своих зон: камнепад в
## вертикальных шахтах перевала и руны-ловушки на полу руин. Оба варианта
## имеют одинаковый читаемый контракт:
##   1. TELEGRAPH — предупреждение (мигающая колонна / руна), урона нет;
##   2. ACTIVE    — короткое окно урона (падающий камень / шипы);
##   3. DONE      — зона исчезает.
##
## Урон идёт через боевое ядро T-10 (`Hitbox`: enemy_hitbox → player_hurtbox),
## поэтому отбрасывание/вспышка/слои совпадают с остальным боем. Геометрия и
## тайминги приходят из `BossPhaseData` (`hazard_*`) и подкласса босса, а не
## хардкодятся здесь. Арт — программные заглушки через `_draw()`.

## Зона отработала (тесты/арена могут очистить список).
signal resolved(hazard: BossHazard)

enum Kind {
	## Камень падает сверху вниз по вертикальной шахте.
	FALLING_ROCK,
	## Шипы/руна срабатывает на полу.
	SPIKE_TRAP,
}

enum Phase {
	IDLE,
	TELEGRAPH,
	ACTIVE,
	DONE,
}

## Частота мигания предупреждения (визуальный telegraph), Гц.
const BLINK_HZ: float = 8.0

var kind: Kind = Kind.FALLING_ROCK
var phase: Phase = Phase.IDLE
var fall_speed: float = 240.0
## Мировой Y пола (для камня — цель падения, для ловушки — линия пола).
var target_y: float = 0.0
var hazard_size: Vector2 = Vector2(16.0, 16.0)
var body_color: Color = Color(0.5, 0.55, 0.6, 1.0)
var warning_color: Color = Color(0.71, 0.28, 0.24, 1.0)

var _telegraph_time: float = 0.5
var _active_time: float = 0.3
var _timer: float = 0.0
var _spawn_y: float = 0.0
var _payload: Damage = null
var _knockback: float = 0.0
var _direction: Vector2 = Vector2.DOWN
var _hitbox: Hitbox = null


## Настраивает зону до добавления в дерево. Тайминги — из `BossPhaseData`.
func configure(
	kind_value: Kind,
	payload: Damage,
	knockback_force: float,
	telegraph: float,
	active: float,
	direction: Vector2,
	speed: float,
	size_value: Vector2,
	color: Color,
	warning: Color
) -> void:
	kind = kind_value
	_payload = payload
	_knockback = maxf(knockback_force, 0.0)
	_telegraph_time = maxf(telegraph, 0.0)
	_active_time = maxf(active, 0.0)
	_direction = direction.normalized() if not direction.is_zero_approx() else Vector2.DOWN
	fall_speed = maxf(speed, 0.0)
	hazard_size = Vector2(maxf(size_value.x, 1.0), maxf(size_value.y, 1.0))
	body_color = color
	warning_color = warning


## Ставит зону в мир. Для камня `spawn` — точка вверху шахты, `floor_y` —
## пол; для ловушки `spawn.x` — колонна, зона садится на пол.
func place_at(spawn: Vector2, floor_y: float) -> void:
	target_y = floor_y
	if kind == Kind.SPIKE_TRAP:
		global_position = Vector2(spawn.x, floor_y - hazard_size.y * 0.5)
	else:
		global_position = spawn
	_spawn_y = global_position.y
	queue_redraw()


func is_telegraphing() -> bool:
	return phase == Phase.TELEGRAPH


func is_dangerous() -> bool:
	return phase == Phase.ACTIVE and _hitbox != null and _hitbox.active


func get_fall_distance() -> float:
	return maxf(target_y - _spawn_y, 1.0)


func _ready() -> void:
	z_index = 5
	_build_hitbox()
	_timer = 0.0
	phase = Phase.TELEGRAPH
	queue_redraw()


func _physics_process(delta: float) -> void:
	match phase:
		Phase.TELEGRAPH:
			_timer += delta
			queue_redraw()
			if _timer >= _telegraph_time:
				_enter_active()
		Phase.ACTIVE:
			if kind == Kind.FALLING_ROCK:
				position.y += fall_speed * delta
				queue_redraw()
				if global_position.y >= target_y:
					_finish()
			else:
				_timer += delta
				if _timer >= _active_time:
					_finish()


func _build_hitbox() -> void:
	_hitbox = Hitbox.new()
	_hitbox.name = "Hitbox"
	_hitbox.hit_layer = CombatLayers.ENEMY_HITBOX
	_hitbox.target_mask = CombatLayers.PLAYER_HURTBOX
	_hitbox.collision_layer = CombatLayers.ENEMY_HITBOX
	_hitbox.collision_mask = CombatLayers.PLAYER_HURTBOX
	_hitbox.start_active = false
	add_child(_hitbox)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = hazard_size
	shape.shape = rect
	_hitbox.add_child(shape)
	_hitbox.deactivate()


func _enter_active() -> void:
	phase = Phase.ACTIVE
	_timer = 0.0
	if _hitbox == null or _payload == null:
		_finish()
		return
	_hitbox.clear_hits()
	_hitbox.activate(_payload, _knockback, _direction)
	queue_redraw()


func _finish() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	if _hitbox != null:
		_hitbox.deactivate()
	resolved.emit(self)
	queue_free()


# ------------------------------------------------------------------------------
# Placeholder art: предупреждение и срабатывание читаются без звука
# ------------------------------------------------------------------------------

func _draw() -> void:
	match phase:
		Phase.TELEGRAPH:
			_draw_telegraph()
		Phase.ACTIVE:
			_draw_active()
		_:
			pass


## Яркость предупреждения. В режиме «Без мигания» (DESIGN §9.3) остаётся
## ровной: telegraph читается формой колонны/руны, а не частотой вспышек.
func _blink_alpha() -> float:
	var config := get_node_or_null("/root/Config")
	if config != null and bool(config.get("no_flash")):
		return 0.7
	var step: int = int(_timer * BLINK_HZ * 0.5)
	return 0.35 if step % 2 == 0 else 0.7


## Публичный доступ к яркости предупреждения (тесты доступности).
func get_warning_alpha() -> float:
	return _blink_alpha()


func _draw_telegraph() -> void:
	var alpha: float = _blink_alpha()
	var warning := warning_color
	warning.a = alpha
	match kind:
		Kind.FALLING_ROCK:
			var distance: float = get_fall_distance()
			var half_width: float = hazard_size.x * 0.5
			# Мигающая колонна шахты: игрок видит, куда упадёт камень.
			draw_rect(
				Rect2(-half_width, 0.0, hazard_size.x, distance),
				Color(warning.r, warning.g, warning.b, alpha * 0.18)
			)
			draw_line(
				Vector2(-half_width, 0.0),
				Vector2(-half_width, distance),
				warning,
				1.0
			)
			draw_line(
				Vector2(half_width, 0.0),
				Vector2(half_width, distance),
				warning,
				1.0
			)
			# Прицел на полу: точка удара.
			draw_line(
				Vector2(-half_width, distance - 1.0),
				Vector2(half_width, distance - 1.0),
				warning,
				2.0
			)
			_draw_rock(Color(body_color.r, body_color.g, body_color.b, alpha))
		Kind.SPIKE_TRAP:
			var floor_y: float = hazard_size.y * 0.5
			draw_rect(
				Rect2(-hazard_size.x * 0.5, floor_y - 2.0, hazard_size.x, 3.0),
				Color(warning.r, warning.g, warning.b, alpha * 0.35)
			)
			# Руна-предупреждение: ромб и перекладина над полом.
			var center := Vector2(0.0, floor_y - 5.0)
			var points := PackedVector2Array([
				center + Vector2(0.0, -4.0),
				center + Vector2(4.0, 0.0),
				center + Vector2(0.0, 4.0),
				center + Vector2(-4.0, 0.0),
			])
			draw_colored_polygon(points, Color(warning.r, warning.g, warning.b, alpha * 0.4))
			var outline := PackedVector2Array([
				points[0], points[1], points[2], points[3], points[0],
			])
			draw_polyline(outline, warning, 1.0)


func _draw_active() -> void:
	match kind:
		Kind.FALLING_ROCK:
			# След падения и сам камень.
			draw_line(
				Vector2(0.0, -hazard_size.y * 3.0),
				Vector2(0.0, 0.0),
				Color(warning_color.r, warning_color.g, warning_color.b, 0.25),
				1.0
			)
			_draw_rock(body_color)
		Kind.SPIKE_TRAP:
			var floor_y: float = hazard_size.y * 0.5
			var teeth: int = maxi(int(hazard_size.x / 6.0), 2)
			var tooth_width: float = hazard_size.x / float(teeth)
			for index: int in teeth:
				var left: float = -hazard_size.x * 0.5 + tooth_width * float(index)
				var points := PackedVector2Array([
					Vector2(left, floor_y),
					Vector2(left + tooth_width * 0.5, floor_y - hazard_size.y),
					Vector2(left + tooth_width, floor_y),
				])
				draw_colored_polygon(points, warning_color)


func _draw_rock(color: Color) -> void:
	var half: Vector2 = hazard_size * 0.5
	draw_rect(Rect2(-half, hazard_size), color)
	draw_rect(
		Rect2(-half.x + 2.0, -half.y + 2.0, hazard_size.x * 0.4, hazard_size.y * 0.4),
		color.lightened(0.25)
	)
