// Heavy rain over the finished map (registered as 'Map - Downpour', shaders.lua;
// sent by the server's regional weather, OTSERV data/world_events/, on extended
// opcode 76):
//   u_WalkOffset  where the camera sits, in fractions of the map rect
//   u_MapSize     the framebuffer's size in pixels
//
// Thin slanted streaks at three depths, the light duller and cooler, and small
// rings popping on the ground, each ring tied to a map tile so they stay put while
// the camera moves. Chosen in a browser preview over the same streaks without the
// splashes. The stock rain.frag ('Map - Rain') is left as it was for Ctrl+Y.
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

const vec3 RAIN_COLOR = vec3(0.80, 0.86, 0.95);
const vec3 SPLASH_COLOR = vec3(0.78, 0.86, 1.00);

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

// One depth of rain. Rain space: x across the fall, y along it (screen y down).
// The streak is held clear of its cell's edges, so no neighbour lookups.
float rainLayer(vec2 p, float scale, float speedPx, float seed, float density, float lenPx)
{
	vec2 dir = normalize(vec2(0.22, 1.0));
	vec2 r = vec2(dot(p, vec2(dir.y, -dir.x)), dot(p, dir));
	float cw = 22.0 / scale, cl = 120.0 / scale;
	r.y -= u_Time * speedPx;
	vec2 uv = vec2(r.x / cw, r.y / cl);
	vec2 id = floor(uv), f = fract(uv);
	float h = hash21(id + seed);
	if (h > density) return 0.0;
	float cx = 0.25 + 0.5 * fract(h * 317.0);
	float L = lenPx / cl * (0.6 + 0.4 * fract(h * 719.0));
	float W = 0.7 / cw;
	float dx = abs(f.x - cx), dy = f.y - 0.5;
	float m = (1.0 - smoothstep(W * 0.4, W * 1.4, dx)) * (1.0 - smoothstep(L * 0.55, L, abs(dy)));
	// Brighter at the leading end.
	m *= 0.45 + 0.55 * clamp(dy / L * 0.5 + 0.5, 0.0, 1.0);
	return m * (0.6 + 0.4 * fract(h * 1439.0));
}

// A ring on the ground: some tiles, each on its own clock, squashed to lie flat.
float splashes(vec2 p)
{
	vec2 t = floor(p / 32.0);
	vec2 tf = fract(p / 32.0) * 32.0;
	float h = hash21(t + 7.0);
	if (h > 0.45) return 0.0;
	float period = 1.4 + 1.6 * fract(h * 53.0);
	float age = fract(u_Time / period + h * 7.0) * period;
	float life = 0.38;
	if (age > life) return 0.0;
	vec2 c = vec2(6.0 + 20.0 * fract(h * 97.0), 6.0 + 20.0 * fract(h * 193.0));
	vec2 d = tf - c;
	d.y *= 2.0;
	float rad = age / life * 6.0;
	return (1.0 - smoothstep(0.0, 0.9, abs(length(d) - rad))) * (1.0 - age / life);
}

void main(void)
{
	// y down, and carried with the camera so the rain and the rings belong to the
	// world rather than the screen.
	vec2 p = vec2(v_TexCoord.x, 1.0 - v_TexCoord.y) * u_MapSize
	       + vec2(u_WalkOffset.x, -u_WalkOffset.y) * u_MapSize;

	float rain = rainLayer(p, 0.8, 1080.0, 0.0, 0.40, 40.0) * 0.65
	           + rainLayer(p, 1.0, 840.0, 4.3, 0.36, 30.0) * 0.50
	           + rainLayer(p, 1.5, 620.0, 8.9, 0.32, 20.0) * 0.30;

	vec3 base = texture2D(u_Tex0, v_TexCoord).rgb;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(base, vec3(lum), 0.20) * vec3(0.86, 0.90, 0.96);
	col += RAIN_COLOR * rain * 0.55;
	col += SPLASH_COLOR * splashes(p) * 0.40;

	gl_FragColor = vec4(mix(base, col, atmosphereFade()), 1.0);
}
