extends Node2D
## Premium main menu: parallax nebula/stars, rotating planets, drifting mothership, glowing logo.

const NEBULA := preload("res://art/nebula.jpg")
const PlanetView := preload("res://scripts/planet_view.gd")
const Galaxy := preload("res://scripts/galaxy.gd")
var t := 0.0
var stars: PackedVector3Array = PackedVector3Array()   # x, y, depth
var fade: ColorRect
var root: Control
var _neb_flip: ImageTexture

func _ready() -> void:
	var im := NEBULA.get_image(); im.flip_x(); _neb_flip = ImageTexture.create_from_image(im)
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	for i in 180: stars.append(Vector3(rng.randf() * 1560, rng.randf() * 720, rng.randf_range(0.2, 1.0)))
	for d in [[Vector2(1350, 560), 150.0, 9001, "gas"], [Vector2(170, 600), 90.0, 4242, "terran"], [Vector2(1180, 170), 46.0, 77, "lava"]]:
		var v := PlanetView.new(); v.position = d[0]; add_child(v); v.setup({"seed": d[2], "ptype": d[3]}, d[1])
	var front := Node2D.new(); front.z_index = 3; add_child(front); front.draw.connect(_draw_front.bind(front))
	var ui := CanvasLayer.new(); add_child(ui)
	root = Control.new(); root.size = Vector2(1560, 720); root.mouse_filter = Control.MOUSE_FILTER_IGNORE; ui.add_child(root)
	root.add_child(_lbl("Conquer the galaxy. Every invasion is a tower-defense battle.", Vector2(0, 168), 26, Color(0.75, 0.85, 1), 1560))
	if Game.result_msg != "":
		root.add_child(_lbl(Game.result_msg, Vector2(0, 205), 34, Color(1, 0.9, 0.5), 1560))
	Game.in_game = false
	Audio.music("music_galaxy")
	var snd_panel := ColorRect.new(); snd_panel.color = Color(0, 0, 0, 0.85); snd_panel.size = Vector2(1560, 720); snd_panel.visible = false
	var sb := Game.make_button("Sound", Vector2(1340, 20), Vector2(200, 80)); root.add_child(sb)
	Game.style_button(sb, Color(0.2, 0.25, 0.4))
	sb.pressed.connect(func(): snd_panel.visible = true)
	if Game.has_save():
		var sg := Game.save_galaxy()
		var c := Game.make_button("CONTINUE\nGalaxy %d  (+%d%%)" % [sg, int(round((pow(1.01, sg - 1) - 1.0) * 100))], Vector2(570, 250), Vector2(420, 130))
		c.add_theme_font_size_override("font_size", 34)
		Game.style_button(c, Color(0.15, 0.5, 0.3), "ship")
		c.pressed.connect(func():
			var s := Game.load_game()
			if s != "": _go("res://scenes/%s.tscn" % s))
		root.add_child(c)
	root.add_child(_lbl("Difficulty", Vector2(160, 408), 30, Color(0.8, 0.9, 1)))
	root.add_child(_lbl("Best galaxy reached: %d" % Game.best_galaxy, Vector2(1040, 408), 28, Color(1, 0.85, 0.45)))
	var dbtns := {}
	var x := 160
	var dcol := {"Easy": Color(0.2, 0.5, 0.3), "Normal": Color(0.2, 0.4, 0.7), "Hard": Color(0.6, 0.4, 0.1), "Brutal": Color(0.65, 0.15, 0.2)}
	for d in Game.Difficulty.ORDER:
		var db := Game.make_button(d, Vector2(x, 450), Vector2(260, 100))
		db.toggle_mode = true; db.button_pressed = d == Game.difficulty
		_style_toggle(db, dcol.get(d, Color(0.3, 0.3, 0.5)))
		db.pressed.connect(func():
			Game.set_difficulty(d)
			for k in dbtns: dbtns[k].button_pressed = k == d)
		dbtns[d] = db; root.add_child(db); x += 280
	var b := Game.make_button("New Game", Vector2(450, 590), Vector2(320, 100))
	Game.style_button(b, Color(0.25, 0.4, 0.85), "factory")
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Start a new game?\nThis overwrites your saved game."
	confirm.ok_button_text = "Start New"; confirm.cancel_button_text = "Cancel"
	confirm.min_size = Vector2i(700, 300)
	confirm.add_theme_font_size_override("font_size", 34)
	confirm.get_label().add_theme_font_size_override("font_size", 34)
	confirm.get_ok_button().add_theme_font_size_override("font_size", 34)
	confirm.get_cancel_button().add_theme_font_size_override("font_size", 34)
	confirm.get_ok_button().custom_minimum_size = Vector2(220, 90)
	confirm.get_cancel_button().custom_minimum_size = Vector2(220, 90)
	confirm.confirmed.connect(_start_new)
	ui.add_child(confirm)
	b.pressed.connect(func():
		if Game.has_save(): confirm.popup_centered()
		else: _start_new())
	root.add_child(b)
	var q := Game.make_button("Quit", Vector2(800, 590), Vector2(320, 100))
	Game.style_button(q, Color(0.3, 0.3, 0.38), "back")
	q.pressed.connect(func(): get_tree().quit())
	root.add_child(q)
	ui.add_child(snd_panel)
	snd_panel.add_child(Game.make_label("SOUND", Vector2(700, 150), 50))
	Audio.make_controls(snd_panel, Vector2(540, 260))
	var close := Game.make_button("Done", Vector2(640, 520), Vector2(280, 90)); snd_panel.add_child(close)
	Game.style_button(close, Color(0.25, 0.4, 0.85))
	close.pressed.connect(func(): snd_panel.visible = false)
	# fade-in
	fade = ColorRect.new(); fade.color = Color.BLACK; fade.size = Vector2(1560, 720); fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := CanvasLayer.new(); top.layer = 20; add_child(top); top.add_child(fade)
	root.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(fade, "color:a", 0.0, 0.8); tw.tween_property(root, "modulate:a", 1.0, 1.0).set_delay(0.2)

