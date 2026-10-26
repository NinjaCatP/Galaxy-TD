extends Node
# Headless smoke test: every screen, full battles to completion, tower persistence.
func _run(n, steps := 4000) -> void:
	for i in steps:
		if n.has_method("_process"): n._process(0.05)
		if "done" in n and n.done: return

func _ready() -> void:
	Game.new_game()
	for s in ["galaxy", "planet", "upgrades", "main_menu"]:
		if s == "planet": Game.selected_planet = 0
		var n = load("res://scenes/%s.tscn" % s).instantiate(); add_child(n); _run(n, 600); print("OK ", s); n.queue_free()
	# 1) Player attacks AI planet 1 to completion
	Game.planets[1].ships = 10
	Game.pending_battle = {"planet": 1, "attacker": 1, "ships": 80, "type": "Trooper"}
	var n = load("res://scenes/battle.tscn").instantiate(); add_child(n)
	for i in 4000:
		if i % 20 == 0: n._player_spawn("Trooper")
		n._process(0.05)
		if n.done: break
	print("ATTACK done=%s owner=%d core=%d" % [n.done, Game.planets[1].owner, n.core_hp]); assert(n.done)
	n.queue_free()
	# 2) AI attacks player planet 0; player builds towers and defends
	Game.planets[0].owner = 1; Game.planets[0].ships = 40; Game.planets[0].towers = {}
	Game.pending_battle = {"planet": 0, "attacker": 2, "ships": 999, "type": "Trooper"}
	n = load("res://scenes/battle.tscn").instantiate(); add_child(n)
	print("DEF enemy pool capped 999->%d" % n.pool); assert(n.pool <= 40)
	print("DEF budget=%d (garrison 40)" % n.budget)
	for s in [0, 1, 2, 4]: n.towers[s] = 1
	_run(n)
	print("DEFENSE done=%s owner=%d ships=%d towers=%s" % [n.done, Game.planets[0].owner, Game.planets[0].ships, Game.planets[0].towers])
	assert(n.done and Game.planets[0].owner == 1 and Game.planets[0].towers.size() == 4)
	n.queue_free()
	# 3) Next defense: towers pre-placed
	Game.pending_battle = {"planet": 0, "attacker": 2, "ships": 5, "type": "Trooper"}
	n = load("res://scenes/battle.tscn").instantiate(); add_child(n)
	print("PERSIST towers preplaced=%d" % n.towers.size()); assert(n.towers.size() == 4)
	n.queue_free()
	# 4) Per-difficulty galaxy simulation (fleets fly and land normally; battles auto-resolved)
	Game.auto_battle = true
	var results := {}
	for diff in Game.Difficulty.ORDER:
		Game.difficulty = diff
		Game.new_game()
		var gx = load("res://scenes/galaxy.tscn").instantiate(); add_child(gx)
		var maxprod := 0.0
		for i in 4800:  # 4 minutes
			gx._process(0.05)
			if Game.count_owned(1) > 0:
				var low: float = Game.weakest_player_production()
				for p in Game.planets:
					if p.owner == 2:
						var r: float = Game.production(p); maxprod = max(maxprod, r)
						if Game.D().prod_cap > 0 and r > low * Game.D().prod_cap + 0.0001: Game.stats.prod_violations += 1
		results[diff] = Game.stats.duplicate()
		print("SIM %-6s attacks=%d max_attack=%d cap_viol=%d prod_viol=%d maxAIprod=%.2f planets you=%d AI=%d" % [diff, Game.stats.attacks, Game.stats.max_attack, Game.stats.cap_violations, Game.stats.prod_violations, maxprod, Game.count_owned(1), Game.count_owned(2)])
		gx.queue_free()
	assert(results.Easy.attacks >= 1 and results.Easy.cap_violations == 0 and results.Easy.prod_violations == 0)
	assert(results.Normal.cap_violations == 0 and results.Hard.cap_violations == 0)
	assert(results.Brutal.attacks > results.Easy.attacks and results.Hard.attacks > results.Easy.attacks)
	Game.auto_battle = false
	Game.difficulty = "Easy"; Game.new_game()
	# 5) Production clamp
	Game.planets[1].owner = 2; Game.planets[1].factories = 10; Game.elapsed = 600
	Game.planets[0].owner = 1; Game.planets[0].factories = 0
	var low := INF
	for p in Game.planets: if p.owner == 1: low = min(low, Game.base_production(p))
	var ai_r: float = Game.production(Game.planets[1])
	print("CLAMP AI base=%.2f effective=%.2f player-weakest=%.2f" % [Game.base_production(Game.planets[1]), ai_r, low])
	assert(ai_r <= low + 0.0001)
	Game.planets[0].factories = 3
	low = INF
	for p in Game.planets: if p.owner == 1: low = min(low, Game.base_production(p))
	print("CLAMP after player builds: effective=%.2f weakest=%.2f" % [Game.production(Game.planets[1]), low])
	assert(Game.production(Game.planets[1]) <= low + 0.0001)
	# 5b) Free first tower
	Game.new_game()
	Game.planets[0].owner = 1; Game.planets[0].ships = 0; Game.planets[0].defense = 0; Game.planets[0].towers = {}
	Game.pending_battle = {"planet": 0, "attacker": 2, "ships": 5, "type": "Trooper"}
	var fb = load("res://scenes/battle.tscn").instantiate(); add_child(fb)
	var a1: bool = fb.try_place(0); var a2: bool = fb.try_place(1)
	print("FREE TOWER budget=%d first=%s second=%s towers=%d" % [fb.budget, a1, a2, fb.towers.size()])
	assert(fb.budget == 0 and a1 and not a2 and fb.towers.size() == 1)
	fb.queue_free()
	# 6) Save / Continue round trip
	Game.difficulty = "Hard"; Game.new_game()
	Game.planets[0].towers = {3: 2, 7: 0}; Game.planets[0].tower_types = {3: "Laser", 7: "Gun"}; Game.planets[0].factories = 4; Game.planets[2].owner = 1
	Game.upg = {"prod": 2, "unlock_Laser": 1, "regen": 1}; Game.tech = 7; Game.unlocked.Tank = true; Game.fleet_type = "Tank"; Game.send_pct = 0.75
	Game.fleets.append({"from": 0, "to": 5, "owner": 1, "count": 17, "pos": Vector2(300, 200), "type": "Tank"})
	Game.elapsed = 99.5; Game.ai_timer = 1.25
	Game.save_game()
	var snap := JSON.stringify([Game.planets, Game.fleets, Game.upg, Game.tech, Game.unlocked, Game.fleet_type, Game.send_pct, Game.elapsed, Game.ai_timer])
	Game.difficulty = "Easy"; Game.new_game()
	assert(Game.has_save())
	var scene := Game.load_game()
	var snap2 := JSON.stringify([Game.planets, Game.fleets, Game.upg, Game.tech, Game.unlocked, Game.fleet_type, Game.send_pct, Game.elapsed, Game.ai_timer])
	print("SAVE round-trip scene=%s difficulty=%s towers=%s match=%s" % [scene, Game.difficulty, Game.planets[0].towers, snap == snap2])
	assert(scene == "galaxy" and Game.difficulty == "Hard" and snap == snap2 and Game.planets[0].towers[3] == 2)
	# mid-battle save resumes into battle
	Game.pending_battle = {"planet": 1, "attacker": 1, "ships": 20, "type": "Trooper"}; Game.save_game()
	Game.pending_battle = null
	assert(Game.load_game() == "battle" and Game.pending_battle.ships == 20)
	print("SAVE mid-battle resume OK")
	# win deletes save
	Game.pending_battle = null
	for p in Game.planets: p.owner = 1
	Game.fleets.clear()
	var gx2 = load("res://scenes/galaxy.tscn").instantiate(); add_child(gx2)
	gx2._check_end()
	print("WIN starts conquest (no game over): %s" % (not gx2.conquest.is_empty())); assert(not gx2.conquest.is_empty())
	gx2.queue_free()
	Game.difficulty = "Easy"
	_new_features()
	_campaign()
	_bosses()
	print("SMOKE PASS")

