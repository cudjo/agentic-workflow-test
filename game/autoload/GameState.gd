extends Node
## GameState — состояние забега: HP, выносливость, инвентарь, способности,
## текущее оружие, репутация, прогресс (PLAN §2.2).
##
## T-04 добавил выносливость; T-10 вынес её логику в `core/combat/stamina.gd`
## (трата/восстановление/флаг «НЕТ СИЛ», AC-03.3) и добавил текущее оружие
## как ссылку на данные `data/weapons/*.tres`.
## Уведомления — через EventBus (`stamina_changed`); флаг «НЕТ СИЛ» HUD читает
## через `is_stamina_exhausted()` (AC-03.3), не заводя отдельного сигнала.
##
## T-06 добавил набор полученных способностей `abilities` (PLAN §3.3):
## типизированный список id — источник истины для FSM игрока, ability gates
## (T-09), HUD (T-19) и сейвов (T-25).
##
## T-26 добавил HP, инвентарь, флаг боя и состояние смерти/corpse run:
##   * `hp`/`hp_max` — здоровье из `balancing.tres` (`max_hp`), смерть при HP = 0;
##   * `inventory`/`currency` — что теряется в corpse-метке (AC-05.2/05.3);
##   * `death_active` — смерть в бюджете `t_death` (персист для EC-04);
##   * `corpse_active`/`corpse_*` — единственная активная метка гибели;
##   * `respawn_bonfire`/`respawn_zone_id`/`respawn_position` — чекпоинт костра;
##   * `in_combat` — запрет сохранения в бою (EC-06);
##   * `active_slot` — слот последнего сохранения/загрузки, цель death-автосейва
##     для EC-04 (ставится SaveManager'ом).
## Смерть и corpse run обрабатывает `core/death/death_handler.gd`.
##
## T-29 добавил прогрессию (US-08):
##   * `stats` — характеристики (сила/ловкость/выносливость/здоровье);
##   * `learning_points` — очки обучения у учителей (AC-08.1);
##   * `level`/`xp` — уровень и накопленный опыт (опыт за врагов/квесты);
##   * `progression_data`/`progression_rules` — таблицы из
##     `data/balance/progression.tres` и чистая логика шагов/требований.
## Сейв пишет их как `state.stats`, `state.learning_points`, `state.level`,
## `state.xp` (schema v5). Требования экипировки для T-21 проверяются
## `get_equipment_info(item_id)`.

const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const PROGRESSION_PATH: String = "res://data/balance/progression.tres"
const DEFAULT_WEAPON_PATH: String = "res://data/weapons/one_handed_sword.tres"

var balance: BalancingParams
var weapon: WeaponData
var stamina_state: Stamina

## Таблицы прогрессии и чистая логика шагов/уровней (T-29).
var progression_data: ProgressionData
var progression_rules: ProgressionRules

## Характеристики забега: stat_id → int (T-29, AC-08.1).
var stats: Dictionary = {}
## Очки обучения (тратятся у учителей, AC-08.1).
var learning_points: int = 0
## Уровень и накопленный опыт (опыт за врагов/квесты).
var level: int = 1
var xp: int = 0

## Полученные способности (id из AbilityRegistry), в порядке получения.
## Типизированный набор; дубликаты невозможны (см. `add_ability`).
var abilities: Array[StringName] = []

## Побеждённые боссы (id, T-30). Источник истины для «босс остаётся мёртвым»
## (EC-09) и персистентности через SaveManager.
var bosses_defeated: Array[StringName] = []
## Отложенные награды: boss_id -> {zone_id, reward_id, gold}. Награда ждёт
## следующего входа в зону, если игрок погиб до её получения (EC-09).
var boss_rewards_pending: Dictionary = {}
## Валюта игрока; награды боссов добавляются сюда.
var currency: int = 0

## Текущее здоровье игрока (T-26). Смерть наступает при HP <= 0.
var hp: float = 0.0

## Инвентарь забега: id предметов (T-26/T-21). При смерти содержимое
## переносится в corpse-метку и очищается (AC-05.2).
var inventory: Array[StringName] = []

## Смерть обрабатывается (бюджет `t_death` идёт либо сейв загружен в момент
## смерти). Персистится для EC-04: выход в бюджете = обычная смерть.
var death_active: bool = false

## Активная corpse-метка: что и где лежит после смерти (AC-05.3, EC-05).
var corpse_active: bool = false
var corpse_zone_id: StringName = &""
var corpse_position: Vector2 = Vector2.ZERO
var corpse_items: Array[StringName] = []
var corpse_currency: int = 0
## Игрок умер повторно до подбора: старая метка потеряна навсегда (EC-05).
var corpse_lost: bool = false

