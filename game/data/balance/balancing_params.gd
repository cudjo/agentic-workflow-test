class_name BalancingParams
extends Resource
## BalancingParams — единый источник игровых таймингов и параметров движения
## (PLAN §3.1, TASKS T-04). Значения хранятся в `data/balance/balancing.tres`;
## в коде игровых систем числа не дублируются.
##
## Импульс прыжка и гравитация не хранятся отдельно: они выводятся из высоты
## прыжка `H_jump` и времени до апекса `t_apex` по формулам PLAN §3.1:
##   vy0 = 2 * H / t_apex,  g = vy0 / t_apex.

@export_group("Movement")
## Горизонтальная скорость ходьбы, px/s.
@export var v_walk: float = 90.0
## Высота прыжка, px (2 тайла по 16 px).
@export var h_jump: float = 32.0
## Время подъёма до апекса, s.
@export var t_apex: float = 0.35
## Доля H_jump для двойного прыжка (AC-02.1).
@export var h_double_factor: float = 0.8
## Скорость скольжения по стене, px/s (AC-02.3).
@export var v_wall_slide: float = 40.0

@export_group("Dash and roll")
## Длина рывка, px (AC-02.2).
@export var d_dash: float = 48.0
## Длительность рывка, s.
@export var t_dash: float = 0.15
## Кулдаун рывка, s (AC-02.2: <= 1 s).
@export var c_dash: float = 0.6
## Горизонтальная скорость переката, px/s.
@export var v_roll: float = 120.0
## Длительность переката: 6 кадров по 70 мс (DESIGN §7).
@export var t_roll: float = 0.42
## Начало i-frames переката (кадр 2), s.
@export var roll_iframe_start: float = 0.07
## Конец i-frames переката (кадр 5), s.
@export var roll_iframe_end: float = 0.35

@export_group("Combat timings")
## Длительность удара (6 кадров по 60 мс).
@export var t_attack: float = 0.36
## Длительность отшатывания (DESIGN §7), s.
@export var t_hurt: float = 0.12
## Длительность приземления (3 кадра по 50 мс), s.
@export var t_land: float = 0.15
## Окно парирования, s (AC-03.2).
@export var t_parry: float = 0.18
## Задержка экрана смерти, s (AC-05.2).
@export var t_death: float = 1.2

@export_group("Stamina")
## Максимальная выносливость.
@export var stamina_max: float = 100.0
## Стоимость атаки.
@export var e_attack: float = 12.0
## Стоимость блока.
@export var e_block: float = 8.0
## Стоимость переката.
@export var e_roll: float = 10.0


## Начальная вертикальная скорость прыжка (px/s, вверх — отрицательная).
func get_jump_velocity() -> float:
	return 2.0 * h_jump / t_apex


## Ускорение свободного падения (px/s²).
func get_gravity() -> float:
	return get_jump_velocity() / t_apex


## Начальная скорость двойного прыжка для высоты `h_double_factor * H_jump`.
func get_double_jump_velocity() -> float:
	return sqrt(2.0 * get_gravity() * h_jump * h_double_factor)
