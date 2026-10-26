extends Node2D
## Tower-defense battle. Attacker sends troops along the path; defender's towers shoot.
## Player is attacker (spawns troops) or defender (builds/upgrades towers) depending on who invaded.

const PATH := [Vector2(0, 170), Vector2(400, 170), Vector2(400, 560), Vector2(800, 560), Vector2(800, 170), Vector2(1200, 170), Vector2(1200, 460), Vector2(1480, 460)]
const SLOTS := [Vector2(250, 300), Vector2(550, 400), Vector2(600, 280), Vector2(650, 660), Vector2(950, 300), Vector2(1000, 450), Vector2(1050, 80), Vector2(1340, 330), Vector2(250, 80), Vector2(1340, 580)]
const BG := preload("res://art/battle_bg.png")
const TCOL := {"Gun": Color(1.0, 0.85, 0.4), "Frost": Color(0.5, 0.9, 1.0), "Missile": Color(1.0, 0.55, 0.25), "Laser": Color(1.0, 0.3, 0.9)}

var b: Dictionary
var player_attacking: bool
var defender := 0
var pool := 0             # ships left to spawn as troops
var budget := 0           # defender's tower budget (from garrison)
var core_hp := 20
var core_max := 20
var towers := {}          # slot -> level (0-based)
var tower_types := {}     # slot -> "Gun"/"Frost"/"Missile"/"Laser"
var tstate := {}          # slot -> {cd, ang, flash}
var troops: Array = []    # {d, hp, max, type, shield, slow}
var projectiles: Array = []
var particles: Array = []
var beams: Array = []
var prep := 8.0
var spawn_timer := 0.0
var wave_left := 0
var wave_pause := 0.0
var ai_spawn_type := "Trooper"
var done := false
var lbl: Label
var stat_lbl: Label
var ui: CanvasLayer
var path_len := 0.0
var build_type := "Gun"
var selected := -1
var shake := 0.0
var core_flash := 0.0
var time := 0.0
var type_btns := {}
var shots_fired := {}
var fleet_mult := 1.0     # attacker troop HP/shield x (1 + ships sent/100), after caps
const BOSS_N := 10        # a boss of type T = 10 units of T (10x cost, HP, shield, core dmg)
const BOSS_MIN_SHIPS := 100
const BOSS_SPEED := 0.6   # bosses move at 60% of their base type speed
const STACK_AT := 40       # above this many live troops, new normal troops merge into stacks (perf)
const STACK_MAX := 10
var boss_btns := {}
var norm_btns: Array = []
var boss_toggle: Button
var _tstats := {}          # type -> cached troop stats for this battle
var _cum: PackedFloat32Array = PackedFloat32Array()
var ai_spawned := 0
var garrison_mult := 1.0  # defender tower damage x (1 + garrison/100), fixed at battle start     # type -> count (tests)

func _ready() -> void:
	b = Game.pending_battle
	var planet = Game.planets[b.planet]
	defender = planet.owner
	player_attacking = b.attacker == Game.PLAYER
	pool = b.ships
	if b.attacker == Game.AI:
		# Cap enemy battle strength at the player's weakest planet garrison (difficulty multiplier)
		pool = min(pool, max(1, int(min(Game.attack_cap(), 1e9))))
		b.ships = pool
	else:
		pool = int(pool * (1.0 + 0.15 * Game.lvl("hull", Game.PLAYER)))  # Hull Plating
	fleet_mult = 1.0 + max(0, b.ships) / 100.0
	ai_spawn_type = b.type
	# Defender budget comes from the planet's garrison (+ defense upgrades)
	budget = int(planet.ships) * 3 + planet.defense * 30
	if planet.owner == Game.AI: budget = int(budget * Game.ai_mult())
	garrison_mult = Game.garrison_mult(planet)
	core_max = 15 + int(planet.ships / 4) + 5 * Game.lvl("shield", defender)
	core_hp = core_max
	_cum.append(0.0)
	for i in PATH.size() - 1:
		path_len += PATH[i].distance_to(PATH[i + 1]); _cum.append(path_len)
	for k in Game.TROOPS: _tstats[k] = Game.troop_stats(k, b.attacker)
	Audio.music("music_battle")
	_build_ui()
	if player_attacking:
		towers = {}; tower_types = {}  # enemy towers are placed fresh every battle
		budget += 30
		_ai_place_towers()
		prep = 0
	else:
		towers = planet.get("towers", {}).duplicate()  # player towers persist while planet is held
		tower_types = planet.get("tower_types", {}).duplicate()
		for s in towers: if not tower_types.has(s): tower_types[s] = "Gun"

