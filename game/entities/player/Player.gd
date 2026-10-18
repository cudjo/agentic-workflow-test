class_name Player
extends CharacterBody2D
## Player — CharacterBody2D controller with manual gravity, V_walk movement and
## H_jump impulse taken from `data/balance/balancing.tres` (PLAN §3.1, T-04).
##
## Input is never read from raw InputMap here: everything goes through the
## InputManager autoload (actions, 150 ms buffer, 0.1 s coyote time).
## Movement/timings are delegated to PlayerStateMachine (DESIGN §7 priorities).

const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const FALLBACK_WEAPON_PATH: String = "res://data/weapons/one_handed_sword.tres"
## Actions whose presses are kept in InputManager's buffer for 150 ms.
## Block is not buffered: it is a held action, so engine state is enough.
const BUFFERED_ACTIONS: Array[StringName] = [&"jump", &"attack", &"roll", &"dash"]
## States in which stamina regenerates after `stamina_regen_delay` (T-10).
const RESTING_STATES: Array[StringName] = [&"idle", &"run", &"land"]
## Способность «Двойной прыжок» (T-06, AC-02.1).
const ABILITY_DOUBLE_JUMP_ID: StringName = AbilityDoubleJump.ID
## Сколько воздушных прыжков доступно до приземления (AC-02.1).
const MAX_DOUBLE_JUMPS: int = AbilityDoubleJump.AIR_JUMPS
## Способность «Рывок» (T-07, AC-02.2).
const ABILITY_DASH_ID: StringName = AbilityDash.ID
## Способность «Карабканье по стенам» (T-08, AC-02.3).
const ABILITY_WALL_CLIMB_ID: StringName = AbilityWallClimb.ID

## Movement/timing data (single source of truth).
@export var balance: BalancingParams
## EC-03: за этой границей по Y игрок считается упавшим в пропасть и получает
## полный урон. `INF` — проверка выключена (зоны без пропастей/T-17 задаёт
## limit из границ зоны).
@export var fall_death_y: float = INF

## FSM node. Untyped on purpose: Player -> PlayerStateMachine -> states -> Player
## would otherwise form a cyclic class reference.
var state_machine
## Melee combo state for the current weapon (T-10).
var combo: ComboTracker
var attack_hitbox: Hitbox
var facing: int = 1
var is_dead: bool = false

## Runtime-флаги способностей (T-06): ключ — id способности, значение true.
## Ставятся `AbilityBase.activate()` при получении (GameState.abilities —
## источник истины) и снимаются `deactivate()`.
var ability_flags: Dictionary = {}
## Потрачено воздушных прыжков с момента последнего приземления (AC-02.1).
var double_jumps_used: int = 0
## Остаток кулдауна рывка, с (C_dash из balancing.tres; T-07, AC-02.2).
var dash_cooldown_left: float = 0.0
## Направление wall kick: сторона, противоположная стене (T-08, AC-02.3).
## Заполняется `try_wall_kick()` и сбрасывается при входе в `wall_kick`.
var wall_kick_dir: int = 0

var _hitbox_step: int = -1
var _combo_weapon_id: StringName = &""

@onready var visual: Sprite2D = $Visual
## Визуальный слой. Untyped on purpose: Player <-> PlayerAnimation иначе
## образуют циклическую ссылку классов.
@onready var animation: Node = get_node_or_null("Animation")


func _ready() -> void:
	if balance == null:
		balance = load(BALANCE_PATH) as BalancingParams
	if balance == null:
		push_error("Player: balancing resource is missing at %s" % BALANCE_PATH)
	attack_hitbox = get_node_or_null("Hitbox") as Hitbox
	_configure_combo()
	var hurtbox: Hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox != null and not hurtbox.damaged.is_connected(_on_hurtbox_damaged):
		hurtbox.damaged.connect(_on_hurtbox_damaged)
	state_machine = get_node_or_null("StateMachine")
	if state_machine == null:
		push_error("Player: StateMachine child node is missing")
		return
	state_machine.setup(self)
	_bind_abilities()
	if not EventBus.ability_acquired.is_connected(_on_ability_acquired):
		EventBus.ability_acquired.connect(_on_ability_acquired)


