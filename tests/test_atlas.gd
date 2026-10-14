extends SceneTree

const Atlas = preload("res://scripts/soldier_atlas.gd")
const Painter = preload("res://scripts/soldier_painter.gd")

func _initialize() -> void:
	var image := Image.load_from_file("res://assets/soldiers.png")
	if image == null or image.get_size() != Atlas.SIZE:
		push_error("Atlas is missing or has incorrect dimensions")
		quit(1)
		return
	if not verify_motion():
		quit(1)
		return
	for i in range(Atlas.SHADOW):
		var origin: Vector2 = Atlas.region(i).position
		# Heads move with leaning/recoil; a fixed head pixel is not a valid probe.
		var bounds := image.get_region(Rect2i(origin, Vector2i(Atlas.TILE, Atlas.TILE))).get_used_rect()
		if bounds.size.x < 20 or bounds.size.y < 40:
			push_error("Empty or incomplete soldier pose %d" % i)
			quit(1)
			return
		for edge in range(Atlas.TILE):
			for point in [Vector2(edge, 0), Vector2(edge, 95), Vector2(0, edge), Vector2(95, edge)]:
				if image.get_pixel(int(origin.x + point.x), int(origin.y + point.y)).a > 0.01:
					push_error("Artwork bleeds across tile %d" % i)
					quit(1)
					return
	for kind in ["sword", "archer", "shield"]:
		for team in range(2):
			for flash in [0.0, 0.18]:
				for state in range(3):
					for frame in range(100):
						var unit := {"kind": kind, "team": team, "flash": flash, "id": 12,
							"moving": state == 1, "attack": frame * 0.0025 if state == 2 else 0.0, "step": frame * 0.13}
						var index: int = Atlas.frame_index(unit, frame * 0.1)
						var base: int = Atlas.KINDS[kind] * 4 + team * 2 + int(flash > 0)
						if index < base * Atlas.POSES or index >= (base + 1) * Atlas.POSES:
							push_error("Animation selected wrong kind/team/flash variant")
							quit(1)
							return
	print("PASS: all %d poses contain artwork, complete tile borders are clear, 3600 animation selections stay in the correct variant" % Atlas.SHADOW)
	quit()

func verify_motion() -> bool:
	for stride in [9.0, 12.0]:
		for sample in range(128):
			var phase: float = sample * TAU / 128
			var foot: Vector2 = Painter.foot_pose(phase, stride, 1.3)
			if sample < 64 and absf(foot.y - 1.3) > 0.0001:
				push_error("Stance foot lifts off the ground")
				return false
			if sample > 64 and foot.y >= 1.3:
				push_error("Swing foot fails to clear the ground")
				return false
			var leg: PackedVector2Array = Painter.leg_pose(phase, stride, 1.3, 2, true, 1)
			if absf(leg[0].distance_to(leg[1]) - 13) > 0.005 or absf(leg[1].distance_to(leg[2]) - 13) > 0.005:
				push_error("Gait stretches leg segments")
				return false
			if absf(leg[2].x + 2 - foot.x) > 0.0001:
				push_error("Body lean moves the planted foot")
				return false
		if Painter.foot_pose(0, stride, 0).distance_to(Painter.foot_pose(TAU, stride, 0)) > 0.0001:
			push_error("Walk cycle does not loop seamlessly")
			return false
	if Painter.strike_weight(0) != 0 or Painter.strike_weight(1) != 0 or Painter.strike_weight(0.18) < 0.99:
		push_error("Strike fails to peak and return to guard")
		return false
	var previous := 1.0
	for sample in range(61):
		var weight: float = Painter.strike_weight(0.4 + sample * 0.01)
		if weight < 0 or weight > previous + 0.0001:
			push_error("Attack recovery reverses or overshoots")
			return false
		previous = weight
	var unit := {"kind": "sword", "team": 0, "flash": 0.0, "id": 0, "moving": false, "attack": 0.25, "step": 0.0}
	if Atlas.frame_index(unit, 0) != Atlas.IDLE + Atlas.WALK:
		push_error("Attack does not start at its first pose")
		return false
	unit.attack = 0.00001
	if Atlas.frame_index(unit, 0) != Atlas.POSES - 1:
		push_error("Attack recovery skips its final pose")
		return false
	print("PASS: planted feet, swing clearance, fixed leg lengths, looping gait, and strike/recovery timing")
	return true
