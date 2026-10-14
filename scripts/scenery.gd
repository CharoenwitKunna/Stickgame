extends Node2D

const VIEW_SIZE := Vector2(1280.0, 800.0)
const IMG_W := 420
const IMG_H := 242
const OUTLINE := Color("12201f")

var terrain_image: Image
var terrain_texture: ImageTexture
var tufts: Array = []
var stones: Array = []
var shrubs: Array = []
var trees: Array = []
var wind_clock: float = 0.0
var _terrain_dirty: bool = false


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73631
	tuf_and_stone_setup(rng)
	paint_terrain()
	set_process(true)


func tuf_and_stone_setup(rng: RandomNumberGenerator) -> void:
	tufts.clear()
	stones.clear()
	shrubs.clear()
	trees.clear()

	for _i in range(650):
		tufts.append({
			"pos": Vector2(rng.randf_range(24.0, 1256.0), rng.randf_range(18.0, 748.0)),
			"h": rng.randf_range(5.0, 10.5),
			"spread": rng.randf_range(2.5, 5.2),
			"phase": rng.randf() * TAU,
			"color": Color("355245").lerp(Color("4c705c"), rng.randf())
		})

	for _i in range(60):
		stones.append({
			"pos": Vector2(rng.randf_range(48.0, 1232.0), rng.randf_range(32.0, 720.0)),
			"radius": Vector2(rng.randf_range(4.5, 9.5), rng.randf_range(2.8, 5.5)),
			"color": Color("586964").lerp(Color("73857e"), rng.randf())
		})

	# Border shrubs and trees outside the main melee lane
	var border_points := [
		Vector2(36, 84), Vector2(1242, 92), Vector2(32, 640), Vector2(1246, 628),
		Vector2(92, 42), Vector2(1188, 48), Vector2(84, 710), Vector2(1196, 706)
	]
	for i in range(border_points.size()):
		if i % 2 == 0:
			trees.append(border_points[i])
		else:
			shrubs.append(border_points[i])


func _process(delta: float) -> void:
	wind_clock += delta
	if _terrain_dirty and terrain_texture != null and terrain_image != null:
		terrain_texture.update(terrain_image)
		_terrain_dirty = false
	queue_redraw()


func paint_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 591
	noise.frequency = 0.017

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = 1907
	detail_noise.frequency = 0.055

	terrain_image = Image.create(IMG_W, IMG_H, false, Image.FORMAT_RGBA8)
	var deep_moss := Color("20352f")
	var mid_sage := Color("29423a")
	var light_glade := Color("335046")
	var worn_path := Color("3b493f")

	var center := Vector2(IMG_W * 0.5, IMG_H * 0.48)
	var inv_scale := Vector2(float(IMG_W) / VIEW_SIZE.x, float(IMG_H) / VIEW_SIZE.y)

	for y in range(IMG_H):
		for x in range(IMG_W):
			var n: float = noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var d: float = detail_noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var base_col: Color = deep_moss.lerp(mid_sage, clampf(n * 1.15, 0.0, 1.0))
			if d > 0.62:
				base_col = base_col.lerp(light_glade, (d - 0.62) * 0.85)

			# Subtle worn central battle lane & soft outer vignette
			var norm_dx: float = (float(x) - center.x) / (IMG_W * 0.46)
			var norm_dy: float = (float(y) - center.y) / (IMG_H * 0.42)
			var radial: float = norm_dx * norm_dx + norm_dy * norm_dy
			var path_band: float = clampf(1.0 - absf(norm_dy) * 2.4, 0.0, 1.0)
			base_col = base_col.lerp(worn_path, path_band * 0.22 * d)
			if radial > 0.72:
				base_col = base_col.darkened(clampf((radial - 0.72) * 0.35, 0.0, 0.22))

			terrain_image.set_pixel(x, y, base_col)

	# Bake stone contact shadows directly into the terrain image to save per-frame draw calls
	for stone in stones:
		var sp: Vector2 = stone.pos * inv_scale
		var sr: Vector2 = stone.radius * inv_scale * 1.35
		_bake_soft_oval(sp + Vector2(0.0, 1.0), sr, Color(0.07, 0.12, 0.10, 0.38))

	terrain_texture = ImageTexture.create_from_image(terrain_image)


