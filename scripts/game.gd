extends Node
## Global game state (autoload "Game"). Galaxy state lives here so the
## galaxy is effectively paused while another scene (battle, planet) is open.

const NEUTRAL := 0
const PLAYER := 1
const AI := 2
const COLORS := [Color(0.72, 0.74, 0.78), Color(0.1, 0.85, 1.0), Color(1.0, 0.2, 0.18), Color(1.0, 0.72, 0.08), Color(1.0, 0.25, 0.85)]
## Shape cue per owner (color-blind friendly): 0 none, 1 star, 2 diamond, 3 triangle, 4 square
const OWNER_NAMES := ["Neutral", "You", "Enemy", "Enemy 2", "Enemy 3"]
const FONT_SIZE := 30

# Troop types: cost = ships consumed per troop
const TROOPS := {
	"Trooper": {"cost": 1, "hp": 30.0, "speed": 80.0, "dmg": 1, "tech": 0},
	"Scout":   {"cost": 1, "hp": 18.0, "speed": 170.0, "dmg": 1, "tech": 2},
	"Tank":    {"cost": 3, "hp": 140.0, "speed": 50.0, "dmg": 3, "tech": 4},
	"Bomber":  {"cost": 2, "hp": 45.0, "speed": 110.0, "dmg": 4, "tech": 5},
	"Shield":  {"cost": 2, "hp": 50.0, "speed": 70.0, "dmg": 2, "tech": 5, "shield": 40.0},
	"Medic":   {"cost": 2, "hp": 35.0, "speed": 75.0, "dmg": 1, "tech": 6, "heal": 10.0},
}
# Tower types: dps at level 1, range, shots/sec. cost in tower budget.
const TOWERS := {
	"Gun":     {"cost": 25, "dps": 30.0, "range": 170.0, "rate": 2.0},
	"Frost":   {"cost": 30, "dps": 10.0, "range": 150.0, "rate": 1.5, "slow": 0.5},
	"Missile": {"cost": 40, "dps": 26.0, "range": 190.0, "rate": 0.8, "splash": 70.0},
	"Laser":   {"cost": 50, "dps": 50.0, "range": 220.0, "rate": 5.0},
}
const Upgrades = preload("res://scripts/upgrades_data.gd")
const ShipArt = preload("res://scripts/ship_art.gd")
var upg := {}   # player upgrade id -> level

var planets: Array = []   # {pos, owner, ships, size, factories, defense}
var fleets: Array = []    # {from, to, owner, count, pos, type}
var tech := 0
var unlocked := {"Trooper": true, "Scout": false, "Tank": false, "Bomber": false, "Shield": false, "Medic": false}
var send_pct := 0.5
var fleet_type := "Trooper"
var pending_battle = null # {planet, attacker, ships, type}
var selected_planet := -1
var result_msg := ""
var elapsed := 0.0
const Difficulty = preload("res://scripts/difficulty.gd")
var difficulty := "Easy"
var battle_speed := 1  # battle-only sim multiplier (1/2/3/5), saved in settings.cfg
var auto_battle := false       # tests: resolve battles instantly, no scene changes
var stats := {}
var recent_captures: Array = [] # planets the player recently took (for AI counterattacks)
const SETTINGS := "user://settings.cfg"
const SAVE_PATH := "user://savegame.json"
var ai_timer := 0.0
var ai_build_timer := 0.0
var since_attack := 0.0
var in_game := false
var galaxy := 1                # campaign galaxy number (endless)
var best_galaxy := 1
const MOTHER_POS := Vector2(205, 360)

## AI strength multiplier: +1% per galaxy conquered.
func ai_mult() -> float: return pow(1.01, galaxy - 1)
func is_mother(p) -> bool: return p.get("mother", false)
func mother_index() -> int:
	for i in planets.size(): if is_mother(planets[i]): return i
	return -1
func mother_ships() -> float:
	var m := mother_index(); return 0.0 if m < 0 else planets[m].ships
