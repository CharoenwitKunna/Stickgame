extends Node2D

const Model = preload("res://scripts/battle_model.gd")
const Atlas = preload("res://scripts/soldier_atlas.gd")
const FX = preload("res://scripts/effect_textures.gd")
const FRIEND := Color("8bd7b0")
const ENEMY := Color("e58375")
const GOLD := Color("e3c989")
const OUTLINE := Color("142623")

var battle
var hovered := -1
var clock := 0.0
var ellipse_points := PackedVector2Array()
var particles: Array[Dictionary] = []
var revival_rings: Array[Dictionary] = []
var impact_pulses: Array[Dictionary] = []
var channel_active := false
var channel_point := Vector2.ZERO
var channel_progress := 0.0
var known_corpses: Dictionary = {}
var rng := RandomNumberGenerator.new()
var font := FontFile.new()
var soldier_atlas

func _ready() -> void:
	font.load_dynamic_font("res://assets/body.ttf")
	soldier_atlas = Atlas.new()
	FX.new()
	rng.seed = 73631
	# Reuse one polygon; apply position/scale in the renderer instead of rebuilding vertices.
	for i in range(24):
		ellipse_points.append(Vector2.from_angle(i * TAU / 24.0))

func reset_effects() -> void:
	particles.clear()
	revival_rings.clear()
	impact_pulses.clear()
	channel_active = false
	channel_progress = 0.0
	known_corpses.clear()

func raise_at(point: Vector2, kind: String = "sword") -> void:
	if revival_rings.size() >= 24:
		revival_rings.pop_front()
	revival_rings.append({"pos": point, "life": 1.2, "kind": kind})
	emit_particles(point + Vector2(0, -14), FRIEND, 24, true)
	emit_particles(point, GOLD, 10, true)

func emit_particles(point: Vector2, tint: Color, count: int, rising: bool = false) -> void:
	for i in range(count):
		if particles.size() >= 240:
			break
		particles.append({"pos": point + Vector2(rng.randf_range(-5, 5), rng.randf_range(-6, 6)),
			"velocity": Vector2(rng.randf_range(-45, 45), rng.randf_range(-100, -35) if rising else rng.randf_range(-55, 15)),
			"life": rng.randf_range(0.3, 0.75), "max_life": 0.75, "tint": tint,
			"size": rng.randf_range(1.2, 3.2), "rising": rising})

func animate(delta: float) -> void:
	clock += delta
	for effect in battle.effects:
		if not effect.get("painted", false):
			effect.painted = true
			emit_particles(effect.to + Vector2(0, -22), GOLD if effect.archer else Color("f5dbb0"), 6)
			if impact_pulses.size() < 32:
				impact_pulses.append({"pos": effect.to + Vector2(0, -25), "life": 0.24,
					"tint": FRIEND if effect.team == 0 else ENEMY})
			effect.render_life = 0.16
		effect.render_life = maxf(0, float(effect.render_life) - delta)
	for corpse in battle.corpses:
		if not known_corpses.has(corpse.id):
			known_corpses[corpse.id] = true
			emit_particles(corpse.pos, GOLD, 7, true)
	for i in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[i]
		particle.life = float(particle.life) - delta
		particle.pos += particle.velocity * delta
		if not particle.rising:
			particle.velocity.y += delta * 160.0
		if particle.life <= 0:
			particles.remove_at(i)
	for i in range(impact_pulses.size() - 1, -1, -1):
		impact_pulses[i].life = float(impact_pulses[i].life) - delta
		if impact_pulses[i].life <= 0:
			impact_pulses.remove_at(i)
	for i in range(revival_rings.size() - 1, -1, -1):
		revival_rings[i].life = float(revival_rings[i].life) - delta
		if revival_rings[i].life <= 0:
			revival_rings.remove_at(i)
	queue_redraw()

func ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	draw_set_transform(center, 0, radius)
	draw_colored_polygon(ellipse_points, color)
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if battle == null:
		return
	# A fixed number of drifting motes adds life without per-unit particles.
	for i in range(18):
		var mote := Vector2(fposmod(i * 173.0 + clock * (3 + i % 3), 1240) + 20,
			fposmod(i * 97.0 - clock * 5, 650) + 30)
		mote.x += sin(clock * 0.7 + i) * 10
		var alpha: float = 0.12 + 0.12 * sin(clock * 1.7 + i * 2.1)
		draw_texture_rect(FX.glow, Rect2(mote - Vector2(6, 6), Vector2(12, 12)), false, Color(GOLD, alpha))
	if battle.outcome.is_empty():
		ellipse(battle.anchor, Vector2(19, 8), Color(FRIEND, 0.15))
		draw_arc(battle.anchor, 15, 0, TAU, 36, Color(FRIEND, 0.38), 1.2, true)
		if battle.has_target:
			var pulse: float = sin(clock * 5) * 2
			draw_arc(battle.move_target, 13 + pulse, 0, TAU, 32, FRIEND, 2, true)
			for i in range(4):
				var direction := Vector2.from_angle(i * PI / 2)
				draw_line(battle.move_target + direction * 18, battle.move_target + direction * 24, FRIEND, 2, true)
	for i in range(battle.corpses.size()):
		draw_corpse(battle.corpses[i], i == hovered)
	var ordered: Array = battle.units.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.y < b.pos.y)
	for unit in ordered:
		draw_soldier(unit)
	for effect in battle.effects:
		draw_attack(effect)
	# Group shared textures instead of switching glow/atlas for every impact.
	for pulse in impact_pulses:
		var tint: Color = pulse.tint
		tint.a = float(pulse.life) / 0.24 * 0.6
		draw_texture_rect(FX.glow, Rect2(pulse.pos - Vector2(24, 24), Vector2(48, 48)), false, tint)
	for pulse in impact_pulses:
		var progress: float = 1.0 - float(pulse.life) / 0.24
		var tint: Color = pulse.tint
		tint.a = (1 - progress) * 0.6
		draw_cached_ring(pulse.pos, 5 + progress * 19, tint)
	if channel_active:
		draw_channel()
	for ring in revival_rings:
		var progress: float = 1.0 - float(ring.life) / 1.2
		var tint := Color(FRIEND, 1.0 - progress)
		draw_cached_ring(ring.pos, 15 + progress * 48, tint)
		draw_cached_ring(ring.pos, 12 + progress * 30, Color(GOLD, (1 - progress) * 0.7))
		draw_texture_rect(FX.glow, Rect2(ring.pos - Vector2(38, 85), Vector2(76, 110)), false, Color(FRIEND, (1 - progress) * 0.65))
		# A rising spectral duplicate celebrates the recruit without moving its body.
		var frame: int = int(Atlas.KINDS[ring.kind]) * 4 * Atlas.POSES
		var ghost: Vector2 = ring.pos - Vector2(0, progress * 38)
		draw_texture_rect_region(soldier_atlas.texture, Rect2(ghost - Atlas.ORIGIN, Vector2(Atlas.TILE, Atlas.TILE)),
			Atlas.regions[frame], Color(FRIEND, (1 - progress) * 0.55))
	for particle in particles:
		var tint: Color = particle.tint
		tint.a = clampf(float(particle.life) / 0.3, 0, 1)
		var radius: float = particle.size
		draw_texture_rect(FX.dot, Rect2(particle.pos - Vector2(radius, radius), Vector2(radius * 2, radius * 2)), false, tint)

func draw_cached_ring(point: Vector2, radius: float, tint: Color, index: int = Atlas.RING) -> void:
	var scale_value: float = radius / 25.0
	draw_texture_rect_region(soldier_atlas.texture,
		Rect2(point - Atlas.FX_ORIGIN * scale_value, Vector2(Atlas.TILE, Atlas.TILE) * scale_value), Atlas.regions[index], tint)

func draw_channel() -> void:
	var pulse: float = sin(clock * 12) * 0.06
	draw_texture_rect(FX.glow, Rect2(channel_point - Vector2(54, 54), Vector2(108, 108)), false,
		Color(GOLD, 0.35 + channel_progress * 0.35 + pulse))
	draw_cached_ring(channel_point, 34, Color(GOLD, 0.35))
	var step: int = clampi(roundi(channel_progress * Atlas.TIMER_STEPS), 0, Atlas.TIMER_STEPS)
	draw_cached_ring(channel_point, 34, Color("fff0b6"), Atlas.TIMER + step)
	for i in range(7):
		var angle: float = clock * 5 + i * TAU / 7
		var radius: float = 39 - channel_progress * 20
		var point := channel_point + Vector2(cos(angle) * radius, sin(angle) * radius * 0.65 - channel_progress * 24)
		draw_texture_rect(FX.glow, Rect2(point - Vector2(9, 9), Vector2(18, 18)), false, Color(GOLD, 0.8))
		draw_texture_rect(FX.dot, Rect2(point - Vector2(2, 2), Vector2(4, 4)), false, Color("fff0b6"))

