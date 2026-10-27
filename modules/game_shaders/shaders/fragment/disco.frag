// A disco over the finished map (registered as 'Map - Disco', shaders.lua;
// toggled by the server's /disco on extended opcode 76):
//   u_MapCenterCoord  the middle of the VISIBLE map, in v_TexCoord space
//   u_MapGlobalCoord  the framebuffer's first tile, times the tile size, over its height
//   u_MapZoom         the scale factor; a tile is 32 * u_MapZoom framebuffer pixels
//   u_MapSize         the framebuffer's size in pixels
//
// Everything keeps time to one tempo, BPM:
//   - every tile of the world is a dance-floor panel, lit in a pattern that
//     changes every bar (scatter, checkerboard, diagonal sweep, rings out from
//     the middle of the screen)
//   - the whole room flashes a colour on each beat
//   - twelve spotlights sweep pools across it, each flickering on eighth notes
//   - beams from two rigs above the screen, laser fans sweeping on alternate bars
//   - two layers of mirror-ball glints drifting opposite ways
//
// The floor, the flash and the pools MULTIPLY the scene, so a magenta pool on
// grass reads as lit grass rather than a disc pasted over it. Beams, lasers and
// glints are the only things that add light.
//
// FLASH RATE IS A HARD LIMIT. Three or more full-screen flashes a second is the
// photosensitive seizure threshold, and at 124 BPM the beat is 2.07 a second.
// Only the room flash and the floor's pattern change move the whole screen, and
// both change on the beat and no faster. The spotlights flicker on eighth notes,
// but each on its own roll, so the lit share of the screen stays roughly level
// while individual lights blink. Do not put a full-screen change on anything
// faster than the beat.
//
// The floor is aligned to real tiles: the framebuffer is drawn starting on a
// tile boundary (mapview.cpp, drawDimension * tileSize), so floor(pixel / tile)
// is a tile, and adding the framebuffer's first tile from u_MapGlobalCoord pins
// the pattern to the world so it does not slide a tile every step.
uniform float u_Time;
uniform sampler2D u_Tex0;
uniform vec2 u_MapCenterCoord;
uniform vec2 u_MapGlobalCoord;
uniform float u_MapZoom;
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

const float BPM = 124.0;

const float AMBIENT = 0.26;       // the room with every light off
const float FLASH_GAIN = 0.70;    // the room flash at the top of each beat
const float FLOOR_GAIN = 0.95;    // a lit dance-floor panel
const float POOL_GAIN = 1.40;
const float POOL_RADIUS = 0.13;   // in screen heights
const float BEAM_OPACITY = 0.11;
const float LASER_OPACITY = 0.75;
const float SPARKLE_OPACITY = 1.0;

const int LIGHTS = 12;
const int LASERS = 7;

float hash11(float n) { return fract(sin(n * 78.233) * 43758.5453123); }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

vec3 hue(float h)
{
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return k * k * (3.0 - 2.0 * k);
}

// Distance from p to the segment a-b, and how far along it p falls (0 at a).
vec2 segment(vec2 p, vec2 a, vec2 b)
{
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	return vec2(length(p - a - ab * t), t);
}

// Which panels are lit this beat. tile is a world tile, centre the tile in the
// middle of the screen; the pattern changes every bar and steps every beat.
float floorPattern(vec2 tile, vec2 centre, float beat, float bar)
{
	float mode = mod(bar, 4.0);
	float beatInBar = mod(beat, 4.0);

	if (mode < 0.5) {
		return hash21(tile + beat * 17.0) < 0.45 ? 1.0 : 0.0;
	}
	if (mode < 1.5) {
		return mod(tile.x + tile.y + beat, 2.0) < 0.5 ? 1.0 : 0.0;
	}
	if (mode < 2.5) {
		return mod(tile.x - tile.y - beatInBar * 2.0, 8.0) < 3.0 ? 1.0 : 0.0;
	}
	vec2 d = abs(tile - centre);
	return mod(max(d.x, d.y) - beatInBar * 2.0, 8.0) < 3.0 ? 1.0 : 0.0;
}

// Mirror-ball glints: a grid sliding sideways as the ball turns, each twinkling
// on its own clock. sp is in pixels so a glint is the same size whatever the
// window.
float sparkles(vec2 sp, float t, float speed, float cell, float seed)
{
	vec2 uv = sp / cell;
	uv.x += t * speed;
	uv.y += sin(uv.x * 0.35 + t * 0.6 + seed) * 0.25;

	vec2 id = floor(uv);
	vec2 f = fract(uv);
	float h = hash21(id + seed);
	if (h > 0.55) return 0.0;

	vec2 c = vec2(0.2 + 0.6 * hash11(h * 13.1), 0.2 + 0.6 * hash11(h * 29.7));
	vec2 a = abs((f - c) * cell);
	float twinkle = 0.5 + 0.5 * sin(t * (4.0 + 6.0 * h) + h * 40.0);
	float core = 1.0 - smoothstep(0.6, 2.4, length(a));
	// A cross makes it a glint rather than a dot.
	float star = (1.0 - smoothstep(0.0, 0.9, min(a.x, a.y))) * (1.0 - smoothstep(0.0, 7.0, max(a.x, a.y)));
	return (core + star * 0.7) * twinkle * twinkle;
}

