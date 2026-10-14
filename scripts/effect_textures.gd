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
			glow_image.set_pixel(x, y, Color(1, 1, 1, pow(maxf(0, 1 - radius), 2)))
	glow = ImageTexture.create_from_image(glow_image)
	var slash_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var point := Vector2(x - 32, y - 32)
			var edge: float = clampf((0.92 - absf(point.angle())) * 22.0, 0, 1)
			var band: float = clampf(1.7 - absf(point.length() - 22), 0, 1)
			slash_image.set_pixel(x, y, Color(1, 1, 1, edge * band))
	slash = ImageTexture.create_from_image(slash_image)
	var arrow_image := Image.create(64, 12, false, Image.FORMAT_RGBA8)
	for y in range(12):
		for x in range(64):
			var tint := Color.TRANSPARENT
			if x >= 8 and x <= 58:
				tint = Color("f1deb0")
				tint.a = clampf(1.5 - absf(y - 6.0), 0, 1) * (0.15 if x < 33 else 1.0)
			if x >= 52 and x <= 58 and absf(y - 6.0) <= (58 - x) * 0.5:
				tint = Color("ebeedc")
			arrow_image.set_pixel(x, y, tint)
	arrow = ImageTexture.create_from_image(arrow_image)
