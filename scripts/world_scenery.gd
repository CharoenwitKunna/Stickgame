extends Node2D

const Scenery = preload("res://scripts/scenery.gd")
const TILE := Vector2(1280, 800)
const REGION_SIZE := 1200.0

var view_rect := Rect2(Vector2.ZERO, Vector2(1280, 738))
var source
var viewport: SubViewport
var wilderness
var battle
var background: Node2D
var terrain_regions: Dictionary = {}
var cache_seed := -1
var cache_visit := 0
var landmark_signature: Array = []
var terrain_builds := 0
const TERRAIN_CACHE_LIMIT := 64

class BackgroundCanvas extends Node2D:
	var painter
	func _draw() -> void:
		painter.draw_background(self)

class RegionCanvas extends Node2D:
	var painter
	var key: Vector2i
	var destination: Vector2
	var visit := 0
	func _draw() -> void:
		painter.draw_region_terrain_features(key, self)

var terrain_texture: ImageTexture:
	get:
		return source.terrain_texture if source != null else null

# Landmark and environment palette
const PATH_BORDER := Color(0.24, 0.20, 0.14, 0.28)
const PATH_DIRT := Color(0.35, 0.30, 0.21, 0.45)
const PATH_WEAR := Color(0.42, 0.36, 0.26, 0.30)
const CLEARING_COLOR := Color(0.48, 0.58, 0.35, 0.25)
const WOODS_SHADOW := Color(0.04, 0.08, 0.05, 0.42)
const WOODS_DARK := Color(0.09, 0.17, 0.11, 0.85)
const WOODS_MID := Color(0.14, 0.24, 0.15, 0.90)
const WOODS_LIGHT := Color(0.20, 0.32, 0.20, 0.75)

func _ready() -> void:
	# Render the existing authored scenery once, then share that texture across
	# world tiles. Exploration never creates another terrain image or grass node.
	viewport = SubViewport.new()
	viewport.size = Vector2i(TILE)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	source = Scenery.new()
	source.tileable = true
	viewport.add_child(source)
	source.set_process(false)
	background = BackgroundCanvas.new()
	background.painter = self
	background.show_behind_parent = true
	add_child(background)
	update_view(view_rect)

func update_view(rectangle: Rect2) -> void:
	var old_low := Vector2i(floori(view_rect.position.x / TILE.x), floori(view_rect.position.y / TILE.y))
	var old_high := Vector2i(floori(view_rect.end.x / TILE.x), floori(view_rect.end.y / TILE.y))
	view_rect = rectangle
	var low_tile := Vector2i(floori(view_rect.position.x / TILE.x), floori(view_rect.position.y / TILE.y))
	var high_tile := Vector2i(floori(view_rect.end.x / TILE.x), floori(view_rect.end.y / TILE.y))
	if background != null and (low_tile != old_low or high_tile != old_high):
		background.queue_redraw()
	var seed_num: int = wilderness.seed_value if wilderness != null else 1
	if seed_num != cache_seed:
		for canvas in terrain_regions.values():
			canvas.hide()
			canvas.queue_free()
		terrain_regions.clear()
		cache_seed = seed_num
	cache_visit += 1
	var wanted: Dictionary = {}
	var low_reg := Vector2i(floori(view_rect.position.x / REGION_SIZE), floori(view_rect.position.y / REGION_SIZE))
	var high_reg := Vector2i(floori(view_rect.end.x / REGION_SIZE), floori(view_rect.end.y / REGION_SIZE))
	for rx in range(low_reg.x - 1, high_reg.x + 2):
		for ry in range(low_reg.y - 1, high_reg.y + 2):
			var key := Vector2i(rx, ry)
			var origin := Vector2(key) * REGION_SIZE
			var dest_center := origin + Vector2(600, 600)
			if wilderness != null and wilderness.regions.has(key) and wilderness.regions[key].has("destination"):
				dest_center = wilderness.regions[key].destination.pos
			# Include road bends/width and destinations that cross region borders.
			var bounds := Rect2(origin, Vector2.ONE * REGION_SIZE).expand(dest_center).grow(72)
			if not bounds.intersects(view_rect):
				continue
			wanted[key] = true
			var canvas: RegionCanvas = terrain_regions.get(key)
			if canvas == null:
				canvas = RegionCanvas.new()
				canvas.painter = self
				canvas.key = key
				canvas.destination = dest_center
				canvas.show_behind_parent = true
				terrain_regions[key] = canvas
				add_child(canvas)
			elif canvas.destination != dest_center:
				canvas.destination = dest_center
				canvas.queue_redraw()
			canvas.visit = cache_visit
			canvas.show()
	# Keep the original X/Y compositing order, including translucent road edges.
	var order := 1
	for key in wanted:
		move_child(terrain_regions[key], order + 1) # viewport, then background
		order += 1
	for key in terrain_regions:
		if not wanted.has(key):
			terrain_regions[key].hide()
	while terrain_regions.size() > TERRAIN_CACHE_LIMIT:
		var oldest: Vector2i
		var oldest_visit := 2147483647
		for key in terrain_regions:
			if not wanted.has(key) and terrain_regions[key].visit < oldest_visit:
				oldest = key
				oldest_visit = terrain_regions[key].visit
		terrain_regions[oldest].queue_free()
		terrain_regions.erase(oldest)
	var signature: Array = []
	if wilderness != null:
		for dest in wilderness.get_visible_landmarks(view_rect):
			signature.append([dest.region, dest.type, dest.pos, dest.get("used", false)])
	if signature != landmark_signature:
		landmark_signature = signature
		queue_redraw()

