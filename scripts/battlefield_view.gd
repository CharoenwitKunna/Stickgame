extends Node2D

const Model = preload("res://scripts/battle_model.gd")
const Atlas = preload("res://scripts/soldier_atlas.gd")
const FX = preload("res://scripts/effect_textures.gd")

const FRIEND := Color("7bd4a8")
const ENEMY := Color("ea7c6e")
const GOLD := Color("e8cc88")
const OUTLINE := Color("12221e")
const GHOST_DAMAGE := Color(1.0, 0.94, 0.88, 0.88)

const MAX_PARTICLES := 240
const MAX_PULSES := 32
const MAX_RINGS := 24
const MAX_MOTES := 18

var battle: RefCounted
var atlas: RefCounted
var fx: RefCounted
var clock: float = 0.0
var visible_world := Rect2(0, 0, 1280, 738)

# Revive / hover state read or set by main.gd
var hovered_corpse: int = -1
var hovered: int:
	get:
		return hovered_corpse
	set(value):
		hovered_corpse = value
var channel_corpse: int = -1
var channel_active: bool = false
var channel_point: Vector2 = Vector2.ZERO
var channel_progress: float = 0.0
var move_marker_pos: Vector2 = Vector2.ZERO
var move_marker_timer: float = 0.0

# Reused visible list and stable tie ranks; native O(N log N) sorting.
var _ordered_units: Array = []
var _visible_indices: Array[int] = []
var _sort_source: Array = []

# Trailing HP ghost bar state & facing cache (keyed by unit.id)
var _hp_ghost: Dictionary = {}
var _unit_facing: Dictionary = {}
var _live_ids: Dictionary = {}
var _membership_ids: Array[int] = []
var _membership_initialized := false
var _cache_prune: Array[int] = []

# Pre-allocated Struct-of-Arrays (SoA) ring buffer for particles (zero GC churn)
var _p_pos := PackedVector2Array()
var _p_vel := PackedVector2Array()
var _p_life := PackedFloat32Array()
var _p_max_life := PackedFloat32Array()
var _p_size := PackedFloat32Array()
var _p_tint := PackedColorArray()
var _p_rising := PackedByteArray()
var _p_cursor: int = 0
var _p_active_count: int = 0
# Sorted physical slots preserve ring overwrite, wind phase and alpha order.
var _p_active_indices: Array[int] = []

# Lightweight pooled arrays for pulses, revival rings, and ambient motes
var pulses: Array = []
var rings: Array = []
var motes: Array = []
var _seen_effect_ids: Dictionary = {}
var _seen_effect_order: Array[int] = []


func _ready() -> void:
	atlas = Atlas.new()
	fx = FX.new()
	_init_particle_pools()
	reset_effects()


func _init_particle_pools() -> void:
	_p_pos.resize(MAX_PARTICLES)
	_p_vel.resize(MAX_PARTICLES)
	_p_life.resize(MAX_PARTICLES)
	_p_max_life.resize(MAX_PARTICLES)
	_p_size.resize(MAX_PARTICLES)
	_p_tint.resize(MAX_PARTICLES)
	_p_rising.resize(MAX_PARTICLES)
	for i in range(MAX_PARTICLES):
		_p_life[i] = 0.0
		_p_max_life[i] = 1.0


func reset_effects() -> void:
	channel_active = false
	channel_corpse = -1
	channel_progress = 0.0
	_seen_effect_ids.clear()
	_seen_effect_order.clear()
	for i in range(MAX_PARTICLES):
		_p_life[i] = 0.0
	_p_cursor = 0
	_p_active_count = 0
	_p_active_indices.clear()
	pulses.clear()
	rings.clear()
	motes.clear()
	_hp_ghost.clear()
	_unit_facing.clear()
	_live_ids.clear()
	_membership_ids.clear()
	_membership_initialized = false
	_cache_prune.clear()
	for i in range(MAX_MOTES):
		motes.append({
			"pos": Vector2(randf_range(60.0, 1220.0), randf_range(40.0, 700.0)),
			"phase": randf() * TAU,
			"speed": randf_range(8.0, 18.0),
			"radius": randf_range(2.0, 4.5)
		})
	queue_redraw()


