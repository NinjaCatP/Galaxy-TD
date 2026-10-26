extends Node2D
## Galcon-style map. Drag from an owned planet to any planet to send ships.
## Tap an owned planet to open its build screen.

const FLEET_SPEED := 110.0
var drag_from := -1
var drag_pos := Vector2.ZERO
var save_timer := 0.0
var pause_panel: Control
var info: Label
var pct_btn: Button
var type_btn: Button

func _ready() -> void:
	var ui := CanvasLayer.new(); add_child(ui)
	info = Game.make_label("", Vector2(20, 10), 26); ui.add_child(info)
	pct_btn = Game.make_button("", Vector2(20, 620), Vector2(200, 80)); ui.add_child(pct_btn)
	pct_btn.pressed.connect(_cycle_pct)
	type_btn = Game.make_button("", Vector2(240, 620), Vector2(240, 80)); ui.add_child(type_btn)
	type_btn.pressed.connect(_cycle_type)
	var up := Game.make_button("Upgrades", Vector2(1320, 620), Vector2(220, 80)); ui.add_child(up)
	up.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/upgrades.tscn"))
	var menu := Game.make_button("Pause", Vector2(1380, 10), Vector2(160, 80)); ui.add_child(menu)
	menu.pressed.connect(_toggle_pause)
	pause_panel = ColorRect.new(); pause_panel.color = Color(0, 0, 0, 0.75)
	pause_panel.position = Vector2(0, 0); pause_panel.size = Vector2(1560, 720); pause_panel.visible = false
	ui.add_child(pause_panel)
	pause_panel.add_child(Game.make_label("PAUSED", Vector2(680, 150), 60))
	var r := Game.make_button("Resume", Vector2(600, 300), Vector2(360, 110)); pause_panel.add_child(r)
	r.pressed.connect(_toggle_pause)
	var sq := Game.make_button("Save & Quit to Menu", Vector2(600, 440), Vector2(360, 110)); pause_panel.add_child(sq)
	sq.pressed.connect(func():
		Game.save_game(); Game.result_msg = ""
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	Game.in_game = true
	Audio.music("music_galaxy")
	Audio.make_controls(pause_panel, Vector2(1020, 300))
	_refresh_buttons()
	_build_planets()
	var legend := Node2D.new(); ui.add_child(legend); legend.draw.connect(_draw_legend.bind(legend))

func _toggle_pause() -> void:
	pause_panel.visible = not pause_panel.visible
	set_process(not pause_panel.visible)

func _cycle_pct() -> void:
	var opts := [0.25, 0.5, 0.75, 1.0]
	Game.send_pct = opts[(opts.find(Game.send_pct) + 1) % opts.size()]
	_refresh_buttons()

func _cycle_type() -> void:
	var keys := Game.TROOPS.keys()
	var i := keys.find(Game.fleet_type)
	for n in range(1, keys.size() + 1):
		var k = keys[(i + n) % keys.size()]
		if Game.unlocked[k]: Game.fleet_type = k; break
	_refresh_buttons()

func _refresh_buttons() -> void:
	pct_btn.text = "Send %d%%" % int(Game.send_pct * 100)
	type_btn.text = "Troops: " + Game.fleet_type

var conquest := {}   # active conquest/jump sequence
var banner: Label

func _process(delta: float) -> void:
	if not conquest.is_empty():
		_conquest_step(delta); return
	save_timer += delta
	if save_timer > 10.0 and not Game.auto_battle: save_timer = 0; Game.save_game()
	for p in Game.planets:
		if p.owner != Game.NEUTRAL:
			p.ships += Game.production(p) * delta
	Game.elapsed += delta
	var regen := 0.2 * Game.lvl("regen", Game.PLAYER)
	if regen > 0:
		for p in Game.planets: if p.owner == Game.PLAYER and not Game.is_mother(p): p.ships += regen * delta
	_move_fleets(delta)
	if get_tree() == null or not is_inside_tree(): return
	_ai(delta)
	_check_end()
	info.text = Game.difficulty_label() + "   [%s]   Tech pts: %d   Planets: you %d / AI %d" % [Game.difficulty, Game.tech, Game.count_owned(Game.PLAYER), Game.count_owned(Game.AI)]
	queue_redraw(); _process_overlay()

func _move_fleets(delta: float) -> void:
	var i := 0
	while i < Game.fleets.size():
		var f = Game.fleets[i]
		var target = Game.planets[f.to]
		var dir: Vector2 = target.pos - f.pos
		if dir.length() < Game.radius(target):
			Game.fleets.remove_at(i)
			if _arrive(f): return  # scene changed
			continue
		var spd := FLEET_SPEED * Game.fleet_speed_mult(f.owner) * (1.6 if f.type == "Scout" else (0.7 if f.type == "Tank" else 1.0))
		f.pos += dir.normalized() * spd * delta
		i += 1

## Returns true if a battle scene was started.
func _arrive(f) -> bool:
	var p = Game.planets[f.to]
	if p.owner == f.owner:
		p.ships += f.count
	elif p.owner == Game.NEUTRAL:
		p.ships -= f.count
		if p.ships < 0:
			p.owner = f.owner; p.ships = -p.ships; p.towers = {}; p.tower_types = {}
			if f.owner == Game.PLAYER: Game.tech += 1; Game.recent_captures.append(f.to); Audio.sfx("capture")
			if not Game.auto_battle: Game.save_game()
	else:
		# Occupied planet -> tower defense battle
		if Game.auto_battle:
			_auto_resolve(f, p); return false
		Game.pending_battle = {"planet": f.to, "attacker": f.owner, "ships": int(f.count), "type": f.type}
		Game.save_game()  # if closed mid-battle, Continue restarts this battle
		get_tree().change_scene_to_file.call_deferred("res://scenes/battle.tscn")
		set_process(false)
		return true
	return false

func send(from: int, to: int, owner: int, pct: float, type: String, cap := -1) -> void:
	var p = Game.planets[from]
	var n := int(p.ships * pct)
	if cap >= 0: n = min(n, cap)
	if n < 1: return
	p.ships -= n
	if owner == Game.PLAYER: Audio.sfx("launch")
	Game.fleets.append({"from": from, "to": to, "owner": owner, "count": n, "pos": p.pos, "type": type})

func _ai(delta: float) -> void:
	var d := Game.D()
	Game.ai_timer += delta; Game.ai_build_timer += delta; Game.since_attack += delta
	if Game.ai_build_timer > max(d.build * 0.4, d.build - Game.elapsed / 40.0):
		Game.ai_build_timer = 0
		# AI builds factories by spending that planet's ships (same rule as the player)
		var cand := []
		for i in Game.planets.size():
			var q = Game.planets[i]
			if q.owner == Game.AI and q.factories < Game.max_factories(Game.AI) and q.ships >= Game.factory_cost(q) + 5: cand.append(i)
		if cand.size() > 0:
			var q = Game.planets[cand.pick_random()]
			q.ships -= Game.factory_cost(q); q.factories += 1
	if Game.ai_timer < d.decision: return
	Game.ai_timer = 0
	var mine := []
	for i in Game.planets.size(): if Game.planets[i].owner == Game.AI: mine.append(i)
	if mine.is_empty(): return
	var cap := Game.attack_cap()
	# Rank player planets as targets
	var targets := []
	var centre := Vector2.ZERO
	for i in mine: centre += Game.planets[i].pos
	centre /= mine.size()
	for i in Game.planets.size():
		var p = Game.planets[i]
		if p.owner != Game.PLAYER or Game.is_mother(p): continue
		var s: float = p.ships + p.defense * 8 + p.get("towers", {}).size() * 6
		if d.target == "near": s += centre.distance_to(p.pos) * 0.05
		elif d.target == "production": s -= Game.production(p) * 15
		if d.counter and i in Game.recent_captures: s -= 40
		targets.append([s, i])
	targets.sort()
	var attacked := false
	for k in min(d.fronts, targets.size()):
		var ti: int = targets[k][1]
		var t = Game.planets[ti]
		var avail := 0.0
		for i in mine: avail += int(Game.planets[i].ships * 0.7)
		var force: float = min(cap, avail)
		var need: float = t.ships * 1.2 + 5
		if force >= need or (Game.since_attack > d.force_timer and force >= d.min_attack):
			_launch(mine, ti, int(force), d)
			attacked = true
	if attacked: Game.since_attack = 0; return
	# Otherwise expand into the cheapest neutral planet
	var best: int = mine.reduce(func(a, b): return a if Game.planets[a].ships > Game.planets[b].ships else b)
	var src = Game.planets[best]
	var nt := -1; var ns := INF
	for i in Game.planets.size():
		var p = Game.planets[i]
		if p.owner != Game.NEUTRAL: continue
		if src.ships * 0.6 > p.ships + 3:
			var s: float = p.ships + src.pos.distance_to(p.pos) * 0.05
			if s < ns: ns = s; nt = i
	if nt != -1: send(best, nt, Game.AI, 0.6, "Trooper")

## Mass a fleet of up to `force` ships from several AI planets at one target.
func _launch(mine: Array, ti: int, force: int, d: Dictionary) -> void:
	if force < 1: return
	var cap := Game.attack_cap()
	mine.sort_custom(func(a, b): return Game.planets[a].ships > Game.planets[b].ships)
	var type := _ai_troop(d, Game.planets[ti])
	var sent := 0
	for i in mine:
		if sent >= force: break
		var before := int(Game.planets[i].ships)
		send(i, ti, Game.AI, 0.7, type, force - sent)
		sent += before - int(Game.planets[i].ships)
	if sent <= 0: return
	Game.stats.attacks = Game.stats.get("attacks", 0) + 1
	Game.stats.max_attack = max(Game.stats.get("max_attack", 0), sent)
	if sent > cap + 0.001: Game.stats.cap_violations = Game.stats.get("cap_violations", 0) + 1

func _ai_troop(d: Dictionary, target) -> String:
	if d.bombers and target.get("towers", {}).size() > 0 and randf() < 0.6: return "Bomber"
	if Game.elapsed > 60 and randf() < min(d.upg, Game.elapsed / 400.0):
		var opts := ["Scout", "Tank", "Bomber", "Shield", "Medic"].filter(func(k): return Game.has_troop(k, Game.AI))
		return "Trooper" if opts.is_empty() else opts.pick_random()
	return "Trooper"

## Instant resolution used by headless tests (same outcome rules as the battle scene).
func _auto_resolve(f, p) -> void:
	var cnt: float = f.count
	if f.owner == Game.AI: cnt = min(cnt, max(1, Game.attack_cap()))
	if cnt > p.ships:
		p.owner = f.owner; p.ships = cnt - p.ships; p.towers = {}; p.tower_types = {}
		if f.owner == Game.PLAYER: Game.recent_captures.append(f.to)
		else: Game.recent_captures.erase(f.to)
	elif p.owner == Game.PLAYER:
		p.ships += cnt   # rule 2: defeated attackers join the garrison
	else:
		p.ships = max(1, p.ships - cnt * 0.5)

func _check_end() -> void:
	if Game.auto_battle: return
	var ai_fleets := Game.fleets.any(func(f): return f.owner == Game.AI)
	var pl_fleets := Game.fleets.any(func(f): return f.owner == Game.PLAYER)
	if Game.count_owned(Game.AI) == 0 and not ai_fleets:
		start_conquest()
	elif lost():
		_end("DEFEAT. Your empire has fallen.")

## Lose: no planets AND mothership empty AND no player fleets.
func lost() -> bool:
	var pl_fleets := Game.fleets.any(func(f): return f.owner == Game.PLAYER)
	return Game.count_owned(Game.PLAYER) == 0 and Game.mother_ships() < 1 and not pl_fleets

const CONQ_GATHER := 3.0
const CONQ_JUMP := 1.6
const MOTHER_CENTER := Vector2(780, 360)

func start_conquest() -> void:
	if not conquest.is_empty(): return
	var src := []
	for p in Game.planets:
		if p.owner == Game.PLAYER and p.ships >= 1: src.append({"pos": p.pos, "n": p.ships, "p": p})
	conquest = {"t": 0.0, "total": Game.conquest_total(), "src": src, "jumped": false, "sound": false,
		"fleet_start": Game.fleets.map(func(f): return f.pos)}
	drag_from = -1
	var shown := Game.galaxy
	banner.text = "Galaxy %d conquered!\nAll ships to the Mothership...  Jumping to Galaxy %d  -  difficulty +1%%" % [shown, shown + 1]
	banner.visible = true
	Audio.sfx("win")

func _conquest_step(delta: float) -> void:
	var c := conquest
	c.t += delta
	var k: float = clamp(c.t / CONQ_GATHER, 0.0, 1.0)
	for s in c.src: s.p.ships = s.n * (1.0 - k)
	for i in Game.fleets.size():
		if i < c.fleet_start.size(): Game.fleets[i].pos = c.fleet_start[i].lerp(MOTHER_CENTER, k)
	if c.t > CONQ_GATHER and not c.sound:
		c.sound = true; Audio.sfx("hyperspace")
	if c.t > CONQ_GATHER + CONQ_JUMP and not c.jumped:
		c.jumped = true
		Game.next_galaxy(int(c.total))
		if not Game.auto_battle: Game.save_game()
		get_tree().change_scene_to_file.call_deferred("res://scenes/galaxy.tscn")
	queue_redraw(); _process_overlay()

## Mothership art: layered procedural capital-ship texture + live engines, lights, shield aura, bob.
const MOTHER_TEX := preload("res://art/ships/mothership.png")
const GLOW_TEX := preload("res://art/ships/glow.png")
static func draw_mother(ci: CanvasItem, pos: Vector2, s: float, t: float, charge := 0.0, stretch := 1.0) -> void:
	var k := s * 0.25
	pos += Vector2(sin(t * 0.7) * 3.0, sin(t * 1.1) * 4.0) * s   # idle drift/bob
	var pc: Color = Game.COLORS[Game.PLAYER]
	# shield aura shimmer
	var sh := 0.18 + 0.06 * sin(t * 2.3) + 0.5 * charge
	ci.draw_texture_rect(GLOW_TEX, Rect2(pos - Vector2(640, 300) * k, Vector2(1280, 600) * k), false, Color(pc, sh))
	for i in 3:
		var a := t * 0.8 + i * 2.1
		ci.draw_arc(pos, 330 * k, a, a + 0.9, 24, Color(pc.lightened(0.4), 0.15 + 0.1 * sin(t * 3 + i)), 3 * s, true)
	# engine exhaust: flickering plumes + particles
	for j in 5:
		var ey := (-120 + j * 60) * k
		var ep := pos + Vector2(-520 * k, ey)
		var fl := 0.8 + 0.2 * sin(t * 23.0 + j * 1.7) + 0.1 * sin(t * 41.0 + j)
		var L := (150 + 120 * charge) * k * fl * stretch
		ci.draw_texture_rect(GLOW_TEX, Rect2(ep - Vector2(L, 30 * k), Vector2(L * 1.3, 60 * k)), false, Color(0.4, 0.7, 1.0, 0.75))
		ci.draw_texture_rect(GLOW_TEX, Rect2(ep - Vector2(L * 0.5, 14 * k), Vector2(L * 0.65, 28 * k)), false, Color(0.9, 0.97, 1.0, 0.95))
		for m in 6:
			var u := fmod(t * 1.6 + m * 0.17 + j * 0.31, 1.0)
			ci.draw_circle(ep + Vector2(-u * L * 1.6, sin(m * 7.0 + j) * 10 * k * u), (3.0 - 2.0 * u) * s, Color(0.6, 0.85, 1, 0.8 * (1.0 - u)))
	ci.draw_texture_rect(MOTHER_TEX, Rect2(pos - Vector2(512, 220) * k, Vector2(1024, 440) * k), false)
	# pulsing running lights
	var lights := [Vector2(488, 0), Vector2(-312, -195), Vector2(-312, 195), Vector2(-152, -137), Vector2(-117, -117), Vector2(140, -120), Vector2(140, 120), Vector2(340, -60), Vector2(340, 60)]
	for i in lights.size():
		var on := 0.5 + 0.5 * sin(t * 3.0 + i * 0.9)
		var lc := Color(1, 0.35, 0.3) if i in [1, 2, 3, 4] else Color(0.55, 0.9, 1)
		ci.draw_texture_rect(GLOW_TEX, Rect2(pos + lights[i] * k - Vector2(14, 14) * s * on, Vector2(28, 28) * s * on), false, Color(lc, 0.9))
	if charge > 0:   # warp charge glow at the bow
		var bow := pos + Vector2(500, 0) * k
		var r := (40 + 160 * charge) * k
		ci.draw_texture_rect(GLOW_TEX, Rect2(bow - Vector2(r, r), Vector2(r, r) * 2), false, Color(0.7, 0.9, 1, 0.5 + 0.5 * charge))

func _end(msg: String) -> void:
	Game.result_msg = msg
	Game.in_game = false
	Game.delete_save()
	set_process(false)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")

func _planet_at(pos: Vector2) -> int:
	for i in Game.planets.size():
		var p = Game.planets[i]
		if Game.is_mother(p):
			if p.ships >= 1 and abs(pos.x - p.pos.x) < 150 and abs(pos.y - p.pos.y) < 80: return i
			continue
		if p.pos.distance_to(pos) < Game.radius(p) + 20: return i
	return -1

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var pos := get_global_mouse_position()
		if e.pressed:
			var i := _planet_at(pos)
			if i != -1 and Game.planets[i].owner == Game.PLAYER and conquest.is_empty():
				drag_from = i; drag_pos = pos
		elif drag_from != -1:
			var t := _planet_at(pos)
			if t == drag_from and Game.is_mother(Game.planets[t]):
				pass
			elif t != -1 and Game.is_mother(Game.planets[t]):
				pass   # nothing can target the mothership
			elif t == drag_from:
				Game.selected_planet = t
				get_tree().change_scene_to_file("res://scenes/planet.tscn")
			elif t != -1:
				send(drag_from, t, Game.PLAYER, Game.send_pct, Game.fleet_type)
			drag_from = -1; hover = -1
	elif e is InputEventMouseMotion and drag_from != -1:
		drag_pos = get_global_mouse_position()
		hover = _planet_at(drag_pos)

const NEBULA := preload("res://art/nebula.jpg")
const ICON_FACTORY := preload("res://art/icons/factory.png")
const ICON_TOWER := preload("res://art/icons/tower.png")
const PlanetView := preload("res://scripts/planet_view.gd")
var overlay: Node2D
var hover := -1
var views := {}   # planet index -> PlanetView
const GLOW := preload("res://art/ships/glow.png")

func _build_planets() -> void:
	banner = Game.make_label("", Vector2(0, 40), 44); banner.size = Vector2(1560, 200)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 10); banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.visible = false
	var top := CanvasLayer.new(); top.layer = 10; add_child(top); top.add_child(banner)
	for i in Game.planets.size():
		var p = Game.planets[i]
		if Game.is_mother(p): continue
		var v := PlanetView.new(); v.position = p.pos; add_child(v); v.setup(p, Game.radius(p))
		v.set_owner_tint(p.owner); views[i] = v
	overlay = Node2D.new(); overlay.z_index = 5; add_child(overlay)
	overlay.draw.connect(_draw_overlay)

