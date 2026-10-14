extends SceneTree

const Model = preload("res://scripts/battle_model.gd")
const View = preload("res://scripts/battlefield_view.gd")
const World = preload("res://scripts/world_scenery.gd")
const Oracle = preload("res://tests/test_optimization.gd")

class CountedModel extends "res://scripts/battle_model.gd":
	var queries := 0
	func nearest_enemy(unit: Dictionary, radius: float, loads: Dictionary = {}) -> Dictionary:
		queries += 1
		return super.nearest_enemy(unit, radius, loads)

# Original rendering path, with the same geometry and fixed landmark metadata.
# This tests culling, compositing order, cache invalidation and actual GPU pixels.
class UncachedWorld extends "res://scripts/world_scenery.gd":
	func _ready() -> void:
		super._ready()
		background.hide()
	func update_view(rectangle: Rect2) -> void:
		view_rect = rectangle
		queue_redraw()
	func _draw() -> void:
		draw_background(self)
		var low := Vector2i(floori(view_rect.position.x / REGION_SIZE), floori(view_rect.position.y / REGION_SIZE))
		var high := Vector2i(floori(view_rect.end.x / REGION_SIZE), floori(view_rect.end.y / REGION_SIZE))
		for x in range(low.x - 1, high.x + 2):
			for y in range(low.y - 1, high.y + 2):
				draw_region_terrain_features(Vector2i(x, y))
		for dest in wilderness.get_visible_landmarks(view_rect):
			draw_landmark(dest)

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func model_checks() -> void:
	var model = Model.new()
	model.endless = true
	for i in range(256):
		model.spawn_unit("sword", 1, Vector2.ZERO)
		check(model.spawn_unit("archer", 0, Vector2.ZERO).slot == i, "Interleaved spawning preserves unique compact slots")
	model.units[7].hp = 0 # Friendly slot 3
	model.units[15].hp = 0 # Friendly slot 7
	model.collect_dead()
	check(model.spawn_unit("shield", 0, Vector2.ZERO).slot == 3, "Recruit reuses the lowest casualty slot")
	check(model.spawn_unit("shield", 0, Vector2.ZERO).slot == 7, "Recruit reuses the next casualty slot")
	model.units.remove_at(3) # External removal of friendly slot 1
	model.spawn_unit("sword", 1, Vector2.ZERO)
	check(model.spawn_unit("sword", 0, Vector2.ZERO).slot == 1, "External edits plus enemy spawning reconcile occupied slots")
	model.units.clear()
	model.collect_dead()
	check(model.spawn_unit("sword", 0, Vector2.ZERO).slot == 0, "External clear does not retain stale occupied slots")
	for i in range(1024):
		var expected := Vector2.ZERO
		if i > 0:
			var ring := int(ceil((sqrt(1.0 + i) - 1.0) * 1.5))
			var angle: float = i * 2.399963
			expected = Vector2(cos(angle), sin(angle)) * (25.0 + ring * 23.0)
		check(model.slot_offset(i) == expected, "Cached formation offset matches original geometry")
	var query := CountedModel.new()
	query.endless = true
	var seeker: Dictionary = query.spawn_unit("sword", 0, Vector2.ZERO)
	query.queries = 0
	check(query.nearest_available_enemy(seeker, 100, {}).is_empty() and query.queries == 1, "Empty target search performs one pass")
	var first: Dictionary = query.spawn_unit("sword", 1, Vector2(20, 0))
	var second: Dictionary = query.spawn_unit("sword", 1, Vector2(-20, 0))
	var loads := {first.id: 2, second.id: 2}
	query.queries = 0
	check(query.nearest_available_enemy(seeker, 100, loads).id == first.id and query.queries == 1, "Saturated fallback preserves distance tie order in one pass")
	check(query.nearest_enemy(seeker, 100, loads).is_empty(), "Direct filtered query retains its original contract")
	check(query.nearest_available_enemy(seeker, 20, loads).is_empty(), "Target radius remains strict at the boundary")
	# A long step may cross from outside chase radius directly into firing range.
	for delta in [0.0, 1.0 / 60, 0.6, 1.0, 2.0]:
		var fast = Model.new()
		var reference = Oracle.Reference.new()
		for simulation in [fast, reference]:
			simulation.endless = true
			simulation.rng.seed = 43
			simulation.anchor = Vector2(500, 0)
			simulation.wilderness.center = simulation.wilderness.cell(simulation.anchor)
			simulation.spawn_unit("archer", 0, Vector2.ZERO).cooldown = 0.0
			simulation.spawn_unit("sword", 1, Vector2(270.1, 0)).cooldown = 0.0
			simulation.tick(delta, Vector2.ZERO)
		check(fast.units == reference.units and fast.effects == reference.effects and fast.corpses == reference.corpses, "Empty-chase certificate preserves attacks after large movement steps")
	# Stress padded queries and large crowds against the independent pair oracle.
	for seed_value in range(4):
		var fast = Model.new()
		var reference = Oracle.Reference.new()
		for simulation in [fast, reference]:
			simulation.endless = true
			simulation.rng.seed = seed_value + 731
			for i in range(256):
				var point := Vector2(640, 320) if seed_value % 2 == 0 else Vector2((i % 16) * 23 - 100, (i / 16) * 17 - 70)
				simulation.spawn_unit(["sword", "archer", "shield"][i % 3], i % 2, point)
		for frame in range(20):
			fast.separate_units([0.0, 1.0 / 60, 0.2][frame % 3])
			reference.separate_units([0.0, 1.0 / 60, 0.2][frame % 3])
			check(fast.units == reference.units, "Padded separation matches oracle, including zero delta and dense piles")

