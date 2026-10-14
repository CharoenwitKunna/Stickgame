extends SceneTree

const Model = preload("res://scripts/battle_model.gd")
const Main = preload("res://main.tscn")

class ProfiledView extends "res://scripts/battlefield_view.gd":
	var draw_samples: Array[int] = []
	func _draw() -> void:
		var begin := Time.get_ticks_usec()
		super._draw()
		draw_samples.append(Time.get_ticks_usec() - begin)

func _initialize() -> void:
	call_deferred("run")

func report(label: String, samples: Array[int]) -> void:
	samples.sort()
	var total := 0.0
	for sample in samples:
		total += sample
	print("BENCH %s: mean %.3f ms, p50 %.3f ms, p95 %.3f ms (%d samples)" % [label, total / samples.size() / 1000.0, samples[samples.size() / 2] / 1000.0, samples[int(samples.size() * 0.95)] / 1000.0, samples.size()])

func run() -> void:
	# Seeded no-casualty runs measure steady simulation cost at growing army sizes.
	for count in [10, 128, 256]:
		var samples: Array[int] = []
		for trial in range(5):
			var model = Model.new()
			model.rng.seed = 731
			for i in range(count):
				var team: int = i % 2
				var unit: Dictionary = model.spawn_unit("sword", team, Vector2(65 + (i % 20) * 57, 220 + (i / 20) * 34))
				unit.hp = 1000000.0
			for i in range(15):
				model.tick(1.0 / 60, Vector2.RIGHT)
			var begin := Time.get_ticks_usec()
			for i in range(30):
				model.tick(1.0 / 60, Vector2.RIGHT)
			samples.append((Time.get_ticks_usec() - begin) / 30)
		report("simulation %d units" % count, samples)
	if DisplayServer.get_name() == "headless":
		quit()
		return
	var game = Main.instantiate()
	game.save_path = "user://benchmark_unused.json"
	root.add_child(game)
	game.set_physics_process(false)
	game.visuals.free()
	var view := ProfiledView.new()
	view.battle = game.battle
	game.visuals = view
	game.add_child(view)
	game.move_child(view, game.scenery.get_index() + 1)
	for count in [10, 128]:
		game.battle.units.clear()
		for i in range(count):
			game.battle.spawn_unit("sword", i % 2, Vector2(70 + (i % 20) * 57, 230 + (i / 20) * 50))
		view.draw_samples.clear()
		for frame in range(35):
			view.animate(1.0 / 60)
			await process_frame
			await RenderingServer.frame_post_draw
		for i in range(mini(5, view.draw_samples.size())):
			view.draw_samples.pop_front()
		report("draw-command CPU %d units" % count, view.draw_samples)
	game.queue_free()
	await process_frame
	quit()