func raise_at(point: Vector2, kind: String = "sword") -> void:
	spawn_revival_burst(point, kind)


func spawn_revival_burst(point: Vector2, kind: String = "sword") -> void:
	if rings.size() >= MAX_RINGS:
		rings.pop_front()
	var ring_scale: float = 1.15 if kind == "shield" else (0.95 if kind == "archer" else 1.0)
	rings.append({
		"pos": point,
		"life": 0.55,
		"max_life": 0.55,
		"radius": 28.0 * ring_scale,
		"tint": GOLD
	})
	emit_particles(point, GOLD, 18, true)
	emit_particles(point, FRIEND, 10, false)


func spawn_impact(point: Vector2, tint: Color = ENEMY, scale_factor: float = 1.0) -> void:
	if pulses.size() >= MAX_PULSES:
		pulses.pop_front()
	pulses.append({
		"pos": point,
		"life": 0.28,
		"max_life": 0.28,
		"radius": 18.0 * scale_factor,
		"tint": tint
	})
	emit_particles(point, tint, 8, false)


func emit_particles(point: Vector2, tint: Color, count: int, rising: bool = false) -> void:
	for _n in range(count):
		var idx: int = _p_cursor
		_p_cursor = (_p_cursor + 1) % MAX_PARTICLES
		var angle: float = randf() * TAU
		var speed: float = randf_range(22.0, 78.0) if not rising else randf_range(14.0, 42.0)
		var vel := Vector2(cos(angle), sin(angle) * 0.65) * speed
		if rising:
			vel.y = -absf(vel.y) - randf_range(28.0, 64.0)
			vel.x *= 0.55
		var lifetime: float = randf_range(0.32, 0.68) if not rising else randf_range(0.45, 0.85)
		if _p_life[idx] <= 0.0:
			_p_active_indices.insert(_p_active_indices.bsearch(idx), idx)
		_p_pos[idx] = point + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
		_p_vel[idx] = vel
		_p_life[idx] = lifetime
		_p_max_life[idx] = lifetime
		_p_size[idx] = randf_range(4.0, 8.5) if not rising else randf_range(5.0, 9.5)
		_p_tint[idx] = tint
		_p_rising[idx] = 1 if rising else 0
	_p_active_count = _p_active_indices.size()