func sort_checks() -> void:
	var model = Model.new()
	var view = View.new()
	view.battle = model
	model.rng.seed = 731
	for i in range(1024):
		model.spawn_unit("sword", 1, Vector2(300, model.rng.randi_range(0, 15) * 40))
	for order in range(3):
		if order == 1:
			model.units.reverse()
		var expected: Array = []
		for unit in model.units:
			if view.visible_world.has_point(unit.pos):
				expected.append(unit)
		# Independent stable insertion sort, exactly the previous implementation.
		for i in range(1, expected.size()):
			var item: Dictionary = expected[i]
			var j := i - 1
			while j >= 0 and expected[j].pos.y > item.pos.y:
				expected[j + 1] = expected[j]
				j -= 1
			expected[j + 1] = item
		view._sort_units_by_y()
		check(view._ordered_units == expected, "Native Y-sort preserves stable ties and reversed source order")
	view.free()

func landmark_checks() -> void:
	var model = Model.new()
	model.endless = true
	model.rng.seed = 731
	model.start_battle()
	for key in model.wilderness.active:
		var region: Dictionary = model.wilderness.regions[key]
		check(region.has("destination"), "Generated destination survives initial streaming")
		check(is_same(region.units, region.destination.units), "Landmark links to current regional units")
	var start: Dictionary = model.wilderness.regions[Vector2i.ZERO].destination
	start.used = true
	model.anchor = Vector2(5000, 440)
	model.wilderness.update(model)
	check(is_same(model.wilderness.regions[Vector2i.ZERO].units, start.units), "Unloading refreshes landmark survivor links")
	model.anchor = Vector2(260, 440)
	model.wilderness.update(model)
	check(is_same(start, model.wilderness.regions[Vector2i.ZERO].destination) and start.used, "Revisiting preserves landmark identity and used state")
	start.type = "shrine"
	start.used = false
	start.pos = model.anchor
	model.units[0].hp = 1.0
	model.check_recovery_shrines()
	check(start.used and model.units[0].hp == model.units[0].max_hp, "Restored shrine metadata makes recovery usable")

func render_checks() -> void:
	var model = Model.new()
	model.endless = true
	model.rng.seed = 731
	model.start_battle()
	var left := SubViewport.new()
	var right := SubViewport.new()
	for viewport in [left, right]:
		viewport.size = Vector2i(1280, 738)
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
	var cached = World.new()
	var original := UncachedWorld.new()
	for scenery in [cached, original]:
		scenery.wilderness = model.wilderness
		scenery.battle = model
	left.add_child(cached)
	right.add_child(original)
	for anchor in [Vector2(260, 440), Vector2(1199, 440), Vector2(-1300, -1400)]:
		model.anchor = anchor
		model.wilderness.update(model)
		var rectangle := Rect2(anchor - Vector2(640, 369), Vector2(1280, 738))
		for scenery in [cached, original]:
			scenery.position = -rectangle.position
			scenery.update_view(rectangle)
		for frame in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var actual: Image = left.get_texture().get_image()
		var expected: Image = right.get_texture().get_image()
		var colors: Dictionary = {}
		# Sample the whole image, not one diagonal that can miss most artwork.
		for y in range(16):
			for x in range(16):
				colors[actual.get_pixel(40 + x * 80, 23 + y * 46)] = true
		print("RENDER CHECK %s: %d sampled colors, %dx%d" % [anchor, colors.size(), actual.get_width(), actual.get_height()])
		check(colors.size() > 16, "Render comparison contains real varied terrain, not two blank images")
		check(actual.get_data() == expected.get_data(), "Cached scenery pixels equal original rendering at %s" % anchor)
		var builds: int = cached.terrain_builds
		for frame in range(3):
			cached.update_view(rectangle)
			await process_frame
			await RenderingServer.frame_post_draw
		check(cached.terrain_builds == builds, "Stationary updates do not rebuild retained geometry")
	# LRU stays bounded while traversing many positive/negative regions.
	for i in range(80):
		var point := Vector2((i - 40) * 1200, (i % 3) * 1200)
		model.anchor = point
		model.wilderness.update(model)
		cached.update_view(Rect2(point - Vector2(640, 369), Vector2(1280, 738)))
		check(cached.terrain_regions.size() <= cached.TERRAIN_CACHE_LIMIT, "Terrain cache remains bounded")
	var old_seed: int = cached.cache_seed
	model.start_battle()
	cached.update_view(Rect2(model.anchor - Vector2(640, 369), Vector2(1280, 738)))
	check(cached.cache_seed != old_seed and cached.cache_seed == model.wilderness.seed_value, "New expedition invalidates old-seed terrain")
	left.queue_free()
	right.queue_free()
	await process_frame

func run() -> void:
	model_checks()
	sort_checks()
	landmark_checks()
	if DisplayServer.get_name() != "headless":
		await render_checks()
	print("PERFORMANCE FIXES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
