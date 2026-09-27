// Annihilon's Chained Spike, drawn as up to FOUR chains of iron links running
// from his body to whatever each spike is in, over the finished map (registered
// as 'Map - Hook Chain', shaders.lua; driven by attachedeffects.lua on opcode 73
// "chain", which sets the anchors with UIMap:setShaderAnchor / setShaderTile).
// The skill was Madareth's before it was moved to Annihilon wholesale, which is
// why the texture generator is still make_madareth.ps1:
//   u_Anchor0     his body, framebuffer pixels, y down (-1,-1: no chains at all)
//   u_Anchor1..4  one chain's far end each -- its spike (-1,-1: no such chain)
//   u_MapSize     the framebuffer's size in pixels
//
// FOUR, because he hooks up to four players at once and hauls himself down one
// of the chains while the other three reel their players in. They all leave the
// same body, so they cross each other constantly; see main() for what a crossing
// is made to look like.
//
// IT IS A SHADER BECAUSE A CHAIN IS A LINE BETWEEN TWO MOVING POINTS, and tile
// effects could not be one. The links were 24 rotated textures laid one per tile
// step, which cost three compromises at once: the angle was quantised to 7.5
// degrees, every link had to be pushed off its tile's centre to sit on the true
// line, and -- the one that showed -- a link hanging over into a neighbouring
// tile was painted over by that tile's creatures and top items, because an
// attached effect is drawn in its own tile's pass. A run that reached 22 px into
// its neighbours was cut to pieces by his own body and by anyone standing
// along it. Here there are no tiles: the chain is one segment in screen space,
// the links repeat along it at whatever angle and length it happens to have, and
// nothing can paint over it because the map is already finished underneath.
//
// A link is a ring of iron seen from the side. Every other one is rolled a
// quarter turn about the chain's own axis, so it keeps its length and loses its
// width -- a run of identical rings reads as a ladder, which is what the texture
// generator's `roll` was for and is reproduced here in LINK_EDGE. The iron is lit
// from the upper left off a normal taken across the link, with a rim and a
// specular streak, and the last stretch before the spike carries the heat the
// spike itself is drawn with: Annihilon is a fire demon and the iron he throws has
// not cooled.
uniform sampler2D u_Tex0;
uniform vec2 u_MapSize;
uniform vec2 u_Anchor0;
uniform vec2 u_Anchor1;
uniform vec2 u_Anchor2;
uniform vec2 u_Anchor3;
uniform vec2 u_Anchor4;
varying vec2 v_TexCoord;

const float PITCH = 5.6;        // px from one link to the next, along the chain.
                                // The texture generator's own figure: about two
                                // thirds of a link's length, so they interlock
                                // rather than sitting end to end
const float LINK_LEN = 4.5;     // half a link's length, px
const float LINK_WIDE = 3.15;   // half a link's width when it lies flat, px
const float LINK_EDGE = 0.33;   // and when it stands on edge, as a fraction of it
const float LINK_THICK = 1.15;  // the iron's own thickness, px
const float END_GAP = 7.0;      // how far short of the spike the chain stops, px:
                                // where the shackle ring on the spike's own
                                // texture is, so the two meet instead of the links
                                // running through the head
const float SAG = 0.045;        // sag across the axis, as a fraction of the length,
                                // pinned to zero at both ends. A hauling chain is
                                // nearly taut; this is only enough to keep it off
                                // a dead straight line
const float SAG_MAX = 5.0;      // and never more than this many px, so a long
                                // chain does not bow
const float SHADOW_DROP = 2.0;  // the chain's shadow, px down the screen
const float SHADOW = 0.34;      // and how dark it is
const float HEAT_PX = 26.0;     // how far back from the spike the iron still glows

const vec3 IRON_DARK = vec3(0.055, 0.045, 0.055);
const vec3 IRON_BODY = vec3(0.275, 0.245, 0.270);
const vec3 IRON_LIT = vec3(0.560, 0.520, 0.545);
const vec3 IRON_SPEC = vec3(0.880, 0.840, 0.850);
const vec3 HEAT = vec3(0.90, 0.28, 0.08);
const vec3 LIGHT = vec3(-0.45, -0.6, 0.66);

