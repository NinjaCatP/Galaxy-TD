extends Node
## AudioManager autoload ("Audio"): SFX pool, looping music, volume settings saved in settings.cfg.

const SETTINGS := "user://settings.cfg"
var music_vol := 0.6
var sfx_vol := 0.8
var muted := false
var _music: AudioStreamPlayer
var _music_name := ""
var _pool: Array = []
var _cache := {}
var _last := {}
var played := 0  # count of sfx played (for tests)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var c := ConfigFile.new()
	if c.load(SETTINGS) == OK:
		music_vol = c.get_value("audio", "music", music_vol)
		sfx_vol = c.get_value("audio", "sfx", sfx_vol)
		muted = c.get_value("audio", "muted", muted)
	_music = AudioStreamPlayer.new(); add_child(_music)
	for i in 10:
		var p := AudioStreamPlayer.new(); add_child(p); _pool.append(p)
	get_tree().node_added.connect(_on_node_added)
	_apply()

func _on_node_added(n: Node) -> void:
	if n is BaseButton: n.pressed.connect(func(): sfx("tap"))

func _stream(name: String) -> AudioStream:
	if not _cache.has(name):
		var path := "res://audio/%s.ogg" % name
		_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return _cache[name]

func sfx(name: String, min_gap := 0.05) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last.get(name, -10.0) < min_gap: return
	_last[name] = now
	var s := _stream(name)
	if s == null: return
	played += 1
	if muted or sfx_vol <= 0.0: return
	for p in _pool:
		if not p.playing:
			p.stream = s; p.volume_db = linear_to_db(sfx_vol); p.play(); return

func music(name: String) -> void:
	if name == _music_name: return
	_music_name = name
	var s = _stream(name)
	if s == null: return
	s.loop = true
	_music.stream = s; _apply(); _music.play()

func _apply() -> void:
	_music.volume_db = linear_to_db(max(0.0001, music_vol))
	_music.stream_paused = muted

func set_volumes(m: float, s: float, mute: bool) -> void:
	music_vol = m; sfx_vol = s; muted = mute; _apply()
	var c := ConfigFile.new(); c.load(SETTINGS)
	c.set_value("audio", "music", m); c.set_value("audio", "sfx", s); c.set_value("audio", "muted", mute)
	c.save(SETTINGS)

## Adds big touch-friendly Music / SFX sliders and a Mute toggle to `parent` at `pos`.
func make_controls(parent: Node, pos: Vector2) -> void:
	var rows := [["Music", music_vol], ["SFX", sfx_vol]]
	var sliders := []
	for i in rows.size():
		var l := Label.new(); l.text = rows[i][0]; l.position = pos + Vector2(0, i * 80 + 10)
		l.add_theme_font_size_override("font_size", 30); parent.add_child(l)
		var sl := HSlider.new(); sl.min_value = 0; sl.max_value = 1; sl.step = 0.05; sl.value = rows[i][1]
		sl.position = pos + Vector2(120, i * 80); sl.size = Vector2(360, 60)
		sl.scale = Vector2(1, 1)
		sl.add_theme_constant_override("grabber_offset", 0)
		parent.add_child(sl); sliders.append(sl)
	var m := CheckButton.new(); m.text = "Mute"; m.button_pressed = muted
	m.position = pos + Vector2(0, 160); m.add_theme_font_size_override("font_size", 30); parent.add_child(m)
	var upd := func(_v = null): set_volumes(sliders[0].value, sliders[1].value, m.button_pressed)
	sliders[0].value_changed.connect(upd); sliders[1].value_changed.connect(upd); m.toggled.connect(upd)