func draw_soldier(unit: Dictionary) -> void:
	var p: Vector2 = unit.pos
	var size_value := Vector2(Atlas.TILE, Atlas.TILE)
	# Shared atlas: two textured quads instead of dozens of tessellated shapes.
	draw_texture_rect_region(soldier_atlas.texture, Rect2(p - Atlas.ORIGIN, size_value), Atlas.regions[Atlas.SHADOW])
	draw_set_transform(p, 0, Vector2(float(unit.facing), 1))
	draw_texture_rect_region(soldier_atlas.texture, Rect2(-Atlas.ORIGIN, size_value), Atlas.regions[Atlas.frame_index(unit, clock)])
	draw_set_transform(Vector2.ZERO)
	var hp_ratio: float = clampf(float(unit.hp) / float(Model.STATS[unit.kind].hp), 0, 1)
	if hp_ratio < 0.99 or float(unit.attack) > 0:
		var team: Color = FRIEND if unit.team == 0 else ENEMY
		draw_rect(Rect2(p + Vector2(-16, -66), Vector2(32, 5)), OUTLINE)
		draw_rect(Rect2(p + Vector2(-15, -65), Vector2(30 * hp_ratio, 3)), team)

func draw_corpse(corpse: Dictionary, highlight: bool) -> void:
	var p: Vector2 = corpse.pos
	var cost: int = Model.STATS[corpse.kind].cost
	var available: bool = battle.soul >= cost and battle.outcome != "defeat"
	var tint: Color = GOLD if available else Color("b5b5a0")
	var fade: float = clampf(float(corpse.ttl) / 3, 0.3, 1.0)
	var size_value := Vector2(Atlas.TILE, Atlas.TILE)
	var ring_rect := Rect2(p - Atlas.FX_ORIGIN, size_value)
	draw_texture_rect_region(soldier_atlas.texture, Rect2(p - Atlas.ORIGIN, size_value), Atlas.regions[Atlas.CORPSE])
	draw_texture_rect_region(soldier_atlas.texture, ring_rect, Atlas.regions[Atlas.RING], Color(tint, (0.65 if highlight else 0.3) * fade))
	var step: int = roundi(clampf(float(corpse.ttl) / 14, 0, 1) * Atlas.TIMER_STEPS)
	draw_texture_rect_region(soldier_atlas.texture, ring_rect, Atlas.regions[Atlas.TIMER + step], Color(tint, fade))
	if available:
		var rise: float = fmod(clock * 16 + float(corpse.id) * 7, 25)
		draw_texture_rect(FX.dot, Rect2(p + Vector2(-2, -18 - rise), Vector2(4, 4)), false, Color(GOLD, 1 - rise / 25))
	draw_texture_rect_region(soldier_atlas.texture, Rect2(p + Vector2(0, 28) - Atlas.FX_ORIGIN, size_value), Atlas.regions[Atlas.COST])
	draw_string(font, p + Vector2(-4.5, 33), str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tint)

func draw_attack(effect: Dictionary) -> void:
	var from: Vector2 = effect.from + Vector2(0, -26)
	var to: Vector2 = effect.to + Vector2(0, -26)
	var alpha: float = clampf(float(effect.get("render_life", effect.ttl)) / 0.16, 0, 1)
	if alpha <= 0:
		return
	if effect.archer:
		var head: Vector2 = from.lerp(to, 1.0 - alpha)
		var direction: Vector2 = (to - from).normalized()
		draw_set_transform(head, direction.angle())
		draw_texture(FX.arrow, Vector2(-58, -6))
		draw_set_transform(Vector2.ZERO)
	else:
		var center: Vector2 = from.lerp(to, 0.6)
		var angle: float = (to - from).angle()
		draw_set_transform(center, angle)
		draw_texture(FX.slash, Vector2(-32, -32), Color(GOLD, alpha * 0.7))
		draw_set_transform(Vector2.ZERO)
