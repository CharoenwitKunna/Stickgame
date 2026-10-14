extends SceneTree

const Model = preload("res://scripts/battle_model.gd")

# Preserve the audited targeting/collision/formation hot paths independently.
# Current streaming, save rules and other game rules are shared, so these timings
# isolate the optimizations rather than comparing different gameplay versions.
class Legacy extends "res://scripts/battle_model.gd":
	func _init() -> void:
		reuse_empty_chase_search = false
	func slot_offset(index: int) -> Vector2:
		if index == 0:
			return Vector2.ZERO
		var ring := int(ceil((sqrt(1.0 + index) - 1.0) * 1.5))
		var angle: float = index * 2.399963
		return Vector2(cos(angle), sin(angle)) * (25.0 + ring * 23.0)
	func nearest_available_enemy(unit: Dictionary, radius: float, loads: Dictionary) -> Dictionary:
		var target: Dictionary = nearest_enemy(unit, radius, loads)
		return target if not target.is_empty() else nearest_enemy(unit, radius)
	func nearest_enemy(unit: Dictionary, radius: float, loads: Dictionary = {}) -> Dictionary:
		if use_team_groups and use_search_grid:
			return nearest_in_grid(unit, radius, loads)
		var result: Dictionary = {}
		var best := radius * radius
		var candidates: Array = team_groups[1 - int(unit.team)] if use_team_groups else units
		for other in candidates:
			if other.team == unit.team or other.hp <= 0 or int(loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
				continue
			var distance: float = (unit.pos as Vector2).distance_squared_to(other.pos)
			if distance < best:
				best = distance
				result = other
		return result
	func nearest_in_grid(unit: Dictionary, radius: float, loads: Dictionary = {}) -> Dictionary:
		var point: Vector2 = unit.pos
		var low := search_cell(point - Vector2(radius, radius))
		var high := search_cell(point + Vector2(radius, radius))
		var buckets: Dictionary = search_buckets[1 - int(unit.team)]
		var best := radius * radius
		var result: Dictionary = {}
		var center := search_cell(point)
		for other in buckets.get(center, EMPTY_BUCKET):
			if other.hp <= 0 or int(loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
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
				for other in buckets.get(Vector2i(x, y), EMPTY_BUCKET):
					if other.hp <= 0 or int(loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
						continue
					var distance: float = point.distance_squared_to(other.pos)
					if distance < best or (distance == best and not result.is_empty() and search_order[other.id] < search_order[result.id]):
						best = distance
						result = other
		return result
	func separation_candidates(point: Vector2, first: int, radius: float = MAX_SEPARATION_DISTANCE) -> Array[int]:
		var candidates: Array[int] = separation_scratch
		candidates.clear()
		var low := separation_cell(point - Vector2(radius, radius))
		var high := separation_cell(point + Vector2(radius, radius))
		for x in range(low.x, high.x + 1):
			for y in range(low.y, high.y + 1):
				for index in separation_buckets.get(Vector2i(x, y), EMPTY_BUCKET):
					if index >= first:
						candidates.append(index)
		candidates.sort()
		return candidates
	func separate_units(delta: float) -> void:
		if units.size() <= 24:
			separate_brute(delta)
			return
		clear_bucket_contents(separation_buckets)
		separation_cells.resize(units.size())
		for i in range(units.size()):
			if units[i].pos != clamp_point(units[i].pos):
				separate_brute(delta)
				return
			var cell := separation_cell(units[i].pos)
			separation_cells[i] = cell
			if not separation_buckets.has(cell):
				separation_buckets[cell] = []
			separation_buckets[cell].append(i)
		for i in range(units.size()):
			var a: Dictionary = units[i]
			var cursor := i + 1
			while cursor < units.size():
				var candidates := separation_candidates(a.pos, cursor)
				if candidates.size() > 12:
					for j in range(cursor, units.size()):
						var b: Dictionary = units[j]
						if push_pair(a, b, delta):
							move_separation_entry(i, a.pos)
							move_separation_entry(j, b.pos)
					break
				var shifted := false
				for j in candidates:
					cursor = j + 1
					var b: Dictionary = units[j]
					var previous: Vector2 = a.pos
					if push_pair(a, b, delta):
						move_separation_entry(i, a.pos)
						move_separation_entry(j, b.pos)
					if a.pos != previous:
						shifted = true
						break
				if not shifted:
					break

func _initialize() -> void:
	call_deferred("run")

func setup(model, label: String, count: int, seed_value: int) -> void:
	model.rng.seed = seed_value
	model.endless = true
	if label == "endless":
		model.start_battle()
	else:
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
	for frame in range(10):
		model.tick(1.0 / 60, Vector2.ZERO)

func mean(samples: Array[float]) -> float:
	var total := 0.0
	for sample in samples:
		total += sample
	return total / samples.size()

func run() -> void:
	print("PAIRED CPU: 3 seeds, alternating order, 10 warm-up + 60 measured ticks per model. Exact state equality required. FPS/GPU not measured.")
	for scenario in [["mixed", 128], ["mixed", 256], ["dense", 256], ["no-contact", 256], ["endless", 4]]:
		var old_samples: Array[float] = []
		var new_samples: Array[float] = []
		for trial in range(3):
			var old := Legacy.new()
			var current = Model.new()
			for simulation in [old, current]:
				setup(simulation, scenario[0], scenario[1], 731 + trial)
			for simulation in ([old, current] if trial % 2 == 0 else [current, old]):
				for frame in range(60):
					var begin := Time.get_ticks_usec()
					simulation.tick(1.0 / 60, Vector2.ZERO)
					var sample := (Time.get_ticks_usec() - begin) / 1000.0
					if simulation == old:
						old_samples.append(sample)
					else:
						new_samples.append(sample)
			if old.units != current.units or old.corpses != current.corpses or old.effects != current.effects or old.soul != current.soul or old.rng.state != current.rng.state:
				push_error("Paired benchmark behavior diverged: %s seed %d" % [scenario[0], trial])
				quit(1)
				return
		old_samples.sort()
		new_samples.sort()
		print("PAIRED %s %d: legacy %.3f -> current %.3f ms/tick (%.1f%% CPU reduction); p95 %.3f -> %.3f; states identical" % [scenario[0], scenario[1], mean(old_samples), mean(new_samples), (mean(old_samples) - mean(new_samples)) / mean(old_samples) * 100, old_samples[171], new_samples[171]])
	quit()