func _draw() -> void:
	# Roads/woods are retained child canvases behind these retained landmarks.
	if wilderness != null:
		for dest in wilderness.get_visible_landmarks(view_rect):
			draw_landmark(dest)

func draw_background(canvas: Node2D) -> void:
	if viewport == null:
		return
	# Base seamless terrain is also retained until its tile span changes.
	var low_tile := Vector2i(floori(view_rect.position.x / TILE.x), floori(view_rect.position.y / TILE.y))
	var high_tile := Vector2i(floori(view_rect.end.x / TILE.x), floori(view_rect.end.y / TILE.y))
	for x in range(low_tile.x, high_tile.x + 1):
		for y in range(low_tile.y, high_tile.y + 1):
			canvas.draw_texture_rect(viewport.get_texture(), Rect2(Vector2(x, y) * TILE, TILE), false)

func get_h_junction_y(seed_num: int, rx: int, ry: int) -> float:
	var h_rng := RandomNumberGenerator.new()
	h_rng.seed = hash("%d:%d:%d:h_edge" % [seed_num, rx, ry])
	return (float(ry) + 0.35 + h_rng.randf() * 0.30) * REGION_SIZE

func get_v_junction_x(seed_num: int, rx: int, ry: int) -> float:
	var v_rng := RandomNumberGenerator.new()
	v_rng.seed = hash("%d:%d:%d:v_edge" % [seed_num, rx, ry])
	return (float(rx) + 0.35 + v_rng.randf() * 0.30) * REGION_SIZE

