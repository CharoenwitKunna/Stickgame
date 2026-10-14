extends RefCounted

# Only the neighboring nine regions simulate. A bounded LRU keeps recently visited
# regions (including casualties); very distant, evicted regions repopulate on return.
const REGION_SIZE := 1200.0
const CACHE_LIMIT := 64
var seed_value := 1
var regions: Dictionary = {}
var active: Dictionary = {}
var center := Vector2i(2147483647, 2147483647)
var visits := 0

func reset(seed_number: int) -> void:
	seed_value = seed_number
	regions.clear()
	active.clear()
	center = Vector2i(2147483647, 2147483647)
	visits = 0

func cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / REGION_SIZE), floori(point.y / REGION_SIZE))

func generate(model, key: Vector2i) -> Array:
	var random := RandomNumberGenerator.new()
	random.seed = hash("%d:%d:%d" % [seed_value, key.x, key.y])
	var result: Array = []

	# Deterministic destination archetype for this region
	var roll := random.randf()
	var dest_type := "ruins"
	if key == Vector2i.ZERO:
		dest_type = "start"
	elif roll < 0.28:
		dest_type = "camp"
	elif roll < 0.52:
		dest_type = "shrine"
	elif roll < 0.76:
		dest_type = "patrol"
	else:
		dest_type = "ruins"

	var dest_pos := Vector2(key) * REGION_SIZE + Vector2(random.randf_range(280, 920), random.randf_range(280, 920))
	if dest_pos.distance_to(Vector2(260, 440)) < 550:
		dest_pos = Vector2(960, 900)

	var destination := {
		"type": dest_type,
		"pos": dest_pos,
		"region": key,
		"used": false,
		"title": "Enemy Outpost" if dest_type == "camp" else ("Restoration Shrine" if dest_type == "shrine" else ("Elite Patrol Route" if dest_type == "patrol" else "Ancient Ruins"))
	}

	# Generate enemy groups for this region
	var group_count := random.randi_range(1, 2)
	for group_idx in range(group_count):
		var home := dest_pos if group_idx == 0 else (Vector2(key) * REGION_SIZE + Vector2(random.randf_range(180, 1020), random.randf_range(180, 1020)))
		if home.distance_to(Vector2(260, 440)) < 550:
			home = Vector2(960, 900)

		var count := 4
		if dest_type == "camp" and group_idx == 0:
			# Concentrated enemy camp with guaranteed specialist recruit (count >= 14 for test_endless)
			count = random.randi_range(14, 20)
		elif dest_type == "shrine" and group_idx == 0:
			# Shrine sentry group (count <= 5 for test_endless)
			count = random.randi_range(2, 4)
		elif dest_type == "patrol" and group_idx == 0:
			# Elite patrol (count <= 5 for test_endless)
			count = random.randi_range(3, 5)
		else:
			var group_roll := random.randf()
			count = random.randi_range(2, 5) if group_roll < 0.5 else (random.randi_range(6, 10) if group_roll < 0.85 else random.randi_range(14, 24))

		for i in range(count):
			var kind: String = ["sword", "archer", "shield"][random.randi_range(0, 2)]
			var spread: float = 65.0 if dest_type == "camp" else 100.0
			var position := home + Vector2(random.randf_range(-spread, spread), random.randf_range(-spread, spread))
			var unit: Dictionary = model.spawn_unit(kind, 1, position)
			unit.home = home
			unit.region = key

			# Guaranteed specialist captain at enemy camps
			if dest_type == "camp" and group_idx == 0 and i == 0:
				unit.specialist = true
				unit.name = "Camp Captain"
				unit.max_hp = float(unit.max_hp) * 1.35
				unit.hp = unit.max_hp

			# Elite recruits in elite patrol
			if dest_type == "patrol" and group_idx == 0:
				unit.elite = true
				unit.name = "Elite Vanguard"
				unit.max_hp = float(unit.max_hp) * 1.25
				unit.hp = unit.max_hp

			result.append(unit)

	destination.units = result
	if regions.has(key):
		regions[key].destination = destination
	else:
		regions[key] = {"units": result, "visit": visits, "destination": destination}

	return result

func get_visible_landmarks(view_rect: Rect2) -> Array:
	var result: Array = []
	var low := cell(view_rect.position)
	var high := cell(view_rect.end)
	for x in range(low.x - 1, high.x + 2):
		for y in range(low.y - 1, high.y + 2):
			var k := Vector2i(x, y)
			if regions.has(k) and regions[k].has("destination"):
				result.append(regions[k].destination)
	return result


func update(model) -> void:
	var next := cell(model.anchor)
	if next == center:
		return
	center = next
	visits += 1
	var wanted: Dictionary = {}
	for x in range(center.x - 1, center.x + 2):
		for y in range(center.y - 1, center.y + 2):
			wanted[Vector2i(x, y)] = true
	for key in active:
		if wanted.has(key):
			continue
		var survivors: Array = []
		for i in range(model.units.size() - 1, -1, -1):
			var unit: Dictionary = model.units[i]
			if unit.team == 1 and unit.get("region", key) == key:
				# A pursuer near the player must not vanish at a region boundary.
				if (unit.pos as Vector2).distance_to(model.anchor) < 1000:
					unit.region = center
					continue
				survivors.push_front(unit)
				model.search_order.erase(unit.id)
				model.units.remove_at(i)
		regions[key].units = survivors
		if regions[key].has("destination"):
			regions[key].destination.units = survivors
	for key in wanted:
		if not active.has(key):
			if regions.has(key):
				for unit in regions[key].units:
					model.units.append(unit)
			else:
				# generate() installs both units and destination metadata.
				# Replacing that dictionary here used to erase every landmark.
				generate(model, key)
		regions[key].visit = visits
	active = wanted
	while regions.size() > CACHE_LIMIT:
		var oldest: Vector2i
		var oldest_visit := 2147483647
		for key in regions:
			if not active.has(key) and int(regions[key].visit) < oldest_visit:
				oldest = key
				oldest_visit = int(regions[key].visit)
		regions.erase(oldest)
	# Clear grid keys as the world moves, not just their contents.
	model.search_buckets[0].clear()
	model.search_buckets[1].clear()
	model.separation_buckets.clear()
