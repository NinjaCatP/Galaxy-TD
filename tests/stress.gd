extends Node
# Battle stress benchmark: 700 ships of tanks, player attacking, 5x speed. Prints avg sim ms/frame.
func _ready() -> void:
	print("STRESS sim_ms_per_frame=%.3f" % run(self))
	get_tree().quit()

static func run(parent: Node, frames := 120) -> float:
	Game.auto_battle = true
	Game.new_game()
	Game.upg["unlock_Tank"] = 1; Game.unlocked["Tank"] = true
	Game.planets[1].ships = 40
	Game.planets[1].towers = {0: 3, 2: 3, 4: 3, 7: 3, 1: 3, 3: 3}
	Game.planets[1].tower_types = {0: "Gun", 2: "Frost", 4: "Missile", 7: "Laser", 1: "Gun", 3: "Missile"}
	Game.pending_battle = {"planet": 1, "attacker": 1, "ships": 700, "type": "Tank"}
	var old := Game.battle_speed; Game.battle_speed = 5
	var n = load("res://scenes/battle.tscn").instantiate(); parent.add_child(n)
	n.prep = 0
	while n.pool >= 3: n._player_spawn("Tank")
	var t0 := Time.get_ticks_usec()
	var cnt := 0
	for i in frames:
		if n.done: break
		n._process(1.0 / 60.0); cnt += 1
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0 / max(1, cnt)
	Game.battle_speed = old
	n.queue_free()
	return ms
