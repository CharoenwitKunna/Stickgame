class_name BattleModel
extends RefCounted

const ARENA := Rect2(42, 0, 1196, 722)
# Read-only fallback: missing-cell lookups must not allocate a fresh empty array.
const EMPTY_BUCKET: Array = []
const MAX_ATTACKERS_PER_TARGET := 2
const MAX_SEPARATION_DISTANCE := 32.0
const MAX_PAIR_PUSH := 12.0
const BODY_RADII := {"sword": 14.0, "archer": 12.0, "shield": 16.0}
const BODY_MASSES := {"sword": 1.0, "archer": 0.75, "shield": 1.6}
const STATS := {
	"sword": {"name": "Swordsman", "hp": 85.0, "damage": 15.0, "range": 39.0, "speed": 155.0, "delay": 0.7, "cost": 2},
	"archer": {"name": "Archer", "hp": 48.0, "damage": 11.0, "range": 180.0, "speed": 145.0, "delay": 1.0, "cost": 3},
	"shield": {"name": "Shieldbearer", "hp": 165.0, "damage": 9.0, "range": 40.0, "speed": 130.0, "delay": 0.85, "cost": 4}
}

var units: Array[Dictionary] = []
var corpses: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var roster: Array[String] = ["sword", "sword", "sword", "shield"]
var stage := 1
var soul := 0
var anchor := Vector2(260, 440)
var move_target := Vector2.ZERO
var has_target := false
var outcome := ""
var next_id := 1
var next_effect_id := 1
var rng := RandomNumberGenerator.new()
var time := 0.0
var team_groups := [[], []]
var use_team_groups := false
var separation_buckets: Dictionary = {}
var separation_cells: Array[Vector2i] = []
var separation_scratch: Array[int] = []
var search_buckets := [{}, {}]
var search_order: Dictionary = {}
var use_search_grid := false

func _init() -> void:
	rng.randomize()

func start_battle() -> void:
	units.clear()
	team_groups[0].clear()
	team_groups[1].clear()
	search_buckets[0].clear()
	search_buckets[1].clear()
	search_order.clear()
	separation_buckets.clear()
	separation_cells.clear()
	separation_scratch.clear()
	use_team_groups = false
	use_search_grid = false
	corpses.clear()
	effects.clear()
	next_effect_id = 1
	soul = 0
	outcome = ""
	time = 0.0
	anchor = Vector2(260, 440)
	has_target = false
	for i in range(roster.size()):
		spawn_unit(roster[i], 0, clamp_point(anchor + slot_offset(i)))
	var enemy_count: int = maxi(4 + stage * 2, int(ceil(roster.size() * (0.9 + minf(stage * 0.04, 0.35)))))
	for i in range(enemy_count):
		var kind := "sword"
		if stage >= 2 and i % 4 == 0:
			kind = "archer"
		if stage >= 3 and i % 5 == 0:
			kind = "shield"
		var group: int = i % 3
		var center := Vector2(880 + group * 95, 270 + group * 150)
		spawn_unit(kind, 1, clamp_point(center + Vector2(rng.randf_range(-50, 50), rng.randf_range(-65, 65))))

func spawn_unit(kind: String, team: int, position: Vector2) -> Dictionary:
	var stats: Dictionary = STATS[kind]
	var unit := {"id": next_id, "kind": kind, "team": team, "pos": position,
		"hp": float(stats.hp), "max_hp": float(stats.hp), "cooldown": rng.randf_range(0.0, 0.4),
		"wander": position, "wander_timer": 0.0, "flash": 0.0, "step": rng.randf_range(0, TAU), "moving": false,
		"facing": 1.0 if team == 0 else -1.0, "attack": 0.0}
	next_id += 1
	units.append(unit)
	return unit

func slot_offset(index: int) -> Vector2:
	if index == 0:
		return Vector2.ZERO
	# Expanding rings keep a growing army together without a fixed deployment cap.
	var ring: int = int(ceil((sqrt(1.0 + index) - 1.0) * 1.5))
	var angle: float = index * 2.399963
	return Vector2(cos(angle), sin(angle)) * (25.0 + ring * 23.0)