func _bake_soft_oval(center_px: Vector2, radius_px: Vector2, tint: Color) -> void:
	var min_x: int = clampi(int(floor(center_px.x - radius_px.x - 1.0)), 0, IMG_W - 1)
	var max_x: int = clampi(int(ceil(center_px.x + radius_px.x + 1.0)), 0, IMG_W - 1)
	var min_y: int = clampi(int(floor(center_px.y - radius_px.y - 1.0)), 0, IMG_H - 1)
	var max_y: int = clampi(int(ceil(center_px.y + radius_px.y + 1.0)), 0, IMG_H - 1)
	var rx: float = maxf(1.0, radius_px.x)
	var ry: float = maxf(1.0, radius_px.y)

	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			var dx: float = (float(px) - center_px.x) / rx
			var dy: float = (float(py) - center_px.y) / ry
			var d2: float = dx * dx + dy * dy
			if d2 <= 1.0:
				var cur: Color = terrain_image.get_pixel(px, py)
				var weight: float = (1.0 - d2) * tint.a
				terrain_image.set_pixel(px, py, cur.lerp(Color(tint.r, tint.g, tint.b, 1.0), weight))


func stamp_battle_scar(world_pos: Vector2, radius: float = 18.0) -> void:
	if terrain_image == null:
		return
	var inv_scale := Vector2(float(IMG_W) / VIEW_SIZE.x, float(IMG_H) / VIEW_SIZE.y)
	_bake_soft_oval(world_pos * inv_scale, Vector2(radius, radius * 0.65) * inv_scale, Color(0.08, 0.13, 0.11, 0.22))
	_terrain_dirty = true


func ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, radius.y / maxf(0.001, radius.x)))
	draw_circle(Vector2.ZERO, radius.x, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	if terrain_texture != null:
		draw_texture_rect(terrain_texture, Rect2(Vector2.ZERO, VIEW_SIZE), false)

	# Stones (contact shadows are pre-baked into terrain_texture)
	for stone in stones:
		var sp: Vector2 = stone.pos
		var sr: Vector2 = stone.radius
		ellipse(sp, sr + Vector2(1.2, 1.2), OUTLINE)
		ellipse(sp, sr, stone.color)
		ellipse(sp - Vector2(sr.x * 0.22, sr.y * 0.25), sr * 0.45, stone.color.lightened(0.16))

	# Wind-animated grass tufts (batched 2-segment V-strokes)
	for tuft in tufts:
		var p: Vector2 = tuft.pos
		var h: float = tuft.h
		var s: float = tuft.spread
		var sway: float = sin(wind_clock * 2.1 + p.x * 0.015 + tuft.phase) * 2.2
		var c: Color = tuft.color
		draw_line(p, p + Vector2(-s + sway, -h), c, 1.35)
		draw_line(p, p + Vector2(s + sway * 1.1, -h * 0.88), c.lightened(0.08), 1.35)

	for shrub_pos in shrubs:
		draw_shrub(shrub_pos)

	for tree_pos in trees:
		draw_tree(tree_pos)


func draw_shrub(p: Vector2) -> void:
	var sway: float = sin(wind_clock * 1.6 + p.x * 0.02) * 1.2
	ellipse(p + Vector2(0, 6), Vector2(18, 7), Color(0, 0, 0, 0.24))
	ellipse(p + Vector2(sway, 0), Vector2(17, 13), OUTLINE)
	ellipse(p + Vector2(sway, 0), Vector2(15, 11), Color("2b473d"))
	ellipse(p + Vector2(-4 + sway, -3), Vector2(9, 7), Color("3c6152"))


func draw_tree(p: Vector2) -> void:
	var sway: float = sin(wind_clock * 1.3 + p.y * 0.02) * 1.8
	ellipse(p + Vector2(0, 12), Vector2(26, 10), Color(0, 0, 0, 0.28))
	draw_rect(Rect2(p + Vector2(-5, -14), Vector2(10, 26)), OUTLINE)
	draw_rect(Rect2(p + Vector2(-3.5, -14), Vector2(7, 24)), Color("4a3b31"))
	var crown := p + Vector2(sway, -26)
	ellipse(crown, Vector2(26, 21), OUTLINE)
	ellipse(crown, Vector2(24, 19), Color("264037"))
	ellipse(crown + Vector2(-5, -5), Vector2(15, 12), Color("37594b"))
	ellipse(crown + Vector2(6, -2), Vector2(12, 10), Color("466e5d"))
