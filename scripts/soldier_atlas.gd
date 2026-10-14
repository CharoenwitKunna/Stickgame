extends RefCounted

const TILE := 96
const COLUMNS := 16
const SIZE := Vector2i(1536, 3072)
const ORIGIN := Vector2(48, 78)
const IDLE := 8
const WALK := 16
const ATTACK := 12
const POSES := IDLE + WALK + ATTACK
const SHADOW := 12 * POSES
const CORPSE := SHADOW + 1
const COST := CORPSE + 1
const RING := COST + 1
const TIMER := RING + 1
const TIMER_STEPS := 64
const TOTAL := TIMER + TIMER_STEPS + 1
const SOLID := TOTAL # A previously unused tile; existing pose indices are unchanged.
static var solid_region: Rect2
const FX_ORIGIN := Vector2(48, 48)
const KINDS := {"sword": 0, "archer": 1, "shield": 2}
static var shared_texture: ImageTexture
static var regions: Array[Rect2] = []
var texture: ImageTexture

func _init() -> void:
	if shared_texture == null:
		var image := Image.load_from_file("res://assets/soldiers.png")
		assert(image != null and image.get_size() == SIZE, "Soldier atlas missing or invalid; run the atlas baker.")
		# White texels let health bars share the soldier texture without moving
		# overlays above other units and changing Y-ordered occlusion.
		var corner := Vector2i(region(SOLID).position) + Vector2i(1, 1)
		image.fill_rect(Rect2i(corner, Vector2i(9, 9)), Color.WHITE)
		solid_region = Rect2(Vector2(corner + Vector2i(4, 4)), Vector2.ONE)
		shared_texture = ImageTexture.create_from_image(image)
		for i in range(TOTAL + 1):
			regions.append(region(i))
	texture = shared_texture

static func region(index: int) -> Rect2:
	return Rect2(Vector2((index % COLUMNS) * TILE, (index / COLUMNS) * TILE), Vector2(TILE, TILE))

static func frame_index(unit: Dictionary, clock: float) -> int:
	var variant: int = int(KINDS[unit.kind]) * 4 + int(unit.team) * 2 + int(unit.flash > 0)
	var pose := 0
	if unit.attack > 0:
		pose = IDLE + WALK + mini(ATTACK - 1, int((1.0 - clampf(float(unit.attack) / 0.25, 0, 1)) * ATTACK))
	elif unit.moving:
		pose = IDLE + int(fposmod(float(unit.step), TAU) / TAU * WALK)
	else:
		pose = int(fposmod(clock * 2 + float(unit.id), TAU) / TAU * IDLE)
	return variant * POSES + pose
