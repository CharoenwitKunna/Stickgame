class_name BattleModel
extends RefCounted

const ARENA := Rect2(42, 0, 1196, 722)
const Wilderness = preload("res://scripts/wilderness.gd")
var endless := false
var wilderness = Wilderness.new()
# Read-only fallback: missing-cell lookups must not allocate a fresh empty array.
const EMPTY_BUCKET: Array = []
const MAX_ATTACKERS_PER_TARGET := 2
const CHASE_RADIUS := 270.0
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
var reuse_empty_chase_search := true
var overflow_enemy: Dictionary = {}
var query_has_overflow := false
var search_cells_scratch: Array[Vector2i] = []
var occupied_slots: Dictionary = {}
var slot_unit_count := 0
var first_free_slot := 0
var slot_offsets: Array[Vector2] = [Vector2.ZERO]

func _init() -> void:
	rng.randomize()

func start_battle() -> void:
	units.clear()
	occupied_slots.clear()
	slot_unit_count = 0
	first_free_slot = 0
	overflow_enemy = {}
	search_cells_scratch.clear()
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
	if endless:
		wilderness.reset(rng.randi())
		wilderness.update(self)
		return
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
	# Remember invalidation even if an enemy spawn restores the old array length.
	if slot_unit_count != units.size():
		slot_unit_count = -1
	var stats: Dictionary = STATS[kind]
	var unit := {"id": next_id, "kind": kind, "team": team, "pos": position,
		"hp": float(stats.hp), "max_hp": float(stats.hp), "cooldown": rng.randf_range(0.0, 0.4),
		"wander": position, "wander_timer": 0.0, "flash": 0.0, "step": rng.randf_range(0, TAU), "moving": false,
		"facing": 1.0 if team == 0 else -1.0, "attack": 0.0}
	if team == 0:
		sync_formation_slots()
		unit.slot = first_free_slot
		occupied_slots[first_free_slot] = true
		while occupied_slots.has(first_free_slot):
			first_free_slot += 1
	next_id += 1
	units.append(unit)
	if team == 0 or slot_unit_count == units.size() - 1:
		slot_unit_count = units.size()
	return unit

func sync_formation_slots() -> void:
	# Population streaming/external edits invalidate the index; reconcile once.
	if slot_unit_count == units.size():
		return
	occupied_slots.clear()
	first_free_slot = 0
	for ally in units:
		if ally.team == 0:
			occupied_slots[int(ally.slot)] = true
	while occupied_slots.has(first_free_slot):
		first_free_slot += 1
	slot_unit_count = units.size()

func slot_offset(index: int) -> Vector2:
	# Formation geometry is immutable; do its square root/trig once per slot.
	while slot_offsets.size() <= index:
		var next := slot_offsets.size()
		var ring: int = int(ceil((sqrt(1.0 + next) - 1.0) * 1.5))
		var angle: float = next * 2.399963
		slot_offsets.append(Vector2(cos(angle), sin(angle)) * (25.0 + ring * 23.0))
	return slot_offsets[index]

func clamp_point(point: Vector2) -> Vector2:
	if endless:
		return point
	return Vector2(clampf(point.x, ARENA.position.x + 16, ARENA.end.x - 16), clampf(point.y, ARENA.position.y + 70, ARENA.end.y - 12))