func _panel(pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new(); p.position = pos; p.size = size
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.07, 0.12, 0.82)
	sb.border_color = Color(0.4, 0.6, 0.9, 0.6); sb.set_border_width_all(2); sb.set_corner_radius_all(12)
	p.add_theme_stylebox_override("panel", sb); ui.add_child(p); return p

func _build_ui() -> void:
	ui = CanvasLayer.new(); add_child(ui)
	_panel(Vector2(8, 640), Vector2(1544, 74))
	lbl = Game.make_label("", Vector2(24, 652), 24); ui.add_child(lbl)
	_panel(Vector2(1150, 8), Vector2(402, 112))
	stat_lbl = Game.make_label("", Vector2(1164, 12), 22); ui.add_child(stat_lbl)
	var spd := Game.make_button(_speed_text(), Vector2(1370, 548), Vector2(180, 84))
	spd.add_theme_font_size_override("font_size", 32)
	spd.pressed.connect(func():
		Game.set_battle_speed({1: 2, 2: 3, 3: 5, 5: 1}.get(Game.battle_speed, 1)); spd.text = _speed_text())
	ui.add_child(spd)
	if player_attacking:
		var x := 8
		for k in Game.TROOPS:
			if not Game.has_troop(k, Game.PLAYER): continue
			var bt := Game.make_button("%s x5 (%d)" % [k, Game.TROOPS[k].cost * 5], Vector2(x, 8), Vector2(190, 76))
			bt.add_theme_font_size_override("font_size", 22)
			bt.pressed.connect(func(): _player_spawn(k)); ui.add_child(bt); norm_btns.append(bt)
			var bb := Game.make_button("", Vector2(x, 8), Vector2(190, 76)); bb.visible = false
			bb.add_theme_font_size_override("font_size", 16)
			Game.style_button(bb, Color(0.5, 0.2, 0.55))
			bb.pressed.connect(func(): spawn_boss(k)); ui.add_child(bb); boss_btns[k] = bb
			x += 196
		boss_toggle = Game.make_button("BOSS\nmode", Vector2(x, 8), Vector2(130, 76)); boss_toggle.toggle_mode = true
		boss_toggle.add_theme_font_size_override("font_size", 20)
		Game.style_button(boss_toggle, Color(0.55, 0.25, 0.1))
		boss_toggle.toggled.connect(func(on: bool):
			for nb in norm_btns: nb.visible = not on
			for k2 in boss_btns: boss_btns[k2].visible = on)
		ui.add_child(boss_toggle)
	else:
		var go := Game.make_button("Start Now", Vector2(900, 8), Vector2(240, 80)); ui.add_child(go)
		go.pressed.connect(func(): prep = 0; go.queue_free())
		var x := 8
		for k in Game.TOWERS:
			if not Game.has_tower(k, Game.PLAYER): continue
			var bt := Game.make_button("%s (%d)" % [k, Game.TOWERS[k].cost], Vector2(x, 8), Vector2(200, 76))
			bt.toggle_mode = true; bt.button_pressed = k == build_type
			bt.add_theme_font_size_override("font_size", 24)
			bt.add_theme_color_override("font_color", TCOL[k])
			bt.pressed.connect(func():
				build_type = k
				for o in type_btns: type_btns[o].button_pressed = o == k)
			type_btns[k] = bt; ui.add_child(bt); x += 206

func _ai_place_towers() -> void:
	var order := range(SLOTS.size()); order.shuffle()
	if Game.D().smart_towers:
		order.sort_custom(func(a, c): return _coverage(SLOTS[a]) > _coverage(SLOTS[c]))
	var avail := Game.TOWERS.keys().filter(func(k): return Game.has_tower(k, Game.AI))
	for s in order:
		var k: String = avail.pick_random()
		if budget < Game.TOWERS[k].cost: k = "Gun"
		if budget < Game.TOWERS[k].cost: break
		towers[s] = 0; tower_types[s] = k; budget -= Game.TOWERS[k].cost
	while budget >= 50 and towers.size() > 0:
		var s = towers.keys().pick_random()
		if towers[s] >= 2: break
		towers[s] += 1; budget -= 50

