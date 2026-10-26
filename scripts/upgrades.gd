extends Node2D
## Tech-point upgrades, by category.

var lbl: Label
var buttons := {}

func _ready() -> void:
	var ui := CanvasLayer.new(); add_child(ui)
	lbl = Game.make_label("", Vector2(30, 14), 32); ui.add_child(lbl)
	var x := 20
	for cat in Game.Upgrades.CATS:
		ui.add_child(Game.make_label(cat.to_upper(), Vector2(x + 6, 62), 26))
		var y := 100
		for id in Game.Upgrades.UP:
			if Game.Upgrades.UP[id].cat != cat: continue
			var b := Game.make_button("", Vector2(x, y), Vector2(296, 76))
			b.add_theme_font_size_override("font_size", 19)
			b.pressed.connect(func(): _buy(id)); ui.add_child(b); buttons[id] = b; y += 82
		x += 306
	var back := Game.make_button("Back", Vector2(1300, 630), Vector2(240, 80)); ui.add_child(back)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/galaxy.tscn"))
	_refresh()

func _buy(id: String) -> void:
	if Game.buy_upgrade(id): Audio.sfx("upgrade")
	_refresh()

func _refresh() -> void:
	lbl.text = "UPGRADES   Tech points: %d   (capture planets +1, win battles +3)" % Game.tech
	for id in buttons:
		var u = Game.Upgrades.UP[id]
		var l: int = Game.upg.get(id, 0); var mx := Game.max_level(id); var c := Game.upgrade_cost(id)
		var lv := ("Lv %d/%d" % [l, mx]) if mx > 1 else ("OWNED" if l > 0 else "")
		if Game.is_infinite(id): lv = "Lv %d (∞)  cap %d" % [l, Game.max_factories(Game.PLAYER)] if id == "max_factories" else "Lv %d (∞)" % l
		buttons[id].text = "%s %s\n%s%s" % [u.name, lv, u.desc, ("" if c < 0 else "  [%d pts]" % c)]
		buttons[id].disabled = c < 0 or Game.tech < c

func _draw() -> void:
	draw_rect(Rect2(-2000, -2000, 6000, 6000), Color(0.05, 0.03, 0.1))
