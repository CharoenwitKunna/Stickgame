extends SceneTree

const Main = preload("res://main.tscn")
var game
var failed := false

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	game.refresh_ui()
	game.queue_redraw()
	game.visuals.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.save_png(path) != OK or image.get_width() < 100:
		push_error("Render capture failed: " + path)
		failed = true
	else:
		print("RENDER PASS: %dx%d %s" % [image.get_width(), image.get_height(), path])

func run() -> void:
	game = Main.instantiate()
	game.endless_mode = false
	game.save_path = "user://render_smoke_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	game.set_physics_process(false)
	game.battle.rng.seed = 6432
	game.battle.stage = 3
	game.battle.roster.assign(["sword", "sword", "sword", "shield", "archer", "archer", "sword", "shield"])
	game.battle.start_battle()
	game.battle.anchor = Vector2(810, 440)
	for i in range(900):
		game.battle.tick(1.0 / 60, Vector2.ZERO)
		game.visuals.animate(1.0 / 60)
		if not game.battle.corpses.is_empty() and not game.battle.effects.is_empty():
			break
	game.hovered = 0 if not game.battle.corpses.is_empty() else -1
	game.visuals.hovered = game.hovered
	await capture("res://tests/preview.png")
	game.battle.corpses.append({"id": 99999, "kind": "shield", "pos": Vector2(650, 430), "ttl": 14.0})
	game.battle.soul = 10
	game.revive_held = true
	game.update_revive(0, Vector2(650, 430))
	game.update_revive(0.42, Vector2(650, 430))
	game.hovered = game.battle.corpse_at(Vector2(650, 430))
	game.visuals.hovered = game.hovered
	await capture("res://tests/preview_channel.png")
	game.update_revive(0.3, Vector2(650, 430))
	game.visuals.animate(0.18)
	game.hovered = -1
	await capture("res://tests/preview_revival.png")
	game.toggle_pause()
	await capture("res://tests/preview_pause.png")
	game.toggle_pause()
	game.battle.outcome = "victory"
	await capture("res://tests/preview_victory.png")
	game.battle.outcome = "defeat"
	await capture("res://tests/preview_defeat.png")
	game.battle.outcome = ""
	root.size = Vector2i(960, 600)
	await capture("res://tests/preview_small.png")
	var temporary_save: String = game.save_path
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(temporary_save)
	root.size = Vector2i(1280, 800)
	game = Main.instantiate()
	game.save_path = "user://render_endless_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	game.set_physics_process(false)
	await capture("res://tests/preview_endless.png")
	game.battle.anchor = Vector2(-3100, 2450)
	game.battle.wilderness.update(game.battle)
	for unit in game.battle.units:
		if unit.team == 0:
			unit.pos = game.battle.anchor + game.battle.slot_offset(unit.slot)
	game.update_camera()
	game.battle.corpses.append({"id": 888888, "kind": "shield", "pos": game.battle.anchor + Vector2(140, 40), "ttl": 14.0})
	game.battle.soul = 10
	game.revive_held = true
	game.update_revive(0, game.battle.corpses.back().pos)
	game.update_revive(0.4, game.battle.corpses.back().pos)
	game.hovered = game.battle.corpses.size() - 1
	game.visuals.hovered = game.hovered
	game.visuals.animate(0.01)
	await capture("res://tests/preview_endless_scrolled.png")
	root.size = Vector2i(960, 600)
	await capture("res://tests/preview_endless_small.png")
	temporary_save = game.save_path
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(temporary_save)
	quit(1 if failed else 0)