func _coverage(pos: Vector2) -> int:
	var n := 0
	var dd := 0.0
	while dd < path_len:
		if _point_at(dd).distance_to(pos) < 170.0: n += 1
		dd += 20.0
	return n

func _player_spawn(k: String) -> void:
	for i in 5:
		if pool < Game.TROOPS[k].cost: return
		pool -= Game.TROOPS[k].cost
		_spawn(k, -i * 30.0)

func boss_unlocked() -> bool: return b.ships >= BOSS_MIN_SHIPS
func boss_cost(k: String) -> int: return Game.TROOPS[k].cost * BOSS_N

## Launch one boss of type k (player). Returns true if spawned.
func spawn_boss(k: String) -> bool:
	if not boss_unlocked() or pool < boss_cost(k): return false
	pool -= boss_cost(k); _spawn(k, 0.0, BOSS_N, true); Audio.sfx("upgrade", 0.0); return true

## n = units represented (stack/boss): n x HP, shield, heal and core damage.
func _spawn(k: String, offset := 0.0, n := 1, boss := false) -> void:
	var d: Dictionary = _tstats[k]
	var hp: float = d.hp * fleet_mult
	var sh: float = d.get("shield", 0.0) * fleet_mult
	if not boss and n == 1 and troops.size() >= STACK_AT:
		var last = troops[-1]
		if last.type == k and not last.boss and last.n < STACK_MAX and absf(last.d - offset) < 40.0:
			last.n += 1; last.hp += hp; last.max += hp; last.shield += sh; return
	troops.append({"d": offset, "hp": hp * n, "max": hp * n, "type": k, "shield": sh * n, "slow": 0.0, "n": n, "boss": boss, "pos": PATH[0]})

func _point_at(dist: float) -> Vector2:
	dist = max(dist, 0)
	if _cum.is_empty():
		for i in PATH.size() - 1:
			var seg: float = PATH[i].distance_to(PATH[i + 1])
			if dist <= seg: return PATH[i].lerp(PATH[i + 1], dist / seg)
			dist -= seg
		return PATH[-1]
	if dist >= path_len: return PATH[-1]
	var i := _cum.bsearch(dist, true) - 1
	i = clampi(i, 0, PATH.size() - 2)
	return PATH[i].lerp(PATH[i + 1], (dist - _cum[i]) / (_cum[i + 1] - _cum[i]))

func _dir_at(dist: float) -> float:
	return (_point_at(dist + 4) - _point_at(dist - 4)).angle()

func shot_damage(k: String, level: int) -> float:
	return Game.tower_stats(k, level, defender).dmg * garrison_mult

func _speed_text() -> String: return "%s %dx" % ["▶".repeat(Game.battle_speed), Game.battle_speed]

func _process(real_delta: float) -> void:
	var total := real_delta * Game.battle_speed   # battle-local speed; galaxy/UI unaffected
	# Substep so fast speeds keep exact fire rates, spawns and hits (max 1/60 s per step)
	var n := maxi(1, ceili(total / (1.0 / 60.0)))
	var delta := total / n
	for _i in n:
		time += delta
		if not done:
			if prep > 0:
				prep -= delta
			else:
				if not player_attacking: _ai_waves(delta)
				_sim(delta)
		_fx(delta)
	_update_label()
	queue_redraw()

func _ai_waves(delta: float) -> void:
	if wave_pause > 0: wave_pause -= delta; return
	if wave_left <= 0 and pool > 0:
		wave_left = max(3, b.ships / 3); wave_pause = 4.0; return
	spawn_timer -= delta
	if spawn_timer <= 0 and pool > 0 and wave_left > 0:
		var k: String = ai_spawn_type
		var c: int = Game.TROOPS[k].cost
		ai_spawned += 1
		# AI uses bosses of its type symmetrically when its force is large enough
		if boss_unlocked() and ai_spawned % 4 == 0 and pool >= boss_cost(k):
			pool -= boss_cost(k); wave_left -= boss_cost(k); _spawn(k, 0.0, BOSS_N, true); spawn_timer = 0.6; return
		if pool < c: k = "Trooper"; c = 1
		pool -= c; wave_left -= c; _spawn(k); spawn_timer = 0.6

func _damage(t, dmg: float) -> void:
	if t.shield > 0:
		var a: float = min(t.shield, dmg); t.shield -= a; dmg -= a
	t.hp -= dmg