func nearest_enemy(unit: Dictionary, radius: float, target_loads: Dictionary = {}) -> Dictionary:
	if use_team_groups and use_search_grid:
		return nearest_in_grid(unit, radius, target_loads)
	query_has_overflow = true
	overflow_enemy = {}
	var overflow_best := radius * radius
	var result: Dictionary = {}
	var best := radius * radius
	# Groups preserve unit order and live dictionary references, including deaths/movement.
	var candidates: Array = team_groups[1 - int(unit.team)] if use_team_groups else units
	for other in candidates:
		if other.team == unit.team or other.hp <= 0:
			continue
		var distance: float = (unit.pos as Vector2).distance_squared_to(other.pos)
		if int(target_loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
			if distance < overflow_best:
				overflow_best = distance
				overflow_enemy = other
			continue
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
	query_has_overflow = false
	var target: Dictionary = nearest_enemy(unit, radius, target_loads)
	if not target.is_empty():
		return target
	# The production query also finds the unrestricted fallback in the same pass.
	# Keep legacy overrides (including the independent test oracle) compatible.
	return overflow_enemy if query_has_overflow else nearest_enemy(unit, radius)

func nearest_in_grid(unit: Dictionary, radius: float, target_loads: Dictionary = {}) -> Dictionary:
	query_has_overflow = true
	overflow_enemy = {}
	var overflow_best := radius * radius
	var point: Vector2 = unit.pos
	var low := search_cell(point - Vector2(radius, radius))
	var high := search_cell(point + Vector2(radius, radius))
	var buckets: Dictionary = search_buckets[1 - int(unit.team)]
	var best := radius * radius
	var result: Dictionary = {}
	var center := search_cell(point)
	# Find a tight bound in the containing cell before probing its neighbors.
	for other in buckets.get(center, EMPTY_BUCKET):
		if other.hp <= 0:
			continue
		var distance: float = point.distance_squared_to(other.pos)
		if int(target_loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
			if distance < overflow_best or (distance == overflow_best and not overflow_enemy.is_empty() and search_order[other.id] < search_order[overflow_enemy.id]):
				overflow_best = distance
				overflow_enemy = other
			continue
		if distance < best or (distance == best and not result.is_empty() and search_order[other.id] < search_order[result.id]):
			best = distance
			result = other
	search_cells_scratch.clear()
	# A small opposing army occupies fewer cells than a normal radius query.
	# Iterate its keys instead of probing dozens of empty cells per idle enemy.
	if buckets.size() <= 8 and buckets.size() < (high.x - low.x + 1) * (high.y - low.y + 1):
		for cell in buckets:
			if cell != center and cell.x >= low.x and cell.x <= high.x and cell.y >= low.y and cell.y <= high.y:
				search_cells_scratch.append(cell)
	else:
		for x in range(low.x, high.x + 1):
			var dx: float = point.x - clampf(point.x, x * 128.0, (x + 1) * 128.0)
			if dx * dx > best:
				continue
			for y in range(low.y, high.y + 1):
				var cell := Vector2i(x, y)
				if cell != center:
					search_cells_scratch.append(cell)
	for cell in search_cells_scratch:
		var dx: float = point.x - clampf(point.x, cell.x * 128.0, (cell.x + 1) * 128.0)
		var dy: float = point.y - clampf(point.y, cell.y * 128.0, (cell.y + 1) * 128.0)
		if dx * dx + dy * dy > best:
			continue
		for other in buckets.get(cell, EMPTY_BUCKET):
			if other.hp <= 0:
				continue
			var distance: float = point.distance_squared_to(other.pos)
			if int(target_loads.get(other.id, 0)) >= MAX_ATTACKERS_PER_TARGET:
				if distance < overflow_best or (distance == overflow_best and not overflow_enemy.is_empty() and search_order[other.id] < search_order[overflow_enemy.id]):
					overflow_best = distance
					overflow_enemy = other
				continue
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
	if endless:
		wilderness.update(self)
		check_recovery_shrines()
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
	for unit in units:
		if unit.hp <= 0:
			continue
		var stats: Dictionary = STATS[unit.kind]
		unit.cooldown = maxf(0, float(unit.cooldown) - delta)
		unit.flash = maxf(0, float(unit.flash) - delta)
		unit.attack = maxf(0, float(unit.attack) - delta)
		var old_position: Vector2 = unit.pos
		var destination: Vector2 = unit.pos
		var no_nearby_enemy := false
		if unit.team == 0:
			var formation_pos: Vector2 = clamp_point(anchor + slot_offset(int(unit.slot)))
			var is_commanded: bool = (direction.length_squared() > 0 or has_target)
			var anchor_dist: float = (unit.pos as Vector2).distance_to(anchor)
			var enemy: Dictionary = {}
			# Tethered engagement: seek foes when within army tether radius
			if not is_commanded or anchor_dist < 200.0:
				enemy = nearest_available_enemy(unit, CHASE_RADIUS, chase_loads[0])
				no_nearby_enemy = enemy.is_empty()
			if not enemy.is_empty():
				chase_loads[0][enemy.id] = int(chase_loads[0].get(enemy.id, 0)) + 1
				var to_enemy: Vector2 = (enemy.pos as Vector2) - (unit.pos as Vector2)
				var dist_to_enemy: float = to_enemy.length()
				if unit.kind == "archer":
					# Archers advance into firing range or step back if rushed
					if dist_to_enemy > float(stats.range) * 0.82:
						destination = enemy.pos
					elif dist_to_enemy < 50.0 and anchor_dist < 160.0:
						destination = formation_pos
					else:
						destination = unit.pos
				else:
					# Melee units (swordsmen & shieldbearers) charge and swarm around the target
					var attack_margin: float = float(stats.range) * 0.8
					if dist_to_enemy > attack_margin:
						var approach: Vector2 = -to_enemy.normalized() if dist_to_enemy > 0.01 else Vector2.RIGHT
						destination = clamp_point((enemy.pos as Vector2) + approach * (float(stats.range) * 0.65))
					else:
						destination = unit.pos
			else:
				destination = formation_pos
		else:
			var enemy: Dictionary = nearest_available_enemy(unit, CHASE_RADIUS, chase_loads[1])
			no_nearby_enemy = enemy.is_empty()
			if not enemy.is_empty():
				chase_loads[1][enemy.id] = int(chase_loads[1].get(enemy.id, 0)) + 1
				var to_target: Vector2 = (enemy.pos as Vector2) - (unit.pos as Vector2)
				var dist: float = to_target.length()
				if unit.kind == "archer":
					if dist > float(stats.range) * 0.85:
						destination = enemy.pos
					else:
						destination = unit.pos
				else:
					var attack_margin: float = float(stats.range) * 0.85
					if dist > attack_margin:
						var approach: Vector2 = -to_target.normalized() if dist > 0.01 else Vector2.RIGHT
						destination = clamp_point((enemy.pos as Vector2) + approach * (float(stats.range) * 0.65))
					else:
						destination = unit.pos
			else:
				unit.wander_timer = float(unit.wander_timer) - delta
				if unit.wander_timer <= 0 or (unit.pos as Vector2).distance_to(unit.wander) < 8:
					var home: Vector2 = unit.get("home", unit.pos)
					unit.wander = clamp_point(home + Vector2(rng.randf_range(-210, 210), rng.randf_range(-160, 160)))
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
		# Reuse a proven empty chase radius only when this step cannot cross its
		# gap to attack range. Large deltas still query; cooldown/timing is unchanged.
		if unit.cooldown <= 0 and (not reuse_empty_chase_search or not no_nearby_enemy or old_position.distance_to(unit.pos) + float(stats.range) > CHASE_RADIUS):
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
	elif not endless and alive_count(1) == 0:
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
	for i in range(units.size()):
		var a: Dictionary = units[i]
		var cursor: int = i + 1
		# Sparse cells need no padding; dense cells amortize repeated push queries.
		var padding: float = MAX_PAIR_PUSH if separation_buckets[separation_cells[i]].size() > 12 else 0.0
		while cursor < units.size():
			var query_origin: Vector2 = a.pos
			# Padding keeps this ordered list valid through small sequential pushes.
			# An omitted body cannot touch A until A has moved beyond the padding.
			var candidates := separation_candidates(query_origin, cursor, MAX_SEPARATION_DISTANCE + padding)
			var shifted := false
			for j in candidates:
				cursor = j + 1
				var b: Dictionary = units[j]
				if push_pair(a, b, delta):
					move_separation_entry(i, a.pos)
					move_separation_entry(j, b.pos)
				if query_origin.distance_squared_to(a.pos) > padding * padding:
					# Resume at the next array index, never revisiting an earlier pair.
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
				if index >= first and point.distance_squared_to(units[index].pos) < radius * radius:
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

func check_recovery_shrines() -> void:
	for key in wilderness.active:
		var reg: Dictionary = wilderness.regions.get(key, {})
		var dest: Dictionary = reg.get("destination", {})
		if dest.get("type", "") == "shrine" and not dest.get("used", false):
			if (dest.pos as Vector2).distance_to(anchor) < 80.0:
				activate_recovery_shrine(dest)

func activate_recovery_shrine(dest: Dictionary) -> void:
	dest.used = true
	# Fully heal all living friendly soldiers
	for unit in units:
		if unit.team == 0 and unit.hp > 0:
			unit.hp = float(unit.max_hp)
			unit.flash = 0.25
	# Restore fallen allies from roster casualties
	var alive_friends := alive_count(0)
	if roster.size() > alive_friends:
		var to_restore := mini(roster.size() - alive_friends, 2)
		for i in range(to_restore):
			var kind: String = roster[alive_friends + i]
			spawn_unit(kind, 0, dest.pos + Vector2((float(i) - 0.5) * 28.0, 16.0))
	effects.append({"visual_id": next_effect_id, "from": dest.pos, "to": dest.pos, "ttl": 0.6, "shrine": true, "team": 0})
	next_effect_id += 1

func is_combat_active(radius: float = 360.0) -> bool:
	for other in units:
		if other.team == 1 and other.hp > 0:
			if (other.pos as Vector2).distance_to(anchor) < radius:
				return true
	return false

func collect_dead() -> void:
	sync_formation_slots()
	for i in range(units.size() - 1, -1, -1):
		var unit: Dictionary = units[i]
		if unit.hp > 0:
			continue
		if unit.team == 1:
			soul += 2
			var corpse := {"id": unit.id, "kind": unit.kind, "pos": unit.pos, "ttl": 14.0}
			if unit.get("specialist", false):
				corpse.specialist = true
			if unit.get("elite", false):
				corpse.elite = true
			corpses.append(corpse)
		if unit.team == 0:
			occupied_slots.erase(int(unit.slot))
			first_free_slot = mini(first_free_slot, int(unit.slot))
		search_order.erase(unit.id)
		units.remove_at(i)
	slot_unit_count = units.size()

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
	var recruit: Dictionary = spawn_unit(corpse.kind, 0, corpse.pos)
	var is_spec: bool = corpse.get("specialist", false)
	var is_elite: bool = corpse.get("elite", false)
	if is_spec:
		recruit.specialist = true
		recruit.max_hp = float(recruit.max_hp) * 1.35
		recruit.hp = recruit.max_hp
	elif is_elite:
		recruit.elite = true
		recruit.max_hp = float(recruit.max_hp) * 1.25
		recruit.hp = recruit.max_hp
	corpses.remove_at(index)
	var prefix := "Veteran " if is_spec else ("Elite " if is_elite else "")
	return "Raised %s%s — permanently in your army." % [prefix, STATS[corpse.kind].name]
