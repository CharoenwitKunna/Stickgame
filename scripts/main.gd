extends Node2D

const Model = preload("res://scripts/battle_model.gd")
const Store = preload("res://scripts/save_store.gd")
const View = preload("res://scripts/battlefield_view.gd")
const Scenery = preload("res://scripts/scenery.gd")
const WorldScenery = preload("res://scripts/world_scenery.gd")
const FIELD := Rect2(0, 0, 1280, 738)
@export var endless_mode := true
var world: Node2D
var revive_screen_pointer := Vector2.ZERO
const FRIEND := Color("7bd4a8")
const ENEMY := Color("ea7c6e")
const GOLD := Color("e8cc88")
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
const CONTROLS_HINT := "WASD / arrows  Move     •     Left-click  March     •     Hold RMB  Raise     •     Space / Esc  Pause"
var _ui_ready := false
var _ui_outcome := ""
var _ui_paused := false
var _tooltip_id := -2
var _tooltip_kind := ""
var _tooltip_specialist := false
var _tooltip_elite := false
var _tooltip_soul := -1
var _tooltip_raising := false
var _tooltip_percent := -1

func _ready() -> void:
	font.load_dynamic_font("res://assets/body.ttf")
	title_font.load_dynamic_font("res://assets/title.ttf")
	var saved: Dictionary = Store.load_army(save_path)
	if not saved.is_empty():
		battle.roster = saved.roster
		battle.stage = saved.stage
	battle.endless = endless_mode
	var world_parent: Node = self
	if endless_mode:
		var field_clip := Control.new()
		field_clip.size = FIELD.size
		field_clip.clip_contents = true
		field_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(field_clip)
		world = Node2D.new()
		field_clip.add_child(world)
		world_parent = world
	scenery = WorldScenery.new() if endless_mode else Scenery.new()
	if endless_mode:
		scenery.wilderness = battle.wilderness
		scenery.battle = battle
	world_parent.add_child(scenery)
	visuals = View.new()
	visuals.battle = battle
	world_parent.add_child(visuals)
	build_ui()
	battle.start_battle()
	update_camera()
	refresh_ui()

func screen_to_world(point: Vector2) -> Vector2:
	return world.to_local(point) if world != null else point

func world_to_screen(point: Vector2) -> Vector2:
	return world.to_global(point) if world != null else point

func inside_field(point: Vector2) -> bool:
	return FIELD.has_point(world_to_screen(point)) if endless_mode else Model.ARENA.has_point(point)

func update_camera(redraw_visuals: bool = true) -> void:
	if world == null:
		return
	world.position = FIELD.size * 0.5 - battle.anchor
	var rectangle := Rect2(-world.position, FIELD.size)
	visuals.visible_world = rectangle.grow(96)
	scenery.update_view(rectangle)
	if redraw_visuals:
		visuals.queue_redraw()
	revive_pointer = screen_to_world(revive_screen_pointer)

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
		update_camera(false) # animate() below already invalidates soldier drawing.
		update_revive(delta, revive_pointer)
		visuals.animate(delta)
		if previous != battle.outcome:
			persist()
	status_time = maxf(0, status_time - delta)
	var mouse_point := screen_to_world(get_global_mouse_position())
	hovered = battle.corpse_at(mouse_point) if inside_field(mouse_point) else -1
	if visuals.hovered != hovered:
		visuals.hovered = hovered
		visuals.queue_redraw()
	refresh_ui()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_WM_MOUSE_EXIT:
		cancel_revive()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		revive_screen_pointer = get_global_transform_with_canvas().affine_inverse() * event.position
		revive_pointer = screen_to_world(revive_screen_pointer)
	if event is InputEventMouseMotion and revive_held:
		update_revive(0, revive_pointer)
	# Releases must reach us even when a UI control consumes the event.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		cancel_revive()

var area_raise_chain := 0

func nearest_affordable_corpse_index(point: Vector2, max_radius: float = 160.0) -> int:
	var best_d2 := max_radius * max_radius
	var best_idx := -1
	for i in range(battle.corpses.size()):
		var corpse: Dictionary = battle.corpses[i]
		var cost: int = Model.STATS[corpse.kind].cost
		if battle.soul >= cost:
			var d2: float = point.distance_squared_to(corpse.pos)
			if d2 < best_d2:
				best_d2 = d2
				best_idx = i
	return best_idx

