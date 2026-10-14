extends SceneTree

const Main = preload("res://main.tscn")

class TimedModel extends "res://scripts/battle_model.gd":
	var nearest_us := 0
	var separation_us := 0
	func nearest_enemy(unit: Dictionary, radius: float, target_loads: Dictionary = {}) -> Dictionary:
		var begin := Time.get_ticks_usec()
		var result: Dictionary = super.nearest_enemy(unit, radius, target_loads)
		nearest_us += Time.get_ticks_usec() - begin
		return result
	func separate_units(delta: float) -> void:
		var begin := Time.get_ticks_usec()
		super.separate_units(delta)
		separation_us += Time.get_ticks_usec() - begin

class TimedView extends "res://scripts/battlefield_view.gd":
	var draw_us := 0
	var soldier_us := 0
	var ellipse_us := 0
	var frames := 0
	var attack_us := 0
	var corpse_us := 0
	var animate_us := 0
	func animate(delta: float) -> void:
		var begin := Time.get_ticks_usec()
		super.animate(delta)
		animate_us += Time.get_ticks_usec() - begin
	func draw_attack(effect: Dictionary) -> void:
		var begin := Time.get_ticks_usec()
		super.draw_attack(effect)
		attack_us += Time.get_ticks_usec() - begin
	func draw_corpse(corpse: Dictionary, highlight: bool) -> void:
		var begin := Time.get_ticks_usec()
		super.draw_corpse(corpse, highlight)
		corpse_us += Time.get_ticks_usec() - begin
	func _draw() -> void:
		var begin := Time.get_ticks_usec()
		super._draw()
		draw_us += Time.get_ticks_usec() - begin
		frames += 1
	func draw_soldier(unit: Dictionary) -> void:
		var begin := Time.get_ticks_usec()
		super.draw_soldier(unit)
		soldier_us += Time.get_ticks_usec() - begin
	func ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
		var begin := Time.get_ticks_usec()
		super.ellipse(center, radius, color)
		ellipse_us += Time.get_ticks_usec() - begin

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var model := TimedModel.new()
	model.rng.seed = 731
	for i in range(128):
		var unit: Dictionary = model.spawn_unit(["sword", "archer", "shield"][i % 3], i % 2, Vector2(65 + (i % 20) * 57, 220 + (i / 20) * 34))
		unit.hp = 1000000.0
	var begin := Time.get_ticks_usec()
	for i in range(60):
		model.tick(1.0 / 60, Vector2.RIGHT)
	var total := Time.get_ticks_usec() - begin
	print("PROFILE simulation 128 mixed units: total %.3f, nearest %.3f, separation %.3f ms/tick" % [total / 60000.0, model.nearest_us / 60000.0, model.separation_us / 60000.0])
	var large_model := TimedModel.new()
	large_model.rng.seed = 731
	for i in range(256):
		var unit: Dictionary = large_model.spawn_unit(["sword", "archer", "shield"][i % 3], i % 2, Vector2(65 + (i % 20) * 57, 220 + (i / 20) * 34))
		unit.hp = 1000000.0
	begin = Time.get_ticks_usec()
	for i in range(60):
		large_model.tick(1.0 / 60, Vector2.RIGHT)
	total = Time.get_ticks_usec() - begin
	print("PROFILE simulation 256 mixed units: total %.3f, nearest %.3f, separation %.3f ms/tick" % [total / 60000.0, large_model.nearest_us / 60000.0, large_model.separation_us / 60000.0])
	var game = Main.instantiate()
	game.save_path = "user://profile_unused.json"
	root.add_child(game)
	game.set_physics_process(false)
	game.visuals.free()
	var view := TimedView.new()
	view.battle = model
	game.visuals = view
	game.add_child(view)
	game.move_child(view, game.scenery.get_index() + 1)
	# Profile stable poses: no simulation or saving runs in these render frames.
	model.effects.clear()
	for i in range(20):
		view.animate(1.0 / 60)
		await process_frame
		await RenderingServer.frame_post_draw
	print("PROFILE drawing 128 mixed units: total %.3f, soldiers %.3f, ellipses %.3f ms/frame (inclusive; %d frames)" % [view.draw_us / float(view.frames) / 1000, view.soldier_us / float(view.frames) / 1000, view.ellipse_us / float(view.frames) / 1000, view.frames])
	print("PROFILE engine draw calls: %d; objects: %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_COUNT)])
	view.frames = 0
	view.draw_us = 0
	view.soldier_us = 0
	view.ellipse_us = 0
	view.battle = large_model
	for i in range(20):
		view.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
	print("PROFILE drawing 256 mixed units: total %.3f, soldiers %.3f ms/frame (inclusive; %d frames)" % [view.draw_us / float(view.frames) / 1000, view.soldier_us / float(view.frames) / 1000, view.frames])
	view.battle = model
	view.frames = 0
	view.draw_us = 0
	view.soldier_us = 0
	view.attack_us = 0
	view.corpse_us = 0
	view.animate_us = 0
	model.nearest_us = 0
	model.separation_us = 0
	game.battle = model
	game.set_physics_process(true)
	Engine.max_fps = 60
	for i in range(80):
		await process_frame
		await RenderingServer.frame_post_draw
	print("PROFILE LIVE rendering: total %.3f, soldiers %.3f, attacks %.3f, corpses %.3f, remainder %.3f ms/frame; animate %.3f ms/frame; particles %d effects %d" % [view.draw_us / float(view.frames) / 1000, view.soldier_us / float(view.frames) / 1000, view.attack_us / float(view.frames) / 1000, view.corpse_us / float(view.frames) / 1000, (view.draw_us - view.soldier_us - view.attack_us - view.corpse_us) / float(view.frames) / 1000, view.animate_us / float(view.frames) / 1000, view.active_particle_count(), model.effects.size()])
	game.queue_free()
	await process_frame
	quit()