func _approx(a: float, b: float) -> bool: return abs(a - b) < 0.001

func _new_features() -> void:
	Game.difficulty = "Easy"; Game.new_game()
	# --- ships are the currency ---
	Game.selected_planet = 0
	var pl = load("res://scenes/planet.tscn").instantiate(); add_child(pl)
	Game.planets[0].ships = 100; Game.planets[0].factories = 1
	var cost := Game.factory_cost(Game.planets[0])
	assert(pl._buy_factory() and _approx(Game.planets[0].ships, 100 - cost) and Game.planets[0].factories == 2)
	Game.planets[0].ships = 5
	assert(not pl._buy_factory() and Game.planets[0].factories == 2)
	assert(not pl._buy_defense())
	Game.planets[0].ships = 20; assert(pl._buy_defense() and _approx(Game.planets[0].ships, 5))
	# Factory cap: base 5, infinite upgrade +2 per level
	Game.planets[0].ships = 100000; Game.planets[0].factories = 0; Game.upg = {}; Game.tech = 1000
	while pl._buy_factory(): pass
	assert(Game.planets[0].factories == 5)
	var costs := []
	for i in 8:
		var cap0 := Game.max_factories(1); costs.append(Game.upgrade_cost("max_factories"))
		assert(Game.buy_upgrade("max_factories") and Game.max_factories(1) == cap0 + 5)
	while pl._buy_factory(): pass
	print("FACTORY CAP after 8 buys: cap=%d built=%d costs=%s" % [Game.max_factories(1), Game.planets[0].factories, costs])
	assert(Game.planets[0].factories == 45 and costs == [2, 3, 4, 5, 6, 7, 8, 8])
	Game.planets[0].factories = 2; Game.upg = {}
	print("SHIPS-AS-CURRENCY factory cost %d deducted, blocked when short: OK" % cost)
	pl.queue_free()
	# --- every upgrade applies ---
	Game.tech = 999
	var p0 = Game.planets[0]
	var before := {"prod": Game.base_production(p0), "spd": Game.fleet_speed_mult(1), "hp": Game.troop_stats("Trooper", 1).hp,
		"tspd": Game.troop_stats("Trooper", 1).speed, "dmg": Game.tower_stats("Gun", 0, 1).dmg, "rng": Game.tower_stats("Gun", 0, 1).range,
		"rate": Game.tower_stats("Gun", 0, 1).rate, "fc": Game.factory_cost(p0)}
	var maxf0 := Game.max_factories(1)
	for id in Game.Upgrades.UP: assert(Game.buy_upgrade(id), id)
	var res := {"prod": Game.base_production(p0) > before.prod, "spd": Game.fleet_speed_mult(1) > before.spd, "hp": Game.troop_stats("Trooper", 1).hp > before.hp,
		"tspd": Game.troop_stats("Trooper", 1).speed > before.tspd, "dmg": Game.tower_stats("Gun", 0, 1).dmg > before.dmg,
		"rng": Game.tower_stats("Gun", 0, 1).range > before.rng, "rate": Game.tower_stats("Gun", 0, 1).rate > before.rate,
		"fc": Game.factory_cost(p0) < before.fc, "maxf": Game.max_factories(1) == maxf0 + 5}
	for k in ["Scout", "Tank", "Bomber", "Shield", "Medic"]: res["troop_" + k] = Game.has_troop(k, 1)
	for k in ["Frost", "Missile", "Laser"]: res["tower_" + k] = Game.has_tower(k, 1)
	# hull + shield: battle values
	Game.planets[1].owner = 2; Game.planets[1].ships = 10
	Game.pending_battle = {"planet": 1, "attacker": 1, "ships": 20, "type": "Trooper"}
	var bt = load("res://scenes/battle.tscn").instantiate(); add_child(bt)
	res["hull"] = bt.pool > 20; bt.queue_free()
	p0.ships = 20; p0.defense = 0
	Game.pending_battle = {"planet": 0, "attacker": 2, "ships": 5, "type": "Trooper"}
	bt = load("res://scenes/battle.tscn").instantiate(); add_child(bt)
	print("core_max=", bt.core_max, " ships=", p0.ships, " sh=", Game.lvl("shield", 1), " owner=", p0.owner)
	res["shield"] = bt.core_max == 15 + 5 + 5; bt.queue_free()
	# regen
	var gx = load("res://scenes/galaxy.tscn").instantiate(); add_child(gx)
	var s0: float = Game.planets[0].ships; var prod0 := Game.production(Game.planets[0])
	gx._process(1.0)
	print("regen d=", Game.planets[0].ships - s0, " prod=", prod0)
	res["regen"] = Game.planets[0].ships - s0 > prod0 * 1.0 + 0.15
	gx.queue_free()
	print("UPGRADES applied: ", res)
	for k in res: assert(res[k], k)
	# --- all tower types fire (one battle per type), new troops work ---
	var fired := {}
	for k in ["Gun", "Frost", "Missile", "Laser"]:
		p0.owner = 1; p0.ships = 30; p0.towers = {0: 0}; p0.tower_types = {0: k}
		Game.pending_battle = {"planet": 0, "attacker": 2, "ships": 12, "type": "Shield"}
		bt = load("res://scenes/battle.tscn").instantiate(); add_child(bt)
		bt.prep = 0; bt._spawn("Medic")
		for i in 3000:
			bt._process(0.05)
			if bt.done: break
		fired[k] = bt.shots_fired.get(k, 0)
		assert(bt.done and fired[k] > 0, k)
		bt.queue_free()
	print("TOWERS fired per type: ", fired, "  persisted type after defense: ", Game.planets[0].tower_types)
	# --- garrison damage bonus ---
	var dm := {}
	for g in [0, 100, 1000]:
		p0.owner = 1; p0.ships = g; p0.towers = {0: 0}; p0.tower_types = {0: "Gun"}
		Game.pending_battle = {"planet": 0, "attacker": 2, "ships": 5, "type": "Trooper"}
		bt = load("res://scenes/battle.tscn").instantiate(); add_child(bt)
		dm[g] = bt.shot_damage("Gun", 0); bt.queue_free()
	print("GARRISON dmg per shot: 0->%.2f 100->%.2f 1000->%.2f (x%.1f, x%.1f)" % [dm[0], dm[100], dm[1000], dm[100] / dm[0], dm[1000] / dm[0]])
	assert(_approx(dm[100] / dm[0], 2.0) and _approx(dm[1000] / dm[0], 11.0))
	# AI defender also gets it
	Game.planets[1].owner = 2; Game.planets[1].ships = 258
	Game.pending_battle = {"planet": 1, "attacker": 1, "ships": 5, "type": "Trooper"}
	bt = load("res://scenes/battle.tscn").instantiate(); add_child(bt)
	assert(_approx(bt.garrison_mult, 3.58)); bt.queue_free()
	# --- fleet toughness ---
	var hp := {}
	for n in [0, 100, 1000]:
		Game.planets[1].owner = 2; Game.planets[1].ships = 10
		Game.pending_battle = {"planet": 1, "attacker": 1, "ships": n, "type": "Trooper"}
		bt = load("res://scenes/battle.tscn").instantiate(); add_child(bt)
		bt._spawn("Shield"); hp[n] = [bt.troops[0].max, bt.troops[0].shield]; bt.queue_free()
	print("FLEET troop HP/shield: 0->%s 100->%s 1000->%s" % [hp[0], hp[100], hp[1000]])
	assert(_approx(hp[100][0] / hp[0][0], 2.0) and _approx(hp[1000][0] / hp[0][0], 11.0) and _approx(hp[1000][1] / hp[0][1], 11.0))
	Game.difficulty = "Easy"
	p0.owner = 1; p0.ships = 50
	for q in Game.planets: if q.owner == 1 and q != p0: q.owner = 0
	Game.pending_battle = {"planet": 0, "attacker": 2, "ships": 500, "type": "Trooper"}
	bt = load("res://scenes/battle.tscn").instantiate(); add_child(bt)
	print("FLEET Easy-capped AI attack 500 -> %d ships, toughness x%.2f" % [bt.b.ships, bt.fleet_mult])
	assert(bt.b.ships == 50 and _approx(bt.fleet_mult, 1.5)); bt.queue_free()
	# --- battle speed toggle ---
	var outcome := {}
	var shots := {}
	for spd in [1, 3, 5]:
		Game.battle_speed = spd
		p0.owner = 1; p0.ships = 30; p0.towers = {0: 1, 4: 0}; p0.tower_types = {0: "Gun", 4: "Frost"}
		Game.pending_battle = {"planet": 0, "attacker": 2, "ships": 25, "type": "Trooper"}
		bt = load("res://scenes/battle.tscn").instantiate(); add_child(bt)
		var steps := 0
		while not bt.done and steps < 20000: bt._process(0.05); steps += 1
		outcome[spd] = [steps, Game.planets[0].owner, bt.core_hp]; shots[spd] = bt.shots_fired.duplicate()
		bt.queue_free()
	print("SPEED 1x steps=%d owner=%d core=%d | 3x steps=%d owner=%d core=%d" % [outcome[1][0], outcome[1][1], outcome[1][2], outcome[3][0], outcome[3][1], outcome[3][2]])
	print("SPEED 5x steps=%d owner=%d core=%d  shots 1x=%s 5x=%s" % [outcome[5][0], outcome[5][1], outcome[5][2], shots[1], shots[5]])
	for s in [3, 5]:
		assert(outcome[1][1] == outcome[s][1] and outcome[1][2] == outcome[s][2] and abs(outcome[s][0] * s - outcome[1][0]) < outcome[1][0] * 0.1)
	assert(abs(shots[5].get("Gun", 0) - shots[1].get("Gun", 0)) <= 2)
	Game.set_battle_speed(5)
	var c2 := ConfigFile.new(); c2.load("user://settings.cfg"); assert(int(c2.get_value("game", "battle_speed")) == 5)
	assert(Engine.time_scale == 1.0)  # galaxy/UI never sped up (battle-local multiplier)
	Game.set_battle_speed(1)
	# --- audio ---
	var n0: int = Audio.played
	for s in ["launch", "capture", "shot_gun", "shot_frost", "shot_missile", "shot_laser", "death", "core_hit", "win", "lose", "tap", "upgrade", "build"]:
		assert(Audio._stream(s) != null, s); Audio.sfx(s, 0.0)
	Audio.music("music_galaxy"); Audio.music("music_battle")
	assert(Audio._stream("music_galaxy") != null and Audio._stream("music_battle") != null)
	Game.set_difficulty("Easy")
	Audio.set_volumes(0.3, 0.45, true)
	var c := ConfigFile.new(); c.load("user://settings.cfg")
	assert(_approx(c.get_value("audio", "music"), 0.3) and _approx(c.get_value("audio", "sfx"), 0.45) and c.get_value("audio", "muted") == true)
	assert(c.get_value("game", "difficulty", "") != "")
	Audio.set_volumes(0.6, 0.8, false)
	print("AUDIO played %d sfx, music ok, settings saved ok" % (Audio.played - n0))
	# --- save includes upgrades ---
	Game.save_game(); var u := JSON.stringify(Game.upg); Game.upg = {}
	Game.load_game(); assert(JSON.stringify(Game.upg) == u and Game.unlocked.Medic)
	print("SAVE upgrades round-trip OK")
	Game.delete_save(); get_tree().quit()