func _physics_process(delta: float) -> void:
	if balance == null or state_machine == null:
		return

	_update_dash_cooldown(delta)
	_capture_input_buffers()
	_update_facing()

	state_machine.physics_update(delta)

	var gravity: float = balance.get_gravity()
	if state_machine.uses_gravity():
		velocity.y += gravity * delta * 0.5

	move_and_slide()

	if state_machine.uses_gravity():
		velocity.y += gravity * delta * 0.5
	if is_on_floor() and velocity.y > 0.0:
		velocity.y = 0.0

	_check_fall_death()
	GameState.update_stamina(delta, is_resting())


# ------------------------------------------------------------------------------
# Input helpers (all through InputManager)
# ------------------------------------------------------------------------------

func get_move_axis() -> float:
	var axis: float = 0.0
	if InputManager.is_pressed(&"move_left"):
		axis -= 1.0
	if InputManager.is_pressed(&"move_right"):
		axis += 1.0
	return axis


func has_move_input() -> bool:
	return not is_zero_approx(get_move_axis())


func is_block_held() -> bool:
	return InputManager.is_pressed(&"block")


## Ground jump (or coyote jump while the 0.1 s window is open).
func try_ground_jump() -> bool:
	if not state_machine.can_request(&"jump"):
		return false
	if not (is_on_floor() or InputManager.is_coyote_time_available(&"jump")):
		return false
	if not InputManager.just_pressed(&"jump"):
		return false
	InputManager.consume_coyote_time(&"jump")
	return state_machine.request_state(&"jump")


## Jump pressed inside the coyote window while falling off an edge.
func try_coyote_jump() -> bool:
	if is_on_floor():
		return false
	if not InputManager.is_coyote_time_available(&"jump"):
		return false
	if not InputManager.just_pressed(&"jump"):
		return false
	InputManager.consume_coyote_time(&"jump")
	return state_machine.force_state(&"jump")


## Roll is a core move: ground-only, costs E_roll stamina (AC-03.3 groundwork).
func try_roll() -> bool:
	if not is_on_floor():
		return false
	if not state_machine.can_request(&"roll"):
		return false
	if not InputManager.just_pressed(&"roll"):
		return false
	if not GameState.try_spend_stamina(balance.e_roll):
		return false
	return state_machine.request_state(&"roll")


## Рывок (T-07, AC-02.2): только со способностью, вне кулдауна C_dash и при
## достаточной выносливости. Вызывается из наземных (idle/run/land) и
## воздушных (jump/fall/double_jump) состояний. Проверки способности/кулдауна
## идут до `just_pressed()`, поэтому нажатие в кулдауне остаётся в 150-мс
## буфере, а не «съедается».
func try_dash() -> bool:
	if not has_ability(ABILITY_DASH_ID):
		return false
	if not is_dash_ready():
		return false
	if not state_machine.can_request(&"dash"):
		return false
	if not InputManager.just_pressed(&"dash"):
		return false
	if not GameState.try_spend_stamina(balance.e_dash):
		return false
	return state_machine.request_state(&"dash")


## Melee attack: costs E_attack; starts the weapon's combo (T-10, AC-03.3).
## At zero stamina the attack is refused and the HUD "no stamina" flag is up.
func try_attack() -> bool:
	if not state_machine.can_request(&"attack"):
		return false
	if not InputManager.just_pressed(&"attack"):
		return false
	if not GameState.try_spend_stamina(balance.e_attack):
		return false
	if combo == null or get_weapon() == null or get_weapon().id != _combo_weapon_id:
		_configure_combo()
	if combo == null:
		return false
	combo.start()
	return state_machine.request_state(&"attack")


## Chains the next combo hit when the link window is open; costs E_attack.
func try_link_attack() -> bool:
	if combo == null or not combo.can_link():
		return false
	if not GameState.try_spend_stamina(balance.e_attack):
		return false
	return combo.try_link()


