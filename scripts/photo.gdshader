shader_type canvas_item;
// "Photo" look for a screenshot of the pixel world: soft pixels, depth of field away from the
// companion, a little bloom, warm grading and a vignette. Draw on a TextureRect with linear filtering.

uniform vec2 focus = vec2(0.5, 0.55);   // the companion, in UV
uniform float px = 0.003;                // one world pixel in UV (x)
uniform float aspect = 1.333;

vec3 disc(sampler2D tex, vec2 uv, float r) {
	vec3 s = texture(tex, uv).rgb * 2.0;
	float n = 2.0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5236;
		float rr = r * (i % 2 == 0 ? 1.0 : 0.6);
		s += texture(tex, uv + vec2(cos(a), sin(a) * aspect) * rr).rgb;
		n += 1.0;
	}
	return s / n;
}

void fragment() {
	float d = length((UV - focus) * vec2(aspect, 1.0));
	float blur = mix(0.45, 2.6, smoothstep(0.12, 0.6, d));
	vec3 c = disc(TEXTURE, UV, blur * px);
	vec3 glow = disc(TEXTURE, UV, 5.0 * px);
	c += max(glow - 0.62, 0.0) * 0.9;                       // bloom on bright bits (lamps, sky, water)
	c *= vec3(1.05, 1.0, 0.93);                             // warm
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(l), c, 1.1);                               // a touch more colour
	c = mix(c, c * c * (3.0 - 2.0 * c), 0.35);              // gentle contrast curve
	c = c * 0.94 + 0.04;                                    // lifted blacks, like film
	c *= 1.0 - 0.38 * smoothstep(0.45, 1.0, d);             // vignette
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
