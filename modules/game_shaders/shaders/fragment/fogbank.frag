// Dense fog over the finished map (registered as 'Map - Fog Banks', shaders.lua;
// sent by the server's regional weather, OTSERV data/world_events/, on extended
// opcode 76):
//   u_WalkOffset  where the camera sits, in fractions of the map rect
//   u_MapSize     the framebuffer's size in pixels
//
// Large soft banks rolling slowly through, thicker in places, with the map's colour
// flattened toward grey under them. Chosen in a browser preview over an even mist
// with thin sideways wisps. The stock fog.frag ('Map - Fog') is left as it was for
// Ctrl+Y.
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

const vec3 FOG_COLOR = vec3(0.80, 0.82, 0.84);

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

void main(void)
{
	// y down, and carried with the camera so the banks lie on the world rather
	// than on the screen.
	vec2 p = vec2(v_TexCoord.x, 1.0 - v_TexCoord.y) * u_MapSize
	       + vec2(u_WalkOffset.x, -u_WalkOffset.y) * u_MapSize;

	// Two octave stacks drifting at different speeds, so the banks change shape as
	// they roll rather than sliding past as one picture.
	vec2 q = p / 330.0 + vec2(u_Time * 0.020, u_Time * 0.007);
	float n = fbm(q) * 0.7 + fbm(q * 1.7 + vec2(-u_Time * 0.012, 0.0) + 5.0) * 0.45;
	float density = 0.30 + 0.55 * smoothstep(0.38, 0.85, n);

	vec3 base = texture2D(u_Tex0, v_TexCoord).rgb;
	vec3 flat_ = mix(base, vec3(dot(base, vec3(0.299, 0.587, 0.114))), 0.25);
	vec3 col = mix(flat_, FOG_COLOR, density);

	gl_FragColor = vec4(mix(base, col, atmosphereFade()), 1.0);
}
