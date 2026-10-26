shader_type canvas_item;
// Rotating lit sphere from an equirectangular texture, with clouds, atmosphere rim/glow and optional rings.
uniform sampler2D surf : repeat_enable, filter_linear;
uniform sampler2D clouds : repeat_enable, filter_linear;
uniform float sphere_r = 0.8;
uniform float speed = 0.01;
uniform float offset = 0.0;
uniform float cloud_amt = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 atmo : source_color = vec4(0.5, 0.7, 1.0, 0.6);
uniform bool rings = false;
uniform vec4 owner_col : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 ring_col : source_color = vec4(0.85, 0.75, 0.6, 0.8);

vec4 ring_at(vec2 p) {
	vec2 q = vec2(p.x, p.y / 0.3);
	float rr = length(q);
	float m = smoothstep(1.3, 1.36, rr) * (1.0 - smoothstep(1.9, 1.96, rr));
	float bands = 0.65 + 0.35 * sin(rr * 40.0);
	return vec4(ring_col.rgb * bands, m * ring_col.a);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	vec2 p = c / sphere_r;
	float r = length(p);
	vec4 ring = rings ? ring_at(p) : vec4(0.0);
	vec4 outc = vec4(0.0);
	if (r < 1.0) {
		float z = sqrt(1.0 - r * r);
		float lon = atan(p.x, z) / 6.2831853 + TIME * speed + offset;
		float lat = asin(clamp(p.y, -1.0, 1.0)) / 3.14159265 + 0.5;
		vec3 col = texture(surf, vec2(lon * 0.5, lat)).rgb * tint.rgb;
		if (cloud_amt > 0.0) {
			float cl = texture(clouds, vec2(lon * 0.5 + TIME * speed * 0.6, lat)).a * cloud_amt;
			col = mix(col, vec3(1.0), cl);
		}
		float lum = dot(col, vec3(0.3, 0.59, 0.11));
		col = mix(col, owner_col.rgb * (0.3 + 0.9 * lum), owner_col.a);
		vec3 n = vec3(p.x, p.y, z);
		float light = clamp(dot(n, normalize(vec3(-0.55, -0.45, 0.7))), 0.0, 1.0);
		col *= 0.12 + 1.0 * light;
		col += atmo.rgb * pow(1.0 - z, 2.5) * atmo.a * (0.4 + light);
		col += owner_col.rgb * pow(1.0 - z, 3.0) * owner_col.a * 2.2;
		float edge = smoothstep(1.0, 0.97, r);
		outc = vec4(col, edge);
		if (ring.a > 0.0 && p.y > 0.0) outc.rgb = mix(outc.rgb, ring.rgb * (0.4 + 0.6 * light), ring.a);
	} else {
		float g = (1.0 - smoothstep(1.0, 1.22, r)) * atmo.a * 0.55;
		outc = vec4(atmo.rgb, g);
		if (ring.a > 0.0) outc = mix(outc, vec4(ring.rgb * 0.8, 1.0), ring.a);
	}
	COLOR = outc;
}