func clamp_point(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, ARENA.position.x + 16, ARENA.end.x - 16), clampf(point.y, ARENA.position.y + 70, ARENA.end.y - 12))

func nearest_enemy(unit: Dictionary, radius: float, target_loads: Dictionary = {}) -> Dictionary:
	if use_team_groups and use_search_grid:
		return nearest_in_grid(unit, radius, target_loads)
	var result: Dictionary = {}
	var best := radius * radius
	# Groups preserve unit order and live dictionary references, including deaths/movement.
	var candidates: Array = team_groups[1 - int(unit.team)] if use_team_groups else units
	for other in candidates:
		if other.team == unit.team or other.hp <= 0:
			continue
		if int(target_loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
			continue
		var distance: float = (unit.pos as Vector2).distance_squared_to(other.pos)
		if distance < best:
			best = distance
			result = other
	return result

func clear_bucket_contents(buckets: Dictionary) -> void:
	# Retain bucket objects/keys across ticks; rebuild only their current contents.
	for cell in buckets:
		buckets[cell].clear()

func search_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / 128.0), floori(point.y / 128.0))

func move_search_entry(unit: Dictionary, previous: Vector2) -> void:
	var old_cell := search_cell(previous)
	var new_cell := search_cell(unit.pos)
	if old_cell == new_cell:
		return
	var buckets: Dictionary = search_buckets[int(unit.team)]
	buckets[old_cell].erase(unit)
	if not buckets.has(new_cell):
		buckets[new_cell] = []
	buckets[new_cell].append(unit)

func nearest_available_enemy(unit: Dictionary, radius: float, target_loads: Dictionary) -> Dictionary:
	var target: Dictionary = nearest_enemy(unit, radius, target_loads)
	# If every nearby defender already has a pair, allow overflow focus fire.
	return target if not target.is_empty() else nearest_enemy(unit, radius)