func _draw() -> void:
	draw_rect(Rect2(-2000, -2000, 6000, 6000), Color(0.02, 0.02, 0.05))
	draw_texture(NEBULA, Vector2.ZERO)
	var t := Time.get_ticks_msec() / 1000.0
	for i in Game.planets.size():
		var p = Game.planets[i]
		if Game.is_mother(p): continue
		var r := Game.radius(p)
		var col: Color = Game.COLORS[p.owner]
		var pulse := 0.5 + 0.5 * sin(t * 2.0 + i)
		if views.has(i): views[i].set_owner_tint(p.owner)
		if p.owner == Game.NEUTRAL:
			for k in 24:
				var a0 := TAU * k / 24.0 + t * 0.1
				draw_arc(p.pos, r + 5, a0, a0 + TAU / 48.0, 4, Color(col, 0.75), 2.5, true)
		else:
			var hr := r * 2.1 + 6
			draw_texture_rect(GLOW, Rect2(p.pos - Vector2(hr, hr), Vector2(hr, hr) * 2), false, Color(col, 0.55 + 0.15 * pulse))
			draw_arc(p.pos, r + 7, 0, TAU, 56, Color(col, 0.35), 14, true)
			draw_arc(p.pos, r + 7, 0, TAU, 56, Color(col.lightened(0.15), 0.95), 6, true)
			draw_arc(p.pos, r + 12 + 2 * pulse, 0, TAU, 56, Color(col, 0.3 * pulse), 2, true)
		if i == drag_from or i == hover:
			draw_arc(p.pos, r + 14 + 3 * pulse, 0, TAU, 48, Color(1, 1, 1, 0.8), 3, true)