## Последний активированный костёр — точка возрождения (T-26, AC-05.2).
## `respawn_bonfire` — id вида `zone_id/bonfire_id` (или только bonfire_id).
var respawn_bonfire: StringName = &""
var respawn_zone_id: StringName = &""
var respawn_position: Vector2 = Vector2.ZERO

## Слот последнего успешного сохранения/загрузки (ставит SaveManager).
## 0 — слот не выбран; death-автосейв тогда не пишется.
var active_slot: int = 0

## Флаг боя (EC-06): сохранение у костра запрещено, пока true.
## Складывается из ручного флага (арены/боссы) и источников-агрессоров
## (обычные враги): у каждого врага свой ключ, поэтому смерть одного из
## нескольких не снимает бой преждевременно (Fix-4b/B-03).
var in_combat: bool = false
## Ручной флаг боя — его держат арены/боссы, пока идёт бой.
var _in_combat_pinned: bool = false
## Instance id -> true: обычные враги, которые сейчас агро/в бою.
var _combat_sources: Dictionary = {}

## Зона, в которой находится игрок (обновляется по `EventBus.zone_entered`).
var current_zone_id: StringName = &""

## Репутация фракций (T-27): id -> int. Шкала и пороги — в `data/factions/`;
## менеджер (`FactionManager`) читает и меняет значения только здесь.
var factions: Dictionary = {}
## Выбранная фракция (T-27). `&""` — выбор не сделан, концовка нейтральная.
var chosen_faction: StringName = &""

## Текущий максимум HP (из balancing.tres + бонус характеристики «здоровье»).
var hp_max: float:
	get:
		var base: float = balance.max_hp if balance != null else 0.0
		return base + _health_bonus()

## Текущий максимум выносливости (база + бонус характеристики «выносливость»).
var stamina_max: float:
	get:
		return stamina_state.maximum if stamina_state != null else 0.0

## Алиас для HUD T-19/T-21: «очки обучения» = learning_points.
## Каноническое имя поля и сейва — `learning_points`.
var training_points: int:
	get:
		return learning_points
	set(value):
		set_learning_points(value)

## Текущая выносливость; setter нужен загрузке сейва/T-04-тестам.
var stamina: float:
	get:
		return stamina_state.current if stamina_state != null else 0.0
	set(value):
		if stamina_state != null:
			stamina_state.set_current(value)


func _ready() -> void:
	balance = load(BALANCE_PATH) as BalancingParams
	if balance == null:
		push_error("GameState: balancing resource is missing at %s" % BALANCE_PATH)
	_load_progression()
	if balance != null:
		stamina_state = Stamina.new()
		stamina_state.changed.connect(_on_stamina_changed)
		stamina_state.setup(
			_stamina_max_for_stats(),
			balance.stamina_regen_delay,
			balance.stamina_regen_rate
		)
	weapon = load(DEFAULT_WEAPON_PATH) as WeaponData
	hp = hp_max
	if not EventBus.zone_entered.is_connected(_on_zone_entered):
		EventBus.zone_entered.connect(_on_zone_entered)
	if not EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.connect(_on_enemy_died)


# ------------------------------------------------------------------------------
# Health (T-26)
# ------------------------------------------------------------------------------

## Полное HP (начало забега, возрождение у костра — AC-05.2).
func reset_hp() -> void:
	set_hp(hp_max)


## Устанавливает HP с ограничением [0, hp_max] и уведомляет HUD.
func set_hp(value: float) -> void:
	var clamped: float = clampf(value, 0.0, maxf(hp_max, 0.0))
	if is_equal_approx(hp, clamped):
		return
	hp = clamped
	EventBus.player_health_changed.emit(hp, hp_max)


## Наносит урон; возвращает оставшееся HP. Смерть запускает Player/DeathHandler.
func damage_hp(amount: float) -> float:
	if amount <= 0.0:
		return hp
	set_hp(hp - amount)
	return hp


func heal_hp(amount: float) -> void:
	if amount > 0.0:
		set_hp(hp + amount)


## Восстанавливает HP из сейва без clamp по «будущему» максимуму:
## значение уже прошло миграцию/валидацию (T-26, v3).
func restore_hp(value: float) -> void:
	var maximum: float = maxf(hp_max, 0.0)
	hp = clampf(value, 0.0, maximum)
	EventBus.player_health_changed.emit(hp, hp_max)


func is_alive() -> bool:
	return hp > 0.0 and not death_active


# ------------------------------------------------------------------------------
# Inventory (T-26/T-21)
# ------------------------------------------------------------------------------

