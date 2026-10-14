extends SceneTree

# Diagnostic only. Never reads/writes the player's army or changes game rules.
# Method instrumentation adds overhead; timings are CPU, not isolated FPS/GPU time.
const Model = preload("res://scripts/battle_model.gd")
const Main = preload("res://scripts/main.gd")
const View = preload("res://scripts/battlefield_view.gd")
const Store = preload("res://scripts/save_store.gd")

class CountedModel extends "res://scripts/battle_model.gd":
	var queries := 0
	var redundant_empty_queries := 0
	var nearest_us := 0
	var separation_us := 0
	var candidate_us := 0
	var pairs := 0
	var collisions := 0
	var dense_queries := 0
	func nearest_enemy(unit: Dictionary, radius: float, loads: Dictionary = {}) -> Dictionary:
		queries += 1
		var begin := Time.get_ticks_usec()
		var result: Dictionary = super.nearest_enemy(unit, radius, loads)
		nearest_us += Time.get_ticks_usec() - begin
		return result
	func nearest_available_enemy(unit: Dictionary, radius: float, loads: Dictionary) -> Dictionary:
		var before := queries
		var result: Dictionary = super.nearest_available_enemy(unit, radius, loads)
		if queries - before == 2 and result.is_empty():
			redundant_empty_queries += 1
		return result
	func separate_units(delta: float) -> void:
		var begin := Time.get_ticks_usec()
		super.separate_units(delta)
		separation_us += Time.get_ticks_usec() - begin
	func separation_candidates(point: Vector2, first: int, radius: float = MAX_SEPARATION_DISTANCE) -> Array[int]:
		var begin := Time.get_ticks_usec()
		var result: Array[int] = super.separation_candidates(point, first, radius)
		candidate_us += Time.get_ticks_usec() - begin
		if result.size() > 12:
			dense_queries += 1
		return result
	func push_pair(a: Dictionary, b: Dictionary, delta: float) -> bool:
		pairs += 1
		var result := super.push_pair(a, b, delta)
		if result:
			collisions += 1
		return result
	func reset_counters() -> void:
		queries = 0
		redundant_empty_queries = 0
		nearest_us = 0
		separation_us = 0
		candidate_us = 0
		pairs = 0
		collisions = 0
		dense_queries = 0

class TimedWorld extends "res://scripts/world_scenery.gd":
	var draw_us := 0
	var region_calls := 0
	func _draw() -> void:
		var begin := Time.get_ticks_usec()
		super._draw()
		draw_us += Time.get_ticks_usec() - begin
	func draw_background(canvas: Node2D) -> void:
		var begin := Time.get_ticks_usec()
		super.draw_background(canvas)
		draw_us += Time.get_ticks_usec() - begin
	func draw_region_terrain_features(reg: Vector2i, target: Node2D = null) -> void:
		var begin := Time.get_ticks_usec()
		region_calls += 1
		super.draw_region_terrain_features(reg, target)
		draw_us += Time.get_ticks_usec() - begin

class TimedView extends "res://scripts/battlefield_view.gd":
	var samples: Array[float] = []
	var sort_us := 0
	func _draw() -> void:
		var begin := Time.get_ticks_usec()
		super._draw()
		samples.append((Time.get_ticks_usec() - begin) / 1000.0)
	func _sort_units_by_y() -> void:
		var begin := Time.get_ticks_usec()
		super._sort_units_by_y()
		sort_us += Time.get_ticks_usec() - begin

func _initialize() -> void:
	call_deferred("run")

func report(label: String, samples: Array[float]) -> void:
	assert(not samples.is_empty(), "Diagnostic received no samples: " + label)
	samples.sort()
	var total := 0.0
	for sample in samples:
		total += sample
	print("AUDIT %s: mean %.3f ms, p50 %.3f, p95 %.3f (%d samples)" % [label, total / samples.size(), samples[samples.size() / 2], samples[mini(samples.size() - 1, int(samples.size() * 0.95))], samples.size()])

