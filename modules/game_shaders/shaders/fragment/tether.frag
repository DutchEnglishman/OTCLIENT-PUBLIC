// The tether between Latrivan and Golgordan, drawn as two intertwined strands from
// body to body over the finished map (registered as 'Map - Tether', shaders.lua;
// driven by attachedeffects.lua on opcode 73 "tether", which sets the anchors with
// UIMap:setShaderAnchor / setShaderPoint):
//   u_Anchor0  Latrivan's body centre, framebuffer pixels, y down (-1,-1: no tether)
//   u_Anchor1  Golgordan's
//   u_Anchor2  the ball: x how far along from Latrivan to Golgordan, y > 0 in flight
//   u_Anchor3  x the flow the server sends, +1 Latrivan -> Golgordan: NOT read here
//              any more, each strand runs out of its own brother (see the strand calls)
//   u_MapSize  the framebuffer's size in pixels
//
// Latrivan's strand is purple, Golgordan's green. At each body the two are pinned
// together into one tube of that brother's colour; between them they part and twist
// round each other, the twist turning on u_Time, each strand fading as it nears the
// other's end. Every strand is a lit cylinder: the distance across it gives a
// surface normal, shaded by a key light from the upper left, a rim light and a
// specular streak, with an energy core running down its axis and a soft glow
// bleeding onto whatever is around it -- the two cores run opposite ways, so the
// braid reads as two currents passing. The whole thing sags down the screen and
// carries a slow ripple, both pinned to zero at the bodies.
uniform float u_Time;
uniform sampler2D u_Tex0;
uniform vec2 u_MapSize;
uniform vec2 u_Anchor0;
uniform vec2 u_Anchor1;
uniform vec2 u_Anchor2;
uniform vec2 u_Anchor3;
varying vec2 v_TexCoord;

const float RADIUS = 3.6;        // half a strand's width, px
const float GLOW = 8.0;          // how far the glow reaches past a surface, px
const float TWIST = 5.0;         // how far each strand swings off the axis mid-tube, px
const float TWIST_PERIOD = 46.0; // px per full turn of the pair
const float SWING_END = 0.35;    // how much of the swing survives at the bodies. Must stay
                                 // above RADIUS_END * RADIUS / TWIST (0.32 here) or the strands
                                 // overlap where the order flips, and appear to pass through
                                 // both strands to the same point there, 1.0 keeps them apart
const float SWING_TAPER = 0.45;  // exponent on pin for the swing. 1.0 is a plain sine, so the
                                 // strands only part near mid-tube; lower opens the braid closer
                                 // to the bodies while still meeting at them
const float FRONT_BIAS = 0.0;    // lean toward the near brother. 0.0 now the strands never
                                 // overlap at a flip: any lean moves the flip off maximum
                                 // separation, which is the one place a swap cannot be seen
                                 // twist owns the order mid-tube; this is added to it, so at 1.0
                                 // the near strand is fully in front by the body. 0.0 disables it
const float RADIUS_END = 0.45;   // how thin a strand gets at a body, as a fraction of RADIUS
                                 // the twist. Below 1.0 the lean saturates early, so the far strand
                                 // stops taking its turn in front well before the tips
const float TETHER_ALPHA = 0.92; // how solid the tether is over the ground (1.0 = opaque)
const float TWIST_SPEED = 0.35;  // turns per second. Deliberately slow: the braid is shared
                                 // by both strands, so a fast one streams toward Golgordan at
                                 // TWIST_PERIOD x this px/s and swamps the only cue for which
                                 // way each strand actually runs (the core, at FLOW_SPEED).
const float FLOW_SPEED = 90.0;   // px per second the energy travels
const float BALL = 2.5;          // the ball's radius, px
// DEBUG KNOB -- set back to 0.0 when you are done looking.
// Snaps both anchors to a grid, reproducing what the tether looked like before
// Creature::getSmoothWalkOffset: 1.0 is exactly the old integer anchors, 8.0
// exaggerates the same artefact until it is obvious, 0.0 is off (normal, and the
// branch compiles away). Watch one brother walk with it at 8.0, then at 0.0.
const float ANCHOR_QUANTISE = 0.0;