func _sim(delta: float) -> void:
	for t in troops:
		var spd: float = _tstats[t.type].speed * (0.5 if t.slow > 0 else 1.0) * (BOSS_SPEED if t.boss else 1.0)
		t.slow = max(0.0, t.slow - delta)
		t.d += spd * delta
		t.pos = _point_at(t.d)
	for t in troops:
		if t.type == "Medic" and t.d >= 0:
			var mp: Vector2 = t.pos
			var heal: float = Game.TROOPS.Medic.heal * delta * t.n
			for o in troops:
				if o.d >= 0 and o.pos.distance_squared_to(mp) < 4900.0: o.hp = min(o.max, o.hp + heal * o.n)
	for s in towers:
		if not tstate.has(s): tstate[s] = {"cd": 0.0, "ang": -PI / 2, "flash": 0.0}
		var st = tstate[s]
		var k: String = tower_types.get(s, "Gun")
		var ts := Game.tower_stats(k, towers[s], defender)
		ts.dmg *= garrison_mult
		st.cd -= delta; st.flash = max(0.0, st.flash - delta)
		var tpos: Vector2 = SLOTS[s]
		var target = null
		var r2: float = ts.range * ts.range
		for t in troops:  # first troop in range (furthest along)
			if t.d >= 0 and t.pos.distance_squared_to(tpos) < r2: target = t; break
		if target == null: continue
		var tp: Vector2 = target.pos
		st.ang = lerp_angle(st.ang, (tp - tpos).angle(), min(1.0, delta * 12.0))
		if st.cd > 0: continue
		st.cd = 1.0 / ts.rate; st.flash = 0.08
		shots_fired[k] = shots_fired.get(k, 0) + 1
		Audio.sfx("shot_" + k.to_lower(), 0.07)
		var muzzle := tpos + Vector2.RIGHT.rotated(st.ang) * 26
		match k:
			"Laser":
				_damage(target, ts.dmg); beams.append({"a": muzzle, "b": tp, "ttl": 0.08})
				_sparks(tp, TCOL.Laser, 3)
			"Missile":
				for t in troops:
					if t.d >= 0 and t.pos.distance_squared_to(tp) < ts.splash * ts.splash: _damage(t, ts.dmg * (t.n if not t.boss else 1))
				projectiles.append({"p": muzzle, "to": tp, "spd": 520.0, "col": TCOL.Missile, "trail": [], "boom": true})
			"Frost":
				_damage(target, ts.dmg); target.slow = 1.0
				projectiles.append({"p": muzzle, "to": tp, "spd": 700.0, "col": TCOL.Frost, "trail": [], "boom": false})
			_:
				_damage(target, ts.dmg)
				projectiles.append({"p": muzzle, "to": tp, "spd": 1100.0, "col": TCOL.Gun, "trail": [], "boom": false})
	var i := 0
	while i < troops.size():
		var t = troops[i]
		if t.hp <= 0:
			_explode(t.pos, Game.COLORS[b.attacker]); Audio.sfx("death", 0.06)
			troops.remove_at(i); continue
		if t.d >= path_len:
			core_hp -= Game.TROOPS[t.type].dmg * t.n; core_flash = 0.25; shake = 0.3
			_explode(PATH[-1], Color(1, 0.5, 0.2)); Audio.sfx("core_hit", 0.1)
			troops.remove_at(i); continue
		i += 1
	if core_hp <= 0: _finish(true)
	elif troops.is_empty() and pool < 1: _finish(false)
	elif player_attacking and troops.is_empty() and not Game.TROOPS.keys().any(func(k): return Game.has_troop(k, Game.PLAYER) and pool >= Game.TROOPS[k].cost): _finish(false)

# ---------- effects ----------
func _sparks(pos: Vector2, col: Color, n := 6) -> void:
	if particles.size() > (260 if troops.size() < 60 else 120): return
	for i in n:
		particles.append({"p": pos, "v": Vector2.from_angle(randf() * TAU) * randf_range(60, 220), "ttl": randf_range(0.15, 0.35), "max": 0.35, "col": col, "r": randf_range(1.5, 3.0)})

func _explode(pos: Vector2, col: Color) -> void:
	_sparks(pos, col.lightened(0.3), 12)
	_sparks(pos, Color(1, 0.8, 0.3), 6)
	particles.append({"p": pos, "v": Vector2.ZERO, "ttl": 0.3, "max": 0.3, "col": Color(1, 0.9, 0.6), "r": -1.0})  # ring