func _campaign() -> void:
	Game.auto_battle = true
	Game.new_game()
	Game.upg = {"max_factories": 7, "prod": 2}; Game.tech = 17; Game.fleet_type = "Trooper"
	for p in Game.planets: p.owner = Game.PLAYER; p.ships = 10
	Game.planets[0].towers = {0: 1}; Game.planets[0].tower_types = {0: "Gun"}
	Game.fleets = [{"from": 0, "to": 3, "owner": 1, "count": 25, "pos": Vector2(300, 300), "type": "Trooper"}]
	var expected := 10 * Game.planets.size() + 25
	var old_pos := Game.planets.map(func(p): return p.pos)
	var total := Game.conquest_total()
	assert(total == expected)
	# run the real sequence in the galaxy scene
	Game.auto_battle = false
	var gx = load("res://scenes/galaxy.tscn").instantiate(); add_child(gx); gx.set_process(false)
	gx._check_end(); assert(not gx.conquest.is_empty())
	var steps := 0
	while not gx.conquest.jumped and steps < 1000: gx._conquest_step(0.05); steps += 1
	Game.auto_battle = true
	gx.queue_free()
	var m := Game.mother_index()
	print("CAMPAIGN galaxy=%d mult=%.4f mother=%d expected=%d planets=%d" % [Game.galaxy, Game.ai_mult(), int(Game.planets[m].ships), expected, Game.planets.size() - 1])
	assert(Game.galaxy == 2 and _approx(Game.ai_mult(), 1.01) and int(Game.planets[m].ships) == expected)
	assert(Game.planets.size() - 1 >= 11 and Game.planets.size() - 1 <= 16)
	assert(Game.planets.map(func(p): return p.pos) != old_pos)
	assert(Game.upg.max_factories == 7 and Game.tech == 17 and Game.max_factories(Game.PLAYER) == 40)
	assert(Game.count_owned(Game.PLAYER) == 1 and Game.count_owned(Game.AI) >= 1)
	for p in Game.planets: assert(p.towers.is_empty() and (p.factories <= 1))
	assert(Game.production(Game.planets[m]) == 0.0)
	assert(Game.best_galaxy >= 2)
	# AI scaling applied
	Game.difficulty = "Normal"
	var ap = Game.planets[[0,1,2,3].filter(func(i): return Game.planets[i].owner == Game.AI)[0] if false else 0]
	for p in Game.planets: if p.owner == Game.AI: ap = p
	var g1 := Game.galaxy; Game.galaxy = 1; var b1 := Game.base_production(ap); var h1: float = Game.troop_stats("Trooper", Game.AI).hp
	Game.galaxy = g1
	assert(_approx(Game.base_production(ap), b1 * 1.01) and _approx(Game.troop_stats("Trooper", Game.AI).hp, h1 * 1.01))
	print("CAMPAIGN AI scaling x1.01 OK; label=%s" % Game.difficulty_label())
	# save/load mid-galaxy-2
	Game.save_game()
	var snap := JSON.stringify(Game.planets)
	Game.galaxy = 9; Game.planets.clear()
	assert(Game.load_game() == "galaxy" and Game.galaxy == 2 and JSON.stringify(Game.planets) == snap and Game.mother_index() == m and Game.save_galaxy() == 2)
	print("CAMPAIGN save/load galaxy 2 OK")
	# lose: no planets, empty mothership, no fleets
	Game.auto_battle = false
	var gx3 = load("res://scenes/galaxy.tscn").instantiate(); add_child(gx3); gx3.set_process(false)
	for p in Game.planets: if p.owner == Game.PLAYER and not Game.is_mother(p): p.owner = Game.AI
	Game.fleets.clear()
	assert(not gx3.lost())   # mothership still has ships
	Game.planets[m].ships = 0
	assert(gx3.lost())
	gx3._check_end()
	assert(not Game.has_save())
	print("CAMPAIGN lose condition OK")
	gx3.queue_free()
	Game.auto_battle = true; Game.difficulty = "Easy"; Game.galaxy = 1

