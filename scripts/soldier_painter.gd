extends Node2D

# Offline source artwork. Live soldiers still use shared atlas quads.
const FRIEND := Color("7bd4a8")
const ENEMY := Color("ea7c6e")
const GOLD := Color("e8cc88")
const OUTLINE := Color("12221e")
const HIP := Vector2(0, -20)
const LEG_LENGTH := 13.0
var clock := 0.0
var ellipse_points := PackedVector2Array()

func _ready() -> void:
	for i in range(24):
		ellipse_points.append(Vector2.from_angle(i * TAU / 24.0))

func ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	draw_set_transform(center, 0, radius)
	draw_colored_polygon(ellipse_points, color)
	draw_set_transform(Vector2.ZERO)

func draw_shadow(p: Vector2) -> void:
	# Ground contact core under feet + soft feathered outer shadow
	ellipse(p + Vector2(2, 1), Vector2(13, 4.5), Color(0.02, 0.05, 0.04, 0.55))
	ellipse(p + Vector2(2, 1), Vector2(19, 7.0), Color(0.02, 0.05, 0.04, 0.30))
	ellipse(p + Vector2(2, 1), Vector2(25, 9.0), Color(0.02, 0.05, 0.04, 0.15))

func limb(points: PackedVector2Array, tint: Color, width: float = 4.0) -> void:
	draw_polyline(points, OUTLINE, width + 3.0, true)
	draw_polyline(points, tint, width, true)

static func foot_pose(phase: float, stride: float, ground: float) -> Vector2:
	var cycle := fposmod(phase, TAU) / TAU
	if cycle < 0.5:
		# Stance: travel backward beneath the moving body without lifting.
		return Vector2(lerpf(stride, -stride, cycle * 2), ground)
	var swing := (cycle - 0.5) * 2
	return Vector2(lerpf(-stride, stride, smoothstep(0, 1, swing)), ground - sin(swing * PI) * 10)

static func leg_pose(phase: float, stride: float, ground: float, body_x: float, moving: bool, side: float) -> PackedVector2Array:
	var hip := HIP
	var foot := foot_pose(phase, stride, ground) if moving else Vector2(side * 8, ground)
	foot.x -= body_x
	var offset := foot - hip
	var knee := (hip + foot) * 0.5 + Vector2(offset.y, -offset.x).normalized() * sqrt(maxf(0, LEG_LENGTH * LEG_LENGTH - offset.length_squared() * 0.25))
	return PackedVector2Array([hip, knee, foot])

static func strike_weight(progress: float) -> float:
	# Damage already happens at attack start: strike quickly, then follow through
	# and recover. Do not invent a wind-up delay in the simulation.
	var p := clampf(progress, 0, 1)
	if p < 0.18:
		return 1.0 - pow(1.0 - p / 0.18, 3)
	if p < 0.4:
		return lerpf(1, 0.82, (p - 0.18) / 0.22)
	return 0.82 * (1.0 - smoothstep(0.4, 1, p))