func _fx(delta: float) -> void:
	shake = max(0.0, shake - delta); core_flash = max(0.0, core_flash - delta)
	position = Vector2(randf_range(-6, 6), randf_range(-6, 6)) * (shake / 0.3) if shake > 0 else Vector2.ZERO
	var i := 0
	while i < particles.size():
		var q = particles[i]; q.ttl -= delta; q.p += q.v * delta; q.v *= 0.92
		if q.ttl <= 0: particles.remove_at(i)
		else: i += 1
	i = 0
	while i < projectiles.size():
		var pr = projectiles[i]
		pr.trail.push_front(pr.p); if pr.trail.size() > 6: pr.trail.pop_back()
		var dv: Vector2 = pr.to - pr.p
		var step: float = pr.spd * delta
		if dv.length() <= step:
			_sparks(pr.to, pr.col, 10 if pr.boom else 4)
			if pr.boom: particles.append({"p": pr.to, "v": Vector2.ZERO, "ttl": 0.35, "max": 0.35, "col": pr.col, "r": -1.0})
			projectiles.remove_at(i); continue
		pr.p += dv.normalized() * step; i += 1
	i = 0
	while i < beams.size():
		beams[i].ttl -= delta
		if beams[i].ttl <= 0: beams.remove_at(i)
		else: i += 1

func _finish(attacker_won: bool) -> void:
	done = true
	var planet = Game.planets[b.planet]
	var player_won := attacker_won == player_attacking
	if attacker_won:
		planet.owner = b.attacker
		var alive := 0
		for t in troops: alive += t.n
		planet.ships = max(1, pool + alive)
		planet.factories = max(0, planet.factories - 1)
		planet.defense = 0
		planet.towers = {}; planet.tower_types = {}  # towers are lost with the planet
		if b.attacker == Game.PLAYER: Game.recent_captures.append(b.planet)
		else: Game.recent_captures.erase(b.planet)
	else:
		if not player_attacking:
			# Successful defense: keep towers, defeated attackers' numbers join the garrison
			planet.towers = towers.duplicate(); planet.tower_types = tower_types.duplicate()
			planet.ships += b.ships
		else:
			planet.ships = max(1, planet.ships * 0.7)
	if player_won: Game.tech += 3
	Audio.sfx("win" if player_won else "lose", 0.0)
	Game.pending_battle = null
	Game.save_game()
	var msg := "VICTORY! +3 tech" if player_won else "DEFEAT"
	msg += ("  -  Planet captured" if attacker_won else "  -  Planet held")
	_panel(Vector2(400, 260), Vector2(760, 250))
	var l := Game.make_label(msg, Vector2(430, 290), 46); l.add_theme_color_override("font_color", Color(0.5, 1, 0.6) if player_won else Color(1, 0.5, 0.5)); ui.add_child(l)
	var c := Game.make_button("Continue", Vector2(650, 400), Vector2(260, 90)); ui.add_child(c)
	c.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/galaxy.tscn"))

func _update_label() -> void:
	var role: String
	if player_attacking: role = "ATTACKING - tap troop buttons to launch waves"
	elif towers.is_empty(): role = "DEFENDING - first tower is FREE: tap a green pad!"
	elif selected != -1: role = "Tower selected - tap it again to upgrade (50), tap a pad to build"
	else: role = "DEFENDING - pick a tower type, tap a pad to build, tap a tower to select/upgrade"
	if prep > 0: role += "   |  Prep %ds" % ceil(prep)
	lbl.text = role
	if boss_toggle: boss_toggle.disabled = not boss_unlocked()
	for k in boss_btns:
		var bb: Button = boss_btns[k]
		bb.text = ("Boss %s x%d (%d)" % [k, pool / boss_cost(k), boss_cost(k)]) if boss_unlocked() else "Boss %s 🔒100" % k
		bb.disabled = not boss_unlocked() or pool < boss_cost(k)
	stat_lbl.text = "Ships left: %d   Budget: %d\nFleet tough x%.1f  Garrison dmg x%.1f\nCore HP: %d/%d" % [pool, budget, fleet_mult, garrison_mult, max(0, core_hp), core_max]

func _unhandled_input(e: InputEvent) -> void:
	if done or player_attacking: return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var pos := get_global_mouse_position()
		for s in SLOTS.size():
			if SLOTS[s].distance_to(pos) < 60:
				if towers.has(s) and selected != s: selected = s; return
				try_place(s); selected = s if towers.has(s) else -1; return
		selected = -1

