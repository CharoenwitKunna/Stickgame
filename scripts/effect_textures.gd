extends RefCounted

static var dot: ImageTexture
static var glow: ImageTexture
static var slash: ImageTexture
static var arrow: ImageTexture

func _init() -> void:
	if dot != null:
		return
	var dot_image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var distance := Vector2(x - 15.5, y - 15.5).length()
			dot_image.set_pixel(x, y, Color(1, 1, 1, clampf((15.5 - distance) / 1.5, 0, 1)))
	dot = ImageTexture.create_from_image(dot_image)
	var glow_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var radius: float = Vector2(x - 31.5, y - 31.5).length() / 31.5
			var alpha: float = pow(maxf(0, 1.0 - radius), 2.2)
			glow_image.set_pixel(x, y, Color(1, 1, 1, alpha))
	glow = ImageTexture.create_from_image(glow_image)
	var slash_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var point := Vector2(x - 32, y - 32)
			var angle := point.angle()
			var edge: float = clampf((1.15 - absf(angle)) * 3.5, 0, 1)
			var taper: float = clampf(1.0 - (angle / 1.15) * 0.5, 0, 1)
			var band: float = clampf(3.2 - absf(point.length() - 22.0), 0, 1)
			slash_image.set_pixel(x, y, Color(1, 1, 1, edge * band * taper))
	slash = ImageTexture.create_from_image(slash_image)
	var arrow_image := Image.create(64, 12, false, Image.FORMAT_RGBA8)
	for y in range(12):
		for x in range(64):
			var tint := Color.TRANSPARENT
			var dy: float = absf(y - 5.5)
			if x >= 10 and x <= 54 and dy <= 1.2:
				tint = Color("d9c18f")
				if dy <= 0.6:
					tint = Color("f6ebd3")
			if x >= 52 and x <= 60 and dy <= (60 - x) * 0.7:
				tint = Color("1e2c26") if (dy >= (60 - x) * 0.7 - 0.7 or x == 52) else Color("ecf3ef")
			if x >= 8 and x <= 22 and dy <= 3.2 and dy >= 1.2:
				if (x - 8) % 4 <= 2:
					tint = Color("7bd4a8") if dy <= 2.2 else Color("162822")
			arrow_image.set_pixel(x, y, tint)
	arrow = ImageTexture.create_from_image(arrow_image)