func _process_overlay() -> void:
	if overlay: overlay.queue_redraw()

func _label(ci: CanvasItem, pos: Vector2, text: String, size: int, col := Color.WHITE, w := 120.0) -> void:
	var font := ThemeDB.fallback_font
	ci.draw_string_outline(font, pos - Vector2(w / 2, 0), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, 6, Color(0, 0, 0, 0.85))
	ci.draw_string(font, pos - Vector2(w / 2, 0), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)

func _draw_overlay() -> void:
	var o := overlay
	var t := Time.get_ticks_msec() / 1000.0
	for p in Game.planets:
		if Game.is_mother(p):
			if p.ships >= 1:
				if drag_from >= 0 and Game.planets[drag_from] == p: o.draw_arc(p.pos, 105, 0, TAU, 48, Color(1, 1, 1, 0.6), 3, true)
				draw_mother(o, p.pos, 1.25, t)
				_pill(o, p.pos + Vector2(0, 92), "MOTHERSHIP  %d" % int(p.ships), 24, Game.PLAYER)
				emblem(o, p.pos + Vector2(-112, 83), 12.0, Game.PLAYER)
			continue
		var r := Game.radius(p)
		var col: Color = Game.COLORS[p.owner]
		_pill(o, p.pos + Vector2(0, 11), str(int(p.ships)), 28, p.owner)
		if p.owner != Game.NEUTRAL: emblem(o, p.pos + Vector2(r * 0.72, -r * 0.72), 11.0, p.owner)
		var bx: Vector2 = p.pos + Vector2(-r * 0.9, r + 6)
		if p.factories > 0:
			# orbiting station + badge
			var sa: float = t * 0.6 + p.pos.x
			var sp: Vector2 = p.pos + Vector2(cos(sa), sin(sa) * 0.45) * (r + 12)
			o.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Color(1, 0.85, 0.4))
			o.draw_texture_rect(ICON_FACTORY, Rect2(bx, Vector2(22, 22)), false)
			_label(o, bx + Vector2(38, 18), str(p.factories), 20, Color(1, 0.9, 0.5), 40)
			bx.x += 50
		if p.get("towers", {}).size() > 0:
			o.draw_texture_rect(ICON_TOWER, Rect2(bx, Vector2(22, 22)), false)
			_label(o, bx + Vector2(36, 18), str(p.towers.size()), 20, Color(0.8, 0.9, 1), 40)
	for f in Game.fleets:
		var ang: float = (Game.planets[f.to].pos - f.pos).angle()
		var n := clampi(int(ceil(f.count / 6.0)), 1, 6)
		var s := 1.0 if f.type != "Tank" else 1.15
		var fwd := Vector2.RIGHT.rotated(ang); var side := fwd.orthogonal()
		for k in n:
			var row := (k + 1) / 2
			var off: Vector2 = -fwd * row * 16.0 + side * (row * 13.0 if k % 2 == 1 else -row * 13.0) if k > 0 else Vector2.ZERO
			Game.ShipArt.draw_ship(o, f.type, f.pos + off, ang, Game.COLORS[f.owner], s, t + k)
		o.draw_texture_rect(GLOW, Rect2(f.pos - Vector2(34, 34), Vector2(68, 68)), false, Color(Game.COLORS[f.owner], 0.5))
		_pill(o, f.pos + Vector2(30, -10), str(f.count), 20, f.owner)
	if not conquest.is_empty(): _draw_conquest(o, t)
	if drag_from != -1:
		var a: Vector2 = Game.planets[drag_from].pos
		var dv := drag_pos - a
		var steps := int(dv.length() / 18.0)
		for i in steps:
			o.draw_circle(a + dv * (float(i) / max(1, steps)), 3, Color(0.6, 0.85, 1, 0.8))
		o.draw_circle(drag_pos, 8, Color(1, 1, 1, 0.8))