func nearest_in_grid(unit: Dictionary, radius: float, target_loads: Dictionary = {}) -> Dictionary:
	var point: Vector2 = unit.pos
	var low := search_cell(point - Vector2(radius, radius))
	var high := search_cell(point + Vector2(radius, radius))
	var buckets: Dictionary = search_buckets[1 - int(unit.team)]
	var best := radius * radius
	var result: Dictionary = {}
	var center := search_cell(point)
	# Seed with the containing cell, then prune cells that cannot beat that distance.
	for other in buckets.get(center, EMPTY_BUCKET):
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
			for other in buckets.get(Vector2i(x, y), EMPTY_BUCKET):
				if other.hp <= 0 or int(target_loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
					continue
				var distance: float = point.distance_squared_to(other.pos)
				if distance < best or (distance == best and not result.is_empty() and search_order[other.id] < search_order[result.id]):
					best = distance
					result = other
	return result


func tick(delta: float, direction: Vector2) -> void:
	if not outcome.is_empty():
		return
	time += delta
	if direction.length_squared() > 0:
		has_target = false
		anchor = clamp_point(anchor + direction.limit_length() * 125.0 * delta)
	elif has_target:
		anchor = clamp_point(anchor.move_toward(move_target, 125.0 * delta))
		if anchor.distance_to(move_target) < 3:
			has_target = false
	team_groups[0].clear()
	team_groups[1].clear()
	clear_bucket_contents(search_buckets[0])
	clear_bucket_contents(search_buckets[1])
	use_search_grid = units.size() >= 48
	for i in range(units.size()):
		var unit: Dictionary = units[i]
		if use_search_grid:
			var cell := search_cell(unit.pos)
			var buckets: Dictionary = search_buckets[int(unit.team)]
			if not buckets.has(cell):
				buckets[cell] = []
			buckets[cell].append(unit)
			search_order[unit.id] = i
		else:
			team_groups[int(unit.team)].append(unit)
	use_team_groups = true
	var attack_loads := [{}, {}]
	var chase_loads := [{}, {}]
	var friendly_index := 0
	for unit in units:
		if unit.hp <= 0:
			continue
		var stats: Dictionary = STATS[unit.kind]
		unit.cooldown = maxf(0, float(unit.cooldown) - delta)
		unit.flash = maxf(0, float(unit.flash) - delta)
		unit.attack = maxf(0, float(unit.attack) - delta)
		var old_position: Vector2 = unit.pos
		var destination: Vector2 = unit.pos
		if unit.team == 0:
			destination = clamp_point(anchor + slot_offset(friendly_index))
			friendly_index += 1
		else:
			var enemy: Dictionary = nearest_available_enemy(unit, 270.0, chase_loads[int(unit.team)])
			if not enemy.is_empty():
				chase_loads[int(unit.team)][enemy.id] = int(chase_loads[int(unit.team)].get(enemy.id, 0)) + 1
				if (unit.pos as Vector2).distance_to(enemy.pos) > float(stats.range) * 0.85:
					destination = enemy.pos
			else:
				unit.wander_timer = float(unit.wander_timer) - delta
				if unit.wander_timer <= 0 or (unit.pos as Vector2).distance_to(unit.wander) < 8:
					unit.wander = clamp_point(unit.pos + Vector2(rng.randf_range(-210, 210), rng.randf_range(-160, 160)))
					unit.wander_timer = rng.randf_range(2, 5)
				destination = unit.wander
		var speed: float = stats.speed
		if unit.team == 1:
			speed *= 0.65
		unit.pos = clamp_point((unit.pos as Vector2).move_toward(destination, speed * delta))
		if use_search_grid:
			move_search_entry(unit, old_position)
		unit.moving = old_position.distance_to(unit.pos) > 0.3
		if absf((unit.pos as Vector2).x - old_position.x) > 0.1:
			unit.facing = signf((unit.pos as Vector2).x - old_position.x)
		unit.step = float(unit.step) + delta * 11.0
		if unit.cooldown <= 0:
			var load_table: Dictionary = attack_loads[int(unit.team)]
			var target: Dictionary = nearest_available_enemy(unit, float(stats.range), load_table)
			if target.is_empty():
				continue
			load_table[target.id] = int(load_table.get(target.id, 0)) + 1
			unit.cooldown = float(stats.delay)
			unit.attack = 0.25
			if absf((target.pos as Vector2).x - (unit.pos as Vector2).x) > 0.1:
				unit.facing = signf((target.pos as Vector2).x - (unit.pos as Vector2).x)
			var damage: float = stats.damage
			if target.kind == "shield":
				damage *= 0.7
			target.hp = float(target.hp) - damage
			target.flash = 0.18
			effects.append({"visual_id": next_effect_id, "from": unit.pos, "to": target.pos, "ttl": 0.16, "archer": unit.kind == "archer", "team": unit.team})
			next_effect_id += 1
	use_team_groups = false
	separate_units(delta)
	collect_dead()
	for i in range(corpses.size() - 1, -1, -1):
		corpses[i].ttl = float(corpses[i].ttl) - delta
		if corpses[i].ttl <= 0:
			corpses.remove_at(i)
	for i in range(effects.size() - 1, -1, -1):
		effects[i].ttl = float(effects[i].ttl) - delta
		if effects[i].ttl <= 0:
			effects.remove_at(i)
	if alive_count(0) == 0:
		outcome = "defeat"
	elif alive_count(1) == 0:
		outcome = "victory"

func separate_units(delta: float) -> void:
	# Small armies avoid grid setup. Larger armies only test nearby pairs.
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
		# Dense buckets use the local ordered fallback below; do not send a single
		# crowded cell through an all-army quadratic pass.
	for i in range(units.size()):
		var a: Dictionary = units[i]
		var cursor: int = i + 1
		while cursor < units.size():
			var candidates := separation_candidates(a.pos, cursor)
			if candidates.size() > 12:
				# Local dense fallback preserves exact pair order but avoids building a
				# huge padded grid query or degrading the whole army to O(n^2).
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
					# A push can expose new neighbors. Re-query only later indices,
					# preserving the exact sequential pair order of the original loop.
					shifted = true
					break
			if not shifted:
				break

func separation_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / 64.0), floori(point.y / 64.0))

