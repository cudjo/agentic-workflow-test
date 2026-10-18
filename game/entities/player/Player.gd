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

## Movement/timing data (single source of truth).
@export var balance: BalancingParams

## FSM node. Untyped on purpose: Player -> PlayerStateMachine -> states -> Player
## would otherwise form a cyclic class reference.
var state_machine
## Melee combo state for the current weapon (T-10).
var combo: ComboTracker
var attack_hitbox: Hitbox
var facing: int = 1
var is_dead: bool = false

var _hitbox_step: int = -1
var _combo_weapon_id: StringName = &""

@onready var visual: Sprite2D = $Visual


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


func _physics_process(delta: float) -> void:
	if balance == null or state_machine == null:
		return

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


func try_dash() -> bool:
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
# Damage / death API (T-10/T-26 extend; T-04 needs the FSM transitions)
# ------------------------------------------------------------------------------

## Enter Hurt. Death outranks Hurt, so it cannot interrupt it.
func apply_hurt() -> void:
	if is_dead:
		return
	state_machine.request_state(&"hurt")


## Входящий урон врага переводит игрока в Hurt (T-12): отбрасывание из
## `Hurtbox` больше не «уносит» игрока в idle без реакции. HP/блок — T-26/T-11.
func _on_hurtbox_damaged(_damage: Damage) -> void:
	if state_machine != null:
		apply_hurt()


## Terminal death: interrupts any action immediately (EC-01).
func kill() -> void:
	if is_dead:
		return
	is_dead = true
	state_machine.force_state(&"death")


## Restores the controller to a clean idle state (respawn/tests).
func reset_player() -> void:
	is_dead = false
	velocity = Vector2.ZERO
	InputManager.consume_coyote_time(&"jump")
	state_machine.force_state(&"idle")


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
