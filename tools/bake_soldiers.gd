extends SceneTree

const Layout = preload("res://scripts/soldier_atlas.gd")

class Tiles extends "res://scripts/soldier_painter.gd":
	func _draw() -> void:
		for variant in range(12):
			for frame in range(Layout.POSES):
				var unit := {"id": 0, "kind": ["sword", "archer", "shield"][variant / 4],
					"team": (variant / 2) % 2, "flash": 0.18 if variant % 2 else 0.0,
					"facing": 1.0, "moving": false, "step": 0.0, "attack": 0.0,
					"pos": Layout.region(variant * Layout.POSES + frame).position + Layout.ORIGIN}
				if frame < Layout.IDLE:
					clock = frame * TAU / Layout.IDLE / 2.0
				elif frame < Layout.IDLE + Layout.WALK:
					unit.moving = true
					unit.step = (frame - Layout.IDLE) * TAU / Layout.WALK
				else:
					clock = 0.0
					unit.attack = 0.25 * (1.0 - (frame - Layout.IDLE - Layout.WALK + 0.5) / Layout.ATTACK)
				draw_soldier(unit)
		draw_shadow(Layout.region(Layout.SHADOW).position + Layout.ORIGIN)
		var p: Vector2 = Layout.region(Layout.CORPSE).position + Layout.ORIGIN
		ellipse(p + Vector2(2, 4), Vector2(24, 6), Color(0.04, 0.08, 0.06, 0.3))
		limb(PackedVector2Array([p + Vector2(-9, -3), p + Vector2(7, -1), p + Vector2(18, 6)]), Color("8f9b81"), 3)
		limb(PackedVector2Array([p + Vector2(7, -1), p + Vector2(18, -6)]), Color("8f9b81"), 3)
		draw_circle(p + Vector2(-15, -5), 5, OUTLINE, true, -1, true)
		draw_circle(p + Vector2(-15, -5), 3.5, Color("9da38a"), true, -1, true)
		draw_circle(Layout.region(Layout.COST).position + Layout.FX_ORIGIN, 10, OUTLINE, true, -1, true)
		draw_arc(Layout.region(Layout.RING).position + Layout.FX_ORIGIN, 25, 0, TAU, 48, Color.WHITE, 1.5, true)
		for step in range(1, Layout.TIMER_STEPS + 1):
			draw_arc(Layout.region(Layout.TIMER + step).position + Layout.FX_ORIGIN, 27, -PI / 2, -PI / 2 + TAU * step / Layout.TIMER_STEPS, 48, Color.WHITE, 1.7, true)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Layout.SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)
	viewport.add_child(Tiles.new())
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if image.get_pixel(48, 34).a < 0.5:
		push_error("Atlas bake produced empty artwork")
		quit(1)
		return
	var error := image.save_png("res://assets/soldiers.png")
	if error != OK:
		push_error("Atlas write failed: %s" % error_string(error))
		quit(1)
		return
	print("BAKE PASS: %d soldier poses plus cached shadows/corpses/rings, %dx%d" % [Layout.SHADOW, image.get_width(), image.get_height()])
	viewport.queue_free()
	await process_frame
	quit()