// One chain from `a` to `b`. Returns its lit colour, and `cover` is how much of
// this pixel the iron takes.
//
// There is no shadow in here on purpose. It was the link's own ring offset in
// the ACROSS direction, which is only down the screen when the chain happens to
// run flat: on a steep chain the shadow fell out sideways and read as a dashed
// second chain beside the first. main() gets it by asking this same function
// what is SHADOW_DROP pixels above the pixel being drawn, which is what a
// shadow is, and is right at every angle for free.
vec3 chain(vec2 p, vec2 a, vec2 b, out float cover)
{
    cover = 0.0;

    vec2 ab = b - a;
    float len = length(ab);
    // Shorter than the gap it leaves for the spike: the spike is at his feet and
    // there is no chain to draw, only the head.
    if (len <= END_GAP + PITCH) {
        return vec3(0.0);
    }
    vec2 dir = ab / len;
    vec2 nrm = vec2(-dir.y, dir.x);

    float run = len - END_GAP;   // the chain's own length, short of the spike
    vec2 ap = p - a;
    float s = dot(ap, dir);      // along the chain, px
    float d = dot(ap, nrm);      // across it, px

    // The sag, taken off the across distance rather than bending the axis: exact
    // enough while the bow is small against the length, which SAG_MAX enforces.
    float along = clamp(s / run, 0.0, 1.0);
    d -= min(SAG_MAX, run * SAG) * sin(along * 3.14159);

    // Which link this is, and where in it. Every other link is rolled a quarter
    // turn, so the run alternates flat, on edge, flat. A link whose centre falls
    // outside the run is not drawn at all, which is what gives the chain two
    // definite ends instead of a half link hanging off each.
    float k = floor(s / PITCH);
    float centre = (k + 0.5) * PITCH;
    if (centre < 0.0 || centre > run) {
        return vec3(0.0);
    }
    float u = s - centre;
    float halfWidth = mix(LINK_WIDE, LINK_WIDE * LINK_EDGE, mod(k, 2.0));

    // A LINK REACHES ONLY AS FAR AS ITS OWN BOX, and saying so is not
    // optional. The ring distance below is the ellipse function divided by its
    // own gradient, which is a true distance near the curve and SATURATES far
    // from it -- at `halfWidth`, not at infinity. For a link standing on edge
    // that is about 1.04 px, inside the smoothstep that decides coverage, so
    // without this every other link painted a band of iron and shadow clean
    // across the screen, perpendicular to the chain. Bounding it here is what
    // makes the approximation safe to use at all.
    float reachU = LINK_LEN + LINK_THICK + 1.0;
    float reachD = halfWidth + LINK_THICK + 1.0;
    if (abs(u) > reachU || abs(d) > reachD) {
        return vec3(0.0);
    }

    // The ring: an ellipse of half-length LINK_LEN and half-width halfWidth,
    // DRAWN rather than filled, so the hole in the middle of a link is a hole --
    // the same reason the texture generator's Draw-Link uses DrawEllipse. The
    // ellipse function on its own is unitless and its contours crowd where the
    // curve is tight, so it is divided by its own gradient to turn it back into
    // a distance in pixels: that is what keeps the iron one thickness the whole
    // way round a link instead of thin at the ends and fat at the sides.
    vec2 q = vec2(u / LINK_LEN, d / halfWidth);
    float e = length(q);
    vec2 grad = vec2(q.x / LINK_LEN, q.y / halfWidth);
    float glen = max(length(grad), 0.0001);
    float ringSigned = (e - 1.0) / glen;              // px from the iron's centre
                                                      // line, negative inside
    cover = 1.0 - smoothstep(LINK_THICK - 0.6, LINK_THICK + 0.6, abs(ringSigned));

    if (cover <= 0.0) {
        return vec3(0.0);
    }

    // The surface normal across the iron: how far this pixel is from the middle
    // of the iron, as a fraction of its thickness, leans the normal outward and
    // the rest is height -- a round bar of iron bent into a ring. The lean is
    // taken along the ellipse's own outward direction, which is in (along,
    // across), so it has to be put back into screen axes before it can meet a
    // light that lives there.
    float side = clamp(ringSigned / LINK_THICK, -1.0, 1.0);
    vec2 outward = grad / glen;
    vec2 outwardScreen = dir * outward.x + nrm * outward.y;
    vec3 n = normalize(vec3(outwardScreen * side, sqrt(max(0.0, 1.0 - side * side))));
    vec3 light = normalize(LIGHT);
    float diffuse = max(0.0, dot(n, light));
    float rim = pow(1.0 - n.z, 2.0);
    vec3 half_ = normalize(light + vec3(0.0, 0.0, 1.0));
    float spec = pow(max(0.0, dot(n, half_)), 24.0);

    vec3 col = mix(IRON_DARK, IRON_BODY, 0.35 + 0.65 * diffuse);
    col = mix(col, IRON_LIT, diffuse * 0.55);
    col += IRON_SPEC * spec * 0.55;
    col = mix(col, IRON_DARK, rim * 0.35);

    // The heat, strongest at the spike and gone a little way back up the chain.
    float heat = 1.0 - smoothstep(0.0, HEAT_PX, run - s);
    col = mix(col, HEAT, heat * heat * 0.55);

    return col;
}

