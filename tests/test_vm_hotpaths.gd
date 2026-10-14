extends "res://tests/test_hotpath_fixes.gd"

# Current-pass baselines captured from 0e45125, not the earlier ead1277 pass.
func original(name: String) -> GDScript:
	var path := "res://tests/pass3_reference/%s.txt" % name
	if not FileAccess.file_exists(path):
		return super.original(name)
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path).replace("class_name BattleModel\n", "")
	assert(script.reload() == OK, "VM baseline failed to compile")
	return script

func particle_checks() -> void:
	var views := [View.new(), original("battlefield_view").new()]
	for view in views:
		seed(723)
		root.add_child(view)
	for phase in range(14):
		for view in views:
			seed(912 + phase)
			if phase == 0:
				view.emit_particles(Vector2(640, 380), Color.RED, 3, true)
			elif phase == 2:
				view.emit_particles(Vector2(640, 380), Color.BLUE, 300)
			elif phase == 4:
				view.emit_particles(Vector2(640, 380), Color.GREEN, 11, true)
			elif phase == 7:
				view.spawn_revival_burst(Vector2(640, 380))
			view.animate(0.5 if phase in [3, 6, 10, 13] else 0.02)
		for field in ["_p_cursor", "_p_pos", "_p_vel", "_p_life", "_p_max_life", "_p_size", "_p_tint", "_p_rising", "pulses", "rings", "motes"]:
			check(views[0].get(field) == views[1].get(field), "Exact particle ring/phase/RNG parity: " + field)
		var actual := 0
		var expected_indices: Array[int] = []
		for slot in range(View.MAX_PARTICLES):
			if views[0]._p_life[slot] > 0.0:
				actual += 1
				expected_indices.append(slot)
		check(views[0].active_particle_count() == actual and views[0]._p_active_indices == expected_indices, "Active slots stay exact, sorted and duplicate-free")
	for count in [1, 28, 240]:
		var samples := [0.0, 0.0]
		for i in [1, 0]:
			seed(811)
			views[i].reset_effects()
			views[i].emit_particles(Vector2(640, 380), Color.GREEN, count, true)
			var begin := Time.get_ticks_usec()
			for frame in range(1000):
				views[i].animate(0.0)
			samples[i] = (Time.get_ticks_usec() - begin) / 1000000.0
		print("VM PARTICLES %d active: %.3f -> %.3f ms/animate" % [count, samples[1], samples[0]])
	for view in views:
		view.free()

func sorting_checks() -> void:
	var old_script := original("battlefield_view")
	for count in [128, 256, 1024]:
		for scenario in ["reverse", "ties", "mixed"]:
			var model = Model.new()
			model.endless = true
			for i in range(count):
				var y := float(count - i) * 0.5
				if scenario == "ties":
					y = 100.0
				elif scenario == "mixed":
					y = float((i * 731) % 500)
				model.spawn_unit("sword", i % 2, Vector2(100, y))
			# IDs deliberately conflict with array order, as with streamed armies.
			model.units.reverse()
			var before: Array = model.units.duplicate(true)
			var views := [View.new(), old_script.new()]
			var times := [0.0, 0.0]
			for index in [1, 0]:
				views[index].battle = model
				views[index]._sort_units_by_y()
				var begin := Time.get_ticks_usec()
				for frame in range(100):
					views[index]._sort_units_by_y()
				times[index] = (Time.get_ticks_usec() - begin) / 100000.0
			check(views[0]._ordered_units == views[1]._ordered_units and model.units == before, "Stable sort preserves arbitrary IDs and never mutates unit dictionaries")
			print("VM SORT %s %d: %.3f -> %.3f ms/sort" % [scenario, count, times[1], times[0]])
			for view in views:
				view.free()