func animate(delta: float) -> void:
	clock += delta
	if move_marker_timer > 0.0:
		move_marker_timer = maxf(0.0, move_marker_timer - delta)

	# Update SoA particle pool in-place (zero allocations)
	var active := 0
	var compacting := false
	if _p_active_count > 0:
		for i in _p_active_indices:
			var life: float = _p_life[i]
			if life <= 0.0:
				compacting = true
				continue
			life -= delta
			_p_life[i] = life
			if life <= 0.0:
				compacting = true
				continue
			if compacting:
				_p_active_indices[active] = i
			active += 1
			var vel: Vector2 = _p_vel[i]
			if _p_rising[i] == 1:
				vel.x += sin(clock * 6.0 + float(i)) * 18.0 * delta
				vel.y -= 15.0 * delta
			else:
				vel = vel.move_toward(Vector2.ZERO, 110.0 * delta)
				vel.y += 95.0 * delta
			_p_vel[i] = vel
			_p_pos[i] += vel * delta
	if compacting:
		_p_active_indices.resize(active)
	_p_active_count = active

	# Update impact pulses backward using swap-and-pop
	var p_idx: int = pulses.size() - 1
	while p_idx >= 0:
		var pulse: Dictionary = pulses[p_idx]
		pulse.life -= delta
		if pulse.life <= 0.0:
			pulses[p_idx] = pulses.back()
			pulses.pop_back()
		p_idx -= 1

	# Update revival rings backward using swap-and-pop
	var r_idx: int = rings.size() - 1
	while r_idx >= 0:
		var ring: Dictionary = rings[r_idx]
		ring.life -= delta
		if ring.life <= 0.0:
			rings[r_idx] = rings.back()
			rings.pop_back()
		r_idx -= 1

	# Trigger one bounded impact burst for each newly observed combat effect.
	if battle != null and "effects" in battle:
		for effect in battle.effects:
			var effect_id: int = int(effect.get("visual_id", -1))
			if effect_id < 0 or _seen_effect_ids.has(effect_id):
				continue
			_seen_effect_ids[effect_id] = true
			_seen_effect_order.append(effect_id)
			if _seen_effect_order.size() > 512:
				_seen_effect_ids.erase(_seen_effect_order.pop_front())
			var tint: Color = FRIEND if is_friendly_team(effect.get("team", 0)) else ENEMY
			spawn_impact(effect.get("to", Vector2.ZERO), tint, 0.8 if effect.get("archer", false) else 1.0)

	# Motes stay in the camera's world-space rectangle as exploration scrolls.
	for mote in motes:
		if not visible_world.has_point(mote.pos):
			mote.pos = visible_world.position + Vector2(randf_range(0, visible_world.size.x), randf_range(0, visible_world.size.y))
		mote.pos.y -= mote.speed * delta
		mote.pos.x += sin(clock * 1.5 + mote.phase) * 9.0 * delta
		if mote.pos.y < visible_world.position.y:
			mote.pos.y = visible_world.end.y
			mote.pos.x = randf_range(visible_world.position.x, visible_world.end.x)

	# Decay trailing HP ghost values smoothly
	if battle != null and "units" in battle:
		var units: Array = battle.units
		var membership_changed := not _membership_initialized or units.size() != _membership_ids.size()
		for index in range(units.size()):
			var unit: Dictionary = units[index]
			var uid: int = unit.get("id", -1)
			if not membership_changed and uid != _membership_ids[index]:
				membership_changed = true
			var max_hp: float = float(unit.get("max_hp", 0.0))
			if not max_hp >= 1.0:
				max_hp = unit_max_hp(unit)
			var hp: float = float(unit.get("hp", max_hp))
			if hp >= max_hp:
				if _hp_ghost.has(uid):
					_hp_ghost.erase(uid)
				continue
			var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
			var prev_ghost: float = _hp_ghost.get(uid, ratio)
			if ratio < 1.0:
				_hp_ghost[uid] = move_toward(prev_ghost, ratio, delta * 0.95) if ratio < prev_ghost else ratio
			else:
				_hp_ghost.erase(uid)
		if membership_changed:
			_membership_initialized = true
			_membership_ids.resize(units.size())
			_live_ids.clear()
			for index in range(units.size()):
				var uid: int = units[index].get("id", -1)
				_membership_ids[index] = uid
				_live_ids[uid] = true
			# Rebuild/prune only on actual identity changes, including same-count swaps.
			_cache_prune.clear()
			for uid in _hp_ghost:
				if not _live_ids.has(uid):
					_cache_prune.append(uid)
			for uid in _cache_prune:
				_hp_ghost.erase(uid)
			_cache_prune.clear()
			for uid in _unit_facing:
				if not _live_ids.has(uid):
					_cache_prune.append(uid)
			for uid in _cache_prune:
				_unit_facing.erase(uid)

	queue_redraw()


func is_friendly_team(team: Variant) -> bool:
	if team is String:
		return team == "friend"
	return int(team) == 0


func active_particle_count() -> int:
	return _p_active_count


func unit_max_hp(unit: Dictionary) -> float:
	var max_hp: float = float(unit.get("max_hp", 0.0))
	if max_hp <= 0.0:
		var stats: Dictionary = Model.STATS.get(unit.get("kind", "sword"), Model.STATS.sword)
		max_hp = float(stats.hp)
	return maxf(1.0, max_hp)


func _sort_units_by_y() -> void:
	_sort_source = battle.units
	_ordered_units.clear()
	_visible_indices.clear()
	for i in range(_sort_source.size()):
		if visible_world.has_point(_sort_source[i].pos):
			_visible_indices.append(i)
	_visible_indices.sort_custom(_compare_unit_indices)
	for i in _visible_indices:
		_ordered_units.append(_sort_source[i])


func _compare_unit_indices(a: int, b: int) -> bool:
	var ay: float = _sort_source[a].pos.y
	var by: float = _sort_source[b].pos.y
	# Source indices preserve streaming ties without mutating simulation data.
	return ay < by if ay != by else a < b