const vec3 P_CORE = vec3(0.93, 0.82, 1.0);
const vec3 P_BODY = vec3(0.40, 0.14, 0.72);
const vec3 P_SHADOW = vec3(0.06, 0.01, 0.13);
const vec3 P_GLOW = vec3(0.66, 0.30, 1.0);

const vec3 G_CORE = vec3(0.75, 1.0, 0.70);
const vec3 G_BODY = vec3(0.10, 0.40, 0.14);
const vec3 G_SHADOW = vec3(0.01, 0.08, 0.02);
const vec3 G_GLOW = vec3(0.20, 0.85, 0.30);

const vec3 LIGHT = vec3(-0.45, -0.6, 0.66);

float hash(float n) { return fract(sin(n) * 43758.5453); }

// One strand. p the pixel, c the strand's centre line point nearest it, nrm the
// across direction, t the distance along the tube, flow the energy direction,
// w how strongly this strand shows here (its colour's own end 1, the far end
// less). Returns the lit colour; `inside` is the strand's coverage and `glow`
// its glow outside the surface.
vec3 strand(vec2 p, vec2 c, vec2 nrm, float t, float flow, float w, float radius,
            vec3 core, vec3 body, vec3 shadow, vec3 glowc,
            out float inside, out float glow)
{
    vec2 pc = p - c;
    float d = length(pc);
    float s = dot(pc, nrm);
    float across = clamp(s / radius, -1.0, 1.0);
    inside = 1.0 - smoothstep(radius - 1.0, radius + 0.5, d);

    vec3 n = normalize(vec3(nrm * across, sqrt(max(0.0, 1.0 - across * across))));
    vec3 light = normalize(LIGHT);
    float diffuse = max(0.0, dot(n, light));
    float rim = pow(1.0 - n.z, 2.5);
    vec3 half_ = normalize(light + vec3(0.0, 0.0, 1.0));
    float spec = pow(max(0.0, dot(n, half_)), 28.0);

    // The core is the ONLY cue for which way this strand runs, so it is a sharp pulse
    // train rather than a soft swell: the fourth power leaves distinct bright packets
    // with dark gaps between them, which read as travelling. Two soft sines beating
    // against each other did not -- the direction was there, it just could not be seen.
    float run = t * flow - u_Time * FLOW_SPEED;
    float wave = pow(0.5 + 0.5 * sin(run * 0.30), 4.0);
    float shimmer = hash(floor(run * 0.5)) * 0.12;
    float coreLine = (1.0 - smoothstep(0.0, 0.45, abs(across))) * (0.30 + 1.30 * wave + shimmer);

    vec3 col = mix(shadow, body, diffuse * 0.9 + 0.1);
    col += core * coreLine * w;
    col += glowc * rim * 0.55 * w;
    col += vec3(1.0) * spec * 0.7;
    // No darkening pass here: the fade lives in `inside` above. Doing both made the far
    // strand dark AND solid, which is the cut this was all chasing.

    glow = (1.0 - smoothstep(0.0, GLOW, d - radius)) * (0.35 + 0.15 * wave) * w;
    return col;
}