func difficulty_label() -> String:
	return "Galaxy %d  (+%d%% difficulty)" % [galaxy, int(round((ai_mult() - 1.0) * 100))]

func _ready() -> void:
	var c := ConfigFile.new()
	if c.load(SETTINGS) == OK:
		difficulty = c.get_value("game", "difficulty", "Easy")
		battle_speed = int(c.get_value("game", "battle_speed", 1))
		if not battle_speed in [1, 2, 3, 5]: battle_speed = 1
		best_galaxy = int(c.get_value("game", "best_galaxy", 1))
	if not Difficulty.DATA.has(difficulty): difficulty = "Easy"

func set_battle_speed(s: int) -> void:
	battle_speed = s
	var c := ConfigFile.new(); c.load(SETTINGS); c.set_value("game", "battle_speed", s); c.save(SETTINGS)

func set_difficulty(d: String) -> void:
	difficulty = d
	var c := ConfigFile.new(); c.load(SETTINGS); c.set_value("game", "difficulty", d); c.save(SETTINGS)

func D() -> Dictionary:
	return Difficulty.DATA[difficulty]

func new_game() -> void:
	galaxy = 1
	planets.clear(); fleets.clear()
	_reset_run_state()
	tech = 0; upg = {}; result_msg = ""
	unlocked = {"Trooper": true, "Scout": false, "Tank": false, "Bomber": false, "Shield": false, "Medic": false}
	var rng := RandomNumberGenerator.new(); rng.randomize()
	planets.append(_mk(Vector2(140, 360), PLAYER, 30, 1.2))
	planets.append(_mk(Vector2(1420, 360), AI, D().start_ships, 1.2))
	_fill_neutrals(rng, 13)
	planets[0].factories = 1; planets[1].factories = 1

func _reset_run_state() -> void:
	ai_timer = 0.0; ai_build_timer = 0.0; since_attack = 0.0; pending_battle = null; in_game = true; elapsed = 0.0; recent_captures = []
	stats = {"attacks": 0, "max_attack": 0, "cap_violations": 0, "prod_violations": 0}

func _fill_neutrals(rng: RandomNumberGenerator, total: int) -> void:
	var tries := 0
	while planets.size() < total and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(260, 1300), rng.randf_range(80, 640))
		var ok := true
		for q in planets:
			if q.pos.distance_to(p) < 140: ok = false; break
		if ok:
			planets.append(_mk(p, NEUTRAL, int(rng.randi_range(5, 25) * ai_mult()), rng.randf_range(0.7, 1.3)))

## All player ships (planets + fleets in flight) -> mothership total.
func conquest_total() -> int:
	var t := 0.0
	for p in planets: if p.owner == PLAYER: t += int(p.ships)
	for f in fleets: if f.owner == PLAYER: t += f.count
	return int(t)

## Jump to a new procedurally generated galaxy carrying `ships` in the mothership.
func next_galaxy(ships: int) -> void:
	galaxy += 1
	if galaxy > best_galaxy:
		best_galaxy = galaxy
		var c := ConfigFile.new(); c.load(SETTINGS); c.set_value("game", "best_galaxy", best_galaxy); c.save(SETTINGS)
	planets.clear(); fleets.clear()
	_reset_run_state(); result_msg = ""
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var total := rng.randi_range(11, 16)
	var m := _mk(MOTHER_POS, PLAYER, ships, 2.2); m["mother"] = true; m["name"] = "Mothership"
	planets.append(m)
	var home := _mk(Vector2(rng.randf_range(330, 400), [200.0, 540.0][rng.randi() % 2]), PLAYER, 10, 0.8)
	home.factories = 1; planets.append(home)
	var n_ai := 1 if total < 14 else 2
	for k in n_ai:
		var y: float = 360.0 if n_ai == 1 else [200.0, 520.0][k]
		var a := _mk(Vector2(rng.randf_range(1380, 1450), y + rng.randf_range(-60, 60)), AI, int(D().start_ships * ai_mult()), 1.2)
		a.factories = 1; planets.append(a)
	_fill_neutrals(rng, total + 1)  # +1 for the mothership entry

