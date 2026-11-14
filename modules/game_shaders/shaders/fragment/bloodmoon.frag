// The Blood Moon over the finished map (registered as 'Map - Blood Moon', shaders.lua;
// sent by the server's moons, OTSERV data/world_events/moons_core.lua, on extended
// opcode 76 as "bloodmoon:<strength>"):
//   u_WalkOffset  where the camera sits, in fractions of the map rect
//   u_MapSize     the framebuffer's size in pixels
//
// fullmoon.frag's look in red: the colour drained toward blood red, highlights lifted,
// darker at the screen's edges, and soft red beams sweeping slowly across. Keep the
// two in step; only the three colours differ. Chosen in a browser preview.
uniform float u_Time;
uniform sampler2D u_Tex0;
uniform vec2 u_WalkOffset;
uniform vec2 u_MapSize;
uniform vec2 u_Anchor0;           // x: how far the atmosphere has rolled in, 0..1
varying vec2 v_TexCoord;

// The ramp shaders.lua runs on the way in and out, through UIMap:setShaderPoint.
// An anchor nobody has set reads -1 (mapview.cpp), and that means FULL strength.
float atmosphereFade()
{
	return u_Anchor0.x < 0.0 ? 1.0 : clamp(u_Anchor0.x, 0.0, 1.0);
}

const vec3 TINT = vec3(1.10, 0.50, 0.45);
const vec3 HIGHLIGHT = vec3(0.14, 0.04, 0.03);
const vec3 BEAM = vec3(0.95, 0.30, 0.25);

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

float vnoise(vec2 p)
{
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p)
{
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 17.0);
		a *= 0.5;
	}
	return s;
}

void main(void)
{
	vec2 uv = vec2(v_TexCoord.x, 1.0 - v_TexCoord.y);
	// Carried with the camera, so the beams lie on the world rather than the screen.
	vec2 p = uv * u_MapSize + vec2(u_WalkOffset.x, -u_WalkOffset.y) * u_MapSize;

	vec3 base = texture2D(u_Tex0, v_TexCoord).rgb;
	float l = dot(base, vec3(0.299, 0.587, 0.114));
	float edge = smoothstep(0.45, 0.95, length(uv - 0.5) * 1.4);

	vec3 col = mix(base, vec3(l), 0.55) * TINT * 0.85;
	col += HIGHLIGHT * smoothstep(0.45, 1.0, l);
	col *= 1.0 - 0.25 * edge;

	float beam = sin((p.x + p.y * 0.6) / 70.0 - u_Time * 0.25) * 0.5 + 0.5;
	beam = smoothstep(0.65, 1.0, beam + 0.25 * fbm(p / 180.0 + u_Time * 0.02));
	col += BEAM * beam * 0.14;

	gl_FragColor = vec4(mix(base, col, atmosphereFade()), 1.0);
}