## Добавляет предмет в инвентарь. Дубликаты допустимы (стаки/копии).
func add_item(item_id: StringName) -> bool:
	if item_id == &"":
		push_warning("GameState.add_item: empty item id")
		return false
	inventory.append(item_id)
	return true


## Копия инвентаря для UI/сейвов: мутация результата не меняет забег.
func get_inventory() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(inventory)
	return copy


func clear_inventory() -> void:
	inventory.clear()


## Восстанавливает инвентарь из сейва (без сигналов).
func restore_inventory(values: Array) -> void:
	inventory.clear()
	for value: Variant in values:
		var item_id: StringName = StringName(str(value))
		if item_id != &"":
			inventory.append(item_id)


# ------------------------------------------------------------------------------
# Death / corpse run (T-26)
# ------------------------------------------------------------------------------

## Кладёт инвентарь и валюту в corpse-метку на месте гибели (AC-05.2).
## Повторная смерть до подбора помечает предыдущую метку потерянной навсегда
## (EC-05): её содержимое очищается и восстановить его нельзя.
## Возвращает снимок: `{previous_lost, previous, corpse}`.
func drop_corpse(zone_id: StringName, position: Vector2) -> Dictionary:
	var previous_lost: bool = false
	var previous: Dictionary = {}
	if corpse_active and not corpse_lost:
		previous = get_corpse_info()
		var had_loot: bool = not corpse_items.is_empty() or corpse_currency > 0
		corpse_items.clear()
		corpse_currency = 0
		corpse_lost = true
		if had_loot:
			previous_lost = true
			EventBus.corpse_lost.emit(corpse_zone_id, corpse_position)

	corpse_active = true
	corpse_zone_id = zone_id
	corpse_position = position
	corpse_items.clear()
	corpse_items.assign(inventory)
	corpse_currency = currency
	corpse_lost = false
	inventory.clear()
	currency = 0

	var corpse_info: Dictionary = get_corpse_info()
	EventBus.corpse_dropped.emit(
		corpse_zone_id,
		corpse_position,
		corpse_info["items"],
		corpse_currency
	)
	return {
		"previous_lost": previous_lost,
		"previous": previous,
		"corpse": corpse_info,
	}


## Подбирает corpse-метку: возвращает предметы/валюту игроку и очищает метку.
## Потерянная метка (EC-05) ничего не возвращает.
## Возвращает `{collected, items, currency}` (items — Array[String]).
func collect_corpse() -> Dictionary:
	var result: Dictionary = {
		"collected": false,
		"items": [],
		"currency": 0,
	}
	if not corpse_active or corpse_lost:
		return result

	var returned_items: Array[String] = []
	for item_id: StringName in corpse_items:
		inventory.append(item_id)
		returned_items.append(String(item_id))
	var returned_currency: int = corpse_currency
	currency += returned_currency
	result["collected"] = true
	result["items"] = returned_items
	result["currency"] = returned_currency
	clear_corpse()
	EventBus.corpse_collected.emit(returned_items, returned_currency)
	return result


## Состояние метки для UI (экран смерти T-22, карта T-33). `items` — строки,
## `preview` — первые 5 предметов (DESIGN §6.5).
func get_corpse_info() -> Dictionary:
	var items: Array[String] = []
	for item_id: StringName in corpse_items:
		items.append(String(item_id))
	var preview: Array[String] = []
	for index: int in mini(items.size(), 5):
		preview.append(items[index])
	return {
		"active": corpse_active,
		"zone_id": String(corpse_zone_id),
		"position": corpse_position,
		"items": items,
		"items_count": items.size(),
		"preview": preview,
		"currency": corpse_currency,
		"lost": corpse_lost,
	}


func has_corpse() -> bool:
	return corpse_active


func is_corpse_lost() -> bool:
	return corpse_active and corpse_lost


## Очищает метку (подбор, новая игра, тесты). Предметы не возвращаются.
func clear_corpse() -> void:
	corpse_active = false
	corpse_zone_id = &""
	corpse_position = Vector2.ZERO
	corpse_items.clear()
	corpse_currency = 0
	corpse_lost = false


## Восстанавливает состояние смерти/corpse из сейва (T-26, v3).
func restore_death_state(
	death_pending: bool,
	corpse_present: bool,
	zone_id: StringName,
	position: Vector2,
	items: Array,
	currency_amount: int,
	lost: bool
) -> void:
	death_active = death_pending
	corpse_active = corpse_present
	corpse_zone_id = zone_id
	corpse_position = position
	corpse_items.clear()
	for value: Variant in items:
		var item_id: StringName = StringName(str(value))
		if item_id != &"":
			corpse_items.append(item_id)
	corpse_currency = maxi(currency_amount, 0)
	corpse_lost = lost