func _draw_conquest(o: CanvasItem, t: float) -> void:
	var c := conquest
	var k: float = clamp(c.t / CONQ_GATHER, 0.0, 1.0)
	var j: float = clamp((c.t - CONQ_GATHER) / CONQ_JUMP, 0.0, 1.0)
	if j > 0:
		# hyperspace: radial star streaks growing from the mothership
		for i in 140:
			var a := float(i) * 2.39996
			var d0 := fmod(i * 53.0, 700.0) * (0.3 + j)
			var d1 := d0 + 40 + 900 * j * j
			o.draw_line(MOTHER_CENTER + Vector2.from_angle(a) * d0, MOTHER_CENTER + Vector2.from_angle(a) * d1, Color(0.7, 0.85, 1, 0.3 + 0.6 * j), 1.5 + 2 * j)
	# streams of ships flying from planets into the mothership
	for s in c.src:
		if k >= 1.0: break
		for m in 6:
			var u := fmod(c.t * 0.9 + m / 6.0, 1.0)
			var p: Vector2 = s.pos.lerp(MOTHER_CENTER, u)
			Game.ShipArt.draw_ship(o, "Trooper", p, (MOTHER_CENTER - s.pos).angle(), Game.COLORS[Game.PLAYER], 0.8, t + m)
	var sc := 1.4 + 0.3 * sin(min(1.0, c.t) * PI / 2)
	var charge: float = clamp((c.t - CONQ_GATHER * 0.6) / (CONQ_GATHER * 0.4 + CONQ_JUMP * 0.4), 0.0, 1.0)
	var go: float = clamp((j - 0.55) / 0.45, 0.0, 1.0)
	if go > 0:   # ship stretches into a streak as it jumps
		var tail := MOTHER_CENTER + Vector2(go * go * 1400, 0)
		o.draw_line(MOTHER_CENTER - Vector2(200, 0), tail, Color(0.7, 0.9, 1, 0.8), 30 * (1.0 - go) + 4)
	draw_mother(o, MOTHER_CENTER + Vector2(go * go * 1400, 0), sc, t, charge, 1.0 + 3.0 * go)
	_label(o, MOTHER_CENTER + Vector2(0, 95), "MOTHERSHIP  %d" % int(c.total * k), 34, Color(0.7, 0.9, 1), 400)
	if j > 0.8:
		o.draw_rect(Rect2(-100, -100, 1800, 1000), Color(1, 1, 1, (j - 0.8) * 5.0))