const SYL := ["ka", "ri", "zor", "vel", "an", "tu", "mir", "xa", "lo", "the", "dra", "sol", "qui", "nex", "or", "ba", "ly", "sef", "ion", "ur"]
const PTYPES := ["rocky", "terran", "gas", "ice", "lava"]

## Deterministic name/type from a seed (planet look stays the same across saves).
func planet_name(seed: int) -> String:
	var r := RandomNumberGenerator.new(); r.seed = seed
	var s := ""
	for i in r.randi_range(2, 3): s += SYL[r.randi() % SYL.size()]
	s = s.capitalize()
	if r.randf() < 0.35: s += " " + ["I", "II", "III", "IV", "Prime", "Major"][r.randi() % 6]
	return s

func planet_type(seed: int) -> String:
	var r := RandomNumberGenerator.new(); r.seed = seed + 7
	return PTYPES[r.randi() % PTYPES.size()]

func _mk(pos, owner, ships, size) -> Dictionary:
	var seed := int(pos.x) * 7919 + int(pos.y) * 104729 + planets.size()
	return {"seed": seed, "name": planet_name(seed), "ptype": planet_type(seed), "pos": pos, "owner": owner, "ships": float(ships), "size": size, "factories": 0, "defense": 0, "towers": {}, "tower_types": {}, "mother": false}

func radius(p) -> float:
	return 28.0 + 18.0 * p.size

func count_owned(o) -> int:
	var n := 0
	for p in planets: if p.owner == o and not is_mother(p): n += 1
	for f in fleets: if f.owner == o: n += 0  # fleets alone don't keep you alive
	return n

func make_button(text: String, pos: Vector2, size := Vector2(220, 80)) -> Button:
	var b := Button.new()
	b.text = text; b.position = pos; b.size = size
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	return b

func make_label(text: String, pos: Vector2, fs := FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos
	l.add_theme_font_size_override("font_size", fs)
	return l

## Garrison of the player's weakest planet (cap for any AI attack).
func weakest_player_garrison() -> float:
	var w := INF
	for p in planets:
		if p.owner == PLAYER and not is_mother(p): w = min(w, p.ships)
	return 0.0 if w == INF else w

func base_production(p) -> float:
	if is_mother(p): return 0.0
	var bonus: float = (1.0 + elapsed / 240.0) * D().prod_bonus * ai_mult() if p.owner == AI else 1.0
	return (0.6 + 0.8 * p.factories) * p.size * bonus * (1.0 + 0.15 * lvl("prod", p.owner))

## Effective ships/sec. AI planets are clamped to (prod_cap x) the player's lowest-producing planet.
func production(p) -> float:
	var r := base_production(p)
	if p.owner == AI and D().prod_cap > 0:
		var low := INF
		for q in planets:
			if q.owner == PLAYER and not is_mother(q): low = min(low, base_production(q))
		if low != INF: r = min(r, low * D().prod_cap * ai_mult())
	return r

func weakest_player_production() -> float:
	var low := INF
	for q in planets: if q.owner == PLAYER and not is_mother(q): low = min(low, base_production(q))
	return low

## Max AI attack force (INF = no cap).
func attack_cap() -> float:
	return INF if D().atk_cap < 0 else weakest_player_garrison() * D().atk_cap * ai_mult()

# ---------------- Save / Continue ----------------
func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_GO_BACK_REQUEST]:
		if in_game and not auto_battle: save_game()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if has_save(): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _v(v: Vector2) -> Array: return [v.x, v.y]