void main(void)
{
    vec4 base = texture2D(u_Tex0, v_TexCoord);
    if (u_Anchor0.x < 0.0 || u_Anchor1.x < 0.0) {
        gl_FragColor = base;
        return;
    }

    // Framebuffer pixel of this fragment, y down like the anchors.
    vec2 p = vec2(v_TexCoord.x, 1.0 - v_TexCoord.y) * u_MapSize;

    vec2 a = u_Anchor0;
    vec2 b = u_Anchor1;
    if (ANCHOR_QUANTISE > 0.0) {
        a = floor(a / ANCHOR_QUANTISE + 0.5) * ANCHOR_QUANTISE;
        b = floor(b / ANCHOR_QUANTISE + 0.5) * ANCHOR_QUANTISE;
    }
    vec2 ab = b - a;
    float len = max(length(ab), 0.001);      // not 1.0: the anchors are sub-pixel now
    vec2 dir = ab / len;
    vec2 nrm = vec2(-dir.y, dir.x);
    vec2 anchor0Dir = dir;                   // out of Latrivan toward Golgordan
    vec2 anchor1Dir = -dir;                  // and back out of Golgordan
    vec2 ap = p - a;
    float t = clamp(dot(ap, dir), 0.0, len);   // along the tube, px
    float along = t / len;                      // 0 at Latrivan, 1 at Golgordan

    // The pair's centre line: sag down the screen, a slow ripple, both pinned to
    // the bodies. Applied as a shift across the axis; exact enough while the bend
    // is small against the length.
    float pin = sin(along * 3.14159);
    float sag = min(14.0, len * 0.12) * pin;
    float ripple = 3.0 * sin(t * 0.09 - u_Time * 3.5) * pin
                 + 1.2 * sin(t * 0.23 + u_Time * 6.0) * pin;
    vec2 bend = vec2(0.0, sag) + nrm * ripple;
    vec2 q = a + dir * t + bend;

    // The twist: each strand swings off the centre line by +/- TWIST, the two half
    // a turn apart, the swing growing from nothing at either body. cos of the same
    // phase says which strand is in front where they cross.
    float phase = 6.28318 * t / TWIST_PERIOD - u_Time * 6.28318 * TWIST_SPEED;
    // The swing gets its own taper, not pin: sag and ripple MUST go to zero at the
    // bodies or the tube would not meet the sprite, but a swing that does the same puts
    // both strands on one centre line there, with no over and under left to read -- they
    // collapse into a single tube at each end. SWING_END keeps most of the width instead.
    // taper narrows the braid toward each body -- and the STRANDS with it. Separation at
    // the flip is 2*TWIST*taper and the two strands together are 2*RADIUS*taper, and
    // TWIST > RADIUS, so they clear each other by the same margin at every distance from
    // the body. Shrinking only the swing is what put the order flip inside an overlap.
    float taper = mix(SWING_END, 1.0, pow(pin, SWING_TAPER));
    float swing = TWIST * taper * sin(phase);
    float rad = RADIUS * max(taper, RADIUS_END);

    // Each strand shows fully at its own brother and is GONE by the other's, not merely
    // dimmed. A strand that survives at 0.30 still lands on the near one at the body,
    // where the two share a point: solid it cuts a bar through it, ghosted it tints it
    // green. Neither is fixable in the compositing -- the far strand simply has no
    // business being there. Faded out, each body shows one colour, its own.
    float wP = mix(1.0, 0.0, smoothstep(0.15, 0.85, along));
    float wG = mix(0.0, 1.0, smoothstep(0.15, 0.85, along));

    // Each brother pushes his own colour out toward the other, so the two currents
    // always oppose: purple leaves Latrivan (+t), green leaves Golgordan (-t). Tied to
    // the brother, not to u_Anchor3's flow -- keyed to the flow the pair swapped between
    // converging and diverging every pulse, which read as one current out of Latrivan.
    float inP, glP, inG, glG;
    vec3 colP = strand(p, q + nrm * swing, nrm, t,  1.0, wP, rad, P_CORE, P_BODY, P_SHADOW, P_GLOW, inP, glP);
    vec3 colG = strand(p, q - nrm * swing, nrm, t, -1.0, wG, rad, G_CORE, G_BODY, G_SHADOW, G_GLOW, inG, glG);

    // The two strands are resolved against each other FIRST, the front one covering the
    // back one outright, and only the finished layer is laid over the map at TETHER_ALPHA.
    // w fades a strand toward the other brother, and here it fades how much that strand
    // OCCLUDES the other one -- not how dark it is, and not the tether's own alpha. A
    // strand dimmed but still solid covers the bright one wherever it passes in front,
    // and at a body, where both sit on the same point, that is a bar straight through
    // the tether. At 0.30 it is a ghost the near strand shows through instead.
    // The map alpha stays on the geometric coverage, or the middle of the tube -- where
    // both w are about 0.65 -- would go see-through against the ground.
    //
    // There is deliberately no blend where the strands meet. One was needed while the
    // front strand could not fully cover the back one and while pin collapsed both onto
    // one centre line at the bodies; with those gone, a crossing is simply the front
    // strand passing over, and blending there only put green inside the purple.
    // Proper front-over-back compositing, each strand carrying its own alpha: its
    // geometric coverage times w, so a strand that has faded out contributes nothing
    // rather than contributing a colour. Mixing toward the other strand's colour by a
    // weight, as this did twice, paints that colour onto pixels the other strand never
    // reaches -- which is how the purple end turned green once w was allowed to hit 0.
    // The layer is resolved first so the front strand covers the back one outright, and
    // TETHER_ALPHA is applied once, to the finished layer, as the ground translucency.
    // w decides which strand WINS, never how solid the tether is. Feeding it into the
    // alphas made the middle of the tube half transparent, since both weights sit at
    // 0.5 there. Both strands are fully opaque; the fade only forces the near brother's
    // strand to the front in the outer quarter at each end, which is the whole reason
    // the far one ever needed dimming -- it can no longer be in front of the near one
    // at a body, so it can neither cut it nor tint it. Between the quarters the twist
    // decides, and the braid reads over and under as before.
    float bias = wP - wG;                      // +1 at Latrivan, -1 at Golgordan, 0 mid
    // Depth, not a switch: cos(phase) is the twist's own front-and-back, and bias leans it
    // toward the near brother as a body approaches. Overriding it outright past a fixed
    // point along the tube flipped the order in the middle of an overlap, which reads as
    // the strands passing through each other. Leaning closes the far strand's turn in
    // front smoothly instead, and it is shut entirely by the time the tips meet.
    float pFront = step(0.0, cos(phase) + bias * FRONT_BIAS);

    // Both strands stay fully opaque. Fading a spent strand out by alpha was tried and
    // reverted: it is what left the runs either side of a body invisible. The dark
    // sliver it was aimed at is the far strand's unlit body taking a turn in front --
    // closed by the lean above, not by taking the strand's solidity away.
    float aP = inP;
    float aG = inG;

    float fa   = pFront > 0.5 ? aP : aG;
    float ba   = pFront > 0.5 ? aG : aP;
    vec3  fcol = pFront > 0.5 ? colP : colG;
    vec3  bcol = pFront > 0.5 ? colG : colP;

    float la = fa + ba * (1.0 - fa);
    vec3 layer = (fcol * fa + bcol * ba * (1.0 - fa)) / max(la, 0.001);
    vec3 col = mix(base.rgb, layer, la * TETHER_ALPHA);
    // la, not the geometric coverage: a faded-out strand draws nothing, so it must not
    // suppress the glow over its own footprint either.
    float covered = la;
    col += (P_GLOW * glP + G_GLOW * glG) * 0.45 * (1.0 - covered);

    // Where each strand enters its body it blooms in that brother's colour, brightest
    // along the tube's own axis so the flare reads as the strand plunging into the
    // body rather than as a disc behind it. The epsilon keeps normalize off (0,0)
    // at the body centre itself, where the bloom is at full strength anyway.
    float endA = 1.0 - smoothstep(0.0, RADIUS * 3.0, length(p - a));
    float endB = 1.0 - smoothstep(0.0, RADIUS * 3.0, length(p - b));
    float axA = max(0.0, dot(normalize(p - a + 1e-4), anchor0Dir));
    float axB = max(0.0, dot(normalize(p - b + 1e-4), anchor1Dir));
    col += (P_CORE * 0.5 + P_GLOW * 0.6) * endA * (0.55 + 0.45 * axA)
         + (G_CORE * 0.5 + G_GLOW * 0.6) * endB * (0.55 + 0.45 * axB);

    // The ball: a bright point on the centre line at its progress, coloured by
    // where it is between the two.
    if (u_Anchor2.y > 0.0) {
        float bAlong = clamp(u_Anchor2.x, 0.0, 1.0);
        float bt = bAlong * len;
        float bpin = sin(bAlong * 3.14159);
        vec2 bbend = vec2(0.0, min(14.0, len * 0.12) * bpin)
                   + nrm * (3.0 * sin(bt * 0.09 - u_Time * 3.5) * bpin + 1.2 * sin(bt * 0.23 + u_Time * 6.0) * bpin);
        vec2 c = a + dir * bt + bbend;
        float bd = length(p - c);
        vec3 bglowc = mix(P_GLOW, G_GLOW, bAlong);
        vec3 bcore = mix(P_CORE, G_CORE, bAlong);
        float bin = 1.0 - smoothstep(BALL - 1.0, BALL + 0.5, bd);
        float bglow = 1.0 - smoothstep(0.0, BALL * 2.4, bd - BALL);
        col = mix(col, bcore, bin);
        col += bglowc * bglow * 0.5 * (1.0 - bin) + bcore * bglow * 0.15;
    }

    gl_FragColor = vec4(col, base.a);
}
