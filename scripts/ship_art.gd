extends RefCounted
## Shared vector ship/troop art used on the galaxy map and in battle.
## Local space: +x is forward. s = scale.

static func _xf(pts: Array, pos: Vector2, ang: float, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts: out.append(pos + (p * s).rotated(ang))
	return out

static func draw_ship(ci: CanvasItem, type: String, pos: Vector2, ang: float, col: Color, s := 1.0, time := 0.0, trail := true) -> void:
	var hull: Array; var engine := Vector2(-8, 0); var trail_len := 18.0
	match type:
		"Scout":  hull = [Vector2(18, 0), Vector2(-10, -4), Vector2(-6, 0), Vector2(-10, 4)]; engine = Vector2(-8, 0); trail_len = 40.0
		"Tank":   hull = [Vector2(12, -5), Vector2(12, 5), Vector2(4, 10), Vector2(-12, 11), Vector2(-14, 0), Vector2(-12, -11), Vector2(4, -10)]; engine = Vector2(-13, 0); trail_len = 12.0
		"Bomber": hull = [Vector2(14, 0), Vector2(-4, -6), Vector2(-12, -16), Vector2(-8, 0), Vector2(-12, 16), Vector2(-4, 6)]; engine = Vector2(-9, 0); trail_len = 20.0
		"Shield": hull = [Vector2(12, 0), Vector2(6, -9), Vector2(-6, -9), Vector2(-12, 0), Vector2(-6, 9), Vector2(6, 9)]; engine = Vector2(-11, 0)
		"Medic":  hull = [Vector2(12, -4), Vector2(12, 4), Vector2(0, 9), Vector2(-10, 7), Vector2(-10, -7), Vector2(0, -9)]; engine = Vector2(-10, 0)
		_:        hull = [Vector2(13, 0), Vector2(-8, -8), Vector2(-4, 0), Vector2(-8, 8)]
	var flick := 0.75 + 0.25 * sin(time * 30.0 + pos.x)
	var ep := pos + (engine * s).rotated(ang)
	if trail:
		var back := Vector2(-1, 0).rotated(ang)
		for i in 6:
			var k := float(i) / 6.0
			ci.draw_circle(ep + back * trail_len * s * k, (3.5 - 2.5 * k) * s, Color(col.lightened(0.5), 0.35 * (1.0 - k)))
	ci.draw_circle(ep, 4.0 * s * flick, Color(1.0, 0.85, 0.5, 0.9))
	var poly := _xf(hull, pos, ang, s)
	ci.draw_colored_polygon(poly, col.darkened(0.15))
	var inner := _xf(hull.map(func(p): return p * 0.6 + Vector2(2, 0)), pos, ang, s)
	ci.draw_colored_polygon(inner, col.lightened(0.2))
	var outline := poly.duplicate(); outline.append(poly[0])
	ci.draw_polyline(outline, col.lightened(0.6), max(1.0, 1.2 * s), true)
	match type:
		"Bomber": ci.draw_colored_polygon(_xf([Vector2(2, -3), Vector2(2, 3), Vector2(-6, 3), Vector2(-6, -3)], pos, ang, s), Color(0.1, 0.1, 0.12))
		"Tank":
			ci.draw_colored_polygon(_xf([Vector2(-2, -14), Vector2(6, -14), Vector2(6, -9), Vector2(-2, -9)], pos, ang, s), col.darkened(0.4))
			ci.draw_colored_polygon(_xf([Vector2(-2, 14), Vector2(6, 14), Vector2(6, 9), Vector2(-2, 9)], pos, ang, s), col.darkened(0.4))
		"Medic":
			ci.draw_line(pos + Vector2(-4, 0) * s, pos + Vector2(4, 0) * s, Color.WHITE, 2.5 * s)
			ci.draw_line(pos + Vector2(0, -4) * s, pos + Vector2(0, 4) * s, Color.WHITE, 2.5 * s)
	if type != "Medic": ci.draw_circle(pos + (Vector2(5, 0) * s).rotated(ang), 2.2 * s, Color(0.8, 0.95, 1.0, 0.9))