func populate(model, label: String, count: int) -> void:
	model.rng.seed = 731
	model.endless = true
	if label == "endless":
		model.start_battle()
	else:
		# Keep isolated workloads from loading world regions during tick.
		model.wilderness.center = model.wilderness.cell(model.anchor)
		for i in range(count):
			var point := Vector2(65 + (i % 20) * 57, 220 + (i / 20) * 34)
			if label == "dense":
				point = Vector2(600, 400)
			elif label == "no-contact":
				point.x += 2000 if i % 2 else 0
			model.spawn_unit(["sword", "archer", "shield"][i % 3], i % 2, point)
	for unit in model.units:
		unit.hp = 1000000.0

func simulation_audit(label: String, count: int) -> void:
	# Independently time the production model before enabling method counters.
	# Repeat identical seeded work; this removes instrumentation cost, not contention.
	var raw_samples: Array[float] = []
	for trial in range(3):
		var raw = Model.new()
		populate(raw, label, count)
		for frame in range(10):
			raw.tick(1.0 / 60, Vector2.ZERO)
		for frame in range(60):
			var begin := Time.get_ticks_usec()
			raw.tick(1.0 / 60, Vector2.ZERO)
			raw_samples.append((Time.get_ticks_usec() - begin) / 1000.0)
	report("production %s %d requested soldiers" % [label, count], raw_samples)
	var model := CountedModel.new()
	populate(model, label, count)
	for frame in range(10):
		model.tick(1.0 / 60, Vector2.ZERO)
	model.reset_counters()
	var samples: Array[float] = []
	for frame in range(60):
		var begin := Time.get_ticks_usec()
		model.tick(1.0 / 60, Vector2.ZERO)
		samples.append((Time.get_ticks_usec() - begin) / 1000.0)
	report("instrumented %s %d active soldiers" % [label, model.units.size()], samples)
	print("AUDIT inclusive CPU/tick: nearest %.3f ms, separation %.3f ms (candidate queries %.3f ms); searches %.1f, redundant empty fallback searches %.1f, tested pairs %.1f, actual pushes %.1f, dense candidate queries %.1f" % [model.nearest_us / 60000.0, model.separation_us / 60000.0, model.candidate_us / 60000.0, model.queries / 60.0, model.redundant_empty_queries / 60.0, model.pairs / 60.0, model.collisions / 60.0, model.dense_queries / 60.0])
	if label == "endless":
		var visible := Rect2(model.anchor - Vector2(640, 369), Vector2(1280, 738)).grow(96)
		var visible_count := 0
		var destinations := 0
		for unit in model.units:
			if visible.has_point(unit.pos):
				visible_count += 1
		for region in model.wilderness.regions.values():
			if region.has("destination"):
				destinations += 1
		print("AUDIT default wilderness: %d visible of %d simulated; %d/%d regions retain generated destination metadata" % [visible_count, model.units.size(), destinations, model.wilderness.regions.size()])

func spawn_and_sort_audit() -> void:
	for count in [128, 256, 512, 1024]:
		var spawn_samples: Array[float] = []
		for trial in range(3):
			var model = Model.new()
			model.endless = true
			var begin := Time.get_ticks_usec()
			for i in range(count):
				model.spawn_unit("sword", 0, Vector2(300, 700.0 - float(i) / count * 600.0))
			spawn_samples.append((Time.get_ticks_usec() - begin) / 1000.0)
		report("deploy %d friendlies" % count, spawn_samples)
		var sort_model = Model.new()
		sort_model.endless = true
		for i in range(count):
			sort_model.spawn_unit("sword", 1, Vector2(300, 700.0 - float(i) / count * 600.0))
		var view = View.new()
		view.battle = sort_model
		var sort_samples: Array[float] = []
		for frame in range(20):
			var begin := Time.get_ticks_usec()
			view._sort_units_by_y()
			sort_samples.append((Time.get_ticks_usec() - begin) / 1000.0)
			assert(view._ordered_units.size() == count)
			assert(view._ordered_units[0].pos.y <= view._ordered_units.back().pos.y)
		report("reverse-Y sort %d visible soldiers (unchanged across frames)" % count, sort_samples)
		view.free()

