// Wind over the finished map (registered as 'Map - Wind', shaders.lua; toggled by
// the server's /wind on extended opcode 76):
//   u_WalkOffset  where the camera sits, in fractions of the map rect
//   u_MapSize     the framebuffer's size in pixels
//
// Air is invisible, so what reads as wind is what it carries. Three layers of dust
// and leaf litter stream downwind at their own depths, fluttering across the flow,
// with long faint wisps of moving air passing between them.
//
// The wind is STEADY: it does not gust, and it does not touch the drawn map. An
// earlier version swelled on a travelling gust band and rocked the world a pixel
// with it; both are gone, for reading as a pulse over the whole screen rather than
// as weather. Everything here is additive on top of u_Tex0, so the map underneath
// is never resampled and pixel art stays exactly as sharp as it was.
uniform float u_Time;
uniform sampler2D u_Tex0;
uniform vec2 u_WalkOffset;
uniform vec2 u_MapSize;
uniform vec2 u_Anchor0;           // x: how far the atmosphere has rolled in, 0..1
varying vec2 v_TexCoord;

// The ramp shaders.lua runs on the way in and out, through UIMap:setShaderPoint.
// An anchor nobody has set reads -1 (mapview.cpp), and that means FULL strength:
// picking this shader by hand in the Ctrl+Y window has no ramp driving it and
// should still show something.
float atmosphereFade()
{
	return u_Anchor0.x < 0.0 ? 1.0 : clamp(u_Anchor0.x, 0.0, 1.0);
}

// Screen pixels, y DOWN (see the p below): blowing right and slightly down.
const vec2 WIND_DIR = vec2(0.9766, 0.2149);

const float CELL = 85.0;          // one litter cell at the middle layer, px
const float MOTE_RADIUS = 0.030;  // in cells
const float MOTE_STRETCH = 0.18;  // d.x scale: smaller is a longer streak
const float DENSITY = 0.50;       // share of cells carrying a mote
const float FLUTTER = 0.06;       // across-wind wobble, in cells

const float MOTE_OPACITY = 0.32;
const float WISP_OPACITY = 0.14;

const vec3 MOTE_COLOR = vec3(1.00, 0.97, 0.88);
const vec3 WISP_COLOR = vec3(0.86, 0.92, 1.00);

float hash11(float n) { return fract(sin(n * 78.233) * 43758.5453123); }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

// One depth of litter. scale > 1 is further away: smaller cells, smaller motes.
// w is wind space (x downwind, y across).
float moteLayer(vec2 w, float scale, float speedPx, float seed)
{
	float k = scale / CELL;                  // px -> cells at this depth
	vec2 uv = w * k;
	uv.x += u_Time * speedPx * k;
	uv.y += sin(uv.x * 1.3 + seed * 9.0) * FLUTTER;

	vec2 id = floor(uv);
	vec2 f = fract(uv);

	// A streak reaches MOTE_RADIUS / MOTE_STRETCH cells downwind, under one cell,
	// so the two neighbours in x are enough to keep it from being cut at the seam.
	float acc = 0.0;
	for (int i = -1; i <= 1; i++) {
		vec2 o = vec2(float(i), 0.0);
		float h = hash21(id + o + seed);
		if (h > DENSITY) continue;
		// c.y stays clear of the cell's own edges for the same reason.
		vec2 c = o + vec2(hash11(h + seed), 0.1 + 0.8 * hash11(h + seed + 3.7));
		vec2 d = f - c;
		d.x *= MOTE_STRETCH;
		acc += (1.0 - smoothstep(0.0, MOTE_RADIUS, length(d))) * (0.5 + 0.5 * hash11(h + seed + 9.1));
	}
	return acc;
}

// Long faint lines of moving air. Each row of the screen runs at its own speed and
// only a lit arc of it shows, so they read as passing streaks rather than rails.
float wisps(vec2 w)
{
	// A slow bend across the flow: dead straight, they read as ruled lines.
	w.y += sin(w.x / 420.0 + u_Time * 0.4) * 9.0;

	float row = w.y / 34.0;
	float h = hash11(floor(row));
	if (h > 0.5) return 0.0;

	float u = w.x + h * 1200.0 + u_Time * (260.0 + h * 420.0);
	float arc = smoothstep(0.80, 1.0, sin(u / 260.0));
	float line = 1.0 - smoothstep(0.0, 0.055, abs(fract(row) - 0.5));
	return arc * line;
}

void main(void)
{
	// y down, and carried with the camera so the litter blows across the world
	// rather than across the screen.
	vec2 p = vec2(v_TexCoord.x, 1.0 - v_TexCoord.y) * u_MapSize
	       + vec2(u_WalkOffset.x, -u_WalkOffset.y) * u_MapSize;
	vec2 w = vec2(dot(p, WIND_DIR), dot(p, vec2(-WIND_DIR.y, WIND_DIR.x)));

	float motes = moteLayer(w, 0.55, 760.0, 0.0) * 0.55
	            + moteLayer(w, 1.00, 520.0, 4.3) * 0.85
	            + moteLayer(w, 1.80, 330.0, 8.9) * 0.45;

	vec3 base = texture2D(u_Tex0, v_TexCoord).rgb;
	vec3 col = base
	         + MOTE_COLOR * motes * MOTE_OPACITY
	         + WISP_COLOR * wisps(w) * WISP_OPACITY;

	// Rolls in rather than snapping on.
	gl_FragColor = vec4(mix(base, col, atmosphereFade()), 1.0);
}
