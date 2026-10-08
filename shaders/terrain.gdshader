shader_type canvas_item;
render_mode unshaded;

// The material grid: one R8 texel per cell, holding the material id, and a
// second one holding each cell's extra byte (how long it has left to burn, or
// how long a short-lived gas has left). Colours come from the palette materials.gd
// builds out of data/materials.json; fog and warnings happen here.
uniform sampler2DArray grid_tex : filter_nearest, repeat_disable;   // cells, a 256 x 256 tile a layer
uniform sampler2DArray aux_tex : filter_nearest, repeat_disable;    // each cell's extra byte, tiled the same
uniform sampler2D pal_tex : filter_nearest, repeat_disable;    // 256 x 4, one column per material
uniform sampler2D known_tex : filter_linear, repeat_disable;   // a byte per 4x4 block: explored areas
uniform sampler2D heat_tex : filter_linear, repeat_disable;    // per block: the hottest cell, (degrees + 60) / 6 (A1)
uniform sampler2D sense_tex : filter_linear, repeat_disable;   // per block: within sensing range of a Drill
uniform sampler2D vis_tex : filter_linear, repeat_disable;     // per block: shows live (lit and explored)
uniform sampler2D light_tex : filter_linear, repeat_disable;   // per block: brightness
uniform float use_light = 0.0;                                  // 0: no per-cell light (GDScript sim)
uniform sampler2DArray mem_tex : filter_nearest, repeat_disable;    // the map as last seen, tiled the same
uniform float time_s = 0.0;
uniform float ground_y = 200.0;
uniform ivec2 map_size = ivec2(1024, 5120);
uniform int tiles_across = 3;

// Where a cell lives in the tiled arrays.
ivec3 tile_at(ivec2 c) {
	c = clamp(c, ivec2(0), map_size - 1);
	return ivec3(c.x & 255, c.y & 255, (c.y >> 8) * tiles_across + (c.x >> 8));
}
uniform float reveal_all = 0.0;
uniform float temp_view = 0.0;                                  // 1: paint the temperature over the map (the lab bench, F6)

// Degrees of a heat texel.
float degrees_of(float t) {
	return t * 255.0 * 6.0 - 60.0;
}

// Cold blue through red and yellow to white, for the temperature view.
vec3 temp_ramp(float deg) {
	vec3 c = mix(vec3(0.05, 0.08, 0.35), vec3(0.1, 0.45, 0.85), smoothstep(-40.0, 20.0, deg));
	c = mix(c, vec3(0.45, 0.2, 0.55), smoothstep(20.0, 120.0, deg));
	c = mix(c, vec3(0.85, 0.15, 0.1), smoothstep(120.0, 450.0, deg));
	c = mix(c, vec3(1.0, 0.65, 0.15), smoothstep(450.0, 850.0, deg));
	c = mix(c, vec3(1.0, 0.97, 0.8), smoothstep(850.0, 1300.0, deg));
	return c;
}

