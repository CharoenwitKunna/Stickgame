extends Node2D

# Offline source artwork. Live soldiers still use shared atlas quads.
const FRIEND := Color("8bd7b0")
const ENEMY := Color("e58375")
const GOLD := Color("e3c989")
const OUTLINE := Color("142623")
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
	for i in range(4, 0, -1):
		ellipse(p + Vector2(4, 2), Vector2(12 + i * 2, 4 + i), Color(0.035, 0.08, 0.06, 0.045))

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
	var team: Color = FRIEND if unit.team == 0 else ENEMY
	var body: Color = Color("b7d6c1") if unit.team == 0 else Color("d9b6a3")
	if unit.flash > 0:
		body = Color("fff6d5")
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
	var scarf_tip := Vector2(-17 - sin(phase + 0.7) * (3 if moving else 1), -25 + cos(phase) * 2)
	draw_colored_polygon(PackedVector2Array([shoulder + Vector2(-2, -2), scarf_tip, scarf_tip + Vector2(6, 5), shoulder + Vector2(3, 1)]), team.darkened(0.23))
	var back_leg := leg_pose(phase + PI, stride, bob, body_x, moving, -1)
	var front_leg := leg_pose(phase, stride, bob, body_x, moving, 1)
	limb(back_leg, body.darkened(0.16), 3.5)
	draw_line(back_leg[2], back_leg[2] + Vector2(4, 0), OUTLINE, 4, true)
	limb(front_leg, body)
	draw_line(front_leg[2], front_leg[2] + Vector2(4, 0), OUTLINE, 4, true)
	limb(PackedVector2Array([shoulder, HIP]), body, 5)
	var arm_swing: float = sin(phase) * 5 if moving else breath
	var back_hand := Vector2(-8 - arm_swing, -18 + strike * 3)
	limb(PackedVector2Array([shoulder, Vector2(-8, -25), back_hand]), body.darkened(0.1), 3.5)
	draw_circle(head + Vector2(0, 1), 9, OUTLINE, true, -1, true)
	draw_circle(head, 6.7, body, true, -1, true)
	draw_arc(head, 6.7, -PI, -0.1, 14, body.lightened(0.2), 1.2, true)
	draw_line(head + Vector2(-6, 0), head + Vector2(6, 0), team.darkened(0.4), 2.5, true)
	draw_circle(head + Vector2(3.5, 2), 1.1, OUTLINE, true, -1, true)
	draw_line(shoulder + Vector2(-3, 3), shoulder + Vector2(3, 4), team, 4, true)
	if unit.kind == "sword":
		var hand := Vector2(10 + strike * 2, -26 - strike * 4 + arm_swing * 0.25)
		limb(PackedVector2Array([shoulder, hand + Vector2(-6, 3), hand]), body, 3.5)
		draw_sword(hand, -0.55 + strike * 1.9)
	elif unit.kind == "archer":
		draw_archer(shoulder, body, attacking, progress, moving)
	else:
		var guard := Vector2(14 + strike * 5, -26 - strike * 2)
		limb(PackedVector2Array([shoulder, Vector2(7, -22), guard]), body, 3.5)
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
	limb(PackedVector2Array([shoulder, Vector2(7, -24), bow]), body, 3.5)
	limb(PackedVector2Array([shoulder, Vector2(-6 - pull * 0.4, -29), string_hand]), body, 3.5)
	draw_arc(bow, 16, -PI / 2, PI / 2, 18, OUTLINE, 5, true)
	draw_arc(bow, 16, -PI / 2, PI / 2, 18, Color("c6a16c"), 2.5, true)
	draw_polyline(PackedVector2Array([bow + Vector2(0, -16), string_hand, bow + Vector2(0, 16)]), Color("eee0ba"), 1, true)
	if not attacking or progress < 0.1 or progress > 0.7:
		var tip := string_hand + Vector2(27, 0)
		draw_line(string_hand, tip, Color("eedbb2"), 1.5, true)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-5, -3), tip + Vector2(-5, 3)]), Color("dddcd2"))
	draw_line(Vector2(-9, -33), Vector2(-15, -43), Color("c9b791"), 2, true)

func draw_shield(center: Vector2, team: Color) -> void:
	var shield := PackedVector2Array([Vector2(-8, -11), Vector2(8, -11), Vector2(9, 5), Vector2(0, 14), Vector2(-9, 5)])
	var inside := PackedVector2Array([Vector2(-6, -9), Vector2(6, -9), Vector2(7, 4), Vector2(0, 11), Vector2(-7, 4)])
	for i in range(shield.size()):
		shield[i] += center
	for i in range(inside.size()):
		inside[i] += center
	draw_colored_polygon(shield, OUTLINE)
	draw_colored_polygon(inside, team.darkened(0.45))
	var edge := inside.duplicate()
	edge.append(inside[0])
	draw_polyline(edge, Color("d8c291"), 1.6, true)
	draw_line(center + Vector2(0, -7), center + Vector2(0, 7), Color("d8c291"), 2, true)
	draw_circle(center, 3, Color("d8c291"), true, -1, true)

func draw_sword(hand: Vector2, angle: float) -> void:
	var direction := Vector2.from_angle(angle - PI / 2)
	var perpendicular := direction.orthogonal()
	var hilt := hand + direction * 5
	var tip := hand + direction * 30
	draw_line(hand - direction * 3, hilt, Color("8b653f"), 4, true)
	draw_line(hilt - perpendicular * 5, hilt + perpendicular * 5, OUTLINE, 4, true)
	draw_line(hilt - perpendicular * 5, hilt + perpendicular * 5, GOLD, 2, true)
	draw_colored_polygon(PackedVector2Array([hilt - perpendicular * 2, tip, hilt + perpendicular * 3]), Color("e5ebd8"))
	draw_line(hilt, tip, Color("a0b4a3"), 1, true)
