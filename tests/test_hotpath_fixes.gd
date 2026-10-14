extends SceneTree

const Model = preload("res://scripts/battle_model.gd")
const View = preload("res://scripts/battlefield_view.gd")
const Scenery = preload("res://scripts/scenery.gd")
const World = preload("res://scripts/world_scenery.gd")
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures := 0

# Immutable pre-pass fixtures from ead1277. Compiling text avoids registering a
# second BattleModel class; original algorithms/precision/draw order stay intact.
func original(name: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string("res://tests/pass2_reference/%s.txt" % name).replace("class_name BattleModel\n", "")
	assert(script.reload() == OK, "Original fixture failed to compile")
	return script

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func units_equal(fast, old) -> bool:
	if fast.units.size() != old.units.size():
		return false
	for i in range(old.units.size()):
		for key in old.units[i]:
			if fast.units[i].get(key) != old.units[i][key]:
				return false
	return true

func setup(model, scenario: String, count: int, value: int) -> void:
	model.rng.seed = value
	model.endless = true
	if scenario == "exploration":
		model.start_battle()
	else:
		model.wilderness.center = model.wilderness.cell(model.anchor)
		for i in range(count):
			var point := Vector2(65 + (i % 20) * 57, 220 + (i / 20) * 34)
			if scenario == "dense":
				point = Vector2(600, 400)
			elif scenario == "separated":
				point.x += 2000 if i % 2 else 0
			model.spawn_unit(["sword", "archer", "shield"][i % 3], i % 2, point)
	for unit in model.units:
		unit.hp = 1000000.0

func simulation_checks(benchmark: bool) -> void:
	var old_script := original("battle_model")
	for scenario in [["mixed", 128], ["mixed", 256], ["dense", 256], ["separated", 256], ["exploration", 4]]:
		var totals := [0.0, 0.0]
		var samples: Array = [[], []]
		for trial in range(3):
			var games := [old_script.new(), Model.new()]
			for game in games:
				setup(game, scenario[0], scenario[1], 731 + trial)
				for frame in range(10):
					game.tick(1.0 / 60, Vector2.ZERO)
			for index in ([0, 1] if trial % 2 == 0 else [1, 0]):
				for frame in range(60 if benchmark else 20):
					var begin := Time.get_ticks_usec()
					games[index].tick(1.0 / 60, Vector2.ZERO)
					var sample := (Time.get_ticks_usec() - begin) / 1000.0
					samples[index].append(sample)
					totals[index] += sample
			check(units_equal(games[1], games[0]) and games[1].corpses == games[0].corpses and games[1].effects == games[0].effects and games[1].rng.state == games[0].rng.state and games[1].soul == games[0].soul and games[1].outcome == games[0].outcome, "Exact pre-pass simulation parity: %s trial %d" % [scenario[0], trial])
		if benchmark:
			for sample in samples:
				sample.sort()
			print("PASS2 PAIRED %s %d: %.3f -> %.3f ms/tick, %.1f%% CPU reduction; p95 %.3f -> %.3f; exact original states" % [scenario[0], scenario[1], totals[0] / samples[0].size(), totals[1] / samples[1].size(), (totals[0] - totals[1]) / totals[0] * 100, samples[0][171], samples[1][171]])
	var model = Model.new()
	setup(model, "mixed", 128, 43)
	var attacks: Dictionary = model.attack_loads[0]
	var chases: Dictionary = model.chase_loads[1]
	attacks[-999] = 99
	chases[-999] = 99
	model.tick(0, Vector2.ZERO)
	check(is_same(attacks, model.attack_loads[0]) and is_same(chases, model.chase_loads[1]) and not attacks.has(-999) and not chases.has(-999), "Load dictionaries are reused and cleared")
	check(model.live_counts[0] == model.alive_count(0) and model.live_counts[1] == model.alive_count(1), "Collected live counts match independent scans")
	for unit in model.units:
		check(is_same(unit.stats, model.kind_stats[unit.kind]) and unit.radius == Model.BODY_RADII[unit.kind] and unit.inv_mass == 1.0 / Model.BODY_MASSES[unit.kind], "Spawn caches immutable stats without changing elite HP")
	# Exact tangent boundaries and tiny offsets exercise float32 sqrt rounding.
	for left in ["sword", "archer", "shield"]:
		for right in ["sword", "archer", "shield"]:
			for distance in [0.0, 0.001, 0.009999, 0.01, 0.010001, Model.BODY_RADII[left] + Model.BODY_RADII[right] - 0.000001, Model.BODY_RADII[left] + Model.BODY_RADII[right], Model.BODY_RADII[left] + Model.BODY_RADII[right] + 0.000001]:
				var fast = Model.new()
				var old = old_script.new()
				for game in [fast, old]:
					game.endless = true
					game.rng.seed = 731
					game.spawn_unit(left, 0, Vector2.ZERO)
					game.spawn_unit(right, 1, Vector2(distance, 0.000001))
					game.separate_units(0.2)
				check(units_equal(fast, old), "Exact mixed-mass collision at touching/normalization boundary")

func terrain_checks() -> void:
	var old_script := original("scenery")
	for tile in [false, true]:
		var fast = Scenery.new()
		var old = old_script.new()
		for scenery in [fast, old]:
			var random := RandomNumberGenerator.new()
			random.seed = 73631
			scenery.tileable = tile
			scenery.tuf_and_stone_setup(random)
		var begin := Time.get_ticks_usec()
		old.paint_terrain()
		var old_ms := (Time.get_ticks_usec() - begin) / 1000.0
		begin = Time.get_ticks_usec()
		fast.paint_terrain()
		var new_ms := (Time.get_ticks_usec() - begin) / 1000.0
		check(fast.terrain_image.get_data() == old.terrain_image.get_data(), "Terrain RGBA bytes equal original, tileable=%s" % tile)
		print("PASS2 TERRAIN tileable=%s: %.3f -> %.3f ms; identical pixel bytes" % [tile, old_ms, new_ms])
		fast.free()
		old.free()

func ui_checks() -> void:
	var old_script := original("main")
	var games := [Main.new(), old_script.new()]
	for i in range(2):
		games[i].endless_mode = false
		games[i].save_path = "user://hotpath_ui_%d_%d.json" % [Time.get_ticks_usec(), i]
		root.add_child(games[i])
		games[i].set_physics_process(false)
	for state in range(12):
		for game in games:
			game.battle.outcome = ["", "", "victory", "defeat"][state % 4]
			game.paused = state % 4 == 1
			game.battle.corpses.assign([{"id": 42, "kind": "shield", "pos": Vector2(300.25 + state, 400), "specialist": state % 2 == 0, "elite": state % 3 == 0}])
			game.hovered = 0 if state % 3 else -1
			game.battle.soul = state
			game.revive_id = 42 if state % 2 else -1
			game.visuals.channel_progress = state / 12.0
			game.status_time = 0
			game.refresh_ui()
		for name in ["hint", "banner", "result_help", "action", "result_panel", "tooltip", "tooltip_title", "tooltip_help"]:
			var fast = games[0].get(name)
			var old = games[1].get(name)
			check(fast.visible == old.visible and fast.position == old.position and fast.modulate == old.modulate, "UI geometry/visibility/color matches original: " + name)
			if "text" in fast:
				check(fast.text == old.text, "UI text matches original: " + name)
	for game in games:
		game.queue_free()

func render_checks() -> void:
	var old_view := original("battlefield_view")
	var model = Model.new()
	for i in range(96):
		var unit: Dictionary = model.spawn_unit(["sword", "archer", "shield"][i % 3], i % 2, Vector2(100.25 + (i % 16) * 63.125, 90.125 + (i / 16) * 65.25))
		unit.hp *= 0.6 if i % 3 == 0 else 1.0
		unit.moving = i % 2 == 0
		unit.facing = -1.0 if i % 3 else 1.0
		unit.flash = 0.18 if i % 5 == 0 else 0.0
		unit.attack = 0.12 if i % 7 == 0 else 0.0
		unit.attack_anim = 0.42 if i % 11 == 0 else 0.0
		unit.specialist = i % 4 == 0
		unit.elite = i % 7 == 0
	var views := [View.new(), old_view.new()]
	var viewports: Array[SubViewport] = []
	for view in views:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 738)
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		view.battle = model
		seed(731)
		viewport.add_child(view)
		viewports.append(viewport)
	for scenario in range(3):
		for view in views:
			seed(731 + scenario)
			view.animate(1.0 / 60)
		for frame in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var actual := viewports[0].get_texture().get_image()
		var expected := viewports[1].get_texture().get_image()
		check(actual.get_data() == expected.get_data(), "Soldier pixels equal original: fractional positions, mirrored facing, damage, badges, recoil/lunge")
		if scenario == 0:
			for unit in model.units:
				unit.hp = unit.max_hp
			check(views[0]._hp_ghost.size() < model.units.size(), "Healthy units do not allocate HP ghost entries")
		elif scenario == 1:
			var uid: int = model.units[0].id
			model.units.remove_at(0)
			model.spawn_unit("sword", 0, Vector2(400, 600))
			for view in views:
				seed(80)
				view.animate(0.0)
			check(not views[0]._unit_facing.has(uid), "Same-count population replacement prunes healthy facing cache")
	for viewport in viewports:
		viewport.queue_free()
	await process_frame

