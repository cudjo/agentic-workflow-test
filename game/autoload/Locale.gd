class_name LocaleText
extends Node
## Locale — локализация RU/EN поверх TranslationServer (PLAN §2.2/§3.5, T-36).
##
## Источник строк — `res://assets/locale/{ru,en}.csv` (импортируются Godot в
## `.translation` и подключены в `project.godot` → `internationalization/`).
## UI обязан брать весь пользовательский текст через `tr(key)`; ключи —
## стабильные идентификаторы (`ui.menu.continue`, `ui.hud.no_stamina`, ...).
##
## Язык хранится в `Config.language` (T-20) и применяется мгновенно:
##   * `Config.language_changed` → `TranslationServer.set_locale` → сигнал
##     `Locale.language_changed` для экранов с вычисляемым текстом;
##   * узлы, привязанные через `bind()`/`bind_tooltip()`, обновляются
##     автоматически при смене локали (без перезапуска и пересоздания UI).
##
## Данные диалогов/квестов уже содержат RU/EN (`DialogueText`), поэтому в CSV
## они не дублируются; ключи фракций/боссов/оружия/врагов из `display_name_key`
## и ключи зон/способностей (`zone.<id>.name`, `ability.<id>.name`) живут в CSV.

## Локаль переключена (после применения к TranslationServer). Экраны с
## вычисляемыми строками пересобирают текст по этому сигналу.
signal language_changed(language_code: String)

const LANGUAGE_RU: String = "ru"
const LANGUAGE_EN: String = "en"
const SUPPORTED_LANGUAGES: Array[String] = [LANGUAGE_RU, LANGUAGE_EN]
const FALLBACK_LANGUAGE: String = LANGUAGE_RU

const META_KEY: StringName = &"l10n_key"
const META_ARGS: StringName = &"l10n_args"
const META_TOOLTIP_KEY: StringName = &"l10n_tooltip_key"
const META_TOOLTIP_ARGS: StringName = &"l10n_tooltip_args"

var _language: String = FALLBACK_LANGUAGE


func _enter_tree() -> void:
	# Config — autoload раньше Locale: его `_ready` уже прочитал user://settings.cfg.
	_language = normalize_language(Config.language)
	TranslationServer.set_locale(_language)
	if not Config.language_changed.is_connected(_on_config_language_changed):
		Config.language_changed.connect(_on_config_language_changed)


func _ready() -> void:
	# Страховка на случай, если локаль сбросили до `_ready` (тесты/смена сцены).
	if TranslationServer.get_locale() != _language:
		TranslationServer.set_locale(_language)


func _on_config_language_changed(language_code: String) -> void:
	var normalized: String = normalize_language(language_code)
	_language = normalized
	if TranslationServer.get_locale() != normalized:
		TranslationServer.set_locale(normalized)
	language_changed.emit(normalized)
	# Привязанные подписи/подсказки обновляем после текущего кадра, чтобы
	# экран успел применить собственный refresh без гонки.
	call_deferred(&"_refresh_bound_nodes")


# ------------------------------------------------------------------------------
# Публичный API
# ------------------------------------------------------------------------------

## Сменить язык (пишет Config → сохраняется настройками T-20).
func set_language(language_code: String) -> void:
	Config.set_language(language_code)


## Текущий код локали: `ru`/`en`.
func get_language() -> String:
	return _language


func is_english() -> bool:
	return _language == LANGUAGE_EN


static func normalize_language(value: Variant) -> String:
	var text: String = str(value).strip_edges().to_lower()
	if text.begins_with(LANGUAGE_EN):
		return LANGUAGE_EN
	return FALLBACK_LANGUAGE


## Перевод для явно заданного языка (статические форматтеры тестов/сейвов):
## `translate_for("en", "ui.common.ok")`. Не зависит от текущей локали.
static func translate_for(language: String, key: StringName, args: Array = []) -> String:
	var code: String = normalize_language(language)
	var translation: Translation = TranslationServer.get_translation_object(code)
	var text: String = String(key)
	if translation != null:
		var message: StringName = translation.get_message(StringName(key))
		if not String(message).is_empty():
			text = String(message)
	else:
		text = TranslationServer.translate(String(key))
	if args.is_empty():
		return text
	return text % args


## Перевод для текущей локали из статических помощников (без Node.tr()).
static func current(key: StringName, args: Array = []) -> String:
	var text: String = TranslationServer.translate(String(key))
	if args.is_empty():
		return text
	return text % args


## Перевод ключа с откатом на исходный текст, если ключ ещё не заведён.
static func lookup(key: StringName, fallback: String) -> String:
	if String(key).is_empty():
		return fallback
	var text: String = TranslationServer.translate(String(key))
	if text == String(key):
		return fallback
	return text



## Перевод ключа. Для отсутствующего ключа возвращает `fallback` (если задан)
## либо сам ключ — это видно в UI и ловится тестами.
func translate_key(key: StringName, fallback: String = "") -> String:
	var text: String = TranslationServer.translate(String(key))
	if text == String(key) and not fallback.is_empty():
		return fallback
	return text


## Перевод с подстановками: `format("ui.saves.slot", [2])`.
func format_key(key: StringName, args: Array = []) -> String:
	var text: String = translate_key(key)
	if args.is_empty():
		return text
	return text % args


## Есть ли ключ в загруженных переводах (не совпадает с самим ключом).
func has_key(key: StringName) -> bool:
	return TranslationServer.translate(String(key)) != String(key)


## Привязать текст узла к ключу: значение применяется сразу и обновляется при
## смене языка. Подходит для `Label`, `Button`, `CheckButton` и любых узлов с
## свойством `text`.
func bind(node: Object, key: StringName, args: Array = []) -> void:
	if node == null:
		return
	node.set_meta(META_KEY, String(key))
	node.set_meta(META_ARGS, args.duplicate())
	_apply_text(node)


## Привязать `tooltip_text` узла к ключу.
func bind_tooltip(node: Object, key: StringName, args: Array = []) -> void:
	if node == null:
		return
	node.set_meta(META_TOOLTIP_KEY, String(key))
	node.set_meta(META_TOOLTIP_ARGS, args.duplicate())
	_apply_tooltip(node)


## Обновить все привязанные подписи в дереве (после смены языка — автоматически).
func refresh_bindings(root: Node = null) -> void:
	var start: Node = root
	if start == null and is_inside_tree():
		start = get_tree().root
	if start == null:
		return
	_refresh_node(start)


func _refresh_bound_nodes() -> void:
	refresh_bindings()


func _refresh_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.has_meta(META_KEY):
		_apply_text(node)
	if node.has_meta(META_TOOLTIP_KEY):
		_apply_tooltip(node)
	for child: Node in node.get_children():
		_refresh_node(child)


func _apply_text(node: Object) -> void:
	if not is_instance_valid(node):
		return
	var key: String = str(node.get_meta(META_KEY, ""))
	if key.is_empty():
		return
	var args: Array = node.get_meta(META_ARGS, [])
	node.set("text", _formatted(key, args))


func _apply_tooltip(node: Object) -> void:
	if not is_instance_valid(node):
		return
	var key: String = str(node.get_meta(META_TOOLTIP_KEY, ""))
	if key.is_empty():
		return
	var args: Array = node.get_meta(META_TOOLTIP_ARGS, [])
	node.set("tooltip_text", _formatted(key, args))


func _formatted(key: String, args: Array) -> String:
	var text: String = TranslationServer.translate(key)
	if args.is_empty():
		return text
	return text % args