func draw_region_terrain_features(reg: Vector2i, target: Node2D = null) -> void:
	var canvas: Node2D = self if target == null else target
	terrain_builds += 1
	var seed_num: int = wilderness.seed_value if wilderness != null else 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%d:scenery" % [seed_num, reg.x, reg.y])

	var origin := Vector2(reg) * REGION_SIZE

	# Determine destination or landmark center for this region
	var dest_center := origin + Vector2(600, 600)
	if wilderness != null and wilderness.regions.has(reg) and wilderness.regions[reg].has("destination"):
		dest_center = wilderness.regions[reg].destination.pos

	# Sunlit grassy clearings to break up uniform ground
	var clearing_count := rng.randi_range(1, 2)
	for i in range(clearing_count):
		var cp := origin + Vector2(rng.randf_range(180, 1020), rng.randf_range(180, 1020))
		var cr: float = rng.randf_range(90, 160)
		canvas.draw_circle(cp, cr, CLEARING_COLOR)

	# Seamless dirt road network meeting neighbors precisely at shared borders
	var p_west := Vector2(origin.x, get_h_junction_y(seed_num, reg.x - 1, reg.y))
	var p_east := Vector2(origin.x + REGION_SIZE, get_h_junction_y(seed_num, reg.x, reg.y))
	var p_bend1 := p_west.lerp(dest_center, 0.45) + Vector2(rng.randf_range(-40, 40), rng.randf_range(-60, 60))
	var p_bend2 := dest_center.lerp(p_east, 0.55) + Vector2(rng.randf_range(-40, 40), rng.randf_range(-60, 60))

	var path_pts: PackedVector2Array = [p_west, p_bend1, dest_center, p_bend2, p_east]
	canvas.draw_polyline(path_pts, PATH_BORDER, 24.0)
	canvas.draw_polyline(path_pts, PATH_DIRT, 15.0)
	canvas.draw_polyline(path_pts, PATH_WEAR, 6.0)

	# North-south branch with 50% occurrence
	if rng.randf() < 0.55:
		var p_north := Vector2(get_v_junction_x(seed_num, reg.x, reg.y - 1), origin.y)
		var p_south := Vector2(get_v_junction_x(seed_num, reg.x, reg.y), origin.y + REGION_SIZE)
		var branch_pts: PackedVector2Array = [p_north, dest_center, p_south]
		canvas.draw_polyline(branch_pts, PATH_BORDER, 20.0)
		canvas.draw_polyline(branch_pts, PATH_DIRT, 13.0)

	# Dense woodland patches / tree groves framing clearings
	var grove_count := rng.randi_range(2, 4)
	for g in range(grove_count):
		var grove_pos := origin + Vector2(rng.randf_range(140, 1060), rng.randf_range(140, 1060))
		if grove_pos.distance_to(dest_center) < 160:
			continue
		var tree_count := rng.randi_range(4, 7)
		for t in range(tree_count):
			var toff := Vector2(rng.randf_range(-36, 36), rng.randf_range(-36, 36))
			var tp := grove_pos + toff
			var tr: float = rng.randf_range(22, 36)
			# Tree base shadow
			canvas.draw_circle(tp + Vector2(3, 7), tr * 0.95, WOODS_SHADOW)
			# Layered canopy
			canvas.draw_circle(tp, tr, WOODS_DARK)
			canvas.draw_circle(tp + Vector2(-2, -3), tr * 0.78, WOODS_MID)
			canvas.draw_circle(tp + Vector2(-4, -5), tr * 0.42, WOODS_LIGHT)

func draw_landmark(dest: Dictionary) -> void:
	var pos: Vector2 = dest.get("pos", Vector2.ZERO)
	var dtype: String = dest.get("type", "")

	match dtype:
		"camp":
			draw_enemy_camp(pos)
		"shrine":
			draw_recovery_shrine(pos, dest.get("used", false))
		"ruins":
			draw_ancient_ruins(pos)
		"patrol":
			draw_patrol_waystone(pos)
		"start":
			draw_start_camp(pos)

func draw_start_camp(pos: Vector2) -> void:
	# Friendly starting outpost: clearing with guide stones and supply packs
	draw_circle(pos, 58.0, CLEARING_COLOR)
	draw_circle(pos + Vector2(0, 4), 16.0, WOODS_SHADOW)
	draw_circle(pos, 14.0, Color(0.32, 0.36, 0.34))
	draw_circle(pos, 8.0, Color(0.48, 0.54, 0.50))
	draw_line(pos + Vector2(0, -18), pos + Vector2(0, -6), Color(0.85, 0.75, 0.45), 2.0)

