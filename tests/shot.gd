extends Node
# Renders screens to PNG. Args after --: <out.png> <battle|attack|galaxy>
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/workspace/galaxy-td/screens/battle.png"
	var mode: String = args[1] if args.size() > 1 else "battle"
	Game.auto_battle = true
	Game.new_game()
	get_window().size = Vector2i(1560, 720)
	var n
	if mode == "mothership" or mode == "mothership_skin":
		Game.next_galaxy(312)
		n = load("res://scenes/galaxy.tscn").instantiate(); add_child(n); n.set_process(false)
		if mode == "mothership_skin":
			n.scale = Vector2(3.4, 3.4); n.position = -Game.MOTHER_POS * 3.4 + Vector2(860, 330)
		for i in 10: n._process_overlay(); n.queue_redraw(); await get_tree().process_frame
	elif mode == "jump":
		for p in Game.planets: p.owner = 1
		n = load("res://scenes/galaxy.tscn").instantiate(); add_child(n); n.set_process(false)
		n.start_conquest()
		for i in 75: n._conquest_step(0.05); await get_tree().process_frame
	elif mode == "boss":
		for k in ["Scout", "Tank", "Shield", "Medic"]: Game.upg["unlock_" + k] = 1; Game.unlocked[k] = true
		Game.planets[1].ships = 25
		Game.pending_battle = {"planet": 1, "attacker": 1, "ships": 400, "type": "Trooper"}
		n = load("res://scenes/battle.tscn").instantiate(); add_child(n)
		n.prep = 0
		var order := ["Tank", "Scout", "Trooper", "Shield", "Medic"]
		for i in order.size(): n._spawn(order[i], -i * 75.0, 10, true); n.pool -= n.boss_cost(order[i])
		for i in 50: n._spawn("Trooper", -600 - i * 12.0)
		n.boss_toggle.button_pressed = true
		for i in 230: n._process(1.0 / 30.0); await get_tree().process_frame
	elif mode == "main_menu":
		Game.auto_battle = false; Game.galaxy = 4; Game.save_game()
		n = load("res://scenes/main_menu.tscn").instantiate(); add_child(n)
		for i in 100: await get_tree().process_frame
		n.t = 14.0
		for i in 3: await get_tree().process_frame
	elif mode == "planet_menu":
		var p = Game.planets[0]
		p.ships = 140; p.factories = 22; p.defense = 5
		p.towers = {0: 1, 2: 0, 4: 2, 7: 1}; p.tower_types = {0: "Gun", 2: "Frost", 4: "Missile", 7: "Laser"}
		Game.upg = {"max_factories": 4}
		Game.selected_planet = 0
		n = load("res://scenes/planet.tscn").instantiate(); add_child(n)
		for i in 8: await get_tree().process_frame
	elif mode == "galaxy":
		Game.planets[2].factories = 3; Game.planets[0].factories = 12
		Game.planets[0].towers = {0: 1, 1: 0}; Game.planets[0].tower_types = {0: "Gun", 1: "Frost"}
		for i in [2, 3, 4]: Game.planets[i].owner = 1
		for i in [5, 6]: Game.planets[i].owner = 2
		var types := ["Trooper", "Scout", "Tank", "Bomber", "Shield", "Medic"]
		for i in types.size():
			var from := 0 if i % 2 == 0 else 1
			var to: int = [7, 8, 9, 10, 11, 12][i]
			var fp: Vector2 = Game.planets[from].pos
			Game.fleets.append({"from": from, "to": to, "owner": 1 if i % 2 == 0 else 2, "count": [8, 14, 30, 22, 12, 6][i], "pos": fp.lerp(Game.planets[to].pos, 0.45), "type": types[i]})
		n = load("res://scenes/galaxy.tscn").instantiate(); add_child(n); n.set_process(false)
		for i in 5: n.queue_redraw(); await get_tree().process_frame
	else:
		Game.upg = {"unlock_Frost": 1, "unlock_Missile": 1, "unlock_Laser": 1}
		Game.planets[0].ships = 30
		Game.planets[0].towers = {0: 1, 2: 0, 4: 2, 7: 1, 1: 0}
		Game.planets[0].tower_types = {0: "Gun", 2: "Frost", 4: "Missile", 7: "Laser", 1: "Gun"}
		Game.pending_battle = {"planet": 0, "attacker": 2, "ships": 40, "type": "Trooper"}
		Game.upg["unlock_Tank"] = 1
		n = load("res://scenes/battle.tscn").instantiate(); add_child(n)
		n.prep = 0; n.selected = 4
		for k in ["Tank", "Bomber", "Shield", "Medic", "Scout"]: n._spawn(k, -randf() * 200)
		for i in 150: n._process(1.0 / 30.0); await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("SAVED ", out); get_tree().quit()