func save_game() -> void:
	var ps := []
	for p in planets:
		var q: Dictionary = p.duplicate(true); q.pos = _v(p.pos); ps.append(q)
	var fs := []
	for f in fleets:
		var q: Dictionary = f.duplicate(); q.pos = _v(f.pos); fs.append(q)
	var data := {"version": 2, "galaxy": galaxy, "planets": ps, "fleets": fs, "tech": tech, "upg": upg,
		"unlocked": unlocked, "send_pct": send_pct, "fleet_type": fleet_type,
		"difficulty": difficulty, "elapsed": elapsed, "recent_captures": recent_captures,
		"ai_timer": ai_timer, "ai_build_timer": ai_build_timer, "since_attack": since_attack,
		"pending_battle": pending_battle}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data))

## Loads the save. Returns the scene to open ("galaxy" or "battle"), or "" on failure.
func load_game() -> String:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return ""
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY: return ""
	planets.clear(); fleets.clear()
	for q in d.planets:
		var t := {}
		for k in q.get("towers", {}): t[int(k)] = int(q.towers[k])
		var tt := {}
		for k in q.get("tower_types", {}): tt[int(k)] = str(q.tower_types[k])
		var sd := int(q.get("seed", int(q.pos[0]) * 7919 + int(q.pos[1]) * 104729 + planets.size()))
		planets.append({"seed": sd, "name": q.get("name", planet_name(sd)), "ptype": q.get("ptype", planet_type(sd)), "pos": Vector2(q.pos[0], q.pos[1]), "owner": int(q.owner), "ships": float(q.ships), "size": float(q.size),
			"factories": int(q.factories), "defense": int(q.defense), "towers": t, "tower_types": tt, "mother": bool(q.get("mother", false))})
	for q in d.fleets:
		fleets.append({"from": int(q.from), "to": int(q.to), "owner": int(q.owner), "count": int(q.count), "pos": Vector2(q.pos[0], q.pos[1]), "type": q.type})
	galaxy = int(d.get("galaxy", 1))
	tech = int(d.tech)   # old saves: "credits" field is ignored
	upg = {}
	for k in d.get("upg", {}): upg[k] = int(d.upg[k])
	if d.has("tower_level") and not upg.has("tower_dmg"): upg["tower_dmg"] = int(d.tower_level)  # migrate v1
	for k in d.unlocked:
		if unlocked.has(k): unlocked[k] = d.unlocked[k]
		if d.unlocked[k] and k != "Trooper" and int(d.get("version", 1)) < 2: upg["unlock_" + k] = 1
	if int(d.get("version", 1)) < 2:
		for k in unlocked: if k != "Trooper": unlocked[k] = upg.get("unlock_" + k, 0) > 0
	send_pct = d.send_pct; fleet_type = d.fleet_type
	if Difficulty.DATA.has(d.difficulty): difficulty = d.difficulty
	elapsed = d.elapsed; ai_timer = d.ai_timer; ai_build_timer = d.ai_build_timer; since_attack = d.since_attack
	recent_captures = []
	for i in d.recent_captures: recent_captures.append(int(i))
	stats = {"attacks": 0, "max_attack": 0, "cap_violations": 0, "prod_violations": 0}
	result_msg = ""; in_game = true
	pending_battle = null
	if d.pending_battle != null:
		var pb = d.pending_battle
		pending_battle = {"planet": int(pb.planet), "attacker": int(pb.attacker), "ships": int(pb.ships), "type": pb.type}
		return "battle"
	return "galaxy"

# ---------------- Upgrades / stats ----------------
func is_infinite(id: String) -> bool: return Upgrades.UP[id].get("infinite", false)
func max_level(id: String) -> int: return 1 << 30 if is_infinite(id) else Upgrades.UP[id].cost.size()

## Upgrade level for an owner. The AI gets difficulty-scaled equivalents.
func lvl(id: String, owner: int) -> int:
	if owner == PLAYER: return upg.get(id, 0)
	if owner == AI: return min(max_level(id), D().ai_upg + int(elapsed / 240.0) + int((galaxy - 1) / 10))
	return 0