## Defender places/upgrades a tower at slot s. If no towers exist, the first one is free.
func try_place(s: int, k := "") -> bool:
	if k == "": k = build_type
	var cost: int = Game.TOWERS[k].cost
	if not towers.has(s):
		if towers.is_empty():
			towers[s] = 0; tower_types[s] = k; Audio.sfx("build"); return true   # free first tower
		if budget >= cost:
			towers[s] = 0; tower_types[s] = k; budget -= cost; Audio.sfx("build"); return true
	elif towers[s] < 3 and budget >= 50:
		towers[s] += 1; budget -= 50; Audio.sfx("upgrade"); return true
	return false

# ---------- drawing ----------
func _draw() -> void:
	draw_texture(BG, Vector2.ZERO)
	# atmosphere glow + parallax stars along the horizon
	for i in 6: draw_rect(Rect2(0, i * 6, 1560, 6), Color(0.4, 0.6, 1.0, 0.10 - i * 0.015))
	for i in 40:
		var sx := fmod(i * 97.0 + time * (4.0 + (i % 3) * 3.0), 1560.0)
		draw_circle(Vector2(sx, 4 + (i * 13) % 34), 1.0, Color(1, 1, 1, 0.3 + 0.3 * sin(time * 2 + i)))
	# road
	var pv := PackedVector2Array(PATH)
	draw_polyline(pv, Color(0, 0, 0, 0.35), 84, true)
	draw_polyline(pv, Color(0.33, 0.29, 0.27), 72, true)
	draw_polyline(pv, Color(0.45, 0.40, 0.35), 60, true)
	var dd := fmod(time * 30.0, 40.0)
	while dd < path_len:
		draw_line(_point_at(dd), _point_at(dd + 16), Color(0.85, 0.8, 0.5, 0.5), 3)
		dd += 40.0
	_draw_core()
	# pads & towers
	var dcol: Color = Game.COLORS[defender]
	for s in SLOTS.size():
		var sp: Vector2 = SLOTS[s]
		if towers.has(s): _draw_tower(s, sp, dcol)
		elif not player_attacking:
			var free := towers.is_empty()
			var c := Color(0.4, 1, 0.4) if free else Color(1, 1, 1, 0.5)
			draw_circle(sp, 30, Color(0, 0, 0, 0.3))
			draw_arc(sp, 30, 0, TAU, 32, c, 3, true)
			draw_line(sp + Vector2(-10, 0), sp + Vector2(10, 0), c, 3); draw_line(sp + Vector2(0, -10), sp + Vector2(0, 10), c, 3)
			if free: draw_string(ThemeDB.fallback_font, sp + Vector2(-40, 52), "FREE", HORIZONTAL_ALIGNMENT_CENTER, 80, 22, c)
	# beams, projectiles
	for bm in beams:
		draw_line(bm.a, bm.b, Color(1, 0.4, 0.95, 0.5), 8); draw_line(bm.a, bm.b, Color(1, 0.9, 1), 3)
	for pr in projectiles:
		for j in pr.trail.size():
			draw_circle(pr.trail[j], 4.0 - j * 0.5, Color(pr.col, 0.6 - j * 0.1))
		draw_circle(pr.p, 4.5, pr.col.lightened(0.5))
	# troops (bosses / auto-stacks drawn bigger with a badge)
	var acol: Color = Game.COLORS[b.attacker]
	var many := troops.size() > 60
	var font := ThemeDB.fallback_font
	for t in troops:
		if t.d < 0: continue
		var p: Vector2 = t.pos + Vector2(0, sin(time * 8.0 + t.d * 0.05) * 2.0)
		var s := 1.5 if t.type == "Tank" else 1.25
		var ang := _dir_at(t.d)
		if t.boss:
			s *= 3.0
			_draw_boss(p, ang, acol, s, t)
		else:
			if t.n > 1: s *= 1.0 + 0.08 * t.n
			if not many: draw_circle(p + Vector2(4, 10), 10 * s, Color(0, 0, 0, 0.25))  # shadow
			if t.n > 1: draw_circle(p, 14 * s, Color(acol, 0.15))
			Game.ShipArt.draw_ship(self, t.type, p, ang, acol, s, time)
		if t.shield > 0: draw_arc(p, 16 * s, 0, TAU, 24, Color(0.5, 0.8, 1, 0.7), 2, true)
		if t.slow > 0: draw_circle(p, 13 * s, Color(0.5, 0.9, 1, 0.25))
		var w := 30.0 * (2.4 if t.boss else 1.0)
		var hy := -22.0 * s - 6
		draw_rect(Rect2(p + Vector2(-w / 2, hy), Vector2(w, 6 if t.boss else 5)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p + Vector2(-w / 2, hy), Vector2(w * clamp(t.hp / t.max, 0, 1), 6 if t.boss else 5)), Color(0.3, 1, 0.3).lerp(Color(1, 0.3, 0.2), 1.0 - t.hp / t.max))
		if t.n > 1 and not t.boss:
			draw_string_outline(font, p + Vector2(10, -10), "x%d" % t.n, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
			draw_string(font, p + Vector2(10, -10), "x%d" % t.n, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.9, 0.6))
	# particles
	for q in particles:
		var a: float = q.ttl / q.max
		if q.r < 0: draw_arc(q.p, 40.0 * (1.0 - a) + 6, 0, TAU, 24, Color(q.col, a), 3, true)
		else: draw_circle(q.p, q.r * (0.5 + a), Color(q.col, a))

