class_name Zone01Boss
extends BossBase
## Босс зоны 1 «Пепельный Страж» (T-30) — ближний бой.
##
## Паттерны (id из `data/bosses/zone_01_boss.tres`):
##   * `cleave` — размеренный замах с телеграфом;
##   * `lunge`  — рывок вперёд с более широким хитбоксом;
##   * `frenzy` — быстрая серия с длинным рывком и короткой паузой.
##
## Реализация остаётся в ближнем хитбоксе: уникальность фаз задаётся
## данными (скорость, тайминги, размер/смещение хитбокса, рывок), поэтому
## паттерн читаем и не требует отдельных сцен снарядов.

func _perform_attack() -> void:
	var phase: BossPhaseData = data.get_phase(phase_index)
	if phase == null:
		return
	match phase.pattern_id:
		&"cleave", &"lunge", &"frenzy":
			_activate_melee(phase)
		_:
			push_warning(
				"Zone01Boss: unknown pattern '%s' in phase %d" % [
					phase.pattern_id,
					phase_index,
				]
			)
			_activate_melee(phase)
