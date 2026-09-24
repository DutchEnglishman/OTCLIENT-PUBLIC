// Drifting ash over the finished map (registered as 'Map - Burn', shaders.lua;
// toggled by the server's /burn on extended opcode 76):
//   u_WalkOffset  where the camera sits, in fractions of the map rect
//   u_MapSize     the framebuffer's size in pixels
//
// Somewhere that has burned: the colour is washed out of everything, and specks of
// ash and the odd live ember drift LEFT TO RIGHT through the air, curling as they
// go. Meant to be quiet -- it should take a moment to notice.
//
// The curl is the whole point and it comes from ONE shared field, not from each
// speck wandering on a clock of its own: curlFlow is the curl of a scalar, so it
// is divergence-free and turns rather than pushing everything one way, and it is
// applied as a DOMAIN WARP -- the sampling point is bent, so every flake in a
// neighbourhood bends the same way and they swirl together. Per-flake wander was
// the first attempt and it read as random specks.
//
// A domain warp also costs one field evaluation per pixel for all three depths,
// where displacing each flake would need a 3x3 cell search per depth. Its price is
// that the local gradient squashes flakes a little; WARP_* are kept low enough to
// hold that near 25%, because at 50% they visibly stretched.
//
// Flakes are mixed INTO the scene rather than added to it, because ash reads
// darker than what is behind it -- the near layer is charcoal and only the far one
// is pale. Embers are the only thing here that adds light.
//
// The grade is CONSTANT. A drifting haze density was the obvious next thing and is
// deliberately absent: the wind shader had a travelling swell and it read as the
// whole screen pulsing every few seconds rather than as weather.
uniform float u_Time;
uniform sampler2D u_Tex0;
uniform vec2 u_WalkOffset;
uniform vec2 u_MapSize;
uniform vec2 u_Anchor0;            // x: how far the atmosphere has rolled in, 0..1
varying vec2 v_TexCoord;

// The ramp shaders.lua runs on the way in and out, through UIMap:setShaderPoint.
// An anchor nobody has set reads -1 (mapview.cpp), and that means FULL strength:
// picking this shader by hand in the Ctrl+Y window has no ramp driving it and
// should still show something.
float atmosphereFade()
{
	return u_Anchor0.x < 0.0 ? 1.0 : clamp(u_Anchor0.x, 0.0, 1.0);
}

const float CELL = 70.0;           // one ash cell at the middle depth, px
const float FLAKE_PX = 2.4;        // flake radius in SCREEN px, before the size roll
const float DENSITY = 0.28;        // share of cells carrying a flake
const float EMBER_SHARE = 0.07;    // share of flakes still hot

const float FLAKE_OPACITY = 0.34;
const float EMBER_OPACITY = 0.60;

// The wash: colour drains, everything pulls toward a warm grey, and the veil of
// ash lifts the blacks and flattens the contrast the way smoke in the air does.
const float DESATURATE = 0.38;
const float TINT = 0.09;
const float HAZE_LIFT = 0.022;
const float HAZE_CONTRAST = 0.95;
const vec3 ASH_TINT = vec3(0.55, 0.53, 0.51);

const vec3 ASH_NEAR = vec3(0.10, 0.09, 0.09);
const vec3 ASH_MID = vec3(0.34, 0.32, 0.31);
const vec3 ASH_FAR = vec3(0.62, 0.60, 0.58);
const vec3 EMBER_COLOR = vec3(1.00, 0.45, 0.12);

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

// The curl of sin(Ax + t) * cos(By - t), plus a smaller faster octave. Returns
// roughly -1.45..1.45 per component; the y factors are A/B, which is what keeps
// the two components in proportion after the differentiation.
vec2 curlFlow(vec2 w)
{
	float t = u_Time * 0.45;

	float a = w.x * 0.0085 + t;
	float b = w.y * 0.0105 - t * 0.8;
	vec2 v = vec2(-sin(a) * sin(b), -0.81 * cos(a) * cos(b));

	float c = w.x * 0.0150 - t * 1.6;
	float d = w.y * 0.0130 + t * 1.2;
	return v + vec2(-sin(c) * sin(d), -1.15 * cos(c) * cos(d)) * 0.28;
}

// One depth of drifting ash. Returns (flake coverage, ember coverage) so the
// caller can colour each depth itself. Every depth's flakes are the same size on
// screen -- FLAKE_PX is in pixels and converted here -- because depth carried by
// size put the far layer below a pixel, where it read as sensor noise.
vec2 ashLayer(vec2 p, vec2 flow, float scale, float speedPx, float sinkPx, float warpPx, float seed)
{
	float k = scale / CELL;                  // px -> cells at this depth
	vec2 q = p + flow * warpPx - vec2(u_Time * speedPx, u_Time * sinkPx);
	vec2 uv = q * k;

	vec2 id = floor(uv);
	vec2 f = fract(uv);

	float h = hash21(id + seed);
	if (h > DENSITY) return vec2(0.0);

	// Four rolls off the one hash: a second sin per cell buys nothing here.
	float r1 = fract(h * 317.0);
	float r2 = fract(h * 719.0);
	float r3 = fract(h * 1439.0);
	float r4 = fract(h * 2707.0);

	// The centre is held clear of the cell's edges by more than the widest a
	// flake reaches, which is what lets this skip neighbouring-cell lookups.
	vec2 c = vec2(0.5 + (r1 - 0.5) * 0.7, 0.5 + (r2 - 0.5) * 0.7);
	float m = 1.0 - smoothstep(0.0, FLAKE_PX * (0.7 + 0.6 * r3) * k, length(f - c));

	// Tumbling: a flake turning edge-on dims. Gentle -- a hard blink is one more
	// thing moving out of step with its neighbours.
	m *= 0.55 + 0.45 * abs(sin(u_Time * (1.1 + 1.6 * r2) + r3 * 6.2831));

	float ember = step(r4, EMBER_SHARE);
	return vec2(m * (1.0 - ember), m * ember);
}

void main(void)
{
	// y down, and carried with the camera so the ash drifts through the world
	// rather than across the screen.
	vec2 p = vec2(v_TexCoord.x, 1.0 - v_TexCoord.y) * u_MapSize
	       + vec2(u_WalkOffset.x, -u_WalkOffset.y) * u_MapSize;

	// One field for every depth: this is what makes them swirl together.
	vec2 flow = curlFlow(p);

	// Drifting right, sinking a little. Nearer air moves faster and curls wider.
	vec2 near = ashLayer(p, flow, 0.60, 46.0, 6.0, 22.0, 0.0);
	vec2 mid = ashLayer(p, flow, 0.90, 34.0, 4.0, 17.0, 4.3);
	vec2 far = ashLayer(p, flow, 1.30, 24.0, 3.0, 12.0, 8.9);

	vec3 base = texture2D(u_Tex0, v_TexCoord).rgb;
	vec3 col = base;

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), DESATURATE);
	col = mix(col, ASH_TINT, TINT);
	col = col * HAZE_CONTRAST + HAZE_LIFT;

	// Far first, so a near flake passes in front of a far one.
	col = mix(col, ASH_FAR, far.x * FLAKE_OPACITY * 0.55);
	col = mix(col, ASH_MID, mid.x * FLAKE_OPACITY * 0.85);
	col = mix(col, ASH_NEAR, near.x * FLAKE_OPACITY);
	col += EMBER_COLOR * min(1.0, near.y + mid.y + far.y) * EMBER_OPACITY;

	// The wash and the ash roll in together, so it settles over the map rather
	// than snapping on.
	gl_FragColor = vec4(mix(base, col, atmosphereFade()), 1.0);
}
