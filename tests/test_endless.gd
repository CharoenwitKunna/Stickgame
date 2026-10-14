extends SceneTree

const Model = preload("res://scripts/battle_model.gd")
const Main = preload("res://scripts/main.gd")
class Reference extends "res://scripts/battle_model.gd":
	func _init() -> void:
		reuse_empty_chase_search = false
	func nearest_enemy(unit: Dictionary, radius: float, target_loads: Dictionary = {}) -> Dictionary:
		var result: Dictionary = {}
		var best := radius * radius
		for other in units:
			if other.team == unit.team or other.hp <= 0 or int(target_loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
				continue
			var distance: float = (unit.pos as Vector2).distance_squared_to(other.pos)
			if distance < best:
				best = distance
				result = other
		return result

	func separate_units(delta: float) -> void:
		separate_brute(delta)

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var fast = Model.new()
	var reference = Reference.new()
	for simulation in [fast, reference]:
		simulation.endless = true
		simulation.rng.seed = 943
		simulation.start_battle()
	for frame in range(80):
		for simulation in [fast, reference]:
			simulation.anchor = Vector2(frame * 600 - 22000, (frame % 5) * 700 - 2000)
			simulation.wilderness.update(simulation)
			for unit in simulation.units:
				unit.hp = 1000000.0
				if unit.team == 0:
					unit.pos = simulation.anchor + simulation.slot_offset(unit.slot)
			simulation.tick(1.0 / 60, Vector2.RIGHT)
		check(fast.units == reference.units and fast.effects == reference.effects and fast.anchor == reference.anchor, "Streamed-world simulation matches linear/pairwise reference frame %d" % frame)
	var formation = Model.new()
	formation.endless = true
	formation.anchor = Vector2(500, 500)
	for i in range(8):
		formation.spawn_unit("sword", 0, formation.anchor + formation.slot_offset(i))
	var survivors: Dictionary = {}
	for unit in formation.units:
		survivors[unit.id] = unit.slot
	formation.units[0].hp = 0
	formation.units[3].hp = 0
	formation.collect_dead()
	for unit in formation.units:
		check(unit.slot == survivors[unit.id], "Casualty preserves survivor slot %d" % unit.id)
	# Avoid streaming in this isolated tick; verify the actual movement destination.
	formation.wilderness.center = formation.wilderness.cell(formation.anchor)
	var follower: Dictionary = formation.units.back()
	var before: Vector2 = follower.pos
	formation.anchor += Vector2(200, 0)
	formation.tick(0.1, Vector2.ZERO)
	check((follower.pos as Vector2).distance_to(before + Vector2(15.5, 0)) < 0.01, "Tick follows persistent slot, not survivor array index")
	var recruit: Dictionary = formation.spawn_unit("archer", 0, Vector2.ZERO)
	check(recruit.slot == 0, "Recruit reuses a vacant slot without displacing survivors")
	formation.start_battle()
	var slots: Dictionary = {}
	for unit in formation.units:
		if unit.team == 0:
			slots[unit.slot] = true
	check(slots.size() == formation.roster.size() and slots.has(0), "Restart assigns unique compact slots")

	var model = Model.new()
	model.endless = true
	model.rng.seed = 42
	model.start_battle()
	check(model.wilderness.active.size() == 9 and model.alive_count(1) > 0, "Exploration scatters groups through nine nearby regions")
	var groups: Dictionary = {}
	for unit in model.units:
		if unit.team == 1:
			groups[unit.home] = int(groups.get(unit.home, 0)) + 1
	var small := false
	var large := false
	for count in groups.values():
		small = small or count <= 5
		large = large or count >= 14
	check(groups.size() >= 9 and small and large, "Seeded map contains scattered small and large armies")
	check(model.clamp_point(Vector2(-50000, 70000)) == Vector2(-50000, 70000), "World movement has no arena boundaries")
	model.anchor = Vector2(-1201, -1201)
	model.tick(0.1, Vector2.LEFT)
	check(model.anchor.x < -1201 and model.wilderness.center == Vector2i(-2, -2), "Negative world coordinates stream correctly")
	check(model.outcome.is_empty(), "Walking outside the old arena stays playable")

	# Save a distant enemy's damage and a casualty; verify unloading/revisiting.
	model.anchor = Vector2(260, 440)
	model.wilderness.update(model)
	var watched: Dictionary = {}
	var killed: Dictionary = {}
	for unit in model.units:
		if unit.team == 1 and unit.region == Vector2i.ZERO:
			if watched.is_empty():
				watched = unit
			elif killed.is_empty():
				killed = unit
	watched.hp = 17.0
	killed.hp = 0
	model.collect_dead()
	var dead_id: int = killed.id
	var soul_before: int = model.soul
	model.anchor = Vector2(3860, 440)
	model.wilderness.update(model)
	check(not model.units.has(watched), "Far enemies stop simulating")
	model.anchor = Vector2(260, 440)
	model.wilderness.update(model)
	check(model.units.has(watched) and watched.hp == 17, "Revisited nearby region preserves enemy damage")
	var dead_returns := false
	for unit in model.units:
		dead_returns = dead_returns or unit.id == dead_id
	check(not dead_returns and model.soul == soul_before, "Revisiting does not resurrect kills or reset Soul")
	# A chasing unit migrated out of its home region remains visible across streaming.
	watched.region = Vector2i(-1, 0)
	watched.pos = Vector2(1300, 440)
	model.anchor = Vector2(1250, 440)
	model.wilderness.update(model)
	check(model.units.has(watched) and watched.region == Vector2i(1, 0), "Nearby pursuer survives unloading its original region")

	for region in range(100):
		model.anchor = Vector2(region * 1200 + 260, 440)
		model.wilderness.update(model)
		check(model.wilderness.regions.size() <= 64 and model.wilderness.active.size() == 9, "Streaming cache bounded at region %d" % region)
	var ids: Dictionary = {}
	for unit in model.units:
		check(not ids.has(unit.id), "Active units have unique IDs")
		ids[unit.id] = true
	check(model.units.size() < 440, "Far exploration does not accumulate active armies")
	check(model.search_buckets[0].is_empty() and model.separation_buckets.is_empty(), "Streaming releases old spatial-grid keys")
	for unit in model.units:
		if unit.team == 1:
			unit.hp = 0
	model.tick(0.01, Vector2.ZERO)
	check(model.outcome.is_empty(), "Clearing all loaded enemies does not end exploration")
	model.anchor.x += 1200
	model.tick(0.01, Vector2.ZERO)
	check(model.alive_count(1) > 0 and model.outcome.is_empty(), "Fresh enemies appear on further exploration")
	for unit in model.units:
		if unit.team == 0:
			unit.hp = 0
	model.tick(0.01, Vector2.ZERO)
	check(model.outcome == "defeat", "Endless expedition still detects army defeat")

	var scene = Main.new()
	scene.save_path = "user://endless_test_%d.json" % Time.get_ticks_usec()
	root.add_child(scene)
	scene.set_physics_process(false)
	check(scene.battle.endless and scene.world != null, "Normal game boots into scrolling exploration")
	scene.battle.anchor = Vector2(10000, -10000)
	scene.battle.wilderness.update(scene.battle)
	scene.update_camera()
	check(scene.world_to_screen(scene.battle.anchor) == Vector2(640, 369), "Camera centers army far from origin")
	check(scene.scenery.terrain_texture != null, "Scrolling terrain shares the original painted texture")
	var terrain: Image = scene.scenery.source.terrain_image
	var seamless := true
	for y in range(terrain.get_height()):
		seamless = seamless and terrain.get_pixel(0, y) == terrain.get_pixel(terrain.get_width() - 1, y)
	for x in range(terrain.get_width()):
		seamless = seamless and terrain.get_pixel(x, 0) == terrain.get_pixel(x, terrain.get_height() - 1)
	check(seamless, "Tiled terrain has matching edges without rectangular seams")
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(840, 369)
	root.push_input(mouse, true)
	check(scene.battle.move_target == scene.battle.anchor + Vector2(200, 0), "March click converts screen position to world position")
	var corpse_position: Vector2 = scene.battle.anchor + Vector2(100, 0)
	scene.battle.corpses.assign([{"id": 999999, "kind": "archer", "pos": corpse_position, "ttl": 14.0}])
	scene.battle.soul = 10
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.position = scene.world_to_screen(corpse_position)
	root.push_input(mouse, true)
	check(scene.revive_id == 999999 and scene.visuals.channel_active, "Scrolled corpse accepts real right-mouse input")
	scene.update_revive(0.35, corpse_position)
	scene.battle.anchor += Vector2(100, 0)
	scene.update_camera()
	scene.update_revive(0.35, scene.revive_pointer)
	check(scene.revive_id == -1, "Scrolling away from a stationary pointer cancels corpse channel")
	mouse.position = scene.world_to_screen(corpse_position)
	root.push_input(mouse, true)
	var roster_before: int = scene.battle.roster.size()
	scene.update_revive(0.71, corpse_position)
	check(scene.battle.roster.size() == roster_before + 1 and scene.battle.soul == 7, "Scrolled recruitment spends Soul and adds permanent unit")
	mouse.position = Vector2(400, 760)
	mouse.button_index = MOUSE_BUTTON_LEFT
	scene.battle.has_target = false
	root.push_input(mouse, true)
	check(not scene.battle.has_target, "Bottom control bar does not issue world movement")
	scene.hovered = -1
	scene.refresh_ui()
	check(not scene.action.visible and not scene.result_panel.visible, "Exploration has no Next battle or victory overlay")
	scene.visuals.animate(0.01)
	scene.visuals._sort_units_by_y()
	var culled := true
	for unit in scene.visuals._ordered_units:
		culled = culled and scene.visuals.visible_world.has_point(unit.pos)
	check(culled, "Rendering excludes offscreen soldiers")
	scene.battle.units[0].hp = 0
	scene.battle.collect_dead()
	scene.visuals.animate(0.01)
	check(scene.visuals._hp_ghost.size() <= scene.battle.units.size(), "Dead-unit visual caches are pruned")
	scene.battle.outcome = "defeat"
	scene.refresh_ui()
	check(scene.action.visible and scene.action.text == "Retry battle", "Defeat offers a working retry")
	scene.continue_battle()
	check(scene.battle.outcome.is_empty() and scene.battle.roster.size() == roster_before + 1, "Retry restores the army including permanent recruits")
	var temporary: String = scene.save_path
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(temporary)
	print("ENDLESS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
