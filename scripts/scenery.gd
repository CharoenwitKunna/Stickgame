extends Node2D

# Static canvas: retained by Godot, never rebuilt for unit animation.
var terrain: ImageTexture
var grass: Array[Dictionary] = []
var stones: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 73631
	paint_terrain()
	for i in range(650):
		var p := Vector2(rng.randf_range(18, 1262), rng.randf_range(12, 731))
		var path_y: float = 450 + sin(p.x / 235.0) * 78
		if absf(p.y - path_y) < 46 and rng.randf() < 0.85:
			continue
		grass.append({"pos": p, "size": rng.randf_range(3, 9), "shade": rng.randf_range(0, 1)})
	for i in range(60):
		stones.append({"pos": Vector2(rng.randf_range(62, 1220), rng.randf_range(85, 699)), "size": rng.randf_range(1, 3)})

func paint_terrain() -> void:
	var image := Image.create(420, 242, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 591
	noise.frequency = 0.017
	for y in range(242):
		for x in range(420):
			var world := Vector2(x * 1280.0 / 420.0, y * 738.0 / 242.0)
			var n: float = noise.get_noise_2d(world.x, world.y) * 0.5 + 0.5
			var tint: Color = Color("354c40").lerp(Color("52614b"), n)
			var distance: float = absf(world.y - (450 + sin(world.x / 235.0) * 78))
			var trail: float = exp(-pow(distance / 54.0, 2.0)) * 0.58
			tint = tint.lerp(Color("797158"), trail)
			var edge: float = minf(minf(world.x / 90.0, (1280 - world.x) / 90.0), minf(world.y / 75.0, (740 - world.y) / 75.0))
			tint = tint.darkened((1.0 - clampf(edge, 0, 1)) * 0.35)
			image.set_pixel(x, y, tint)
	terrain = ImageTexture.create_from_image(image)

func ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(24):
		var angle: float = i * TAU / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)

func _draw() -> void:
	if terrain == null:
		return
	draw_texture_rect(terrain, Rect2(0, 0, 1280, 738), false)
	for tuft in grass:
		var p: Vector2 = tuft.pos
		var h: float = tuft.size
		var tint: Color = Color("69765b").lerp(Color("283f35"), float(tuft.shade))
		draw_line(p, p + Vector2(-3, -h), tint, 1.2, true)
		draw_line(p, p + Vector2(1, -h * 1.15), tint, 1.2, true)
		draw_line(p, p + Vector2(4, -h * 0.7), tint, 1.2, true)
	for stone in stones:
		ellipse(stone.pos + Vector2(1, 2), Vector2(stone.size * 2, stone.size), Color(0.05, 0.1, 0.08, 0.15))
		ellipse(stone.pos, Vector2(stone.size * 1.5, stone.size), Color("8a8970"))
	# Frame the clearing with foliage, not collision obstacles.
	for p in [Vector2(5, 269), Vector2(-6, 500), Vector2(1257, 267), Vector2(1292, 439), Vector2(18, 714), Vector2(1204, 746)]:
		draw_tree(p)
	for p in [Vector2(88, 742), Vector2(206, 736), Vector2(1052, 740), Vector2(1264, 660)]:
		draw_shrub(p)
func draw_tree(p: Vector2) -> void:
	for i in range(5, 0, -1):
		ellipse(p + Vector2(18, 27), Vector2(45 + i * 4, 16 + i * 2), Color(0.04, 0.09, 0.07, 0.035))
	draw_line(p + Vector2(0, 15), p + Vector2(-8, -54), Color("363d2c"), 11, true)
	draw_line(p + Vector2(-7, -36), p + Vector2(16, -69), Color("363d2c"), 6, true)
	for i in range(9):
		var direction := Vector2.from_angle(i * 2.399)
		var center: Vector2 = p + Vector2(0, -54) + direction * (19 + i % 3 * 9)
		ellipse(center + Vector2(2, 6), Vector2(28, 20), Color("20392f"))
		ellipse(center, Vector2(27, 19), Color("2b4939").lerp(Color("445b40"), (i % 4) / 4.0))
		ellipse(center + Vector2(-5, -7), Vector2(15, 7), Color(0.38, 0.45, 0.30, 0.18))

func draw_shrub(p: Vector2) -> void:
	ellipse(p + Vector2(6, 8), Vector2(32, 10), Color(0.06, 0.1, 0.08, 0.2))
	for i in range(5):
		var center := p + Vector2((i - 2) * 10, -float(i % 2) * 8)
		ellipse(center, Vector2(13, 9), Color("40563a"))
		draw_line(center, center + Vector2(-3, -6), Color("778563"), 1, true)