## Полный сброс смерти/HP для новой игры и тестов. Чекпоинт костра сохраняется,
## если `clear_checkpoint` = false.
func reset_death_state(clear_checkpoint: bool = false) -> void:
	death_active = false
	clear_corpse()
	hp = maxf(hp_max, 0.0)
	if clear_checkpoint:
		respawn_bonfire = &""
		respawn_zone_id = &""
		respawn_position = Vector2.ZERO


# ------------------------------------------------------------------------------
# Respawn checkpoint / combat flag (T-26)
# ------------------------------------------------------------------------------

## Костёр становится точкой возрождения (AC-05.2). `position` — уже с offset
## спавна игрока (Bonfire.respawn_offset).
func set_respawn_bonfire(
	zone_id: StringName,
	bonfire_id: StringName,
	position: Vector2
) -> void:
	respawn_zone_id = zone_id
	if bonfire_id == &"":
		respawn_bonfire = zone_id
	elif zone_id == &"":
		respawn_bonfire = bonfire_id
	else:
		respawn_bonfire = StringName("%s/%s" % [zone_id, bonfire_id])
	respawn_position = position
	EventBus.checkpoint_activated.emit(zone_id, bonfire_id)


func has_checkpoint() -> bool:
	return respawn_bonfire != &""


## Восстанавливает чекпоинт из сейва без побочных сигналов.
func restore_respawn_bonfire(
	bonfire_key: StringName,
	zone_id: StringName,
	position: Vector2
) -> void:
	respawn_bonfire = bonfire_key
	respawn_zone_id = zone_id
	respawn_position = position


## Ручной флаг боя (арены/боссы). `false` — явное окончание боя: снимает
## и ручной флаг, и источники-врагов (победа над боссом/выход из зоны/смерть),
## чтобы призванные или ещё живые враги не держали запрет сохранения.
func set_in_combat(value: bool) -> void:
	_in_combat_pinned = value
	if not value:
		_combat_sources.clear()
	_refresh_in_combat()


## Регистрирует/снимает источник боя обычного врага (агро/бой).
## Refcount по принципу «любой активный агрессор»: флаг остаётся включённым,
## пока активен хотя бы один источник или арена (B-03).
func set_combat_source(source: Object, active: bool) -> void:
	if source == null:
		return
	var key: int = source.get_instance_id()
	if active:
		_combat_sources[key] = true
	else:
		_combat_sources.erase(key)
	_refresh_in_combat()


## Активен ли источник боя (для тестов/диагностики состояния).
func is_combat_source_active(source: Object) -> bool:
	return source != null and _combat_sources.has(source.get_instance_id())


## Полный сброс боя: смерть игрока/новая игра. Снимает и ручной флаг арены,
## и все источники-врагов (B-03: после смерти на арене сохранение доступно).
func reset_combat_state() -> void:
	_in_combat_pinned = false
	_combat_sources.clear()
	_refresh_in_combat()


func _refresh_in_combat() -> void:
	# Освобождённый источник не должен «залипать» в реестре.
	for key: int in _combat_sources.keys():
		if instance_from_id(key) == null:
			_combat_sources.erase(key)
	var value: bool = _in_combat_pinned or not _combat_sources.is_empty()
	if in_combat == value:
		return
	in_combat = value
	EventBus.combat_state_changed.emit(in_combat)


## Сохранение разрешено только вне боя (Q3, EC-06).
func can_save() -> bool:
	return not in_combat


func set_active_slot(slot: int) -> void:
	active_slot = slot


func _on_zone_entered(zone_id: StringName, _display_name: String) -> void:
	current_zone_id = zone_id


## Опыт за побеждённого врага (T-29): таблица `enemy_xp` из данных.
## `EventBus.enemy_died` эмитится только окончательной смертью (T-12).
func _on_enemy_died(enemy_id: StringName, _at_position: Vector2) -> void:
	if progression_data == null:
		return
	var amount: int = progression_data.get_enemy_xp(enemy_id)
	if amount > 0:
		add_xp(amount)


## Spend `amount` stamina. Returns false (and spends nothing) when it is not enough.
func try_spend_stamina(amount: float) -> bool:
	if stamina_state == null:
		return false
	return stamina_state.spend(amount)


## Restore stamina, clamped to the maximum.
func restore_stamina(amount: float) -> void:
	if stamina_state != null:
		stamina_state.restore(amount)


## Restore full stamina (respawn / start of a run / tests).
func reset_stamina() -> void:
	if stamina_state != null:
		stamina_state.reset()