func _draw() -> void:
	if battle == null:
		return

	# 1. Ground move command ripple if present
	if move_marker_timer > 0.0:
		var mp: float = move_marker_timer / 0.45
		var m_col := Color(FRIEND.r, FRIEND.g, FRIEND.b, mp * 0.55)
		draw_cached_ring(move_marker_pos, 18.0 + (1.0 - mp) * 14.0, m_col, Atlas.RING)

	# 2. Ground impact pulses
	for pulse in pulses:
		var progress: float = 1.0 - (pulse.life / pulse.max_life)
		var alpha: float = (1.0 - progress) * 0.65
		var col := Color(pulse.tint.r, pulse.tint.g, pulse.tint.b, alpha)
		draw_cached_ring(pulse.pos, pulse.radius * (0.65 + progress * 0.75), col, Atlas.RING)

	# 3. Corpses & decay rings
	if "corpses" in battle:
		for index in range(battle.corpses.size()):
			var corpse: Dictionary = battle.corpses[index]
			var cid: int = corpse.get("id", -1)
			var is_highlighted: bool = (index == hovered_corpse or cid == channel_corpse)
			if visible_world.has_point(corpse.pos):
				draw_corpse(corpse, is_highlighted)

	# 4. Active revive channeling aura (underneath soldiers)
	draw_channel()

	# 5. Y-sorted living soldiers (using persistent zero-allocation buffer)
	if "units" in battle:
		_sort_units_by_y()
		for unit in _ordered_units:
			draw_soldier(unit)

	# 6. Active weapon slashes, shield bashes, and parabolic arrows
	if "effects" in battle:
		for effect in battle.effects:
			draw_attack(effect)
	initializers_fallback_effects()

	# 7. Revival burst rings
	for ring in rings:
		var r_prog: float = 1.0 - (ring.life / ring.max_life)
		var r_col := Color(ring.tint.r, ring.tint.g, ring.tint.b, (1.0 - r_prog) * 0.85)
		draw_cached_ring(ring.pos, ring.radius * (0.45 + r_prog * 1.15), r_col, Atlas.RING)

	# 8. Pooled particles & ambient battlefield motes
	_draw_particles_and_motes()


func initializers_fallback_effects() -> void:
	if "attacks" in battle:
		for effect in battle.attacks:
			draw_attack(effect)


