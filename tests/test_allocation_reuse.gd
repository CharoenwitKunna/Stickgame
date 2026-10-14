extends SceneTree

const Model = preload("res://scripts/battle_model.gd")

# Same game rules; restore the previous bucket/query/rank storage and fresh
# empty default arrays for an independent allocation-path comparison.
class FreshStorage extends "res://scripts/battle_model.gd":
	func nearest_in_grid(unit: Dictionary, radius: float, target_loads: Dictionary = {}) -> Dictionary:
		if not target_loads.is_empty():
			return super.nearest_in_grid(unit, radius, target_loads)
		var point: Vector2 = unit.pos
		var low := search_cell(point - Vector2(radius, radius))
		var high := search_cell(point + Vector2(radius, radius))
		var buckets: Dictionary = search_buckets[1 - int(unit.team)]
		var best := radius * radius
		var result: Dictionary = {}
		var center := search_cell(point)
		for other in buckets.get(center, []):
			if other.hp <= 0 or int(target_loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
				continue
			var distance: float = point.distance_squared_to(other.pos)
			if distance < best or (distance == best and not result.is_empty() and search_order[other.id] < search_order[result.id]):
				best = distance
				result = other
		for x in range(low.x, high.x + 1):
			var dx: float = point.x - clampf(point.x, x * 128.0, (x + 1) * 128.0)
			var dx_sq: float = dx * dx
			if dx_sq > best:
				continue
			for y in range(low.y, high.y + 1):
				if Vector2i(x, y) == center:
					continue
				var dy: float = point.y - clampf(point.y, y * 128.0, (y + 1) * 128.0)
				if dx_sq + dy * dy > best:
					continue
				for other in buckets.get(Vector2i(x, y), []):
					if other.hp <= 0 or int(target_loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
						continue
					var distance: float = point.distance_squared_to(other.pos)
					if distance < best or (distance == best and not result.is_empty() and search_order[other.id] < search_order[result.id]):
						best = distance
						result = other
		return result
	func clear_bucket_contents(buckets: Dictionary) -> void:
		buckets.clear()
	func tick(delta: float, direction: Vector2) -> void:
		search_order.clear()
		super.tick(delta, direction)
	func separation_candidates(point: Vector2, first: int, radius: float = MAX_SEPARATION_DISTANCE) -> Array[int]:
		var candidates: Array[int] = []
		var low := separation_cell(point - Vector2(radius, radius))
		var high := separation_cell(point + Vector2(radius, radius))
		for x in range(low.x, high.x + 1):
			for y in range(low.y, high.y + 1):
				for index in separation_buckets.get(Vector2i(x, y), []):
					if index >= first:
						candidates.append(index)
		candidates.sort()
		return candidates

var checks := 0
var failures := 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var model = Model.new()
	model.rng.seed = 731
	for i in range(64):
		model.spawn_unit("sword", i % 2, Vector2(100 + (i % 16) * 65, 120 + (i / 16) * 65))
	model.tick(0, Vector2.ZERO)
	var first_cell = model.search_buckets[0].keys()[0]
	var first_bucket: Array = model.search_buckets[0][first_cell]
	var separation_cell = model.separation_buckets.keys()[0]
	var separation_bucket: Array = model.separation_buckets[separation_cell]
	model.tick(0, Vector2.ZERO)
	expect(is_same(first_bucket, model.search_buckets[0][first_cell]), "Targeting reuses bucket objects")
	expect(is_same(separation_bucket, model.separation_buckets[separation_cell]), "Separation reuses bucket objects")
	var candidates: Array[int] = model.separation_candidates(model.units[0].pos, 0)
	expect(not candidates.is_empty(), "Nearby candidate query finds units")
	expect(is_same(candidates, model.separation_scratch), "Candidate query borrows the reusable buffer")
	var empty: Array[int] = model.separation_candidates(Vector2(-1000, -1000), 0)
	expect(empty.is_empty() and is_same(empty, candidates), "Next query clears rather than leaking previous candidates")
	model.units[0].hp = 0
	var dead_id: int = model.units[0].id
	model.collect_dead()
	expect(not model.search_order.has(dead_id), "Collected deaths remove cached targeting ranks")
	model.units.reverse()
	model.tick(0, Vector2.ZERO)
	for i in range(model.units.size()):
		expect(model.search_order[model.units[i].id] == i, "Targeting rank follows current array order")
	model.start_battle()
	expect(model.search_order.is_empty() and model.search_buckets[0].is_empty() and model.search_buckets[1].is_empty(), "New battle releases old targeting references")

	# Exercise shrink/grow across grid thresholds, old occupied cells becoming
	# empty, simultaneous deaths, reverse ordering, stage reset, and recruitment.
	for seed_value in range(6):
		var pooled = Model.new()
		var fresh = FreshStorage.new()
		for game in [pooled, fresh]:
			game.rng.seed = 731 + seed_value
			for i in range(96):
				game.spawn_unit(["sword", "archer", "shield"][i % 3], i % 2,
					Vector2(65 + (i % 20) * 57, 220 + (i / 20) * 34))
		for frame in range(90):
			for game in [pooled, fresh]:
				if frame == 15:
					for i in range(56):
						game.units[i].hp = 0
					game.collect_dead()
				if frame == 16:
					game.units.reverse()
					game.soul = 1000
					for i in range(12):
						game.revive_at(game.corpses[0].pos)
				if frame == 45:
					game.stage = 3
					game.start_battle()
				game.tick([1.0 / 60, 0.025, 0.05][frame % 3], Vector2.RIGHT)
			expect(pooled.units == fresh.units and pooled.corpses == fresh.corpses and
				pooled.effects == fresh.effects and pooled.soul == fresh.soul and
				pooled.outcome == fresh.outcome and pooled.anchor == fresh.anchor,
				"Pooled storage diverged: seed %d frame %d" % [seed_value, frame])
	print("ALLOCATION REUSE: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	if "--bench" in OS.get_cmdline_user_args():
		benchmark()
	quit()

func benchmark() -> void:
	for count in [10, 128, 256]:
		var pooled_samples: Array[float] = []
		var fresh_samples: Array[float] = []
		for trial in range(9):
			var games := [Model.new(), FreshStorage.new()]
			for game in games:
				game.rng.seed = 731 + trial
				for i in range(count):
					var unit: Dictionary = game.spawn_unit("sword", i % 2,
						Vector2(65 + (i % 20) * 57, 220 + (i / 20) * 34))
					unit.hp = 1000000.0
				for frame in range(60):
					game.tick(1.0 / 60, Vector2.RIGHT)
			# Alternate timing order to reduce thermal/order bias.
			for index in ([0, 1] if trial % 2 == 0 else [1, 0]):
				var begin := Time.get_ticks_usec()
				for frame in range(120):
					games[index].tick(1.0 / 60, Vector2.RIGHT)
				var sample := (Time.get_ticks_usec() - begin) / 120000.0
				if index == 0:
					pooled_samples.append(sample)
				else:
					fresh_samples.append(sample)
			assert(games[0].units == games[1].units)
		var pooled_mean := 0.0
		var fresh_mean := 0.0
		for sample in pooled_samples:
			pooled_mean += sample / pooled_samples.size()
		for sample in fresh_samples:
			fresh_mean += sample / fresh_samples.size()
		print("PAIRED STORAGE %d units: fresh %.3f ms/tick, pooled %.3f ms/tick; %.1f%% CPU reduction (9 seeds, 60 warm-up + 120 ticks each)" % [count, fresh_mean, pooled_mean, (fresh_mean - pooled_mean) / fresh_mean * 100])