## Per-physics-tick regeneration; `resting` = no attack/block/roll/dash now.
func update_stamina(delta: float, resting: bool) -> void:
	if stamina_state != null:
		stamina_state.update(delta, resting)


## HUD flag: stamina is empty, attacks are refused (AC-03.3).
func is_stamina_exhausted() -> bool:
	return stamina_state != null and stamina_state.is_exhausted()


# ------------------------------------------------------------------------------
# Factions (T-27)
# ------------------------------------------------------------------------------

## Репутация фракции; 0 — нейтрально/неизвестно (шкала задаётся данными).
func get_faction_reputation(faction_id: StringName) -> int:
	if faction_id == &"":
		return 0
	var value: Variant = factions.get(faction_id)
	if value is int:
		return value
	if value is float:
		return int(value)
	return 0


## Копия всех репутаций (id -> int) для UI/сейва.
func get_all_faction_reputation() -> Dictionary:
	var copy: Dictionary = {}
	for key: Variant in factions.keys():
		var faction_id: StringName = StringName(str(key))
		if faction_id == &"":
			continue
		copy[faction_id] = get_faction_reputation(faction_id)
	return copy


## Записывает репутацию без сигналов: сигналы эмитит FactionManager (T-27).
func set_faction_reputation(faction_id: StringName, value: int) -> void:
	if faction_id == &"":
		return
	factions[faction_id] = value


## Восстанавливает репутации/выбор из сейва (schema v4). Пустые id и
## нечисловые значения пропускаются — старые/ручные сейвы не ломают загрузку.
func restore_factions(values: Dictionary, chosen: StringName) -> void:
	factions.clear()
	for key: Variant in values.keys():
		var faction_id: StringName = StringName(str(key))
		if faction_id == &"":
			continue
		var value: Variant = values[key]
		if value is int or value is float:
			factions[faction_id] = int(value)
	chosen_faction = chosen


## Сброс фракционного состояния (новая игра/тесты).
func reset_factions() -> void:
	factions.clear()
	chosen_faction = &""


# ------------------------------------------------------------------------------
# Abilities (T-06)
# ------------------------------------------------------------------------------

## Получена ли способность в этом забеге (AC-02.1, AC-04.3).
func has_ability(ability_id: StringName) -> bool:
	return abilities.has(ability_id)


## Добавляет способность один раз; true — только при первом получении.
## Эмитит `EventBus.ability_acquired`, чтобы живые системы (FSM игрока,
## ability gates, HUD) разблокировали поведение сразу.
func add_ability(ability_id: StringName) -> bool:
	if ability_id == &"":
		push_warning("GameState.add_ability: empty ability id")
		return false
	if abilities.has(ability_id):
		return false
	abilities.append(ability_id)
	EventBus.ability_acquired.emit(ability_id)
	return true


## Копия набора для UI/gates/сейвов: мутация результата не меняет забег.
func get_abilities() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(abilities)
	return copy


## Очищает набор (новая игра, загрузка сейва перед повторной выдачей).
## Флаги на живом игроке снимаются через `AbilityBase.deactivate()`.
func clear_abilities() -> void:
	abilities.clear()


## Восстанавливает способности из сейва (T-26, schema v3). Идёт через
## `add_ability`, поэтому живой Player получает `ability_acquired` и
## разблокирует поведение; повторная загрузка идемпотентна.
func restore_abilities(values: Array) -> void:
	clear_abilities()
	for value: Variant in values:
		var ability_id: StringName = StringName(str(value))
		if ability_id != &"":
			add_ability(ability_id)


# ------------------------------------------------------------------------------
# Progression: stats, learning points, experience (T-29, US-08)
# ------------------------------------------------------------------------------

func get_stat(stat_id: StringName) -> int:
	var value: Variant = stats.get(stat_id)
	if value is int:
		return value
	if value is float:
		return int(value)
	return 0


## Копия характеристик (stat_id → int) для UI/сейва.
func get_stats() -> Dictionary:
	var copy: Dictionary = {}
	for key: Variant in stats.keys():
		copy[StringName(str(key))] = get_stat(StringName(str(key)))
	return copy


func get_stat_name(stat_id: StringName) -> String:
	if progression_rules != null:
		return progression_rules.get_stat_name(stat_id)
	return String(stat_id)


func get_stat_ids() -> Array[StringName]:
	if progression_rules != null:
		return progression_rules.get_stat_ids()
	var result: Array[StringName] = []
	return result