func make_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 738)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport

func compare_viewports(viewports: Array, label: String) -> void:
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var actual: Image = viewports[0].get_texture().get_image()
	var expected: Image = viewports[1].get_texture().get_image()
	check(actual.get_data() == expected.get_data(), label)

func scenery_render_checks() -> void:
	var old_scenery := original("scenery")
	var scenery := [Scenery.new(), old_scenery.new()]
	var viewports := [make_viewport(), make_viewport()]
	for i in range(2):
		viewports[i].add_child(scenery[i])
		scenery[i].set_process(false)
	for clock in [0.0, 1.25, 3.17]:
		for node in scenery:
			node.wind_clock = clock
			node.queue_redraw()
		await compare_viewports(viewports, "Retained stones preserve original wind/grass/tree compositing pixels")
	for node in scenery:
		node.stamp_battle_scar(Vector2(300, 400), 40)
		node._process(0.0)
	await compare_viewports(viewports, "Terrain scars update retained background without disturbing stones")
	for viewport in viewports:
		viewport.queue_free()
	await process_frame

func world_checks() -> void:
	var model = Model.new()
	model.endless = true
	model.rng.seed = 731
	model.start_battle()
	var old_world := original("world_scenery")
	var scenery := [World.new(), old_world.new()]
	var viewports := [make_viewport(), make_viewport()]
	var rectangle := Rect2(model.anchor - Vector2(640, 369), Vector2(1280, 738))
	for i in range(2):
		scenery[i].wilderness = model.wilderness
		scenery[i].battle = model
		viewports[i].add_child(scenery[i])
		scenery[i].position = -rectangle.position
		scenery[i].update_view(rectangle)
	await compare_viewports(viewports, "World matches pre-pass retained renderer")
	var rebuilds: int = scenery[0].view_rebuilds
	for i in [1, 0]:
		var begin := Time.get_ticks_usec()
		for frame in range(1000):
			scenery[i].update_view(rectangle)
		print("PASS2 STATIONARY VIEW %s: %.3f ms/call" % ["current" if i == 0 else "original", (Time.get_ticks_usec() - begin) / 1000000.0])
	check(scenery[0].view_rebuilds == rebuilds, "Stationary camera skips terrain membership/ordering/LRU rebuilds")
	var destination: Dictionary = model.wilderness.regions[Vector2i.ZERO].destination
	# These direct dictionary edits intentionally bypass all version counters.
	for phase in range(4):
		if phase == 0:
			destination.type = "shrine"
			destination.pos = model.anchor + Vector2(80, 0)
		elif phase == 1:
			destination.used = true
		elif phase == 2:
			destination.pos += Vector2(180, 120)
		else:
			rectangle.position += Vector2(60, 0) # Same region span, different culling.
		for node in scenery:
			node.position = -rectangle.position
			node.update_view(rectangle)
		await compare_viewports(viewports, "Stationary metadata edits and same-span movement invalidate exactly")
	for viewport in viewports:
		viewport.queue_free()
	await process_frame