func separation_candidates(point: Vector2, first: int, radius: float = MAX_SEPARATION_DISTANCE) -> Array[int]:
	# Borrowed until the next query. Pair processing never nests another query.
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

func move_separation_entry(index: int, point: Vector2) -> void:
	var cell := separation_cell(point)
	var previous: Vector2i = separation_cells[index]
	if cell == previous:
		return
	separation_buckets[previous].erase(index)
	if not separation_buckets.has(cell):
		separation_buckets[cell] = []
	separation_buckets[cell].append(index)
	separation_cells[index] = cell

func push_pair(a: Dictionary, b: Dictionary, delta: float) -> bool:
	var offset: Vector2 = a.pos - b.pos
	var minimum_distance: float = float(BODY_RADII[a.kind]) + float(BODY_RADII[b.kind])
	var length: float = offset.length()
	if length >= minimum_distance:
		return false
	var normal: Vector2 = offset / length if length > 0.01 else Vector2.RIGHT
	var overlap: float = minimum_distance - length
	# Soft circle collisions with bounded positional correction; heavier shields
	# yield less, so a crowd opens around them instead of collapsing into them.
	var total_push: float = minf(overlap, minf(MAX_PAIR_PUSH, maxf(delta * 240.0, overlap * 0.45)))
	var inverse_a: float = 1.0 / float(BODY_MASSES[a.kind])
	var inverse_b: float = 1.0 / float(BODY_MASSES[b.kind])
	var inverse_total: float = inverse_a + inverse_b
	a.pos = clamp_point(a.pos + normal * total_push * inverse_a / inverse_total)
	b.pos = clamp_point(b.pos - normal * total_push * inverse_b / inverse_total)
	return true

func separate_brute(delta: float) -> void:
	for i in range(units.size()):
		for j in range(i + 1, units.size()):
			var a: Dictionary = units[i]
			var b: Dictionary = units[j]
			push_pair(a, b, delta)

func collect_dead() -> void:
	for i in range(units.size() - 1, -1, -1):
		var unit: Dictionary = units[i]
		if unit.hp > 0:
			continue
		if unit.team == 1:
			soul += 2
			corpses.append({"id": unit.id, "kind": unit.kind, "pos": unit.pos, "ttl": 14.0})
		search_order.erase(unit.id)
		units.remove_at(i)

func alive_count(team: int) -> int:
	var count := 0
	for unit in units:
		if unit.team == team and unit.hp > 0:
			count += 1
	return count

func corpse_at(point: Vector2) -> int:
	var nearest := -1
	var distance := 30.0 * 30.0
	for i in range(corpses.size()):
		var candidate: float = point.distance_squared_to(corpses[i].pos)
		if candidate < distance:
			nearest = i
			distance = candidate
	return nearest

func revive_at(point: Vector2) -> String:
	var index := corpse_at(point)
	return revive_corpse(int(corpses[index].id) if index >= 0 else -1)

func revive_corpse(corpse_id: int) -> String:
	if outcome == "defeat":
		return "Retry the battle to recruit again."
	var index := -1
	for i in range(corpses.size()):
		if int(corpses[i].id) == corpse_id:
			index = i
			break
	if index < 0:
		return "Hold right mouse over a fallen enemy inside its glowing ring."
	var corpse: Dictionary = corpses[index]
	var cost: int = STATS[corpse.kind].cost
	if soul < cost:
		return "Need %d Soul to raise this %s." % [cost, STATS[corpse.kind].name]
	soul -= cost
	roster.append(corpse.kind)
	spawn_unit(corpse.kind, 0, corpse.pos)
	corpses.remove_at(index)
	return "Raised %s — permanently in your army." % STATS[corpse.kind].name
