extends SceneTree

class TimedMain extends "res://scripts/main.gd":
	var physics_samples: Array[float] = []
	func _physics_process(delta: float) -> void:
		var begin := Time.get_ticks_usec()
		super._physics_process(delta)
		physics_samples.append((Time.get_ticks_usec() - begin) / 1000.0)

func _initialize() -> void:
	call_deferred("run")

func summarize(label: String, samples: Array[float]) -> void:
	samples.sort()
	var sum := 0.0
	for value in samples:
		sum += value
	print("LIVE %s: mean %.3f ms, p50 %.3f ms, p95 %.3f ms" % [label, sum / samples.size(), samples[samples.size() / 2], samples[int(samples.size() * 0.95)]])

func run() -> void:
	Engine.max_fps = 60
	var game := TimedMain.new()
	var exploration := "--endless" in OS.get_cmdline_user_args()
	game.endless_mode = exploration
	game.save_path = "user://live_benchmark_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	for count in ([4, 128, 256] if exploration else [10, 128, 256]):
		game.battle.rng.seed = 731
		if exploration:
			game.battle.roster.clear()
			for i in range(count):
				game.battle.roster.append(["sword", "archer", "shield"][i % 3])
		game.battle.start_battle()
		game.visuals.reset_effects()
		if not exploration:
			game.battle.units.clear()
			game.battle.anchor = Vector2(600, 400)
			for i in range(count):
				game.battle.spawn_unit(["sword", "archer", "shield"][i % 3], i % 2, Vector2(65 + (i % 20) * 57, 220 + (i / 20) * 34))
		for unit in game.battle.units:
			unit.hp = 1000000.0
		game.update_camera()
		var label := "%d recruits/%d active exploration units" % [count, game.battle.units.size()] if exploration else "%d mixed units" % count
		var frame_times: Array[float] = []
		var last := Time.get_ticks_usec()
		for frame in range(140):
			await process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			if frame == 19:
				game.physics_samples.clear()
			if frame >= 20:
				frame_times.append((now - last) / 1000.0)
			last = now
		summarize(label + " frame interval (60 FPS cap)", frame_times)
		summarize(label + " scene physics CPU per tick", game.physics_samples)
	game.queue_free()
	await process_frame
	quit()
