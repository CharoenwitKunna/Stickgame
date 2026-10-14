extends SceneTree

const Model = preload("res://scripts/battle_model.gd")

# Independent linear targeting and pairwise circle-collision reference; shares game rules only.
class Reference extends "res://scripts/battle_model.gd":
	func nearest_enemy(unit: Dictionary, radius: float, target_loads: Dictionary = {}) -> Dictionary:
		var result: Dictionary = {}
		var best := radius * radius
		var fallback: Dictionary = {}
		var fallback_distance := radius * radius
		for other in units:
			if other.team == unit.team or other.hp <= 0:
				continue
			var distance: float = (unit.pos as Vector2).distance_squared_to(other.pos)
			if not target_loads.is_empty() and distance < fallback_distance:
				fallback_distance = distance
				fallback = other
			if int(target_loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
				continue
			if distance < best:
				best = distance
				result = other
		return fallback if result.is_empty() else result

	func separate_units(delta: float) -> void:
		for i in range(units.size()):
			for j in range(i + 1, units.size()):
				var a: Dictionary = units[i]
				var b: Dictionary = units[j]
				var offset: Vector2 = a.pos - b.pos
				var minimum_distance: float = float(BODY_RADII[a.kind]) + float(BODY_RADII[b.kind])
				var length: float = offset.length()
				if length < minimum_distance:
					var normal: Vector2 = offset / length if length > 0.01 else Vector2.RIGHT
					var overlap: float = minimum_distance - length
					var total_push: float = minf(overlap, minf(MAX_PAIR_PUSH, maxf(delta * 240.0, overlap * 0.45)))
					var inverse_a: float = 1.0 / float(BODY_MASSES[a.kind])
					var inverse_b: float = 1.0 / float(BODY_MASSES[b.kind])
					var inverse_total: float = inverse_a + inverse_b
					a.pos = clamp_point(a.pos + normal * total_push * inverse_a / inverse_total)
					b.pos = clamp_point(b.pos - normal * total_push * inverse_b / inverse_total)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var comparisons := 0
	var distributed = Model.new()
	distributed.anchor = Vector2(500, 500)
	for i in range(4):
		var ally: Dictionary = distributed.spawn_unit("archer", 0, distributed.anchor + distributed.slot_offset(i))
		ally.cooldown = 0
	var first: Dictionary = distributed.spawn_unit("sword", 1, Vector2(500, 500))
	var second: Dictionary = distributed.spawn_unit("sword", 1, Vector2(560, 500))
	first.cooldown = 10
	second.cooldown = 10
	distributed.tick(0.01, Vector2.ZERO)
	if first.hp > 63 or second.hp > 63:
		push_error("Nearby target selection failed to distribute a four-unit volley")
		quit(1)
		return
	var physical = Model.new()
	for kind in ["sword", "archer", "shield"]:
		physical.spawn_unit(kind, 0, Vector2(500, 500))
	for frame in range(24):
		physical.separate_units(1.0 / 60.0)
	for a in range(physical.units.size()):
		for b in range(a + 1, physical.units.size()):
			var left: Dictionary = physical.units[a]
			var right: Dictionary = physical.units[b]
			var minimum: float = Model.BODY_RADII[left.kind] + Model.BODY_RADII[right.kind]
			if left.pos.distance_to(right.pos) < minimum - 1.0:
				push_error("Physical separation failed to resolve mixed-unit overlap")
				quit(1)
				return
	for seed_value in range(20):
		var fast = Model.new()
		var reference = Reference.new()
		for model in [fast, reference]:
			model.rng.seed = seed_value + 731
			model.stage = 3
			model.roster.clear()
			for i in range(24):
				model.roster.append(["sword", "archer", "shield"][i % 3])
			model.start_battle()
			model.anchor = Vector2(900, 420)
			# Also exercise coincident positions, distance boundaries, and ties.
			model.units[0].pos = Vector2(800, 400)
			model.units[1].pos = Vector2(800, 400)
			model.units[2].pos = Vector2(818, 400)
		for frame in range(180):
			var direction := Vector2.RIGHT if frame % 40 < 20 else Vector2.UP
			var delta: float = [1.0 / 60.0, 0.025, 0.05][frame % 3]
			fast.tick(delta, direction)
			reference.tick(delta, direction)
			if fast.units != reference.units or fast.corpses != reference.corpses or fast.effects != reference.effects or fast.soul != reference.soul or fast.outcome != reference.outcome or fast.anchor != reference.anchor:
				push_error("Optimized simulation diverged: seed %d frame %d" % [seed_value, frame])
				quit(1)
				return
			comparisons += 1
			if frame % 30 == 0 and not fast.corpses.is_empty():
				var point: Vector2 = fast.corpses[0].pos
				if fast.revive_at(point) != reference.revive_at(point):
					push_error("Recruitment diverged")
					quit(1)
					return
	# Larger populations stress dense fallback, cell crossings, and cumulative pushes.
	for scenario in range(12):
		var fast = Model.new()
		var reference = Reference.new()
		for model in [fast, reference]:
			model.rng.seed = scenario + 91
			for i in range(128):
				var point := Vector2(640, 320)
				if scenario % 3 == 1:
					point += Vector2((i % 12) * 15, (i / 12) * 15)
				elif scenario % 3 == 2:
					point = Vector2(model.rng.randf_range(58, 1222), model.rng.randf_range(70, 710))
				model.spawn_unit("sword", i % 2, point)
		for frame in range(12):
			var delta: float = 0.2 if frame % 2 else 1.0 / 60
			fast.separate_units(delta)
			reference.separate_units(delta)
			if fast.units != reference.units:
				push_error("Spatial separation diverged in stress scenario %d frame %d" % [scenario, frame])
				quit(1)
				return
			comparisons += 1
	# Equal-distance enemy ties must follow array order, not bucket or ID order.
	var fast_ties = Model.new()
	var reference_ties = Reference.new()
	for model in [fast_ties, reference_ties]:
		model.rng.seed = 25
		for i in range(64):
			var unit: Dictionary = model.spawn_unit("archer", i % 2, Vector2(512 + (20 if i % 4 < 2 else -20), 320))
			unit.cooldown = 0
		model.units.reverse()
		model.tick(0, Vector2.ZERO)
	if fast_ties.units != reference_ties.units or fast_ties.effects != reference_ties.effects:
		push_error("Equal-distance targeting order diverged")
		quit(1)
		return
	comparisons += 1
	print("PASS: %d exact comparisons against reference targeting/separation, including dense piles, ties, casualties and revival; nearby volleys distribute and mixed bodies collide" % comparisons)
	quit()