func moving_world_checks() -> void:
	var model = Model.new()
	model.endless = true
	model.rng.seed = 731
	model.start_battle()
	var nodes := [World.new(), original("world_scenery").new()]
	var viewports := [make_viewport(), make_viewport()]
	for i in range(2):
		nodes[i].wilderness = model.wilderness
		viewports[i].add_child(nodes[i])
	var rectangle := Rect2(-100, 100, 1280, 738)
	for phase in range(12):
		var previous: Array = nodes[0].active_region_keys.duplicate()
		var rebuilds: int = nodes[0].region_membership_rebuilds
		var frame_rectangle := Rect2(rectangle.position + Vector2(phase * 3, 0), rectangle.size)
		for node in nodes:
			node.position = -frame_rectangle.position
			node.update_view(frame_rectangle)
		if previous == nodes[0].active_region_keys:
			check(nodes[0].region_membership_rebuilds == rebuilds, "Moving within membership skips all show/hide/reorder operations")
		await compare_viewports(viewports, "Moving-camera retained pixels equal previous renderer")
	var times := [0.0, 0.0]
	for i in [1, 0]:
		var begin := Time.get_ticks_usec()
		for frame in range(1000):
			nodes[i].update_view(Rect2(rectangle.position + Vector2(frame % 30, 0), rectangle.size))
		times[i] = (Time.get_ticks_usec() - begin) / 1000000.0
	print("VM MOVING WORLD: %.3f -> %.3f ms/update" % [times[1], times[0]])
	for seed_value in [731, 924, 731]:
		for coordinate in range(-150, 150):
			check(nodes[0].get_h_junction_y(seed_value, coordinate, -coordinate) == nodes[1].get_h_junction_y(seed_value, coordinate, -coordinate), "Cached horizontal junction preserves authored string-hash layout")
			check(nodes[0].get_v_junction_x(seed_value, coordinate, -coordinate) == nodes[1].get_v_junction_x(seed_value, coordinate, -coordinate), "Cached vertical junction preserves authored string-hash layout")
		check(nodes[0].h_junction_cache.size() <= 256 and nodes[0].v_junction_cache.size() <= 256, "Junction caches stay bounded across exploration and seed changes")
	for viewport in viewports:
		viewport.queue_free()
	await process_frame

func particle_render_checks() -> void:
	var views := [View.new(), original("battlefield_view").new()]
	var viewports := [make_viewport(), make_viewport()]
	for i in range(2):
		views[i].battle = Model.new()
		seed(821)
		viewports[i].add_child(views[i])
	for phase in range(6):
		for view in views:
			seed(124 + phase)
			view.emit_particles(Vector2(640, 380), Color(0.8, 0.2, 0.5), 300 if phase == 2 else 8, phase % 2 == 0)
			view.animate(0.5 if phase == 3 else 0.02)
		await compare_viewports(viewports, "Sparse, expired and overwritten particles retain exact alpha compositing pixels")
	for viewport in viewports:
		viewport.queue_free()
	await process_frame

func boundary_checks() -> void:
	var models := [Model.new(), original("battle_model").new()]
	for model in models:
		model.anchor = Vector2.ZERO
		model.spawn_unit("sword", 1, Vector2.ZERO)
	var different := 0
	for radius in [80.0, 160.0, 360.0]:
		for index in range(2048):
			var angle := index * TAU / 2048.0
			var point := Vector2(cos(angle) * radius, sin(angle) * radius)
			for model in models:
				model.units[0].pos = point
			var expected: bool = models[1].is_combat_active(radius)
			check(models[0].is_combat_active(radius) == expected, "Original float32 radius boundary is preserved")
			if (point.length_squared() < radius * radius) != expected:
				different += 1
	check(different > 0, "Naive squared-radius replacement demonstrably changes float32 decisions")
	print("VM BOUNDARIES: %d real counterexamples to naive squared thresholds; original behavior retained" % different)

func fallback_render_checks() -> void:
	var model = Model.new()
	for index in range(3):
		var corpse := {"id": index + 1, "pos": Vector2(200 + index * 200, 300), "specialist": index == 1}
		corpse[["ttl", "timer", "life"][index]] = 7.0
		model.corpses.append(corpse)
		var effect := {"from": Vector2(150 + index * 200, 500), "to": Vector2(250 + index * 200, 500), "team": index % 2}
		effect[["ttl", "timer", "life"][index]] = 0.08
		effect[["duration", "max_life", "duration"][index]] = 0.16
		if index == 0:
			effect.kind = "arrow"
		else:
			effect.archer = index == 1
		model.effects.append(effect)
	var viewports := [make_viewport(), make_viewport()]
	var views := [View.new(), original("battlefield_view").new()]
	for index in range(2):
		views[index].battle = model
		seed(91)
		viewports[index].add_child(views[index])
	await compare_viewports(viewports, "Legacy corpse/effect TTL/duration/kind fallbacks preserve exact pixels")
	for viewport in viewports:
		viewport.queue_free()
	await process_frame

func run() -> void:
	print("VM HOTPATH BASELINE: 0e45125 (shared paired benchmark below)")
	simulation_checks("--bench" in OS.get_cmdline_user_args())
	particle_checks()
	sorting_checks()
	boundary_checks()
	if DisplayServer.get_name() != "headless":
		await render_checks()
		await particle_render_checks()
		await fallback_render_checks()
		await moving_world_checks()
	print("VM HOTPATHS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