func _bosses() -> void:
	# stress: 700 ships of tanks at 5x must stay fast (auto-stacking + cached sim)
	var ms: float = load("res://tests/stress.gd").run(self, 60)
	print("STRESS 700 tanks @5x: %.2f ms/frame sim" % ms); assert(ms < 4.0)
	Game.auto_battle = true
	Game.new_game()
	Game.upg["unlock_Tank"] = 1; Game.upg["unlock_Scout"] = 1; Game.unlocked["Tank"] = true; Game.unlocked["Scout"] = true
	Game.pending_battle = {"planet": 1, "attacker": 1, "ships": 99, "type": "Trooper"}
	var bt = load("res://scenes/battle.tscn").instantiate(); add_child(bt)
	assert(not bt.spawn_boss("Tank"))   # locked under 100 ships
	bt.queue_free()
	Game.pending_battle = {"planet": 1, "attacker": 1, "ships": 200, "type": "Trooper"}
	bt = load("res://scenes/battle.tscn").instantiate(); add_child(bt)
	var single: float = Game.troop_stats("Tank", 1).hp * bt.fleet_mult
	var p0: int = bt.pool
	assert(bt.spawn_boss("Tank") and bt.pool == p0 - 30)
	var boss = bt.troops[-1]
	assert(_approx(boss.max, single * 10) and boss.n == 10 and boss.boss)
	bt._spawn("Tank"); var tank = bt.troops[-1]
	bt.prep = 0; bt._sim(0.1)
	assert(_approx(boss.d / tank.d, 0.6))
	assert(bt.spawn_boss("Scout") and bt.pool == p0 - 30 - 10)
	# stacked units: equivalent HP, not slowed
	bt.troops.clear()
	for i in 45: bt._spawn("Trooper", 0.0)
	var tot := 0; var hp := 0.0
	for t in bt.troops: tot += t.n; hp += t.max
	assert(tot == 45 and _approx(hp, 45 * Game.troop_stats("Trooper", 1).hp * bt.fleet_mult) and bt.troops.size() < 45)
	print("BOSS/STACK OK: boss hp x10, speed x0.6, cost 10x; 45 troopers -> %d units" % bt.troops.size())
	bt.queue_free()
	# AI uses bosses when force >= 100
	Game.planets[0].ships = 300
	Game.pending_battle = {"planet": 0, "attacker": 2, "ships": 250, "type": "Trooper"}
	var ab = load("res://scenes/battle.tscn").instantiate(); add_child(ab)
	if ab.b.ships >= 100:
		ab.prep = 0
		for i in 600: ab._ai_waves(0.1)
		assert(ab.troops.any(func(t): return t.boss))
		print("AI bosses OK")
	ab.queue_free()