func _draw_particles_and_motes() -> void:
	var dot_tex: Texture2D = FX.dot
	var glow_tex: Texture2D = FX.glow
	if dot_tex != null and _p_active_count > 0:
		for i in _p_active_indices:
			var life: float = _p_life[i]
			if life <= 0.0:
				continue
			var ratio: float = clampf(life / _p_max_life[i], 0.0, 1.0)
			var base_c: Color = _p_tint[i]
			var col := Color(base_c.r, base_c.g, base_c.b, ratio * 0.9)
			var sz: float = _p_size[i] * (0.45 + 0.55 * ratio)
			var half := Vector2(sz * 0.5, sz * 0.5)
			draw_texture_rect(dot_tex, Rect2(_p_pos[i] - half, Vector2(sz, sz)), false, col)

	if glow_tex != null:
		for mote in motes:
			var pulse: float = 0.22 + 0.14 * sin(clock * 2.2 + mote.phase)
			var m_col := Color(GOLD.r, GOLD.g, GOLD.b, pulse)
			var r: float = mote.radius * 3.0
			draw_texture_rect(glow_tex, Rect2(mote.pos - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, m_col)


func draw_cached_ring(point: Vector2, radius: float, tint: Color, index: int = Atlas.RING) -> void:
	if atlas == null or atlas.get("texture") == null:
		draw_arc(point, radius, 0.0, TAU, 32, tint, 2.0)
		return
	var reg: Rect2 = Atlas.regions[index]
	var diameter: float = radius * 2.0
	var dest := Rect2(point - Vector2(radius, radius), Vector2(diameter, diameter))
	draw_texture_rect_region(atlas.texture, dest, reg, tint)


func draw_channel() -> void:
	if not channel_active:
		return
	var active_prog: float = channel_progress
	var target_pos: Vector2 = channel_point
	if battle != null and "revive_progress" in battle and battle.revive_progress > 0.0:
		active_prog = battle.revive_progress
		if "revive_pos" in battle:
			target_pos = battle.revive_pos
	if active_prog <= 0.001:
		return

	var step_idx: int = clampi(int(round(active_prog * float(Atlas.TIMER_STEPS))), 0, Atlas.TIMER_STEPS)
	var pulse_radius: float = 26.0 + sin(clock * 14.0) * 2.0
	var glow_tex: Texture2D = FX.glow
	if glow_tex != null:
		var g_rad: float = pulse_radius * (1.35 + active_prog * 0.45)
		var g_col := Color(GOLD.r, GOLD.g, GOLD.b, 0.22 + active_prog * 0.32)
		draw_texture_rect(glow_tex, Rect2(target_pos - Vector2(g_rad, g_rad), Vector2(g_rad * 2.0, g_rad * 2.0)), false, g_col)

	draw_cached_ring(target_pos, pulse_radius, Color(GOLD.r, GOLD.g, GOLD.b, 0.35), Atlas.RING)
	draw_cached_ring(target_pos, pulse_radius, GOLD, Atlas.TIMER + step_idx)

	# Converging spiral soul wisps during the 0.7s hold
	var dot_tex: Texture2D = FX.dot
	if dot_tex != null:
		for i in range(6):
			var angle: float = clock * 5.5 + float(i) * (TAU / 6.0)
			var orbit_r: float = lerpf(28.0, 5.0, active_prog)
			var wisp_pos: Vector2 = target_pos + Vector2(cos(angle), sin(angle) * 0.7) * orbit_r
			wisp_pos.y -= active_prog * 10.0
			var w_col := Color(GOLD.r, GOLD.g, GOLD.b, 0.55 + 0.4 * active_prog)
			draw_texture_rect(dot_tex, Rect2(wisp_pos - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), false, w_col)


func draw_soldier(unit: Dictionary) -> void:
	var pos: Vector2 = unit.pos
	var uid: int = unit.get("id", -1)
	var is_friend: bool = is_friendly_team(unit.get("team", 0))

	# Determine horizontal facing with hysteresis to prevent rapid flip jitter
	var cached_facing = _unit_facing.get(uid)
	var facing: float = float(cached_facing) if cached_facing != null else (1.0 if is_friend else -1.0)
	if cached_facing == null:
		# Drawing can precede animate(), then the population can change again.
		_membership_initialized = false
	if "vel" in unit and absf(unit.vel.x) > 4.0:
		facing = 1.0 if unit.vel.x >= 0.0 else -1.0
	elif "facing" in unit and unit.facing != 0:
		facing = 1.0 if float(unit.facing) >= 0.0 else -1.0
	_unit_facing[uid] = facing

	# 1. Ground shadow from atlas
	if atlas != null and atlas.get("texture") != null:
		var shadow_reg: Rect2 = Atlas.regions[Atlas.SHADOW]
		var shadow_dest := Rect2(pos - Atlas.ORIGIN, Vector2(Atlas.TILE, Atlas.TILE))
		draw_texture_rect_region(atlas.texture, shadow_dest, shadow_reg, Color(1, 1, 1, 0.88))

		# 2. Compute subtle attack lunge and hit recoil squash-and-stretch
		var atk_prog: float = float(unit.attack_anim if "attack_anim" in unit else unit.get("attack_progress", 0.0))
		var flash_t: float = float(unit.flash if "flash" in unit else unit.get("hit_flash", 0.0))
		var tilt: float = 0.0
		var scale_vec := Vector2.ONE
		if atk_prog > 0.0:
			var swing_wave: float = sin(atk_prog * PI)
			tilt = 0.12 * swing_wave * facing
			scale_vec = Vector2(1.0 + 0.08 * swing_wave, 1.0 - 0.05 * swing_wave)
		if flash_t > 0.0:
			var hit_wave: float = clampf(flash_t * 5.0, 0.0, 1.0)
			tilt -= 0.11 * hit_wave * facing
			scale_vec = Vector2(1.0 + 0.12 * hit_wave, 1.0 - 0.10 * hit_wave)

		var frame_idx: int = Atlas.frame_index(unit, clock)
		var src_reg: Rect2 = Atlas.regions[frame_idx]
		var draw_w: float = float(Atlas.TILE) * (1.0 if facing >= 0.0 else -1.0)
		var local_dest := Rect2(-Atlas.ORIGIN, Vector2(draw_w, float(Atlas.TILE)))

		if tilt == 0.0 and scale_vec == Vector2.ONE:
			draw_texture_rect_region(atlas.texture, Rect2(pos + local_dest.position, local_dest.size), src_reg, Color.WHITE)
		else:
			draw_set_transform(pos, tilt, scale_vec)
			draw_texture_rect_region(atlas.texture, local_dest, src_reg, Color.WHITE)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 3. Crisp two-layer health bar (with delayed damage ghost bar & highlight bevel)
	var max_hp: float = unit_max_hp(unit)
	var hp: float = clampf(float(unit.get("hp", max_hp)), 0.0, max_hp)
	if hp < max_hp:
		var ratio: float = hp / max_hp
		var ghost_ratio: float = maxf(ratio, float(_hp_ghost.get(uid, ratio)))
		var bar_w: float = 26.0
		var bar_h: float = 4.0
		var bar_pos := pos + Vector2(-bar_w * 0.5, -54.0)
		draw_atlas_rect(Rect2(bar_pos - Vector2(1.0, 1.0), Vector2(bar_w + 2.0, bar_h + 2.0)), OUTLINE)
		if ghost_ratio > ratio + 0.01:
			draw_atlas_rect(Rect2(bar_pos, Vector2(bar_w * ghost_ratio, bar_h)), GHOST_DAMAGE)
		var fill_col: Color = FRIEND if is_friend else ENEMY
		draw_atlas_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), fill_col)
		if ratio > 0.04:
			draw_atlas_rect(Rect2(bar_pos, Vector2(bar_w * ratio, 1.0)), fill_col.lightened(0.35))

	# 4. Specialist / Elite visual crest badge
	var is_spec: bool = unit.get("specialist", false)
	var is_elite: bool = unit.get("elite", false)
	if is_spec or is_elite:
		var badge_pos := pos + Vector2(0, -48.0)
		var crest_col := Color(1.0, 0.85, 0.25) if is_spec else Color(0.95, 0.60, 0.25)
		draw_circle(badge_pos + Vector2(0, -2), 3.0, crest_col)
		draw_line(badge_pos + Vector2(-4, 0), badge_pos + Vector2(4, 0), crest_col, 2.0)
		draw_line(badge_pos + Vector2(0, -4), badge_pos + Vector2(0, 0), crest_col, 2.0)