## Advances the active combo by one physics tick; true when the swing ended.
func advance_combo(delta: float) -> bool:
	if combo == null:
		return true
	return combo.advance(delta)


func try_block() -> bool:
	if not state_machine.can_request(&"block"):
		return false
	if not is_block_held():
		return false
	if not GameState.try_spend_stamina(balance.e_block):
		return false
	return state_machine.request_state(&"block")


func begin_coyote_time() -> void:
	InputManager.start_coyote_time(&"jump")


# ------------------------------------------------------------------------------
# Abilities (T-06, PLAN §3.3)
# ------------------------------------------------------------------------------

## Ставит/снимает runtime-флаг способности. Вызывается AbilityBase.activate()
## при получении способности; ключ — id способности (`double_jump`).
func set_ability_flag(flag: StringName, value: bool = true) -> void:
	if flag == &"":
		return
	if value:
		ability_flags[flag] = true
	else:
		ability_flags.erase(flag)


func has_ability_flag(flag: StringName) -> bool:
	return bool(ability_flags.get(flag, false))


## Способность получена в этом забеге; GameState — источник истины.
func has_ability(ability_id: StringName) -> bool:
	return GameState.has_ability(ability_id)


## Второй прыжок доступен: способность разблокирована, игрок в воздухе и
## воздушный прыжок ещё не потрачен (AC-02.1).
func can_double_jump() -> bool:
	if is_on_floor():
		return false
	if double_jumps_used >= MAX_DOUBLE_JUMPS:
		return false
	return has_ability_flag(ABILITY_DOUBLE_JUMP_ID)


## Второй прыжок по нажатию jump: ровно один раз до приземления (AC-02.1).
## Переход внутри воздушного тира (Jump/Fall = 50), поэтому force_state.
func try_double_jump() -> bool:
	if not can_double_jump():
		return false
	if not InputManager.just_pressed(&"jump"):
		return false
	if not state_machine.force_state(&"double_jump"):
		return false
	double_jumps_used += 1
	return true


## Сброс счётчика воздушных прыжков (AC-02.1: доступен только после
## приземления). Вызывается из `states/land.gd` и `reset_player()`.
func on_landed() -> void:
	double_jumps_used = 0


## Проигрывает анимацию/вспышку двойного прыжка (API T-05).
func play_double_jump_animation() -> void:
	if animation != null and animation.has_method(&"play_double_jump"):
		animation.call(&"play_double_jump")


# ------------------------------------------------------------------------------
# Wall climb (T-08, SPEC US-02, AC-02.3)
# ------------------------------------------------------------------------------

## Направление от игрока к стене: 1 — справа, -1 — слева, 0 — стены нет.
## Опирается на `is_on_wall()`/`get_wall_normal()` последнего `move_and_slide`.
func get_wall_dir() -> int:
	if not is_on_wall():
		return 0
	return AbilityWallClimb.wall_dir_from_normal(get_wall_normal())


## Удержание на стене возможно: способность получена, игрок в воздухе,
## касается вертикальной стены и удерживает направление в её сторону.
func can_wall_slide() -> bool:
	if not has_ability(ABILITY_WALL_CLIMB_ID):
		return false
	if is_on_floor():
		return false
	var wall_dir: int = get_wall_dir()
	if wall_dir == 0:
		return false
	return AbilityWallClimb.is_holding_into_wall(get_move_axis(), wall_dir)


## Вход в wall slide из `fall` (AC-02.3). Без способности всегда false.
func try_wall_slide() -> bool:
	if not can_wall_slide():
		return false
	return state_machine.force_state(&"wall_slide")


## Прыжок от стены: горизонтальный импульс в противоположную сторону
## (`V_wall_kick`) + обычный вертикальный импульс прыжка. Вызывается из
## `states/wall_slide.gd`; без способности или вне стены — false.
func try_wall_kick() -> bool:
	if not has_ability(ABILITY_WALL_CLIMB_ID):
		return false
	var wall_dir: int = get_wall_dir()
	if wall_dir == 0:
		return false
	if not InputManager.just_pressed(&"jump"):
		return false
	wall_kick_dir = -wall_dir
	if not state_machine.force_state(&"wall_kick"):
		wall_kick_dir = 0
		return false
	return true