func draw_enemy_camp(pos: Vector2) -> void:
	# Trampled dirt ground
	draw_circle(pos, 115.0, Color(0.24, 0.19, 0.14, 0.75))
	draw_circle(pos, 75.0, Color(0.20, 0.16, 0.11, 0.85))

	# Palisade stakes surrounding perimeter
	var stake_count := 14
	for i in range(stake_count):
		if i == 0 or i == 1: # Camp entrance opening
			continue
		var angle: float = float(i) * (TAU / float(stake_count))
		var sp := pos + Vector2(cos(angle), sin(angle)) * 102.0
		draw_line(sp, sp + Vector2(0, -18), Color(0.28, 0.19, 0.12), 4.5)
		draw_line(sp + Vector2(0, -18), sp + Vector2(0, -24), Color(0.40, 0.28, 0.18), 3.0)

	# Canvas war tents
	draw_tent(pos + Vector2(-54, -20), 40.0, true)
	draw_tent(pos + Vector2(52, -32), 36.0, false)

	# Central campfire
	draw_circle(pos, 20.0, Color(0.18, 0.16, 0.15))
	for s in range(8):
		var sa: float = float(s) * (TAU / 8.0)
		var stone_p := pos + Vector2(cos(sa), sin(sa)) * 15.0
		draw_circle(stone_p, 4.0, Color(0.35, 0.34, 0.32))
	# Burning coals & fire glow
	draw_circle(pos, 28.0, Color(1.0, 0.55, 0.12, 0.35))
	draw_circle(pos, 9.0, Color(1.0, 0.75, 0.20, 0.90))
	draw_circle(pos, 4.0, Color(1.0, 0.95, 0.60, 0.95))

func draw_tent(pos: Vector2, size_w: float, flip: bool) -> void:
	var h: float = size_w * 0.9
	var left := pos + Vector2(-size_w * 0.5, h * 0.4)
	var right := pos + Vector2(size_w * 0.5, h * 0.4)
	var apex := pos + Vector2(0, -h * 0.6)
	var ground_shadow := PackedVector2Array([left, right, right + Vector2(6, 6), left + Vector2(6, 6)])
	draw_colored_polygon(ground_shadow, WOODS_SHADOW)

	var tent_pts := PackedVector2Array([left, apex, right])
	draw_colored_polygon(tent_pts, Color(0.54, 0.48, 0.40))
	draw_polyline(PackedVector2Array([left, apex, right, left]), Color(0.32, 0.27, 0.21), 2.0)
	draw_line(apex, pos + Vector2(0, h * 0.4), Color(0.24, 0.20, 0.16), 2.0)

	# Crimson enemy banner on tent pole
	var banner_top := apex + Vector2(0, -12)
	draw_line(apex, banner_top, Color(0.28, 0.20, 0.14), 2.0)
	var banner_flag := PackedVector2Array([
		banner_top,
		banner_top + Vector2(14 if not flip else -14, 4),
		banner_top + Vector2(0, 8)
	])
	draw_colored_polygon(banner_flag, Color(0.85, 0.25, 0.22))

