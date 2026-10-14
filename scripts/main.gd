extends Node2D

const Model = preload("res://scripts/battle_model.gd")
const Store = preload("res://scripts/save_store.gd")
const View = preload("res://scripts/battlefield_view.gd")
const Scenery = preload("res://scripts/scenery.gd")
const FRIEND := Color("8bd7b0")
const ENEMY := Color("e58375")
const GOLD := Color("e3c989")
const INK := Color("f1ecd9")
const MUTED := Color("b8c8b7")
const PANEL := Color("172622")
const REVIVE_HOLD_TIME := 0.7

var battle = Model.new()
var save_path: String = Store.SAVE_PATH
var paused := false
var status_time := 0.0
var hovered := -1
var revive_held := false
var revive_pointer := Vector2.ZERO
var revive_id := -1
var revive_elapsed := 0.0
var rejected_revive_id := -1
var hint: Label
var banner: Label
var result_help: Label
var result_panel: Panel
var action: Button
var pause_button: Button
var reset_dialog: ConfirmationDialog
var tooltip: Panel
var tooltip_title: Label
var tooltip_help: Label
var visuals
var scenery
var font := FontFile.new()
var title_font := FontFile.new()

func _ready() -> void:
	font.load_dynamic_font("res://assets/body.ttf")
	title_font.load_dynamic_font("res://assets/title.ttf")
	var saved: Dictionary = Store.load_army(save_path)
	if not saved.is_empty():
		battle.roster = saved.roster
		battle.stage = saved.stage
	scenery = Scenery.new()
	add_child(scenery)
	visuals = View.new()
	visuals.battle = battle
	add_child(visuals)
	build_ui()
	battle.start_battle()
	refresh_ui()