## Цена следующего повышения; -1 — максимум/неизвестная характеристика.
## `value_override` позволяет спросить цену шага после повышения (UI).
func get_training_cost(stat_id: StringName, value_override: int = -1) -> int:
	if progression_rules == null:
		return -1
	var current: int = get_stat(stat_id) if value_override < 0 else value_override
	return progression_rules.get_step_cost(stat_id, current)


func can_train_stat(stat_id: StringName) -> bool:
	var cost: int = get_training_cost(stat_id)
	return cost > 0 and learning_points >= cost


## Тратит очки обучения и повышает характеристику на 1 (AC-08.1).
## Возвращает `{ok, reason, stat_id, value, cost_paid, next_cost,
## learning_points}`; при отказе состояние не меняется.
func train_stat(stat_id: StringName) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"reason": "",
		"stat_id": stat_id,
		"value": get_stat(stat_id),
		"cost_paid": 0,
		"next_cost": -1,
		"learning_points": learning_points,
	}
	if progression_rules == null:
		result["reason"] = "no_data"
		return result
	if not progression_rules.has_stat(stat_id):
		result["reason"] = "unknown_stat"
		return result

	var current: int = get_stat(stat_id)
	var cost: int = progression_rules.get_step_cost(stat_id, current)
	if cost < 0:
		result["reason"] = "max"
		result["next_cost"] = -1
		return result
	if learning_points < cost:
		result["reason"] = "not_enough_points"
		result["cost_paid"] = 0
		result["next_cost"] = cost
		return result

	learning_points -= cost
	stats[stat_id] = current + 1
	_apply_stat_gain(stat_id, 1)

	var next_cost: int = progression_rules.get_step_cost(stat_id, current + 1)
	EventBus.stat_changed.emit(stat_id, current + 1, next_cost)
	EventBus.learning_points_changed.emit(learning_points)

	result["ok"] = true
	result["value"] = current + 1
	result["cost_paid"] = cost
	result["next_cost"] = next_cost
	result["learning_points"] = learning_points
	return result


func set_learning_points(value: int) -> void:
	var clamped: int = maxi(value, 0)
	if clamped == learning_points:
		return
	learning_points = clamped
	EventBus.learning_points_changed.emit(learning_points)


func add_learning_points(amount: int) -> int:
	if amount > 0:
		set_learning_points(learning_points + amount)
	return learning_points


## Списывает очки (навыки учителя). false — недостаточно, ничего не списано.
func spend_learning_points(amount: int) -> bool:
	if amount < 0 or learning_points < amount:
		return false
	if amount > 0:
		set_learning_points(learning_points - amount)
	return true


## Начисляет опыт (враги/квесты) и повышает уровень по таблице.
## Возвращает `{ok, xp, level, levels_gained, points_awarded,
## xp_to_next, max_level}`.
func add_xp(amount: int) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"xp": xp,
		"level": level,
		"levels_gained": 0,
		"points_awarded": 0,
		"xp_to_next": get_xp_to_next_level(),
		"max_level": progression_rules.get_max_level() if progression_rules != null else 1,
	}
	if amount <= 0 or progression_rules == null:
		return result

	xp = maxi(xp + amount, 0)
	var previous_level: int = level
	var new_level: int = progression_rules.get_level_for_xp(xp)
	if new_level > level:
		level = new_level
		var awarded: int = progression_rules.get_learning_points_awarded(
			previous_level,
			new_level
		)
		learning_points += awarded
		result["levels_gained"] = new_level - previous_level
		result["points_awarded"] = awarded
		EventBus.level_changed.emit(level, awarded)
		EventBus.learning_points_changed.emit(learning_points)

	result["ok"] = true
	result["xp"] = xp
	result["level"] = level
	result["xp_to_next"] = get_xp_to_next_level()
	EventBus.xp_changed.emit(xp, result["xp_to_next"])
	return result


## Опыт за квест по таблице `quest_xp` (T-28 вызывает после завершения).
## Неизвестный квест ничего не начисляет: `{ok:false, reason:"unknown_quest"}`.
func award_quest_xp(quest_id: StringName) -> Dictionary:
	if progression_data == null:
		return {
			"ok": false,
			"reason": "no_data",
			"xp": xp,
			"level": level,
			"levels_gained": 0,
			"points_awarded": 0,
			"xp_to_next": get_xp_to_next_level(),
			"amount": 0,
		}
	var amount: int = progression_data.get_quest_xp(quest_id)
	if amount <= 0:
		return {
			"ok": false,
			"reason": "unknown_quest",
			"xp": xp,
			"level": level,
			"levels_gained": 0,
			"points_awarded": 0,
			"xp_to_next": get_xp_to_next_level(),
			"amount": 0,
		}
	var result: Dictionary = add_xp(amount)
	result["amount"] = amount
	result["quest_id"] = quest_id
	return result


