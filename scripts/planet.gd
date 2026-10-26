extends Node2D
## Planet build screen: spend THIS planet's ships on factories (production) and defense (tower budget).

const PlanetView := preload("res://scripts/planet_view.gd")
const NEBULA := preload("res://art/nebula.jpg")
const MAX_STATIONS := 16
const C := Vector2(380, 370)
const R := 190.0
const TOWER_COL := {"Gun": Color(1, 0.85, 0.3), "Frost": Color(0.5, 0.9, 1), "Missile": Color(1, 0.45, 0.3), "Laser": Color(0.9, 0.4, 1)}

var lbl: Label          # kept for compatibility (stats text)
var title: Label
var sub: Label
var rows := {}
var towers_lbl: Label
var fbtn: Button
var dbtn: Button
var fcost: Label
var dcost: Label
var front: Node2D

func _icon_tex(n: String) -> Texture2D: return load("res://art/icons/%s.png" % n)

func _ready() -> void:
	var p = _p()
	var view := PlanetView.new(); view.position = C; add_child(view); view.setup(p, R)
	front = Node2D.new(); front.z_index = 2; add_child(front); front.draw.connect(_draw_front)
	var ui := CanvasLayer.new(); add_child(ui)
	var card := Panel.new(); card.position = Vector2(770, 24); card.size = Vector2(760, 410)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.07, 0.15, 0.82); sb.set_corner_radius_all(20)
	sb.set_border_width_all(2); sb.border_color = Game.COLORS[p.owner].lightened(0.2)
	card.add_theme_stylebox_override("panel", sb); ui.add_child(card)
	title = Game.make_label(p.get("name", "Planet"), Vector2(28, 14), 44); card.add_child(title)
	sub = Game.make_label("", Vector2(30, 72), 22); card.add_child(sub)
	sub.add_theme_color_override("font_color", Game.COLORS[p.owner].lightened(0.4))
	var y := 115
	for k in [["ship", "ships"], ["factory", "fact"], ["shield", "def"], ["tower", "bonus"]]:
		var ic := TextureRect.new(); ic.texture = _icon_tex(k[0]); ic.position = Vector2(30, y); ic.size = Vector2(40, 40)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; card.add_child(ic)
		var l := Game.make_label("", Vector2(84, y + 2), 28); card.add_child(l); rows[k[1]] = l
		y += 54
	towers_lbl = Game.make_label("", Vector2(30, y + 4), 22); card.add_child(towers_lbl)
	lbl = Label.new(); lbl.visible = false; ui.add_child(lbl)
	fbtn = Game.make_button("", Vector2(770, 450), Vector2(760, 86)); ui.add_child(fbtn)
	Game.style_button(fbtn, Color(0.55, 0.42, 0.12), "factory"); fbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fbtn.pressed.connect(_buy_factory); fcost = _cost_tag(fbtn)
	dbtn = Game.make_button("", Vector2(770, 546), Vector2(760, 86)); ui.add_child(dbtn)
	Game.style_button(dbtn, Color(0.15, 0.4, 0.7), "shield"); dbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	dbtn.pressed.connect(_buy_defense); dcost = _cost_tag(dbtn)
	var back := Game.make_button("Back to Galaxy", Vector2(24, 632), Vector2(330, 76)); ui.add_child(back)
	Game.style_button(back, Color(0.28, 0.3, 0.38), "back")
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/galaxy.tscn"))
	_process(0)

func _cost_tag(b: Button) -> Label:
	var ic := TextureRect.new(); ic.texture = _icon_tex("ship"); ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.size = Vector2(36, 36); ic.position = Vector2(b.size.x - 170, 25); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(ic)
	var l := Game.make_label("", Vector2(b.size.x - 126, 20), 32); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(l)
	return l

func _p(): return Game.planets[Game.selected_planet]

func can_factory() -> bool:
	var p = _p(); return p.ships >= Game.factory_cost(p) and p.factories < Game.max_factories(p.owner)

func _buy_factory() -> bool:
	var p = _p()
	if not can_factory(): return false
	p.ships -= Game.factory_cost(p); p.factories += 1; Audio.sfx("build"); return true

func _buy_defense() -> bool:
	var p = _p()
	if p.ships < Game.DEFENSE_COST: return false
	p.ships -= Game.DEFENSE_COST; p.defense += 1; Audio.sfx("build"); return true