func draw_atlas_rect(rectangle: Rect2, tint: Color) -> void:
	if atlas != null and atlas.texture != null:
		draw_texture_rect_region(atlas.texture, rectangle, Atlas.solid_region, tint)
	else:
		draw_rect(rectangle, tint)


func draw_corpse(corpse: Dictionary, highlight: bool) -> void:
	var pos: Vector2 = corpse.pos
	var decay_ratio: float = clampf(float(corpse.ttl if "ttl" in corpse else (corpse.timer if "timer" in corpse else corpse.get("life", 7.0))) / 14.0, 0.0, 1.0)
	var ring_alpha: float = (0.55 if highlight else 0.28) * (0.35 + 0.65 * decay_ratio)
	var ring_col := Color(GOLD.r, GOLD.g, GOLD.b, ring_alpha)

	if highlight and FX.glow != null:
		var h_rad: float = 28.0 + sin(clock * 8.0) * 2.5
		draw_texture_rect(FX.glow, Rect2(pos - Vector2(h_rad, h_rad), Vector2(h_rad * 2.0, h_rad * 2.0)), false, Color(GOLD.r, GOLD.g, GOLD.b, 0.28))

	draw_cached_ring(pos, 22.0, ring_col, Atlas.RING)

	# Distinctive crest ring for specialist / elite corpses
	var is_spec: bool = corpse.get("specialist", false)
	var is_elite: bool = corpse.get("elite", false)
	if is_spec or is_elite:
		var badge_col := Color(1.0, 0.85, 0.25, 0.85) if is_spec else Color(0.95, 0.60, 0.25, 0.85)
		draw_cached_ring(pos, 26.0, badge_col, Atlas.RING)

	if atlas != null and atlas.get("texture") != null:
		var c_reg: Rect2 = Atlas.regions[Atlas.CORPSE]
		var c_dest := Rect2(pos - Atlas.FX_ORIGIN, Vector2(Atlas.TILE, Atlas.TILE))
		var c_tint := Color(1.0, 1.0, 1.0, 0.50 + 0.50 * decay_ratio)
		draw_texture_rect_region(atlas.texture, c_dest, c_reg, c_tint)