func streaming_and_save_audit() -> void:
	var model = Model.new()
	model.endless = true
	model.rng.seed = 731
	model.start_battle()
	var samples: Array[float] = []
	for cell in range(1, 81):
		model.anchor.x = cell * 1200.0 + 260.0
		var begin := Time.get_ticks_usec()
		model.wilderness.update(model)
		samples.append((Time.get_ticks_usec() - begin) / 1000.0)
	report("region-boundary streaming including generation/eviction", samples)
	for count in [256, 1024]:
		var roster: Array[String] = []
		for i in range(count):
			roster.append("sword")
		var path := "user://performance_audit_%d_%d.json" % [Time.get_ticks_usec(), count]
		var save_samples: Array[float] = []
		for trial in range(8):
			var begin := Time.get_ticks_usec()
			assert(Store.save_army(roster, 1, path))
			save_samples.append((Time.get_ticks_usec() - begin) / 1000.0)
		assert(Store.load_army(path).roster == roster)
		assert(DirAccess.remove_absolute(path) == OK)
		report("synchronous atomic save %d recruits" % count, save_samples)

func scene_audit() -> void:
	var scene = Main.new()
	scene.save_path = "user://performance_audit_unused_%d.json" % Time.get_ticks_usec()
	scene.battle.rng.seed = 731
	var begin := Time.get_ticks_usec()
	root.add_child(scene)
	print("AUDIT endless scene ready CPU %.3f ms (procedural terrain/texture construction included)" % ((Time.get_ticks_usec() - begin) / 1000.0))
	scene.set_physics_process(false)
	var ui_samples: Array[float] = []
	for trial in range(30):
		begin = Time.get_ticks_usec()
		for frame in range(100):
			scene.refresh_ui()
		ui_samples.append((Time.get_ticks_usec() - begin) / 100000.0)
	report("unchanged UI refresh CPU per call", ui_samples)
	if DisplayServer.get_name() != "headless":
		var parent: Node = scene.world
		scene.scenery.free()
		var scenery := TimedWorld.new()
		scenery.wilderness = scene.battle.wilderness
		scenery.battle = scene.battle
		scene.scenery = scenery
		parent.add_child(scenery)
		parent.move_child(scenery, 0)
		scene.visuals.free()
		var view := TimedView.new()
		view.battle = scene.battle
		scene.visuals = view
		parent.add_child(view)
		Engine.max_fps = 60
		for frame in range(10):
			scene.update_camera()
			view.animate(1.0 / 60)
			await process_frame
			await RenderingServer.frame_post_draw
		for phase in ["stationary", "scrolling", "region-boundaries"]:
			var scenery_samples: Array[float] = []
			scenery.region_calls = 0
			view.samples.clear()
			view.sort_us = 0
			for frame in range(35):
				var before := scenery.draw_us
				if phase == "scrolling":
					scene.battle.anchor.x += 2.0
				elif phase == "region-boundaries":
					scene.battle.anchor.x += 1200.0
					scene.battle.wilderness.update(scene.battle)
				scene.update_camera()
				view.animate(1.0 / 60)
				await process_frame
				await RenderingServer.frame_post_draw
				scenery_samples.append((scenery.draw_us - before) / 1000.0)
				assert(scenery.terrain_regions.size() <= scenery.TERRAIN_CACHE_LIMIT)
			if phase == "stationary":
				assert(scenery.region_calls == 0, "Static terrain rebuilt while stationary")
			report("endless %s scenery draw-command CPU per frame (warm cache)" % phase, scenery_samples)
			report("endless %s soldier/effects draw-command CPU" % phase, view.samples)
			print("AUDIT %s scenery regenerated %.1f regions/frame, soldier Y-sort %.3f ms/draw; engine draw calls %d" % [phase, scenery.region_calls / 35.0, view.sort_us / float(view.samples.size()) / 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	scene.queue_free()
	await process_frame

func run() -> void:
	print("AUDIT instrumented CPU diagnostics; other running games may contend. No isolated FPS claims.")
	for scenario in [["mixed", 128], ["mixed", 256], ["dense", 256], ["no-contact", 256], ["endless", 4]]:
		simulation_audit(scenario[0], scenario[1])
	spawn_and_sort_audit()
	streaming_and_save_audit()
	await scene_audit()
	print("AUDIT complete; assertions passed; player save untouched.")
	quit()