func _process(_d: float) -> void:
	var p = _p()
	var owner_s: String = ["Neutral", "Your planet", "Enemy planet"][clampi(p.owner, 0, 2)] if p.owner is int else str(p.owner)
	sub.text = "%s  ·  %s world  ·  sector #%d" % [owner_s, str(p.get("ptype", "rocky")).capitalize(), Game.selected_planet]
	rows.ships.text = "Ships: %d   (your currency here)" % int(p.ships)
	rows.fact.text = "Factories: %d / %d   (+%.1f ships/s)" % [p.factories, Game.max_factories(p.owner), Game.production(p)]
	rows.def.text = "Defense: %d   (tower budget %d)" % [p.defense, int(p.ships) * 3 + p.defense * 30]
	rows.bonus.text = "Garrison tower dmg bonus: x%.2f" % Game.garrison_mult(p)
	var counts := {}
	for k in p.get("tower_types", {}): counts[p.tower_types[k]] = counts.get(p.tower_types[k], 0) + 1
	var parts := []
	for t in counts: parts.append("%s x%d" % [t, counts[t]])
	towers_lbl.text = "Towers: " + (", ".join(parts) if parts.size() > 0 else "none (first one is free)")
	var maxed: bool = p.factories >= Game.max_factories(p.owner)
	lbl.text = rows.fact.text
	fbtn.text = "Build Factory" if not maxed else "Factories MAXED (upgrade Factory Cap)"
	fcost.text = "" if maxed else str(Game.factory_cost(p))
	fbtn.get_child(0).visible = not maxed
	fbtn.disabled = not can_factory()
	dbtn.text = "Add Defense"
	dcost.text = str(Game.DEFENSE_COST)
	dbtn.disabled = p.ships < Game.DEFENSE_COST
	queue_redraw(); front.queue_redraw()

func _station_pos(i: int, n: int, t: float) -> Vector2:
	var a := TAU * i / n + t * 0.25
	var ring := 1 + (i % 2)
	return C + Vector2(cos(a) * (R + 30 + ring * 18), sin(a) * (R + 30 + ring * 18) * 0.32)

func _stations(ci: CanvasItem, front_side: bool) -> void:
	var p = _p()
	var n := mini(p.factories, MAX_STATIONS)
	var t := Time.get_ticks_msec() / 1000.0
	for i in n:
		var a := TAU * i / n + t * 0.25
		if (sin(a) > 0) != front_side: continue
		var sp := _station_pos(i, n, t)
		var sh := 0.75 + 0.25 * sin(a)
		ci.draw_rect(Rect2(sp - Vector2(14, 3), Vector2(28, 6)), Color(0.35, 0.55, 0.9) * sh)
		ci.draw_rect(Rect2(sp - Vector2(6, 6), Vector2(12, 12)), Color(0.95, 0.82, 0.4) * sh)
		ci.draw_circle(sp, 2.5, Color(1, 1, 0.8, 0.6 + 0.4 * sin(t * 4 + i)))

func _draw() -> void:
	draw_texture(NEBULA, Vector2.ZERO)
	_stations(self, false)

func _draw_front() -> void:
	var p = _p()
	var font := ThemeDB.fallback_font
	_stations(front, true)
	if p.factories > MAX_STATIONS:
		var bp := C + Vector2(R * 0.75, R * 0.85)
		front.draw_circle(bp, 30, Color(0.95, 0.75, 0.2)); front.draw_arc(bp, 30, 0, TAU, 32, Color.WHITE, 2, true)
		front.draw_string(font, bp + Vector2(-30, 9), "+%d" % (p.factories - MAX_STATIONS), HORIZONTAL_ALIGNMENT_CENTER, 60, 24, Color.BLACK)
	# defense: shield ring segments
	if p.defense > 0:
		var segs := mini(p.defense, 12)
		var t := Time.get_ticks_msec() / 1000.0
		for i in segs:
			var a0 := TAU * i / 12.0 - PI / 2
			front.draw_arc(C, R + 12, a0 + 0.05, a0 + TAU / 12.0 - 0.05, 12, Color(0.45, 0.8, 1, 0.55 + 0.25 * sin(t * 2 + i)), 6, true)
		var sp := C + Vector2(-R - 10, -R + 10)
		front.draw_texture_rect(load("res://art/icons/shield.png"), Rect2(sp - Vector2(22, 22), Vector2(44, 44)), false)
		front.draw_string_outline(font, sp + Vector2(24, 10), "x%d" % p.defense, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 6, Color.BLACK)
		front.draw_string(font, sp + Vector2(24, 10), "x%d" % p.defense, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.7, 0.9, 1))
	# persistent towers as type chips under the planet
	var i := 0
	for k in p.get("tower_types", {}):
		var tp: String = p.tower_types[k]
		var cp := C + Vector2(-R + 20 + i * 44, R + 70)
		if cp.x > C.x + R: break
		front.draw_circle(cp, 17, Color(0.15, 0.15, 0.2)); front.draw_circle(cp, 11, TOWER_COL.get(tp, Color.WHITE))
		front.draw_arc(cp, 17, 0, TAU, 20, TOWER_COL.get(tp, Color.WHITE), 2, true)
		i += 1