func style_box(fill: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

func make_label(text: String, at: Vector2, size_value: int, tint: Color = INK, display: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", title_font if display else font)
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func make_panel(rectangle: Rect2) -> Panel:
	var panel := Panel.new()
	panel.position = rectangle.position
	panel.size = rectangle.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := style_box(PANEL, Color("4d6350"))
	style.shadow_color = Color(0.02, 0.04, 0.03, 0.3)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 5)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel

func make_button(text: String, rectangle: Rect2, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rectangle.position
	button.size = rectangle.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 16)
	var fill: Color = GOLD if primary else Color("263d31")
	var tint: Color = PANEL if primary else INK
	button.add_theme_color_override("font_color", tint)
	button.add_theme_color_override("font_hover_color", tint)
	button.add_theme_color_override("font_pressed_color", tint)
	button.add_theme_stylebox_override("normal", style_box(fill, fill.lightened(0.15)))
	button.add_theme_stylebox_override("hover", style_box(fill.lightened(0.12), GOLD if primary else FRIEND))
	button.add_theme_stylebox_override("pressed", style_box(fill.darkened(0.12), fill))
	button.add_theme_stylebox_override("disabled", style_box(PANEL, Color("364c3e")))
	button.add_theme_color_override("font_disabled_color", MUTED.darkened(0.25))
	var focus := style_box(Color.TRANSPARENT, INK)
	focus.set_border_width_all(2)
	focus.expand_margin_left = 3
	focus.expand_margin_top = 3
	focus.expand_margin_right = 3
	focus.expand_margin_bottom = 3
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(callback)
	add_child(button)
	return button

func build_ui() -> void:
	pause_button = make_button("Pause", Rect2(984, 744, 110, 40), toggle_pause)
	hint = make_label("", Vector2(36, 749), 15, MUTED)
	hint.size = Vector2(924, 26)
	hint.clip_text = true
	make_button("New game", Rect2(1107, 744, 131, 40), request_reset)
	result_panel = make_panel(Rect2(59, 22, 700, 88))
	banner = make_label("", Vector2(81, 35), 25, INK, true)
	result_help = make_label("", Vector2(82, 73), 14, MUTED)
	action = make_button("Next battle", Rect2(1032, 29, 184, 46), continue_battle, true)
	action.visible = false
	tooltip = make_panel(Rect2(0, 0, 240, 67))
	tooltip.z_index = 10
	tooltip_title = Label.new()
	tooltip_title.position = Vector2(14, 10)
	tooltip_title.add_theme_font_override("font", font)
	tooltip_title.add_theme_font_size_override("font_size", 17)
	tooltip_title.add_theme_color_override("font_color", INK)
	tooltip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(tooltip_title)
	tooltip_help = Label.new()
	tooltip_help.position = Vector2(14, 37)
	tooltip_help.add_theme_font_override("font", font)
	tooltip_help.add_theme_font_size_override("font_size", 12)
	tooltip_help.add_theme_color_override("font_color", GOLD)
	tooltip_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(tooltip_help)
	tooltip.visible = false
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.title = "Start a new army?"
	reset_dialog.dialog_text = "This replaces your saved army and campaign progress."
	reset_dialog.confirmed.connect(reset_game)
	var dialog_theme := Theme.new()
	dialog_theme.default_font = font
	dialog_theme.default_font_size = 16
	reset_dialog.theme = dialog_theme
	add_child(reset_dialog)

func movement_input() -> Vector2:
	var x := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var y := float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	return Vector2(x, y).limit_length()

func _physics_process(delta: float) -> void:
	if not paused and not reset_dialog.visible:
		var previous: String = battle.outcome
		battle.tick(delta, movement_input())
		update_revive(delta, revive_pointer)
		visuals.animate(delta)
		if previous != battle.outcome:
			persist()
	status_time = maxf(0, status_time - delta)
	hovered = battle.corpse_at(get_global_mouse_position())
	if visuals.hovered != hovered:
		visuals.hovered = hovered
		visuals.queue_redraw()
	refresh_ui()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_WM_MOUSE_EXIT:
		cancel_revive()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		revive_pointer = get_global_transform_with_canvas().affine_inverse() * event.position
	if event is InputEventMouseMotion and revive_held:
		update_revive(0, revive_pointer)
	# Releases must reach us even when a UI control consumes the event.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		cancel_revive()

func cancel_revive() -> void:
	revive_held = false
	rejected_revive_id = -1
	clear_revive_progress()

func clear_revive_progress() -> void:
	revive_id = -1
	revive_elapsed = 0.0
	if is_instance_valid(visuals):
		visuals.channel_active = false
		visuals.channel_corpse = -1
		visuals.channel_progress = 0.0
		visuals.queue_redraw()

func update_revive(delta: float, point: Vector2) -> void:
	if not revive_held:
		return
	if paused or reset_dialog.visible or battle.outcome == "defeat":
		cancel_revive()
		return
	var index: int = battle.corpse_at(point) if Model.ARENA.has_point(point) else -1
	if index < 0:
		clear_revive_progress()
		rejected_revive_id = -1
		return
	var corpse: Dictionary = battle.corpses[index]
	var cost: int = Model.STATS[corpse.kind].cost
	if battle.soul < cost:
		if rejected_revive_id != int(corpse.id):
			show_message("Need %d Soul to raise this %s." % [cost, Model.STATS[corpse.kind].name])
		rejected_revive_id = int(corpse.id)
		clear_revive_progress()
		return
	rejected_revive_id = -1
	if revive_id != int(corpse.id):
		clear_revive_progress()
		revive_id = int(corpse.id)
		# A new target starts at zero; never inherit another corpse's hold time.
	else:
		revive_elapsed += delta
	visuals.channel_active = true
	visuals.channel_corpse = revive_id
	visuals.channel_point = corpse.pos
	visuals.channel_progress = clampf(revive_elapsed / REVIVE_HOLD_TIME, 0, 1)
	if revive_elapsed >= REVIVE_HOLD_TIME:
		var before: int = battle.roster.size()
		var position: Vector2 = corpse.pos
		var kind: String = corpse.kind
		show_message(battle.revive_corpse(revive_id))
		clear_revive_progress()
		if battle.roster.size() != before:
			visuals.raise_at(position, kind)
			persist()

func _unhandled_input(event: InputEvent) -> void:
	if reset_dialog.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE:
			toggle_pause()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and not paused:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not Model.ARENA.has_point(point):
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			revive_held = true
			update_revive(0.0, point)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and battle.outcome.is_empty():
			battle.move_target = battle.clamp_point(point)
			battle.has_target = true

func show_message(message: String) -> void:
	hint.text = message
	hint.modulate = INK
	status_time = 4.0

func persist() -> void:
	if not Store.save_army(battle.roster, battle.stage, save_path):
		show_message("Save failed. Progress is still in memory; check disk permissions.")

func toggle_pause() -> void:
	cancel_revive()
	paused = not paused
	pause_button.text = "Resume" if paused else "Pause"

func continue_battle() -> void:
	cancel_revive()
	if battle.outcome == "victory":
		battle.stage += 1
	battle.start_battle()
	visuals.reset_effects()
	paused = false
	pause_button.text = "Pause"
	persist()

func request_reset() -> void:
	cancel_revive()
	reset_dialog.popup_centered(Vector2i(430, 160))

func reset_game() -> void:
	cancel_revive()
	battle.roster.assign(["sword", "sword", "sword", "shield"])
	battle.stage = 1
	battle.start_battle()
	visuals.reset_effects()
	paused = false
	pause_button.text = "Pause"
	persist()

func refresh_ui() -> void:
	action.visible = not battle.outcome.is_empty()
	result_panel.visible = paused or not battle.outcome.is_empty()
	banner.visible = result_panel.visible
	result_help.visible = result_panel.visible
	if battle.outcome == "victory":
		banner.text = "The field is yours."
		banner.modulate = FRIEND
		result_help.text = "VICTORY · Raise remaining corpses before the next battle."
		action.text = "Next battle"
	elif battle.outcome == "defeat":
		banner.text = "Live to fight again."
		banner.modulate = ENEMY
		result_help.text = "DEFEAT · Your army recovers. Every recruit is kept."
		action.text = "Retry battle"
	elif paused:
		banner.text = "Battle paused"
		banner.modulate = INK
		result_help.text = "Press Space or Resume to return to the field."
	else:
		banner.text = ""
		result_help.text = ""
	tooltip.visible = hovered >= 0 and not paused and battle.outcome != "defeat"
	if tooltip.visible:
		var corpse: Dictionary = battle.corpses[hovered]
		var stats: Dictionary = Model.STATS[corpse.kind]
		tooltip.position = Vector2(clampf(corpse.pos.x + 34, 45, 984), clampf(corpse.pos.y - 82, 118, 652))
		tooltip_title.text = "Raise %s" % stats.name
		if revive_id == int(corpse.id):
			tooltip_help.text = "Raising %d%% · Release to cancel" % roundi(visuals.channel_progress * 100)
		else:
			tooltip_help.text = "Hold RMB · %d Soul · %d available" % [stats.cost, battle.soul]
	if status_time <= 0:
		hint.text = "WASD / arrows  Move     •     Left-click  March     •     Hold RMB  Raise     •     Space / Esc  Pause"
		hint.modulate = Color.WHITE

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), PANEL)
	draw_line(Vector2(0, 738), Vector2(1280, 738), Color("65735b"), 2)