func _bind_abilities() -> void:
	for ability_id: StringName in GameState.get_abilities():
		_activate_ability(ability_id)


func _activate_ability(ability_id: StringName) -> bool:
	var ability: AbilityBase = AbilityRegistry.get_ability(ability_id)
	if ability == null:
		push_warning("Player: unknown ability '%s' in GameState" % ability_id)
		return false
	return ability.activate(self)


func _on_ability_acquired(ability_id: StringName) -> void:
	_activate_ability(ability_id)


# ------------------------------------------------------------------------------
# Dash cooldown (T-07, AC-02.2)
# ------------------------------------------------------------------------------

## Кулдаун C_dash истёк (доступность способности проверяет `try_dash()`).
func is_dash_ready() -> bool:
	return dash_cooldown_left <= 0.0


## Остаток кулдауна рывка в секундах (0 — готов).
func get_dash_cooldown_left() -> float:
	return dash_cooldown_left


## Запускает кулдаун C_dash при входе в рывок (`states/dash.gd`).
## HUD T-19 получает `EventBus.ability_cooldown_changed(id, remaining,
## duration)` и рисует полосу; по remaining = 0 полоса гаснет.
func begin_dash_cooldown() -> void:
	dash_cooldown_left = _dash_cooldown_duration()
	EventBus.ability_cooldown_changed.emit(
		ABILITY_DASH_ID,
		dash_cooldown_left,
		dash_cooldown_left
	)


## Снимает кулдаун (возрождение у костра/новая игра): рывок снова готов.
func reset_dash_cooldown() -> void:
	if dash_cooldown_left <= 0.0:
		return
	dash_cooldown_left = 0.0
	EventBus.ability_cooldown_changed.emit(
		ABILITY_DASH_ID,
		0.0,
		_dash_cooldown_duration()
	)


## C_dash из balancing.tres, зажатый пределом AC-02.2 (≤ 1 с).
func _dash_cooldown_duration() -> float:
	if balance == null:
		return 0.0
	return clampf(balance.c_dash, 0.0, AbilityDash.MAX_COOLDOWN_SEC)


## Тикает кулдаун по physics-кадрам и зеркалит остаток в EventBus для HUD.
func _update_dash_cooldown(delta: float) -> void:
	if dash_cooldown_left <= 0.0:
		return
	dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	EventBus.ability_cooldown_changed.emit(
		ABILITY_DASH_ID,
		dash_cooldown_left,
		_dash_cooldown_duration()
	)


# ------------------------------------------------------------------------------
# Damage / death API (T-10/T-26 extend; T-04 needs the FSM transitions)
# ------------------------------------------------------------------------------

## Enter Hurt. Death outranks Hurt, so it cannot interrupt it.
func apply_hurt() -> void:
	if is_dead:
		return
	state_machine.request_state(&"hurt")


## Наносит урон игроку (T-26): HP живёт в GameState, смерть при HP <= 0.
## `ignore_iframes` — только для падения в пропасть (EC-03: полный урон,
## рывок/перекат не спасают). Возвращает оставшееся HP.
func apply_damage(amount: float, ignore_iframes: bool = false) -> float:
	if is_dead or amount <= 0.0:
		return GameState.hp
	if not ignore_iframes and is_invulnerable():
		return GameState.hp

	var remaining: float = GameState.damage_hp(amount)
	if remaining <= 0.0:
		kill()
	else:
		apply_hurt()
	return remaining


## EC-03: падение в пропасть наносит полный урон (100% max HP) и убивает
## даже в i-frames рывка.
func apply_fall_damage() -> void:
	apply_damage(GameState.hp_max, true)


## Граница смерти от падения (T-17/тесты). `INF` отключает проверку.
func set_fall_limit_y(value: float) -> void:
	fall_death_y = value