func _lbl(text: String, pos: Vector2, fs: int, col := Color.WHITE, w := 0.0) -> Label:
	var l := Game.make_label(text, pos, fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 6); l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	if w > 0: l.size.x = w; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _style_toggle(b: Button, col: Color) -> void:
	Game.style_button(b, col.darkened(0.45))
	var on := StyleBoxFlat.new(); on.bg_color = col; on.set_corner_radius_all(14); on.set_border_width_all(3)
	on.border_color = Color(1, 1, 1, 0.9); on.shadow_color = Color(col.lightened(0.3), 0.6); on.shadow_size = 10
	b.add_theme_stylebox_override("pressed", on); b.add_theme_stylebox_override("hover_pressed", on)

func _go(path: String) -> void:
	var tw := create_tween(); tw.tween_property(fade, "color:a", 1.0, 0.3)
	tw.tween_callback(func(): get_tree().change_scene_to_file(path))

func _start_new() -> void:
	Game.new_game()
	Game.save_game()
	_go("res://scenes/galaxy.tscn")

func _process(delta: float) -> void:
	t += delta
	queue_redraw()
	for c in get_children(): if c is Node2D and c.z_index == 3: c.queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-400, -400, 2400, 1600), Color(0.01, 0.01, 0.04))
	var ox := fmod(t * 6.0, 3120.0)
	for k in 3:   # alternate mirrored tiles so the scrolling nebula has no seam
		var x0 := k * 1560.0 - ox
		if k % 2 == 0: draw_texture_rect(NEBULA, Rect2(x0, 0, 1560, 720), false)
		else: draw_texture_rect(_neb_flip, Rect2(x0, 0, 1560, 720), false)
	for s in stars:
		var x := fposmod(s.x - t * 25.0 * s.z, 1560.0)
		draw_circle(Vector2(x, s.y), 0.6 + 1.6 * s.z, Color(1, 1, 1, 0.3 + 0.6 * s.z * (0.7 + 0.3 * sin(t * 3 + s.x))))

func _draw_front(ci: Node2D) -> void:
	# mothership drifting across behind the menu
	var mx := fposmod(t * 40.0, 2400.0) - 400.0
	Galaxy.draw_mother(ci, Vector2(mx, 330 + sin(t * 0.4) * 20), 1.0, t)
	_draw_logo(ci)

func _draw_logo(ci: Node2D) -> void:
	var font := ThemeDB.fallback_font
	var text := "GALAXY  TD"
	var fs := 108
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(780 - w / 2, 138)
	for g in [28, 18, 10]:   # glow
		ci.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, g, Color(0.35, 0.6, 1.0, 0.12))
	ci.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.05, 0.08, 0.25))
	var shine := fmod(t * 0.35, 1.6) - 0.3
	var x := base.x
	for i in text.length():
		var ch := text[i]
		var f := (x - base.x) / w
		var col := Color(0.55, 0.85, 1.0).lerp(Color(1.0, 0.75, 0.35), f)   # gradient
		col = col.lerp(Color.WHITE, clamp(1.0 - abs(f - shine) * 7.0, 0.0, 1.0) * 0.85)  # moving shine
		ci.draw_char(font, Vector2(x, base.y), ch, fs, col)
		x += font.get_char_size(ch.unicode_at(0), fs).x
	ci.draw_line(Vector2(780 - w / 2, 156), Vector2(780 + w / 2, 156), Color(0.5, 0.8, 1, 0.5), 3)