func _pill(ci: CanvasItem, pos: Vector2, text: String, size: int, owner: int) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 18
	var h := size + 8.0
	var c: Color = Game.COLORS[owner]
	var fill := Color(c.darkened(0.25), 0.92) if owner != Game.NEUTRAL else Color(0.35, 0.36, 0.4, 0.88)
	var rc := Rect2(pos.x - w / 2, pos.y - size * 0.78 - 4, w, h)
	var sb := StyleBoxFlat.new(); sb.bg_color = fill; sb.set_corner_radius_all(int(h / 2))
	sb.border_color = Color(1, 1, 1, 0.85) if owner != Game.NEUTRAL else Color(0.8, 0.8, 0.85, 0.6)
	sb.set_border_width_all(2)
	ci.draw_style_box(sb, rc)
	ci.draw_string_outline(font, Vector2(rc.position.x, pos.y), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, 5, Color(0, 0, 0, 0.9))
	ci.draw_string(font, Vector2(rc.position.x, pos.y), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color.WHITE)

## Owner shape cue: player star, enemy diamond / triangle / square.
static func emblem(ci: CanvasItem, c: Vector2, s: float, owner: int) -> void:
	var pts := PackedVector2Array()
	match owner:
		1:
			for k in 10:
				var rr := s if k % 2 == 0 else s * 0.45
				pts.append(c + Vector2.from_angle(-PI / 2 + k * PI / 5) * rr)
		2: pts = PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.8, 0), c + Vector2(0, s), c + Vector2(-s * 0.8, 0)])
		3: pts = PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, s * 0.8), c + Vector2(-s, s * 0.8)])
		4: pts = PackedVector2Array([c + Vector2(-s, -s) * 0.75, c + Vector2(s, -s) * 0.75, c + Vector2(s, s) * 0.75, c + Vector2(-s, s) * 0.75])
		_: return
	ci.draw_circle(c, s + 5, Color(0, 0, 0, 0.75))
	ci.draw_colored_polygon(pts, Game.COLORS[owner])
	var loop := pts.duplicate(); loop.append(pts[0])
	ci.draw_polyline(loop, Color.WHITE, 1.5, true)

func _draw_legend(ci: Node2D) -> void:
	var x := 20.0; var y := 58.0
	var font := ThemeDB.fallback_font
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.45); bg.set_corner_radius_all(10)
	ci.draw_style_box(bg, Rect2(x - 8, y - 16, 330, 32))
	for o in [Game.PLAYER, Game.AI, Game.NEUTRAL]:
		var c: Color = Game.COLORS[o]
		if o == Game.NEUTRAL:
			ci.draw_arc(Vector2(x + 8, y), 8, 0, TAU, 16, c, 2, true)
		else:
			ci.draw_circle(Vector2(x + 8, y), 10, c); emblem(ci, Vector2(x + 8, y), 6.0, o)
		var name: String = Game.OWNER_NAMES[o]
		ci.draw_string_outline(font, Vector2(x + 24, y + 7), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color.BLACK)
		ci.draw_string(font, Vector2(x + 24, y + 7), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		x += 34 + font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 26