const BOSS_TRIM := {"Trooper": Color(1, 0.85, 0.3), "Scout": Color(0.4, 1, 0.6), "Tank": Color(1, 0.5, 0.2), "Bomber": Color(1, 0.3, 0.3), "Shield": Color(0.5, 0.8, 1), "Medic": Color(0.5, 1, 0.7)}
func _draw_boss(p: Vector2, ang: float, col: Color, s: float, t) -> void:
	var trim: Color = BOSS_TRIM.get(t.type, Color.GOLD)
	var pulse := 0.5 + 0.5 * sin(time * 4.0 + t.d * 0.01)
	for i in 4: draw_circle(p, (16 + i * 6) * s * 0.5 + pulse * 3, Color(col, 0.12 - i * 0.025))   # aura
	draw_circle(p + Vector2(6, 16), 12 * s, Color(0, 0, 0, 0.3))
	var fwd := Vector2.RIGHT.rotated(ang); var side := fwd.orthogonal()
	# armour plating behind the ship
	var plate := PackedVector2Array([p + fwd * 14 * s, p + side * 11 * s - fwd * 4 * s, p - fwd * 13 * s + side * 7 * s, p - fwd * 13 * s - side * 7 * s, p - side * 11 * s - fwd * 4 * s])
	draw_colored_polygon(plate, col.darkened(0.55))
	draw_polyline(plate + PackedVector2Array([plate[0]]), trim, 3, true)
	Game.ShipArt.draw_ship(self, t.type, p, ang, col.lightened(0.15), s * 0.8, time)
	# per-type emblem
	match t.type:
		"Scout": for i in 3: draw_line(p - fwd * (16 + i * 6) * s + side * (i - 1) * 6 * s, p - fwd * (24 + i * 10) * s + side * (i - 1) * 6 * s, Color(trim, 0.7), 3)
		"Tank": draw_rect(Rect2(p - Vector2(5, 5) * s, Vector2(10, 10) * s), Color(trim, 0.6), false, 3)
		"Shield": draw_arc(p, 18 * s, 0, TAU, 32, Color(trim, 0.4 + 0.4 * pulse), 4, true)
		"Medic": draw_line(p - Vector2(0, 6) * s, p + Vector2(0, 6) * s, trim, 4); draw_line(p - Vector2(6, 0) * s, p + Vector2(6, 0) * s, trim, 4)
		"Bomber": draw_circle(p, 4 * s, Color(trim, 0.7))
	# crown
	var c := p + Vector2(0, -15 * s)
	var crown := PackedVector2Array([c + Vector2(-12, 6), c + Vector2(-12, -4), c + Vector2(-6, 2), c + Vector2(0, -8), c + Vector2(6, 2), c + Vector2(12, -4), c + Vector2(12, 6)])
	draw_colored_polygon(crown, Color(1, 0.82, 0.25)); draw_polyline(crown, Color(0.5, 0.3, 0.05), 2, true)
	draw_string_outline(ThemeDB.fallback_font, p + Vector2(-60, 22 * s + 14), "BOSS " + t.type.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120, 16, 4, Color.BLACK)
	draw_string(ThemeDB.fallback_font, p + Vector2(-60, 22 * s + 14), "BOSS " + t.type.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120, 16, trim)