func cancel_revive() -> void:
	revive_held = false
	rejected_revive_id = -1
	area_raise_chain = 0
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

	var in_combat: bool = battle.is_combat_active()
	var index: int = battle.corpse_at(point) if inside_field(point) else -1
	# Outside of active combat, after raising a corpse, continue area-chaining nearby corpses
	if not in_combat and index < 0 and area_raise_chain > 0 and inside_field(point):
		index = nearest_affordable_corpse_index(point, 180.0)

	if index < 0:
		clear_revive_progress()
		rejected_revive_id = -1
		area_raise_chain = 0
		return

	var corpse: Dictionary = battle.corpses[index]
	var cost: int = Model.STATS[corpse.kind].cost
	if battle.soul < cost:
		if rejected_revive_id != int(corpse.id):
			show_message("Need %d Soul to raise this %s." % [cost, Model.STATS[corpse.kind].name])
		rejected_revive_id = int(corpse.id)
		clear_revive_progress()
		area_raise_chain = 0
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
	var target_time: float = REVIVE_HOLD_TIME if (in_combat or area_raise_chain == 0) else 0.18
	visuals.channel_progress = clampf(revive_elapsed / target_time, 0, 1)

	if revive_elapsed >= target_time:
		var before: int = battle.roster.size()
		var position: Vector2 = corpse.pos
		var kind: String = corpse.kind
		var msg: String = battle.revive_corpse(revive_id)
		show_message(msg)
		clear_revive_progress()
		if battle.roster.size() != before:
			visuals.raise_at(position, kind)
			persist()
			area_raise_chain += 1

		# After combat, continue holding to chain next nearby corpse
		if not in_combat and revive_held:
			var next_idx := nearest_affordable_corpse_index(point, 180.0)
			if next_idx >= 0:
				var next_corpse: Dictionary = battle.corpses[next_idx]
				revive_id = int(next_corpse.id)
				revive_elapsed = 0.0
				visuals.channel_active = true
				visuals.channel_corpse = revive_id
				visuals.channel_point = next_corpse.pos
				visuals.channel_progress = 0.0
			else:
				area_raise_chain = 0

func _unhandled_input(event: InputEvent) -> void:
	if reset_dialog.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE:
			toggle_pause()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and not paused:
		var point := screen_to_world(get_global_transform_with_canvas().affine_inverse() * event.position)
		if not inside_field(point):
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
	if not endless_mode and battle.outcome == "victory":
		battle.stage += 1
	battle.start_battle()
	update_camera()
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
	update_camera()
	visuals.reset_effects()
	paused = false
	pause_button.text = "Pause"
	persist()

func refresh_ui() -> void:
	if not _ui_ready or _ui_outcome != battle.outcome or _ui_paused != paused:
		_ui_ready = true
		_ui_outcome = battle.outcome
		_ui_paused = paused
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
	var show_tooltip: bool = hovered >= 0 and hovered < battle.corpses.size() and not paused and battle.outcome != "defeat"
	if tooltip.visible != show_tooltip:
		tooltip.visible = show_tooltip
	if show_tooltip:
		var corpse: Dictionary = battle.corpses[hovered]
		# Position still follows the camera even when the displayed text is cached.
		var screen_point := world_to_screen(corpse.pos)
		tooltip.position = Vector2(clampf(screen_point.x + 34, 45, 984), clampf(screen_point.y - 82, 12, 652))
		var is_spec: bool = corpse.get("specialist", false)
		var is_elite: bool = corpse.get("elite", false)
		var changed: bool = _tooltip_id != int(corpse.id) or _tooltip_kind != corpse.kind or _tooltip_specialist != is_spec or _tooltip_elite != is_elite
		if changed:
			_tooltip_id = int(corpse.id)
			_tooltip_kind = corpse.kind
			_tooltip_specialist = is_spec
			_tooltip_elite = is_elite
			var prefix: String = "Veteran " if is_spec else ("Elite " if is_elite else "")
			var suffix: String = " ★" if (is_spec or is_elite) else ""
			tooltip_title.text = "Raise %s%s%s" % [prefix, Model.STATS[corpse.kind].name, suffix]
		var raising := revive_id == int(corpse.id)
		var percent: int = roundi(visuals.channel_progress * 100) if raising else -1
		if changed or _tooltip_raising != raising or _tooltip_percent != percent or _tooltip_soul != battle.soul:
			_tooltip_raising = raising
			_tooltip_percent = percent
			_tooltip_soul = battle.soul
			tooltip_help.text = "Raising %d%% · Release to cancel" % percent if raising else "Hold RMB · %d Soul · %d available" % [Model.STATS[corpse.kind].cost, battle.soul]
	if status_time <= 0:
		if hint.text != CONTROLS_HINT:
			hint.text = CONTROLS_HINT
		if hint.modulate != Color.WHITE:
			hint.modulate = Color.WHITE

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), PANEL)
	draw_line(Vector2(0, 738), Vector2(1280, 738), Color("65735b"), 2)