func draw_recovery_shrine(pos: Vector2, used: bool) -> void:
	# Circular carved stone dais
	draw_circle(pos + Vector2(0, 4), 56.0, WOODS_SHADOW)
	draw_circle(pos, 54.0, Color(0.34, 0.38, 0.36))
	draw_circle(pos, 47.0, Color(0.42, 0.46, 0.44))
	draw_circle(pos, 43.0, Color(0.30, 0.34, 0.32))

	# Standing runic monolith stones in a ring
	var pillar_count := 5
	for p in range(pillar_count):
		var pa: float = float(p) * (TAU / float(pillar_count)) - (PI * 0.5)
		var pp := pos + Vector2(cos(pa), sin(pa)) * 34.0
		draw_circle(pp + Vector2(2, 3), 7.0, Color(0.12, 0.16, 0.14, 0.6))
		draw_rect(Rect2(pp - Vector2(5, 14), Vector2(10, 16)), Color(0.25, 0.29, 0.27))
		draw_rect(Rect2(pp - Vector2(4, 15), Vector2(8, 4)), Color(0.44, 0.49, 0.46))
		if not used:
			draw_circle(pp - Vector2(0, 6), 2.0, Color(0.95, 0.85, 0.40, 0.85))

	# Central fountain
	var font_r := 16.0
	draw_circle(pos, font_r, Color(0.20, 0.24, 0.22))
	if not used:
		# Radiant golden pool
		draw_circle(pos, font_r * 2.2, Color(0.92, 0.80, 0.32, 0.24))
		draw_circle(pos, font_r * 1.5, Color(0.94, 0.84, 0.38, 0.45))
		draw_circle(pos, font_r * 0.85, Color(1.0, 0.94, 0.58, 0.95))
		draw_circle(pos, font_r * 0.45, Color(1.0, 1.0, 0.85, 1.0))
	else:
		# Serene dormant stone font
		draw_circle(pos, font_r * 0.85, Color(0.28, 0.32, 0.30))

func draw_ancient_ruins(pos: Vector2) -> void:
	var offsets: Array[Vector2] = [
		Vector2(-42, -28), Vector2(12, -35), Vector2(-25, 20), Vector2(35, 15),
		Vector2(-10, -5), Vector2(28, -12), Vector2(-48, 12)
	]
	for off in offsets:
		draw_rect(Rect2(pos + off, Vector2(24, 16)), Color(0.32, 0.35, 0.33, 0.60))
		draw_rect(Rect2(pos + off + Vector2(1, 1), Vector2(22, 14)), Color(0.38, 0.42, 0.40, 0.70))

	draw_broken_column(pos + Vector2(-36, -20), 12.0)
	draw_broken_column(pos + Vector2(28, -25), 18.0)
	# Toppled broken column segment
	draw_rect(Rect2(pos + Vector2(-8, 22), Vector2(36, 10)), Color(0.34, 0.38, 0.36))
	draw_circle(pos + Vector2(-8, 27), 5.0, Color(0.42, 0.46, 0.44))
	draw_circle(pos + Vector2(28, 27), 5.0, Color(0.26, 0.30, 0.28))

	# Overgrown moss
	draw_circle(pos + Vector2(-15, 18), 10.0, Color(0.22, 0.32, 0.18, 0.5))
	draw_circle(pos + Vector2(16, -18), 8.0, Color(0.22, 0.32, 0.18, 0.5))

func draw_broken_column(pos: Vector2, height: float) -> void:
	draw_circle(pos + Vector2(0, 3), 9.0, WOODS_SHADOW)
	draw_rect(Rect2(pos - Vector2(7, height), Vector2(14, height)), Color(0.32, 0.36, 0.34))
	draw_circle(pos - Vector2(0, height), 7.0, Color(0.44, 0.48, 0.46))

func draw_patrol_waystone(pos: Vector2) -> void:
	draw_circle(pos + Vector2(2, 4), 14.0, WOODS_SHADOW)
	var stone_pts := PackedVector2Array([
		pos + Vector2(-8, 6),
		pos + Vector2(-7, -24),
		pos + Vector2(0, -32),
		pos + Vector2(7, -24),
		pos + Vector2(8, 6)
	])
	draw_colored_polygon(stone_pts, Color(0.30, 0.28, 0.32))
	draw_polyline(stone_pts, Color(0.42, 0.40, 0.44), 1.5)
	# Crimson glowing warning glyph
	draw_line(pos + Vector2(0, -22), pos + Vector2(0, -8), Color(0.90, 0.30, 0.25, 0.85), 2.0)
	draw_line(pos + Vector2(-4, -14), pos + Vector2(4, -14), Color(0.90, 0.30, 0.25, 0.85), 2.0)