## Сколько XP осталось до следующего уровня (0 — максимум).
func get_xp_to_next_level() -> int:
	if progression_rules == null:
		return 0
	return progression_rules.get_xp_to_next_level(level, xp)


## Проверка предусловий навыка/требований экипировки (AC-08.2, T-21):
## `{requirements, met, missing, reason}`.
func check_requirements(requirements: Dictionary) -> Dictionary:
	if progression_rules == null:
		return EquipmentRequirements.describe(requirements, stats)
	return progression_rules.check_requirements(requirements, stats)


## Требования предмета из данных (пусто — требований нет).
func get_equipment_requirements(item_id: StringName) -> Dictionary:
	if progression_rules == null:
		return {}
	return progression_rules.get_equipment_requirements(item_id)


## Состояние экипировки для слота инвентаря T-21:
## `{item_id, requirements, met, missing, reason}`. При невыполненных
## требованиях `met = false`, а `reason` содержит требуемое значение.
func get_equipment_info(item_id: StringName) -> Dictionary:
	if progression_rules == null:
		return {
			"item_id": item_id,
			"requirements": {},
			"met": true,
			"missing": [],
			"reason": "",
		}
	return progression_rules.get_equipment_info(item_id, stats)


func meets_equipment_requirements(item_id: StringName) -> bool:
	return bool(get_equipment_info(item_id).get("met", true))


## Восстанавливает прогрессию из сейва (schema v5). Значения валидируются
## таблицами: неизвестные id отбрасываются, характеристики зажимаются в
## [start, max], LP/XP неотрицательны, уровень — в [1, max_level].
## Эмитит change-сигналы, чтобы живой UI (T-19/T-21) обновился после загрузки.
func restore_progression(
	stats_data: Dictionary,
	learning_points_value: int,
	level_value: int,
	xp_value: int
) -> void:
	if progression_rules == null:
		return
	stats = progression_rules.normalize_stats(stats_data)
	learning_points = maxi(learning_points_value, 0)
	xp = maxi(xp_value, 0)
	var safe_level: int = level_value
	if safe_level <= 0:
		safe_level = progression_rules.get_level_for_xp(xp)
	level = progression_rules.clamp_level(safe_level)

	if stamina_state != null:
		stamina_state.set_maximum(_stamina_max_for_stats(), false)
	hp = minf(hp, hp_max)

	for stat_id: StringName in progression_rules.get_stat_ids():
		EventBus.stat_changed.emit(stat_id, get_stat(stat_id), get_training_cost(stat_id))
	EventBus.learning_points_changed.emit(learning_points)
	EventBus.level_changed.emit(level, 0)
	EventBus.xp_changed.emit(xp, get_xp_to_next_level())


## Сброс прогрессии для новой игры/тестов. Сигналы эмитятся для UI.
func reset_progression() -> void:
	if progression_rules == null:
		stats = {}
		learning_points = 0
		level = 1
		xp = 0
		return
	stats = progression_rules.get_start_stats()
	learning_points = 0
	level = 1
	xp = 0
	if stamina_state != null:
		stamina_state.set_maximum(_stamina_max_for_stats(), false)
	hp = minf(hp, hp_max)
	for stat_id: StringName in progression_rules.get_stat_ids():
		EventBus.stat_changed.emit(stat_id, get_stat(stat_id), get_training_cost(stat_id))
	EventBus.learning_points_changed.emit(learning_points)
	EventBus.level_changed.emit(level, 0)
	EventBus.xp_changed.emit(xp, get_xp_to_next_level())


# ------------------------------------------------------------------------------
# Boss progress and rewards (T-30, EC-09)
# ------------------------------------------------------------------------------

## Побеждён ли босс в этом забеге/сохранении (EC-09).
func is_boss_defeated(boss_id: StringName) -> bool:
	return bosses_defeated.has(boss_id)


## Фиксирует победу один раз. Возвращает true только при первом вызове.
func mark_boss_defeated(boss_id: StringName) -> bool:
	if boss_id == &"" or bosses_defeated.has(boss_id):
		return false
	bosses_defeated.append(boss_id)
	return true


func get_bosses_defeated() -> Array[StringName]:
	var copy: Array[StringName] = []
	copy.assign(bosses_defeated)
	return copy