func draw_soldier(unit: Dictionary) -> void:
	var p: Vector2 = unit.pos
	var is_friend: bool = (unit.team == 0)
	var team: Color = FRIEND if is_friend else ENEMY
	var body: Color = Color("c0dfce") if is_friend else Color("dfbba8")
	var back_tint: Color = body.darkened(0.24).lerp(Color("162822" if is_friend else "281b1a"), 0.28)
	if unit.flash > 0:
		body = Color("ffffff")
		team = Color("fff3c0")
		back_tint = Color("f5e7c8")
	var facing: float = unit.get("facing", 1.0)
	var moving: bool = unit.moving
	var phase: float = unit.step
	var attacking: bool = float(unit.get("attack", 0.0)) > 0
	var progress: float = 1.0 - clampf(float(unit.get("attack", 0.0)) / 0.25, 0, 1)
	var strike: float = strike_weight(progress) if attacking else 0.0
	var breath: float = sin(clock * 2 + float(unit.id))
	var bob: float = (1.0 - cos(phase * 2)) * 0.9 if moving else breath * 0.7
	var lunge: float = 3.0 if unit.kind == "sword" else (4.0 if unit.kind == "archer" else 6.0)
	var body_x: float = (2.0 if moving else breath * 0.3) + strike * lunge
	var shoulder := Vector2(1.0 + strike * 2.0, -32 - strike)
	var head := shoulder + Vector2(-1 - strike, -12)
	var stride: float = 9.0 if unit.team == 1 else 12.0
	draw_set_transform(p + Vector2(body_x * facing, -bob), 0, Vector2(facing, 1))

	# Flowing cloth scarf with crease & light highlight
	var scarf_tip := Vector2(-17 - sin(phase + 0.7) * (3 if moving else 1), -25 + cos(phase) * 2)
	draw_colored_polygon(PackedVector2Array([shoulder + Vector2(-3, -3), scarf_tip, scarf_tip + Vector2(6, 5), shoulder + Vector2(3, 2)]), OUTLINE)
	draw_colored_polygon(PackedVector2Array([shoulder + Vector2(-2, -2), scarf_tip + Vector2(0.8, 0.8), scarf_tip + Vector2(5.2, 4.2), shoulder + Vector2(2, 1)]), team.darkened(0.18))
	draw_line(shoulder + Vector2(-1, -1), scarf_tip + Vector2(2, 1.5), team.lightened(0.22), 1.2, true)

	# Depth-tinted legs (back leg is recessed and darker)
	var back_leg := leg_pose(phase + PI, stride, bob, body_x, moving, -1)
	var front_leg := leg_pose(phase, stride, bob, body_x, moving, 1)
	limb(back_leg, back_tint, 3.2)
	draw_line(back_leg[2] - Vector2(1, 0), back_leg[2] + Vector2(4, 0), OUTLINE, 4.0, true)
	limb(front_leg, body, 4.0)
	draw_line(front_leg[2] - Vector2(1, 0), front_leg[2] + Vector2(4, 0), OUTLINE, 4.0, true)
	draw_line(front_leg[2] - Vector2(0.5, 0), front_leg[2] + Vector2(3, 0), body.darkened(0.18), 1.8, true)

	# Strong torso line
	limb(PackedVector2Array([shoulder, HIP]), body, 5.2)
	draw_line(HIP + Vector2(-3, 0), HIP + Vector2(3, 0), team.darkened(0.2), 2.0, true)

	# Back arm (recessed)
	var arm_swing: float = sin(phase) * 5 if moving else breath
	var back_hand := Vector2(-8 - arm_swing, -18 + strike * 3)
	limb(PackedVector2Array([shoulder, Vector2(-8, -25), back_hand]), back_tint, 3.2)

	# Head with specular glint, clear headband, and sharp eye
	draw_circle(head + Vector2(0, 1), 9, OUTLINE, true, -1, true)
	draw_circle(head, 6.7, body, true, -1, true)
	draw_arc(head + Vector2(-0.8, -0.8), 5.4, -2.7, -0.4, 12, body.lightened(0.35), 1.4, true)
	draw_line(head + Vector2(-6, 0), head + Vector2(6, 0), team.darkened(0.2), 2.6, true)
	draw_circle(head + Vector2(3.5, 1.5), 1.2, OUTLINE, true, -1, true)

	# Shoulder collar / clasp
	draw_line(shoulder + Vector2(-3, 3), shoulder + Vector2(3, 4), team, 4.2, true)

	if unit.kind == "sword":
		var hand := Vector2(10 + strike * 2, -26 - strike * 4 + arm_swing * 0.25)
		limb(PackedVector2Array([shoulder, hand + Vector2(-6, 3), hand]), body, 3.8)
		draw_sword(hand, -0.55 + strike * 1.9)
	elif unit.kind == "archer":
		draw_archer(shoulder, body, attacking, progress, moving)
	else:
		var guard := Vector2(14 + strike * 5, -26 - strike * 2)
		limb(PackedVector2Array([shoulder, Vector2(7, -22), guard]), body, 3.8)
		draw_shield(guard, team)
	draw_set_transform(Vector2.ZERO)