func upgrade_cost(id: String) -> int:
	var l: int = upg.get(id, 0)
	var costs: Array = Upgrades.UP[id].cost
	if is_infinite(id): return costs[min(l, costs.size() - 1)]
	return -1 if l >= max_level(id) else costs[l]

func buy_upgrade(id: String) -> bool:
	var c := upgrade_cost(id)
	if c < 0 or tech < c: return false
	tech -= c; upg[id] = upg.get(id, 0) + 1
	if id.begins_with("unlock_") and unlocked.has(id.substr(7)): unlocked[id.substr(7)] = true
	return true

func has_troop(k: String, owner: int) -> bool:
	if k == "Trooper": return true
	if owner == PLAYER: return unlocked.get(k, false)
	return lvl("unlock_" + k, AI) > 0 or D().ai_upg >= 2

func has_tower(k: String, owner: int) -> bool:
	if k == "Gun": return true
	if owner == PLAYER: return upg.get("unlock_" + k, 0) > 0
	return D().ai_upg + int(elapsed / 240.0) >= ["Gun", "Frost", "Missile", "Laser"].find(k)

func troop_stats(k: String, owner: int) -> Dictionary:
	var d: Dictionary = TROOPS[k].duplicate()
	d.hp *= 1.0 + 0.2 * lvl("troop_hp", owner)
	if owner == AI: d.hp *= ai_mult()
	d.speed *= 1.0 + 0.1 * lvl("troop_speed", owner)
	return d

## Per-shot damage, range, rate for a tower type at a tower level (0-based) for owner.
func tower_stats(k: String, level: int, owner: int) -> Dictionary:
	var d: Dictionary = TOWERS[k].duplicate()
	var dmg_l: int = lvl("tower_dmg", owner) + (D().tower_bonus if owner == AI else 0)
	d.rate *= 1.0 + 0.2 * lvl("tower_rate", owner)
	d.range *= 1.0 + 0.12 * lvl("tower_range", owner)
	d.dmg = d.dps * (1.0 + 0.5 * level) * (1.0 + 0.25 * dmg_l) / TOWERS[k].rate
	return d

func fleet_speed_mult(owner: int) -> float: return 1.0 + 0.15 * lvl("fleet_speed", owner)
func factory_cost(p) -> int: return int(round((20 + 10 * p.factories) * (1.0 - 0.15 * lvl("cheap_factory", p.owner))))
func max_factories(owner: int) -> int: return 5 + 5 * lvl("max_factories", owner)
const DEFENSE_COST := 15
## Defender tower damage multiplier from the planet's garrison: 1 + ships/100.
func garrison_mult(p) -> float: return 1.0 + max(0.0, p.ships) / 100.0

## Styled button (rounded, coloured, clear disabled state) with optional icon.
func style_button(b: Button, col := Color(0.25, 0.45, 0.8), icon_name := "") -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		var c := col
		match st:
			"hover": c = col.lightened(0.15)
			"pressed": c = col.darkened(0.2)
			"disabled": c = Color(0.2, 0.2, 0.24)
			"focus": c = Color(0, 0, 0, 0)
		sb.bg_color = c; sb.set_corner_radius_all(14); sb.set_border_width_all(2)
		sb.border_color = c.lightened(0.35) if st != "disabled" else Color(0.35, 0.35, 0.4)
		sb.content_margin_left = 16; sb.content_margin_right = 16
		if st == "focus": sb.draw_center = false; sb.set_border_width_all(0)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.6))
	if icon_name != "":
		b.icon = load("res://art/icons/%s.png" % icon_name)
		b.add_theme_constant_override("icon_max_width", 44)

## Galaxy number stored in the save (for the Continue button), 0 if none.
func save_galaxy() -> int:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return 0
	var d = JSON.parse_string(f.get_as_text())
	return int(d.get("galaxy", 1)) if typeof(d) == TYPE_DICTIONARY else 0
