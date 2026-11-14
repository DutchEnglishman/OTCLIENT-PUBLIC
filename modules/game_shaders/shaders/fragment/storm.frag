// A snowstorm over the finished map (registered as 'Map - Storm', shaders.lua;
// sent by the server's regional weather, OTSERV data/world_events/, on extended
// opcode 76):
//   u_WalkOffset  where the camera sits, in fractions of the map rect
//   u_MapSize     the framebuffer's size in pixels
//
// A sideways gale: snow flying almost flat across the screen in long fast streaks
// at three depths, white banks of blown snow racing through, and the map a shade
// colder and greyer. Chosen side by side in a browser preview against a diagonal
// blizzard and two calm snowfalls; the calm ones read as "twinkling down", not as
// a storm. Built like wind.frag's litter: each flake is smeared along its motion in
// wind space, and the two downwind neighbours are checked so a streak is never cut
// at a cell seam.
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

// Screen pixels, y DOWN: blowing right and a little down.
const vec2 WIND_DIR = vec2(0.9840, 0.1771);
const float CELL = 70.0;

const vec3 SNOW_FAR = vec3(0.92, 0.95, 1.00);
const vec3 SNOW_MID = vec3(0.97, 0.98, 1.00);
const vec3 SNOW_NEAR = vec3(1.00, 1.00, 1.00);
const vec3 WHITEOUT = vec3(0.90, 0.93, 0.98);

float hash11(float n) { return fract(sin(n * 78.233) * 43758.5453123); }
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
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}

// One depth of driven snow. w is wind space (x downwind, y across); scale > 1 is
// further away. stretch < 1 smears the flake along the wind.
float stormLayer(vec2 w, float scale, float speedPx, float seed, float density, float radius, float stretch)
{
	float k = scale / CELL;
	vec2 uv = w * k;
	uv.x -= u_Time * speedPx * k;
	uv.y += sin(uv.x * 0.9 + seed * 7.0) * 0.08;
	vec2 id = floor(uv), f = fract(uv);

	float acc = 0.0;
	for (int i = -1; i <= 1; i++) {
		vec2 o = vec2(float(i), 0.0);
		float h = hash21(id + o + seed);
		if (h > density) continue;
		vec2 c = o + vec2(hash11(h + seed), 0.15 + 0.7 * hash11(h + seed + 3.7));
		vec2 d = f - c;
		d.x *= stretch;
		acc += (1.0 - smoothstep(radius * 0.4, radius, length(d))) * (0.6 + 0.4 * hash11(h + seed + 9.1));
	}
	return min(acc, 1.0);
}

// Blowing snow: soft white banks racing downwind.
float whiteout(vec2 w)
{
	vec2 q = vec2((w.x - u_Time * 520.0) / 380.0, w.y / 170.0);
	return smoothstep(0.35, 0.85, fbm(q));
}

void main(void)
{
	// y down, and carried with the camera so the snow blows across the world
	// rather than across the screen.
	vec2 p = vec2(v_TexCoord.x, 1.0 - v_TexCoord.y) * u_MapSize
	       + vec2(u_WalkOffset.x, -u_WalkOffset.y) * u_MapSize;
	vec2 w = vec2(dot(p, WIND_DIR), dot(p, vec2(-WIND_DIR.y, WIND_DIR.x)));

	float near = stormLayer(w, 0.55, 1150.0, 0.0, 0.50, 0.048, 0.16);
	float mid = stormLayer(w, 0.85, 900.0, 4.3, 0.50, 0.042, 0.20);
	float far = stormLayer(w, 1.30, 660.0, 8.9, 0.50, 0.038, 0.26);

	vec3 base = texture2D(u_Tex0, v_TexCoord).rgb;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(base, vec3(lum), 0.25) * vec3(0.93, 0.97, 1.03) + vec3(0.025, 0.03, 0.045);
	col = mix(col, WHITEOUT, 0.08 + 0.30 * whiteout(w));

	// Far first, so a near streak passes in front of a far one.
	col = mix(col, SNOW_FAR, far * 0.50);
	col = mix(col, SNOW_MID, mid * 0.70);
	col = mix(col, SNOW_NEAR, near * 0.85);

	gl_FragColor = vec4(mix(base, col, atmosphereFade()), 1.0);
}