## Входящий урон врага (T-12) уменьшает HP и переводит в Hurt (T-26).
## Блок/парирование (T-11) могут отменить урон до этого вызова.
func _on_hurtbox_damaged(damage: Damage) -> void:
	if damage != null:
		apply_damage(damage.amount)


## Terminal death: interrupts any action immediately (EC-01).
## Бюджет `t_death`, corpse-метку и возрождение обрабатывает DeathHandler.
func kill() -> void:
	if is_dead:
		return
	is_dead = true
	GameState.set_hp(0.0)
	stop_attack_hitbox()
	state_machine.force_state(&"death")


## Restores the controller to a clean idle state (respawn/tests).
func reset_player() -> void:
	is_dead = false
	velocity = Vector2.ZERO
	wall_kick_dir = 0
	on_landed()
	reset_dash_cooldown()
	stop_attack_hitbox()
	InputManager.consume_coyote_time(&"jump")
	state_machine.force_state(&"idle")


## EC-03: проверка выхода за границу мира/пропасти (раз в physics-tick).
func _check_fall_death() -> void:
	if is_dead or not is_finite(fall_death_y):
		return
	if global_position.y > fall_death_y:
		apply_fall_damage()


# ------------------------------------------------------------------------------
# Queries
# ------------------------------------------------------------------------------

## Weapon data for the current run (GameState is the source of truth).
func get_weapon() -> WeaponData:
	if GameState.weapon != null:
		return GameState.weapon
	return load(FALLBACK_WEAPON_PATH) as WeaponData


## Stamina regenerates only in locomotion states (T-10).
func is_resting() -> bool:
	return RESTING_STATES.has(get_state_name())


## Mirrors the combo hit window onto the Hitbox child (AC-03.1).
## Hitbox is enabled for the active phase of the current combo step only.
func sync_attack_hitbox() -> void:
	if attack_hitbox == null or combo == null:
		return
	var hit_active: bool = (
		combo.is_active()
		and combo.is_hit_active(balance.combo_hit_start_ratio, balance.combo_hit_end_ratio)
	)
	if not hit_active:
		attack_hitbox.deactivate()
		return
	if combo.step_index != _hitbox_step:
		_hitbox_step = combo.step_index
		attack_hitbox.clear_hits()
	var weapon_data: WeaponData = get_weapon()
	var weapon_damage: float = weapon_data.damage if weapon_data != null else 0.0
	var step_multiplier: float = (
		weapon_data.get_step_multiplier(combo.step_index) if weapon_data != null else 1.0
	)
	var payload: Damage = Damage.compute(balance, weapon_damage, step_multiplier)
	var knockback_force: float = (
		weapon_data.knockback * balance.knockback_scale if weapon_data != null else 0.0
	)
	attack_hitbox.activate(payload, knockback_force, Vector2(float(facing), 0.0))


func stop_attack_hitbox() -> void:
	_hitbox_step = -1
	if attack_hitbox != null:
		attack_hitbox.deactivate()


func _configure_combo() -> void:
	var weapon_data: WeaponData = get_weapon()
	if weapon_data == null or balance == null:
		combo = ComboTracker.new()
		return
	combo = ComboTracker.new()
	combo.setup(
		weapon_data.get_combo_length(),
		balance.t_attack * weapon_data.attack_speed,
		balance.combo_link_window
	)
	_combo_weapon_id = weapon_data.id


func get_state_name() -> StringName:
	if state_machine == null:
		return &""
	return state_machine.current_state_name


## True while the current state (Roll frames 2–5, Dash) grants i-frames.
func is_invulnerable() -> bool:
	if state_machine == null or state_machine.current_state == null:
		return false
	return state_machine.current_state.is_invulnerable()


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _capture_input_buffers() -> void:
	for action: StringName in BUFFERED_ACTIONS:
		InputManager.capture_buffer(action)


func _update_facing() -> void:
	var axis: float = get_move_axis()
	if not is_zero_approx(axis):
		facing = 1 if axis > 0.0 else -1
	if visual != null:
		visual.flip_h = facing < 0