func _draw_core() -> void:
	var c: Vector2 = PATH[-1] + Vector2(30, 0)
	var dcol: Color = Game.COLORS[defender]
	var pulse := 0.5 + 0.5 * sin(time * 3.0)
	for i in 5: draw_circle(c, 70 - i * 8, Color(dcol, 0.05 + 0.03 * i * pulse))
	draw_circle(c, 40, dcol.darkened(0.4))
	draw_circle(c, 32, dcol)
	draw_circle(c + Vector2(-8, -8), 12, dcol.lightened(0.6))
	if core_flash > 0: draw_circle(c, 46, Color(1, 0.2, 0.1, core_flash * 2.5))
	draw_rect(Rect2(c + Vector2(-50, 52), Vector2(100, 10)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(c + Vector2(-50, 52), Vector2(100 * clamp(float(core_hp) / core_max, 0, 1), 10)), Color(0.3, 1, 0.5))
	draw_string(ThemeDB.fallback_font, c + Vector2(-50, 84), "CORE", HORIZONTAL_ALIGNMENT_CENTER, 100, 20, Color.WHITE)

func _draw_tower(s: int, sp: Vector2, dcol: Color) -> void:
	var k: String = tower_types.get(s, "Gun")
	var lvl: int = towers[s]
	var st = tstate.get(s, {"ang": -PI / 2, "flash": 0.0})
	var tc: Color = TCOL[k]
	if selected == s or (not player_attacking and prep > 0):
		var rng: float = Game.tower_stats(k, lvl, defender).range
		draw_circle(sp, rng, Color(tc, 0.06 if selected != s else 0.12))
		draw_arc(sp, rng, 0, TAU, 64, Color(tc, 0.4 if selected == s else 0.15), 2, true)
	# base: octagon with team-colour rim
	var oct := PackedVector2Array()
	for i in 8: oct.append(sp + Vector2.from_angle(i * TAU / 8 + PI / 8) * 30)
	draw_circle(sp + Vector2(3, 6), 30, Color(0, 0, 0, 0.35))
	draw_colored_polygon(oct, Color(0.25, 0.27, 0.3))
	var rim := oct.duplicate(); rim.append(oct[0])
	draw_polyline(rim, dcol, 4, true)
	for i in lvl + 1: draw_circle(sp + Vector2(-12 + i * 8, 22), 3, Color(1, 0.9, 0.3))
	# turret
	var a: float = st.ang
	var fwd := Vector2.RIGHT.rotated(a); var side := fwd.orthogonal()
	match k:
		"Gun":
			draw_line(sp + side * 5, sp + side * 5 + fwd * 26, Color(0.15, 0.15, 0.15), 5)
			draw_line(sp - side * 5, sp - side * 5 + fwd * 26, Color(0.15, 0.15, 0.15), 5)
			draw_circle(sp, 14, tc.darkened(0.2)); draw_circle(sp, 8, tc)
		"Frost":
			var dia := PackedVector2Array([sp + fwd * 24, sp + side * 10, sp - fwd * 10, sp - side * 10])
			draw_colored_polygon(dia, tc); draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color.WHITE, 2, true)
			draw_circle(sp, 6, Color(1, 1, 1, 0.6 + 0.4 * sin(time * 5)))
		"Missile":
			var box := PackedVector2Array([sp + side * 13 + fwd * 14, sp - side * 13 + fwd * 14, sp - side * 13 - fwd * 12, sp + side * 13 - fwd * 12])
			draw_colored_polygon(box, tc.darkened(0.3))
			draw_circle(sp + side * 6 + fwd * 10, 4, Color(0.1, 0.1, 0.1)); draw_circle(sp - side * 6 + fwd * 10, 4, Color(0.1, 0.1, 0.1))
		"Laser":
			draw_line(sp, sp + fwd * 32, Color(0.2, 0.2, 0.25), 6)
			draw_circle(sp + fwd * 32, 4, Color(tc, 0.7 + 0.3 * sin(time * 9)))
			draw_circle(sp, 12, tc.darkened(0.3)); draw_circle(sp, 6, tc)
	if st.flash > 0:
		draw_circle(sp + fwd * 30, 9, Color(1, 0.95, 0.6, 0.9))
		draw_circle(sp + fwd * 30, 15, Color(tc, 0.4))