// Depth colours were drawn for the 1024-row v2 map; rows scale to it.
float v2_depth(float y) {
	return y * 1024.0 / float(map_size.y);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise, for haze.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

int mat_at(ivec2 c) {
	return int(texelFetch(grid_tex, tile_at(c), 0).r * 255.0 + 0.5);
}

float aux_at(ivec2 c) {
	return floor(texelFetch(aux_tex, tile_at(c), 0).r * 255.0 + 0.5);
}

int mem_at(ivec2 c) {
	return int(texelFetch(mem_tex, tile_at(c), 0).r * 255.0 + 0.5);
}

vec3 sky(float y, vec2 cf) {
	vec3 top = vec3(0.08, 0.09, 0.19);
	vec3 horizon = vec3(0.33, 0.30, 0.47);
	vec3 c = mix(top, horizon, smoothstep(0.0, ground_y, y));
	float star = step(0.994, hash12(cf * 1.7 + 3.1));
	float tw = 0.6 + 0.4 * sin(time_s * 2.0 + hash12(cf) * 40.0);
	return c + vec3(0.8, 0.8, 0.9) * star * tw * (1.0 - smoothstep(0.0, ground_y * 0.8, y));
}

vec3 cave(float y) {
	y = v2_depth(y);
	return mix(vec3(0.055, 0.055, 0.075), vec3(0.07, 0.04, 0.04), smoothstep(600.0, 900.0, y));
}

vec3 stone_col(float y) {
	vec3 a = vec3(0.46, 0.45, 0.47);
	vec3 b = vec3(0.37, 0.38, 0.44);
	vec3 c = vec3(0.36, 0.27, 0.26);
	y = v2_depth(y);
	if (y < 320.0) return a;
	if (y < 600.0) return mix(a, b, smoothstep(300.0, 600.0, y));
	return mix(b, c, smoothstep(600.0, 880.0, y));
}

vec3 unknown_col(float y) {
	y = v2_depth(y);
	if (y < 300.0) return vec3(0.20, 0.145, 0.10);
	if (y < 600.0) return vec3(0.17, 0.17, 0.19);
	if (y < 900.0) return vec3(0.18, 0.13, 0.13);
	return vec3(0.09, 0.08, 0.10);
}

// Palette flags (materials.gd).
const int F_ROCK = 1;
const int F_BURNS = 2;
const int F_GLINTS = 4;
const int F_SENSED = 8;

int flags_of(int id) {
	return int(texelFetch(pal_tex, ivec2(id, 3), 0).r * 255.0 + 0.5);
}

vec3 accent_of(int id) {
	return texelFetch(pal_tex, ivec2(id, 2), 0).rgb;
}

// Colour of one material; `a` is the cell's extra byte and `t` the clock (both 0
// for remembered cells, which don't move or burn).
vec3 mat_color(int id, float a, vec2 cf, float y, float h, float j, vec3 bg, float t, out bool rock) {
	vec4 p0 = texelFetch(pal_tex, ivec2(id, 0), 0);
	vec4 p1 = texelFetch(pal_tex, ivec2(id, 1), 0);
	vec4 p2 = texelFetch(pal_tex, ivec2(id, 2), 0);
	vec4 p3 = texelFetch(pal_tex, ivec2(id, 3), 0);
	int style = int(p0.a * 255.0 + 0.5);
	int flags = int(p3.r * 255.0 + 0.5);
	rock = (flags & F_ROCK) != 0;
	float grain = p2.a;
	float mixv = p1.a;
	vec3 c1 = p0.rgb;
	vec3 c2 = p1.rgb;
	vec3 c;
	if (style == 0) {                // empty
		c = bg;
	} else if (style == 1) {         // flat
		c = c1;
	} else if (style == 2) {         // rock: grain
		c = c1 * (1.0 + j * grain);
	} else if (style == 3) {         // strata: stone tinted by depth
		c = stone_col(y) * (1.0 + j * grain);
	} else if (style == 4) {         // speckle: flecks of color2
		c = mix(c1, c2, step(mixv, h)) * (1.0 + j * grain);
	} else if (style == 5) {         // sparkle: now and then a cell flashes color2
		c = c1 * (1.0 + j * grain);
		float tw = hash12(cf + floor(t * 3.0 + h * 5.0));
		c = mix(c, c2, step(0.97, tw));
	} else if (style == 6) {         // water: slow ripples
		float s = sin(t * 2.6 + cf.x * 0.55 + cf.y * 0.8) * 0.5 + 0.5;
		c = mix(c1, c2, s * 0.6 + h * 0.2);
	} else if (style == 7) {         // lava: churning
		float f = sin(t * 2.2 + h * 6.28 + cf.y * 0.35) * 0.5 + 0.5;
		c = mix(c1, c2, f * 0.7 + h * 0.2);
	} else if (style == 8) {         // fade: see-through (steam's stages)
		c = mix(c1, bg, mixv + j * grain);
	} else if (style == 9) {         // smoke: a drifting haze that thins out as it dies
		float life = a / max(p3.g * 255.0, 1.0);
		float n = vnoise(cf * 0.18 + vec2(t * 0.25, -t * 0.6));
		float thick = mixv * smoothstep(0.0, 0.4, life) * (0.55 + 0.45 * n);
		c = mix(bg, mix(c1, c2, n), thick);
	} else {                         // fire: color young, color2 as it dies, flickering
		float life = a / max(p3.g * 255.0, 1.0);
		float fl = hash12(cf + floor(t * 14.0));
		c = mix(c2, c1, clamp(life * 1.2 + fl * 0.35 - 0.15, 0.0, 1.0));
		c = mix(bg, c, 0.92);
	}
	// Anything alight glows with flickering embers.
	if ((flags & F_BURNS) != 0 && a > 0.5) {
		float fl = hash12(cf + floor(t * 7.0 + h * 13.0));
		vec3 ember = mix(vec3(0.80, 0.16, 0.03), vec3(1.0, 0.70, 0.22), fl);
		c = mix(c, ember, 0.45 + 0.4 * fl);
	}
	return c;
}

void fragment() {
	ivec2 cell = ivec2(floor(UV * vec2(map_size)));
	vec2 cf = vec2(cell);
	float y = cf.y;
	int id = mat_at(cell);
	float a = aux_at(cell);
	float h = hash12(cf);
	float j = h - 0.5;
	// Dips in the ground line show sky, not cave.
	vec3 bg = y < ground_y + 4.0 ? sky(y, cf) : cave(y);
	bool rock = false;
	vec3 col = mat_color(id, a, cf, y, h, j, bg, time_s, rock);

	// Light: a live cell is as bright as the light on it, and where the light
	// runs out it shows as last seen, dimmed and still, like everywhere unlit.
	float v = max(texture(vis_tex, UV).r, reveal_all);
	float lt = 1.0;
	if (use_light > 0.5 && reveal_all < 0.5 && y >= ground_y) {
		lt = texture(light_tex, UV).r;
		col *= mix(0.5, 1.0, lt);
		// Lit open space picks up a faint warm haze, so pools of light read as light.
		if (id == 0) {
			col += vec3(0.11, 0.085, 0.055) * lt * lt;
		}
		v *= smoothstep(0.0, 0.12, lt);
	}
	if (v < 0.99 && y >= ground_y) {
		bool mrock = false;
		vec3 mc = mat_color(mem_at(cell), 0.0, cf, y, h, j, bg, 0.0, mrock);
		float lum = dot(mc, vec3(0.3, 0.59, 0.11));
		mc = mix(vec3(lum), mc, 0.55) * 0.5;
		col = mix(mc, col, smoothstep(0.35, 0.65, v));
		if (v < 0.5) {
			rock = mrock;
		}
	}

	// Fog (A1): what has never been seen is black. Seen ground shows live while it's
	// lit, and as last seen, dimmed, while it isn't (above).
	float k = max(texture(known_tex, UV).r, reveal_all);
	float deg = degrees_of(texture(heat_tex, UV).r);
	if (y >= ground_y) {
		// Hot rock glows: faintly warm from about 300, red by lava's heat.
		if (rock) {
			float glow = smoothstep(300.0, 1100.0, deg);
			float pulse = 0.75 + 0.25 * sin(time_s * 1.6 + cf.y * 0.05);
			col += vec3(0.55, 0.12, 0.02) * glow * pulse * 0.6;
		}
		col *= smoothstep(0.3, 0.7, k);
	}

	// The temperature view: the field painted over the map, per 4x4 block.
	if (temp_view > 0.5 && (k > 0.5 || y < ground_y)) {
		col = mix(col * 0.35, temp_ramp(deg), 0.75);
	}

	// Warning: hidden pockets within 16 cells of a Drill show as a faint outline.
	if (k < 0.5 && (flags_of(id) & F_SENSED) != 0 && texture(sense_tex, UV).r > 0.4) {
		bool edge = mat_at(cell + ivec2(1, 0)) != id || mat_at(cell - ivec2(1, 0)) != id
				|| mat_at(cell + ivec2(0, 1)) != id || mat_at(cell - ivec2(0, 1)) != id;
		if (edge) {
			col = mix(col, accent_of(id), 0.55);
		}
	}

	COLOR = vec4(col, 1.0);
}
