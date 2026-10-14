extends SceneTree

const Model = preload("res://scripts/battle_model.gd")
const Store = preload("res://scripts/save_store.gd")
const MainScript = preload("res://scripts/main.gd")
var failures := 0
var checks := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var model = Model.new()
	model.rng.seed = 1234
	model.start_battle()
	check(model.alive_count(0) == 4, "Starter army is spawned")
	check(model.alive_count(1) == 6, "Stage one enemy army is spawned")
	var initial: Vector2 = model.anchor
	model.tick(0.5, Vector2.RIGHT)
	check(model.anchor.x > initial.x, "Movement input controls friendly army")
	var stopped: Vector2 = model.anchor
	model.tick(0.1, Vector2.ZERO)
	check(model.anchor == stopped, "Friendly army does not wander without input")
	model.move_target = model.anchor + Vector2(100, 0)
	model.has_target = true
	model.tick(0.1, Vector2.ZERO)
	check(model.anchor.x > stopped.x, "Click destination moves army")
	model.tick(0.1, Vector2.UP)
	check(not model.has_target, "Keyboard movement overrides click destination")
	for i in range(100):
		model.tick(0.1, Vector2(-1, -1))
	check(Model.ARENA.has_point(model.anchor), "Army anchor stays in arena")
	var enemy: Dictionary = {}
	for unit in model.units:
		if unit.team == 1:
			enemy = unit
			break
	var enemy_start: Vector2 = enemy.pos
	model.tick(0.5, Vector2.ZERO)
	check(enemy.pos != enemy_start, "Enemies roam independently")
	enemy.hp = 0
	var dead_position: Vector2 = enemy.pos
	model.collect_dead()
	check(model.corpses.size() == 1 and model.soul == 2, "Enemy death leaves corpse and earns Soul")
	var roster_before: int = model.roster.size()
	model.revive_at(dead_position)
	check(model.roster.size() == roster_before + 1, "Right-click revival permanently recruits matching unit")
	check(model.soul == 0 and model.corpses.is_empty(), "Revival spends Soul and consumes corpse")
	model.revive_at(dead_position)
	check(model.roster.size() == roster_before + 1, "Same corpse cannot be recruited twice")
	model.corpses.append({"id": 100, "pos": Vector2(500, 500), "kind": "shield", "ttl": 10.0})
	model.revive_at(Vector2(500, 500))
	check(model.corpses.size() == 1, "Insufficient Soul preserves corpse")
	model.corpses[0].ttl = 0.01
	model.tick(0.1, Vector2.ZERO)
	check(model.corpses.is_empty(), "Corpse expires after timer")
	model.start_battle()
	check(model.alive_count(0) == roster_before + 1 and model.soul == 0, "Recruits carry forward and Soul resets")
	for unit in model.units:
		if unit.team == 0:
			unit.hp = 0
	model.tick(0.02, Vector2.ZERO)
	check(model.outcome == "defeat", "Army loss gives defeat")
	model.start_battle()
	check(model.alive_count(0) == roster_before + 1, "Fallen friendly recruits recover on retry")
	for unit in model.units:
		if unit.team == 1:
			unit.hp = 0
	model.tick(0.02, Vector2.ZERO)
	check(model.outcome == "victory", "Enemy army loss gives victory")
	var corpse_count: int = model.corpses.size()
	model.tick(20.0, Vector2.ZERO)
	check(model.corpses.size() == corpse_count, "Victory freezes corpses for post-battle recruiting")
	model.revive_at(model.corpses[0].pos)
	check(model.roster.size() == roster_before + 2, "Can recruit after victory")
	var duel = Model.new()
	duel.roster.assign(["sword"])
	duel.anchor = Vector2(500, 500)
	duel.spawn_unit("sword", 0, duel.anchor)
	duel.spawn_unit("sword", 1, duel.anchor + Vector2(30, 0))
	for i in range(200):
		duel.tick(0.05, Vector2.ZERO)
	check(not duel.outcome.is_empty(), "Automatic melee combat reaches a result")
	var archery = Model.new()
	archery.anchor = Vector2(500, 500)
	archery.spawn_unit("archer", 0, archery.anchor)
	var victim: Dictionary = archery.spawn_unit("sword", 1, Vector2(650, 500))
	archery.units[0].cooldown = 0
	archery.tick(0.01, Vector2.ZERO)
	check(victim.hp < 85, "Archer attacks at ranged distance")
	var test_path := "user://test_army_%d.json" % Time.get_ticks_usec()
	check(Store.save_army(model.roster, 3, test_path), "Save writes successfully")
	var loaded: Dictionary = Store.load_army(test_path)
	check(loaded.get("roster", []) == model.roster and loaded.get("stage", 0) == 3, "Save restores exact army and campaign stage")
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string('{"version":1,"roster":["bad"],"stage":1}')
	file.close()
	check(Store.load_army(test_path).is_empty(), "Invalid unit in save is rejected safely")
	file = FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string("broken JSON")
	file.close()
	check(Store.load_army(test_path).is_empty(), "Corrupt save is rejected safely")
	DirAccess.remove_absolute(test_path)
	# Boot real scene and run several render/physics frames without touching real saves.
	var scene: Node2D = MainScript.new()
	scene.endless_mode = false
	scene.save_path = test_path
	root.add_child(scene)
	check(scene.get_node_or_null(".") != null, "Main scene boots with battlefield")
	await process_frame
	await process_frame
	var top_controls := 0
	for child in scene.get_children():
		if child is Control and child.visible and child.position.y < 140:
			top_controls += 1
	check(top_controls == 0, "Top HUD is removed, not hidden behind scenery")
	check(Model.ARENA.position.y == 0, "Battlefield occupies the old header area")
	check(scene.scenery.terrain_texture != null, "Painted battlefield texture is generated")
	check(scene.visuals.atlas != null and scene.visuals.atlas.texture != null, "Baked soldier atlas is loaded")
	check(scene.font.data.size() > 0 and scene.title_font.data.size() > 0, "Bundled UI fonts load")
	var edge: Vector2 = scene.battle.clamp_point(Vector2.ZERO)
	check(edge.y - 66 >= Model.ARENA.position.y, "Unit health bars stay inside the arena")
	scene.toggle_pause()
	check(scene.paused, "Pause control works")
	# Exercise the real mouse input path with coordinates mapped through the viewport.
	scene.toggle_pause()
	scene.battle.start_battle()
	var before_anchor: Vector2 = scene.battle.anchor
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(650, 60)
	root.push_input(mouse, true)
	await process_frame
	check(scene.battle.has_target and scene.battle.move_target.y == 70, "Former header area accepts battlefield movement clicks")
	mouse.position = Vector2(650, 430)
	root.push_input(mouse, true)
	await process_frame
	check(scene.battle.has_target or scene.battle.anchor != before_anchor, "Left-click movement reaches gameplay input")
	# Step the real hold controller deterministically, without wall-clock test delays.
	scene.set_physics_process(false)
	scene.battle.corpses.clear()
	scene.battle.corpses.append({"id": 10000, "kind": "sword", "pos": Vector2(650, 430), "ttl": 10.0})
	scene.battle.soul = 2
	var original_roster: int = scene.battle.roster.size()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	root.push_input(mouse, true)
	await process_frame
	check(scene.revive_held and scene.battle.roster.size() == original_roster, "Right press begins channel without instant recruitment")
	scene.update_revive(0.3, mouse.position)
	check(scene.visuals.channel_active and scene.visuals.channel_progress > 0.4 and scene.battle.soul == 2, "Partial hold shows progress without spending Soul")
	mouse.pressed = false
	root.push_input(mouse, true)
	scene.update_revive(1.0, mouse.position)
	check(not scene.visuals.channel_active and scene.battle.roster.size() == original_roster, "Release cancels without recruitment or Soul cost")
	mouse.pressed = true
	root.push_input(mouse, true)
	scene.update_revive(0.69, mouse.position)
	check(scene.battle.roster.size() == original_roster, "Short hold cannot revive")
	scene.update_revive(0.02, mouse.position)
	check(scene.battle.roster.size() == original_roster + 1 and scene.battle.soul == 0, "Full hold revives exactly once and spends Soul")
	scene.update_revive(2.0, mouse.position)
	check(scene.battle.roster.size() == original_roster + 1, "Continuing to hold cannot duplicate a recruit")
	check(not scene.visuals.rings.is_empty(), "Revival triggers visual feedback")
	var saved_count: int = scene.battle.roster.size()
	scene.visuals.animate(1.5)
	check(scene.visuals.rings.is_empty() and scene.battle.roster.size() == saved_count, "Cosmetic effects expire without changing recruitment")
	check(Store.load_army(test_path).get("roster", []).size() == original_roster + 1, "Revival auto-saves immediately")
	test_hold_cancellation(scene)
	for i in range(40):
		scene.visuals.raise_at(Vector2(500, 400), "archer")
	check(scene.visuals.active_particle_count() <= 240 and scene.visuals.rings.size() <= 24, "Repeated revival effects stay bounded")
	scene.visuals.animate(2.0)
	check(scene.visuals.active_particle_count() == 0 and scene.visuals.rings.is_empty() and scene.visuals.pulses.is_empty(), "Transient effects expire completely")
	scene.battle.outcome = "victory"
	scene.continue_battle()
	check(scene.battle.stage == 2, "Continue advances campaign")
	scene.reset_game()
	check(scene.battle.stage == 1 and scene.battle.roster.size() == 4, "New game resets army without typed-array errors")
	check(Store.load_army(test_path).get("stage", 0) == 1, "Atomic save replaces existing progress")
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(test_path)
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func test_hold_cancellation(scene) -> void:
	var a := Vector2(550, 420)
	var b := Vector2(700, 420)
	scene.battle.corpses.assign([
		{"id": 11000, "kind": "sword", "pos": a, "ttl": 10.0},
		{"id": 11001, "kind": "archer", "pos": b, "ttl": 10.0}])
	scene.battle.soul = 10
	var before: int = scene.battle.roster.size()
	scene.revive_held = true
	scene.update_revive(0, a)
	scene.update_revive(0.5, a)
	scene.update_revive(0.3, b)
	check(scene.revive_id == 11001 and scene.revive_elapsed == 0, "Switching corpses restarts the hold")
	scene.update_revive(0.4, b)
	scene.update_revive(0.4, Vector2(800, 600))
	check(scene.revive_id == -1 and not scene.visuals.channel_active, "Leaving the corpse cancels its progress")
	scene.update_revive(0, a)
	scene.update_revive(0.5, a)
	scene.toggle_pause()
	scene.toggle_pause()
	scene.update_revive(1, a)
	check(not scene.revive_held and scene.battle.roster.size() == before, "Pause cancels hold and resume requires a fresh press")
	scene.revive_held = true
	scene.update_revive(0, a)
	scene._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not scene.revive_held and not scene.visuals.channel_active, "Focus loss cancels hold")
	scene.revive_held = true
	scene.update_revive(0, a)
	scene.request_reset()
	check(not scene.revive_held, "New-game dialog cancels hold")
	scene.reset_dialog.hide()
	scene.battle.soul = 0
	scene.revive_held = true
	scene.update_revive(1, a)
	check(not scene.visuals.channel_active and scene.battle.roster.size() == before, "Unaffordable corpse cannot begin channel")
	scene.battle.soul = 10
	scene.update_revive(0, a)
	scene.update_revive(0.5, a)
	scene.battle.soul = 0
	scene.update_revive(0.3, a)
	check(scene.revive_id == -1 and scene.battle.roster.size() == before, "Loss of Soul during hold cancels without overspending")
	scene.battle.soul = 10
	scene.update_revive(0, a)
	scene.update_revive(0.5, a)
	scene.battle.corpses.remove_at(0)
	scene.update_revive(0.3, a)
	check(scene.revive_id == -1 and scene.battle.roster.size() == before, "Expired target cannot revive or redirect by array index")
	scene.battle.outcome = "defeat"
	scene.update_revive(1, b)
	check(not scene.revive_held and scene.battle.roster.size() == before, "Defeat cancels recruitment")
	scene.battle.outcome = "victory"
	scene.revive_held = true
	scene.update_revive(0, b)
	scene.update_revive(0.71, b)
	check(scene.battle.roster.size() == before + 1 and scene.battle.roster.back() == "archer", "Hold works after victory and recruits the selected kind")
	# Coincident corpses must still recruit by identity, not a second position lookup.
	scene.battle.corpses.assign([
		{"id": 12000, "kind": "sword", "pos": a, "ttl": 10.0},
		{"id": 12001, "kind": "shield", "pos": a, "ttl": 10.0}])
	scene.battle.revive_corpse(12001)
	check(scene.battle.roster.back() == "shield" and scene.battle.corpses[0].id == 12000, "Identity-based revival disambiguates overlapping corpses")
	scene.cancel_revive()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = a
	root.push_input(press, true)
	scene._physics_process(0.3)
	check(scene.visuals.channel_active and scene.revive_elapsed > 0.29, "Real input feeds the physics-driven hold timer")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(1150, 760)
	root.push_input(motion, true)
	check(not scene.visuals.channel_active, "Moving onto bottom UI cancels immediately")
	motion.position = a
	root.push_input(motion, true)
	scene._physics_process(0.4)
	press.pressed = false
	press.position = Vector2(1150, 760)
	root.push_input(press, true)
	check(not scene.revive_held, "Right release over a button still reaches cancellation")
	press.position = a
	press.pressed = true
	root.push_input(press, true)
	var count: int = scene.battle.roster.size()
	scene._physics_process(0.35)
	scene._physics_process(0.36)
	check(scene.battle.roster.size() == count + 1, "Real input and physics complete hold-to-revive end to end")
	scene.battle.effects.clear()
	for i in range(80):
		scene.battle.effects.append({"visual_id": 100000 + i, "from": a, "to": b, "ttl": 0.16, "team": i % 2, "archer": false})
	scene.visuals.animate(0.01)
	check(scene.visuals.pulses.size() == 32 and scene.visuals.active_particle_count() <= 240, "Combat bursts cap impact pulses and particles")
	scene.battle.effects.clear()
	scene.continue_battle()
	check(not scene.revive_held and scene.visuals.pulses.is_empty(), "Stage transition clears held input and effects")
	scene.battle.stage = 1