func batch_checks() -> void:
	var old_view := original("battlefield_view")
	var model = Model.new()
	for i in range(128):
		var unit: Dictionary = model.spawn_unit("sword", i % 2, Vector2(70 + (i % 16) * 70, 100 + (i / 16) * 70))
		unit.hp *= 0.5
		unit.flash = 0.0
		unit.attack = 0.0
	var views := [View.new(), old_view.new()]
	var viewports := [make_viewport(), make_viewport()]
	for i in range(2):
		views[i].battle = model
		seed(731)
		viewports[i].add_child(views[i])
	await compare_viewports(viewports, "Batched injured-unit health bars preserve exact original pixels")
	var draw_calls := [0.0, 0.0]
	for index in [1, 0]:
		for i in range(2):
			viewports[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS if i == index else SubViewport.UPDATE_DISABLED
		for frame in range(10):
			views[index].queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			if frame >= 5:
				draw_calls[index] += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME) / 5.0
	print("PASS2 BATCH 128 injured soldiers: %.1f -> %.1f engine draw calls/frame" % [draw_calls[1], draw_calls[0]])
	check(draw_calls[0] < draw_calls[1], "Atlas health bars/identity transforms reduce actual renderer draw calls")
	for viewport in viewports:
		viewport.queue_free()
	await process_frame

func run() -> void:
	simulation_checks("--bench" in OS.get_cmdline_user_args())
	terrain_checks()
	ui_checks()
	if DisplayServer.get_name() != "headless":
		await render_checks()
		await scenery_render_checks()
		await world_checks()
		await batch_checks()
	print("HOTPATH FIXES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