func draw_attack(effect: Dictionary) -> void:
	var kind: String = effect.kind if "kind" in effect else ("archer" if effect.get("archer", false) else "sword")
	var total_dur: float = maxf(0.001, float(effect.duration if "duration" in effect else effect.get("max_life", 0.16)))
	var rem: float = float(effect.ttl if "ttl" in effect else (effect.timer if "timer" in effect else effect.get("life", total_dur * 0.5)))
	var progress: float = clampf(1.0 - (rem / total_dur), 0.0, 1.0)
	var is_friend: bool = is_friendly_team(effect.get("team", 0))
	var tint: Color = FRIEND if is_friend else ENEMY

	if kind == "archer" or kind == "arrow":
		var from_p: Vector2 = effect.from if "from" in effect else effect.get("pos", Vector2.ZERO)
		var to_p: Vector2 = effect.to if "to" in effect else effect.get("target", from_p + Vector2(60.0, 0.0))
		var ground_p: Vector2 = from_p.lerp(to_p, progress)
		var dist: float = from_p.distance_to(to_p)
		var arc_h: float = clampf(dist * 0.16, 14.0, 44.0)
		var lift: float = 4.0 * arc_h * progress * (1.0 - progress)
		var prev_p: float = maxf(0.0, progress - 0.05)
		var prev_lift: float = 4.0 * arc_h * prev_p * (1.0 - prev_p)
		var air_pos: Vector2 = ground_p - Vector2(0.0, lift)
		var prev_air: Vector2 = from_p.lerp(to_p, prev_p) - Vector2(0.0, prev_lift)
		var flight_angle: float = (air_pos - prev_air).angle()

		# Ground shadow under parabolic arrow
		draw_line(ground_p - Vector2(7.0, 0.0), ground_p + Vector2(7.0, 0.0), Color(0.02, 0.05, 0.04, 0.35), 2.5)

		if FX.arrow != null:
			draw_set_transform(air_pos, flight_angle, Vector2.ONE)
			draw_texture_rect(FX.arrow, Rect2(Vector2(-32.0, -6.0), Vector2(64.0, 12.0)), false, Color.WHITE)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_line(prev_air, air_pos, tint.lightened(0.25), 2.5)
	else:
		var center: Vector2 = effect.pos if "pos" in effect else effect.get("to", Vector2.ZERO)
		var from_p: Vector2 = effect.get("from", center)
		var to_p: Vector2 = effect.get("to", center + Vector2.RIGHT)
		var angle: float = float(effect.angle if "angle" in effect else (to_p - from_p).angle())
		var alpha: float = sin(progress * PI)
		var slash_col := Color(tint.r, tint.g, tint.b, alpha * 0.95)
		if FX.glow != null:
			var g_col := Color(tint.r, tint.g, tint.b, alpha * 0.35)
			draw_texture_rect(FX.glow, Rect2(center - Vector2(30.0, 30.0), Vector2(60.0, 60.0)), false, g_col)
		if FX.slash != null:
			draw_set_transform(center, angle, Vector2(1.0 + 0.18 * progress, 1.0))
			draw_texture_rect(FX.slash, Rect2(Vector2(-32.0, -32.0), Vector2(64.0, 64.0)), false, slash_col)
			# Razor-hot core glint
			draw_texture_rect(FX.slash, Rect2(Vector2(-28.0, -28.0), Vector2(56.0, 56.0)), false, Color(1, 1, 1, alpha * 0.72))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