func draw_archer(shoulder: Vector2, body: Color, attacking: bool, progress: float, moving: bool) -> void:
	var bow := Vector2(15, -28)
	var pull: float = 3 if moving else 6
	if attacking:
		if progress < 0.2:
			pull = 10 * (1.0 - smoothstep(0, 0.2, progress))
		else:
			pull = sin((progress - 0.2) * TAU * 3) * exp(-6 * (progress - 0.2)) + smoothstep(0.7, 1, progress) * 6
	var string_hand := bow + Vector2(-pull, 0)
	limb(PackedVector2Array([shoulder, Vector2(7, -24), bow]), body, 3.6)
	limb(PackedVector2Array([shoulder, Vector2(-6 - pull * 0.4, -29), string_hand]), body, 3.4)
	# Recurve stave with polished wood tone and dark rim
	draw_arc(bow, 16, -PI / 2, PI / 2, 18, OUTLINE, 5.5, true)
	draw_arc(bow, 16, -PI / 2, PI / 2, 18, Color("9e6c3a"), 3.0, true)
	draw_arc(bow, 16, -PI / 3.5, PI / 3.5, 10, Color("cca065"), 1.4, true)
	# High-visibility bowstring
	draw_polyline(PackedVector2Array([bow + Vector2(0, -16), string_hand, bow + Vector2(0, 16)]), Color("f6eee0"), 1.2, true)
	# Nocked arrow with steel point
	if not attacking or progress < 0.1 or progress > 0.7:
		var tip := string_hand + Vector2(27, 0)
		draw_line(string_hand, tip, OUTLINE, 2.5, true)
		draw_line(string_hand, tip, Color("eeddb6"), 1.5, true)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(1, 0), tip + Vector2(-5, -2.8), tip + Vector2(-5, 2.8)]), OUTLINE)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4, -2), tip + Vector2(-4, 2)]), Color("e5eee8"))
	# Quiver on back with fletching
	draw_line(Vector2(-9, -33), Vector2(-15, -43), OUTLINE, 3.8, true)
	draw_line(Vector2(-9, -33), Vector2(-15, -43), Color("765130"), 2.2, true)
	draw_line(Vector2(-13, -39), Vector2(-17, -46), Color("eeddb6"), 1.4, true)
	draw_line(Vector2(-11, -37), Vector2(-14, -45), Color("e0c28d"), 1.4, true)

func draw_shield(center: Vector2, team: Color) -> void:
	var shield := PackedVector2Array([Vector2(-8, -11), Vector2(8, -11), Vector2(9, 5), Vector2(0, 14), Vector2(-9, 5)])
	var inside := PackedVector2Array([Vector2(-6, -9), Vector2(6, -9), Vector2(7, 4), Vector2(0, 11), Vector2(-7, 4)])
	for i in range(shield.size()):
		shield[i] += center
	for i in range(inside.size()):
		inside[i] += center
	# Heavy dark rim
	draw_colored_polygon(shield, OUTLINE)
	# Rich heraldic team field
	draw_colored_polygon(inside, team.darkened(0.22))
	# Golden metallic border
	var edge := inside.duplicate()
	edge.append(inside[0])
	draw_polyline(edge, GOLD, 1.8, true)
	# Heraldic gold cross
	draw_line(center + Vector2(0, -8), center + Vector2(0, 9), GOLD, 2.0, true)
	draw_line(center + Vector2(-5, -2), center + Vector2(5, -2), GOLD, 2.0, true)
	# Central golden boss (dome) with specular dot
	draw_circle(center, 3.4, OUTLINE, true, -1, true)
	draw_circle(center, 2.4, GOLD, true, -1, true)
	draw_circle(center + Vector2(-0.7, -0.7), 0.8, Color.WHITE, true, -1, true)

func draw_sword(hand: Vector2, angle: float) -> void:
	var direction := Vector2.from_angle(angle - PI / 2)
	var perpendicular := direction.orthogonal()
	var hilt := hand + direction * 5
	var tip := hand + direction * 30
	# Leather wrapped grip
	draw_line(hand - direction * 3, hilt, OUTLINE, 4.6, true)
	draw_line(hand - direction * 3, hilt, Color("6b4524"), 2.6, true)
	# Crossguard with gold accent
	draw_line(hilt - perpendicular * 5.5, hilt + perpendicular * 5.5, OUTLINE, 4.6, true)
	draw_line(hilt - perpendicular * 5, hilt + perpendicular * 5, GOLD, 2.4, true)
	# Blade silhouette outline (gives clean separation against bodies)
	draw_colored_polygon(PackedVector2Array([hilt - perpendicular * 3.0, tip + direction * 2.0, hilt + perpendicular * 3.5]), OUTLINE)
	# Cold steel blade
	draw_colored_polygon(PackedVector2Array([hilt - perpendicular * 1.8, tip, hilt + perpendicular * 2.2]), Color("ecf3f0"))
	# Razor cutting edge highlight
	draw_line(hilt + perpendicular * 1.2, tip, Color.WHITE, 1.2, true)
	# Steel fuller groove
	draw_line(hilt, tip - direction * 6, Color("8ba196"), 1.0, true)
	# Golden pommel
	draw_circle(hand - direction * 4, 2.3, OUTLINE, true, -1, true)
	draw_circle(hand - direction * 4, 1.4, GOLD, true, -1, true)