## Ставит награду в очередь. Идемпотентно: повторная запись того же босса
## не дублирует награду (важно при повторном входе в зону, EC-09).
func queue_boss_reward(
	boss_id: StringName,
	zone_id: StringName,
	reward_id: StringName,
	gold: int
) -> void:
	if boss_id == &"" or boss_rewards_pending.has(boss_id):
		return
	boss_rewards_pending[boss_id] = {
		"zone_id": String(zone_id),
		"reward_id": String(reward_id),
		"gold": maxi(gold, 0),
	}


## Выдаёт отложенную награду: добавляет золото и эмитит
## `EventBus.boss_reward_granted`. Возвращает false, если награды нет.
func claim_boss_reward(boss_id: StringName) -> bool:
	if not boss_rewards_pending.has(boss_id):
		return false
	var entry: Variant = boss_rewards_pending[boss_id]
	boss_rewards_pending.erase(boss_id)
	var data: Dictionary = entry if entry is Dictionary else {}
	var gold: int = maxi(int(data.get("gold", 0)), 0)
	var reward_id: StringName = StringName(str(data.get("reward_id", "")))
	currency += gold
	EventBus.boss_reward_granted.emit(boss_id, reward_id, gold)
	return true


## Выдаёт все награды, ожидающие указанной зоны (вход в зону, EC-09).
## Возвращает число выданных наград.
func claim_pending_boss_rewards(zone_id: StringName) -> int:
	var pending_ids: Array[StringName] = []
	for key: Variant in boss_rewards_pending.keys():
		var entry: Variant = boss_rewards_pending[key]
		var data: Dictionary = entry if entry is Dictionary else {}
		if StringName(str(data.get("zone_id", ""))) == zone_id:
			pending_ids.append(StringName(str(key)))
	var claimed: int = 0
	for boss_id: StringName in pending_ids:
		if claim_boss_reward(boss_id):
			claimed += 1
	return claimed


## Копия очереди наград (тесты/сейв): мутация результата не меняет забег.
func get_pending_boss_rewards() -> Dictionary:
	return boss_rewards_pending.duplicate(true)


## Очищает прогресс боссов (новая игра/тесты).
func reset_boss_progress() -> void:
	bosses_defeated.clear()
	boss_rewards_pending.clear()
	currency = 0


## Восстанавливает прогресс из сейва без побочных сигналов (T-25/T-30).
func restore_boss_progress(
	defeated: Array,
	pending: Dictionary,
	currency_value: int
) -> void:
	bosses_defeated.clear()
	for value: Variant in defeated:
		var boss_id: StringName = StringName(str(value))
		if boss_id != &"" and not bosses_defeated.has(boss_id):
			bosses_defeated.append(boss_id)

	boss_rewards_pending.clear()
	for key: Variant in pending.keys():
		var entry: Variant = pending[key]
		if not entry is Dictionary:
			continue
		boss_rewards_pending[StringName(str(key))] = (entry as Dictionary).duplicate(true)

	currency = maxi(currency_value, 0)


func set_weapon(new_weapon: WeaponData) -> void:
	weapon = new_weapon


func _load_progression() -> void:
	progression_data = load(PROGRESSION_PATH) as ProgressionData
	if progression_data == null:
		push_error("GameState: progression resource is missing at %s" % PROGRESSION_PATH)
		return
	if not progression_data.is_valid():
		push_error("GameState: invalid progression data at %s" % PROGRESSION_PATH)
		return
	progression_rules = ProgressionRules.new(progression_data)
	stats = progression_rules.get_start_stats()
	learning_points = 0
	level = 1
	xp = 0


## Бонус максимального HP от характеристики «здоровье» (T-29).
func _health_bonus() -> float:
	if progression_data == null:
		return 0.0
	var gained: int = get_stat(&"health") - progression_data.get_start_value(&"health")
	return float(maxi(gained, 0)) * progression_data.health_per_point


## Максимум выносливости с бонусом характеристики «выносливость».
func _stamina_max_for_stats() -> float:
	var base: float = balance.stamina_max if balance != null else 0.0
	if progression_data == null:
		return base
	var gained: int = get_stat(&"endurance") - progression_data.get_start_value(&"endurance")
	return base + float(maxi(gained, 0)) * progression_data.stamina_per_point


## Применяет производные эффекты повышения характеристики.
func _apply_stat_gain(stat_id: StringName, delta: int) -> void:
	if progression_data == null or delta <= 0:
		return
	if stat_id == &"health":
		set_hp(hp + float(delta) * progression_data.health_per_point)
	elif stat_id == &"endurance" and stamina_state != null:
		stamina_state.set_maximum(
			stamina_state.maximum + float(delta) * progression_data.stamina_per_point,
			true
		)


func _on_stamina_changed(current: float, maximum: float) -> void:
	EventBus.stamina_changed.emit(current, maximum)