void main(void)
{
    vec4 base = texture2D(u_Tex0, v_TexCoord);
    if (u_Anchor0.x < 0.0) {
        gl_FragColor = base;
        return;
    }

    // Framebuffer pixel of this fragment, y down like the anchors.
    vec2 p = vec2(v_TexCoord.x, 1.0 - v_TexCoord.y) * u_MapSize;

    // The chain SHADOW_DROP pixels above this pixel is what casts a shadow on it,
    // so every chain's shadow is gathered first and laid down before any iron is,
    // or one chain would be drawn onto another's shadow.
    vec2 up = p - vec2(0.0, SHADOW_DROP);
    float cover1 = 0.0, cover2 = 0.0, cover3 = 0.0, cover4 = 0.0;
    float shade1 = 0.0, shade2 = 0.0, shade3 = 0.0, shade4 = 0.0;
    vec3 iron1 = vec3(0.0), iron2 = vec3(0.0), iron3 = vec3(0.0), iron4 = vec3(0.0);
    if (u_Anchor1.x >= 0.0) {
        iron1 = chain(p, u_Anchor0, u_Anchor1, cover1);
        chain(up, u_Anchor0, u_Anchor1, shade1);
    }
    if (u_Anchor2.x >= 0.0) {
        iron2 = chain(p, u_Anchor0, u_Anchor2, cover2);
        chain(up, u_Anchor0, u_Anchor2, shade2);
    }
    if (u_Anchor3.x >= 0.0) {
        iron3 = chain(p, u_Anchor0, u_Anchor3, cover3);
        chain(up, u_Anchor0, u_Anchor3, shade3);
    }
    if (u_Anchor4.x >= 0.0) {
        iron4 = chain(p, u_Anchor0, u_Anchor4, cover4);
        chain(up, u_Anchor0, u_Anchor4, shade4);
    }

    vec3 col = base.rgb;
    col *= 1.0 - max(max(shade1, shade2), max(shade3, shade4)) * SHADOW;

    // WHICHEVER CHAIN COVERS THIS PIXEL MOST OWNS IT: four chains leaving one
    // body cross each other constantly, and a crossing has to read as one chain
    // passing over another rather than as their colours averaged. So the winner
    // is found first and every other chain is laid down without it, then the
    // winner goes on top -- rather than painting all four and the winner again,
    // which would lay the winner's own antialiased edge over itself and thicken
    // it. A tie drops one of the two, which at equal coverage cannot be seen.
    float best = max(max(cover1, cover2), max(cover3, cover4));
    vec3 bestIron = iron1;
    if (cover2 >= best) bestIron = iron2;
    if (cover3 >= best) bestIron = iron3;
    if (cover4 >= best) bestIron = iron4;

    if (cover1 < best) col = mix(col, iron1, cover1);
    if (cover2 < best) col = mix(col, iron2, cover2);
    if (cover3 < best) col = mix(col, iron3, cover3);
    if (cover4 < best) col = mix(col, iron4, cover4);
    col = mix(col, bestIron, best);

    gl_FragColor = vec4(col, base.a);
}
