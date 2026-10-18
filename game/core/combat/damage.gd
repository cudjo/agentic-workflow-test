class_name Damage
extends RefCounted
## Damage — значение попадания и формула урона (T-10, AC-03.1).
##
## Формула (все коэффициенты — из `data/balance/balancing.tres`):
##   amount = max(min_damage, weapon_damage * combo_multiplier * damage_multiplier - defense)
##
## Отбрасывание и вспышка попадания применяются к цели через
## `apply_reaction()`; вспышка никогда не длится дольше 0.1 s (AC-03.1).

## Жёсткий предел вспышки попадания (AC-03.1): 100 мс.
const HIT_FLASH_MAX_SEC: float = 0.1
## Цвет вспышки попадания (белёсая, DESIGN §7 «вспышка спрайта»).
const FLASH_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

var amount: float = 0.0
var knockback: Vector2 = Vector2.ZERO
var hit_flash_duration: float = HIT_FLASH_MAX_SEC
var source: Node = null


## Считает урон по формуле из `balancing.tres` (см. шапку файла).
static func compute(
	balance: BalancingParams,
	weapon_damage: float,
	combo_multiplier: float = 1.0,
	defense: float = 0.0
) -> Damage:
	var result := Damage.new()
	if balance == null:
		return result
	var scaled: float = (
		maxf(weapon_damage, 0.0)
		* maxf(combo_multiplier, 0.0)
		* balance.damage_multiplier
	)
	result.amount = maxf(balance.min_damage, scaled - maxf(defense, 0.0))
	result.hit_flash_duration = clampf(balance.hit_flash_duration, 0.0, HIT_FLASH_MAX_SEC)
	return result


## Явное попадание (тесты/скриптовые эффекты), вспышка также ограничена 0.1 s.
static func create(
	amount_value: float,
	knockback_vector: Vector2 = Vector2.ZERO,
	flash_duration: float = HIT_FLASH_MAX_SEC
) -> Damage:
	var result := Damage.new()
	result.amount = maxf(amount_value, 0.0)
	result.knockback = knockback_vector
	result.hit_flash_duration = clampf(flash_duration, 0.0, HIT_FLASH_MAX_SEC)
	return result


## Копия значения: каждый задетый hurtbox получает собственный payload.
func duplicate_damage() -> Damage:
	var copy := Damage.new()
	copy.amount = amount
	copy.knockback = knockback
	copy.hit_flash_duration = hit_flash_duration
	copy.source = source
	return copy


## Отбрасывание: CharacterBody2D получает импульс к текущей velocity.
func apply_knockback(body: Node) -> void:
	if body is CharacterBody2D and not knockback.is_zero_approx():
		(body as CharacterBody2D).velocity += knockback


## Вспышка попадания на CanvasItem; длительность всегда ≤ 0.1 s (AC-03.1).
## Вызывается без `await` — корутина сама вернёт исходный modulate.
## T-35/DESIGN §9.3: в режиме «Без мигания» вспышка не показывается вовсе.
func flash(visual: CanvasItem) -> void:
	if visual == null or not is_instance_valid(visual) or not visual.is_inside_tree():
		return
	var config := visual.get_node_or_null("/root/Config")
	if config != null and bool(config.get("no_flash")):
		return
	var base_color: Color = visual.modulate
	visual.modulate = FLASH_COLOR
	await visual.get_tree().create_timer(hit_flash_duration).timeout
	if is_instance_valid(visual):
		visual.modulate = base_color


## Полная реакция на попадание: отбрасывание + вспышка.
func apply_reaction(body: Node, visual: CanvasItem) -> void:
	apply_knockback(body)
	flash(visual)