// A fan of thin laser lines out of one point, swinging as a whole.
float laserFan(vec2 n, vec2 origin, float t, float swing, float seed)
{
	float acc = 0.0;
	vec2 rel = n - origin;
	for (int i = 0; i < LASERS; i++) {
		float fi = float(i);
		float angle = 1.5708 + (fi - float(LASERS - 1) * 0.5) * 0.16 + sin(t * swing + seed) * 0.55;
		vec2 dir = vec2(cos(angle), sin(angle));
		float along = dot(rel, dir);
		if (along <= 0.0) continue;
		float across = abs(rel.x * dir.y - rel.y * dir.x) * u_MapSize.y; // pixels
		acc += (1.0 - smoothstep(0.0, 1.6, across)) + (1.0 - smoothstep(0.0, 7.0, across)) * 0.25;
	}
	return acc;
}

void main(void)
{
	vec3 base = texture2D(u_Tex0, v_TexCoord).rgb;
	float t = u_Time;

	float beats = t * BPM / 60.0;
	float beat = floor(beats);
	float kick = exp(-fract(beats) * 7.0);
	float eighth = floor(beats * 2.0);
	float bar = floor(beats / 4.0);

	// Pixels from the framebuffer's top-left, y down: the tile grid's own space.
	vec2 fb = vec2(v_TexCoord.x, 1.0 - v_TexCoord.y) * u_MapSize;
	// Pixels from the middle of the visible map, y down, and the same in screen
	// heights for everything that should scale with the window.
	vec2 sp = (v_TexCoord - u_MapCenterCoord) * u_MapSize;
	sp.y = -sp.y;
	vec2 n = sp / u_MapSize.y;

	// --- Dance floor --------------------------------------------------------
	float tileSize = 32.0 * u_MapZoom;
	vec2 firstTile = floor(vec2(u_MapGlobalCoord.x, -u_MapGlobalCoord.y) * u_MapSize.y / tileSize + 0.5);
	vec2 local = fb / tileSize;
	vec2 tile = floor(local) + firstTile;
	vec2 centre = floor(vec2(u_MapCenterCoord.x, 1.0 - u_MapCenterCoord.y) * u_MapSize / tileSize) + firstTile;

	// A panel glows brightest in its middle and leaves a dark seam round its edge.
	vec2 inTile = abs(fract(local) - 0.5);
	float panel = 1.0 - smoothstep(0.34, 0.47, max(inTile.x, inTile.y));
	panel *= 0.75 + 0.25 * (1.0 - length(inTile) * 1.4);

	float lit = floorPattern(tile, centre, beat, bar);
	vec3 floorColor = hue(hash21(tile * 0.37 + bar) * 0.35 + bar * 0.21 + (tile.x + tile.y) * 0.04);
	vec3 floorLight = floorColor * panel * lit * FLOOR_GAIN * (0.55 + 0.45 * kick);

	// --- Room flash ---------------------------------------------------------
	vec3 flashColor = mix(vec3(1.0), hue(beat * 0.137), 0.65);
	vec3 flash = flashColor * kick * FLASH_GAIN;

	// --- Spotlights and their beams -------------------------------------------
	vec3 pools = vec3(0.0);
	vec3 beams = vec3(0.0);
	for (int i = 0; i < LIGHTS; i++) {
		float fi = float(i);

		// Each light blinks on eighth notes on a roll of its own, so between them
		// the room stays about equally lit while individual lights strobe.
		float on = hash11(eighth * 7.0 + fi * 3.1) < 0.70 ? 1.0 : 0.0;

		vec2 pos = vec2(sin(t * (0.9 + 0.17 * fi) + fi * 1.7) * 0.72,
		                cos(t * (0.7 + 0.13 * fi) + fi * 2.3) * 0.38);
		vec3 color = hue(fi / float(LIGHTS) + bar * 0.17);

		float r = length(n - pos) / POOL_RADIUS;
		float pool = 1.0 - smoothstep(0.5, 1.0, r);
		pools += color * pool * on;

		// Odd lights hang from the left rig, even ones from the right.
		vec2 rig = vec2(mod(fi, 2.0) < 0.5 ? 0.55 : -0.55, -0.75);
		vec2 s = segment(n, rig, pos);
		float width = mix(0.006, POOL_RADIUS * 0.55, s.y);
		beams += color * (1.0 - smoothstep(0.0, width, s.x)) * s.y * on;
	}

	// --- Lasers, on alternate bars ------------------------------------------
	float laserOn = mod(bar, 2.0) < 0.5 ? 1.0 : 0.0;
	vec3 laserColor = mod(bar, 4.0) < 1.5 ? vec3(0.25, 1.0, 0.30) : vec3(1.0, 0.18, 0.25);
	float lasers = laserFan(n, vec2(-0.35, -0.70), t, 1.7, 0.0)
	             + laserFan(n, vec2(0.35, -0.70), t, 1.7, 3.14159);
	vec3 laser = laserColor * lasers * laserOn * LASER_OPACITY;

	// --- Mirror ball --------------------------------------------------------
	float glints = sparkles(sp, t, 1.4, 40.0, 0.0) + sparkles(sp, t, -0.9, 58.0, 11.0) * 0.8;
	vec3 glintColor = mix(vec3(1.0), hue(eighth * 0.071), 0.35);

	vec3 col = base * (AMBIENT + flash + floorLight + pools * POOL_GAIN)
	         + beams * BEAM_OPACITY
	         + laser
	         + glintColor * glints * SPARKLE_OPACITY;

	gl_FragColor = vec4(mix(base, clamp(col, 0.0, 1.0), atmosphereFade()), 1.0);
}
