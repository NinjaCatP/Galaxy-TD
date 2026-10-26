extends Sprite2D
## Shader-rendered planet. setup(planet_dict, radius_px)

const SHADER := preload("res://shaders/planet.gdshader")
const TYPES := {
	"rocky":  {"tex": "rocky",  "atmo": Color(0.8, 0.7, 0.6, 0.35), "clouds": 0.0},
	"terran": {"tex": "terran", "atmo": Color(0.45, 0.7, 1.0, 0.8),  "clouds": 0.7},
	"gas":    {"tex": "gas",    "atmo": Color(1.0, 0.8, 0.55, 0.55), "clouds": 0.0},
	"ice":    {"tex": "ice",    "atmo": Color(0.7, 0.9, 1.0, 0.6),   "clouds": 0.2},
	"lava":   {"tex": "lava",   "atmo": Color(1.0, 0.4, 0.15, 0.7),  "clouds": 0.0},
}
static var _white: ImageTexture
static var _cache := {}

static func tex(name: String) -> Texture2D:
	if not _cache.has(name): _cache[name] = load("res://art/planets/%s.png" % name)
	return _cache[name]

func setup(p: Dictionary, radius: float) -> void:
	if _white == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8); img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	texture = _white
	var t: String = p.get("ptype", "rocky")
	var d: Dictionary = TYPES.get(t, TYPES.rocky)
	var seed: int = int(p.get("seed", 0))
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var has_rings: bool = t == "gas" and rng.randf() < 0.6
	var sphere_r := 0.48 if has_rings else 0.8
	var m := ShaderMaterial.new(); m.shader = SHADER
	m.set_shader_parameter("surf", tex(d.tex))
	m.set_shader_parameter("clouds", tex("clouds"))
	m.set_shader_parameter("cloud_amt", d.clouds)
	m.set_shader_parameter("atmo", d.atmo)
	m.set_shader_parameter("sphere_r", sphere_r)
	m.set_shader_parameter("rings", has_rings)
	m.set_shader_parameter("speed", rng.randf_range(0.006, 0.02) * (1 if rng.randf() < 0.8 else -1))
	m.set_shader_parameter("offset", rng.randf())
	m.set_shader_parameter("tint", Color.from_hsv(rng.randf(), rng.randf_range(0.0, 0.25), 1.0).lerp(Color.WHITE, 0.4))
	material = m
	var quad := 2.0 * radius / sphere_r
	scale = Vector2.ONE * quad / 8.0

var _owner := -99
func set_owner_tint(o: int) -> void:
	if o == _owner: return
	_owner = o
	var c: Color = Game.COLORS[o]
	(material as ShaderMaterial).set_shader_parameter("owner_col", Color(c, 0.0 if o == Game.NEUTRAL else 0.28))
