// Rarity shine, worn by an item lying on the floor whose upgrade-system rarity
// is Rare or better (game_attachedeffects/attachedeffects.lua, opcode 72).
//
// The sprite's own alpha is the mask, which is the whole point of doing this
// as a shader on the item instead of a texture over the tile: the shine covers
// every pixel of the weapon -- both cells of a 2x2 sprite included -- and none
// of the empty tile around it. A 32x32 texture on the tile could do neither.
//
// One band, sweeping NW to SE, and deliberately nothing else: between sweeps
// the piece is drawn exactly as it is. An earlier version also held a constant
// mix toward the rarity colour so the item always read as rare at a glance,
// and in game that is a permanent glow sitting on the sprite -- it recolours
// the item rather than lighting it. If a resting tint is ever wanted back it
// belongs at a fraction of what looks right on paper; 0.22 was far too much.
//
// v_TexCoord runs 0..1 over the thing's texture sheet, which for a piece of
// equipment -- one animation phase, one pattern -- is exactly the sprite, so
// the band crosses the weapon once a cycle. An item that animates or carries
// patterns packs several frames into that sheet and would get a band that
// narrow; nothing the upgrade system rolls a rarity onto is either.
//
// TUNING IS A THREE-FILE EDIT: rarity_shine_rare, _epic and _legendary differ
// only in RARITY, which is that rarity's tooltip colour
// (game_itemtooltip/itemtooltip.lua, RARITY_COLORS).
uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

const vec3 RARITY = vec3(0.251, 0.502, 1.000); // #4080FF rare
const float BEAM = 0.75;  // how hard the band brightens
const float SPEED = 0.70; // sprite traversals a second
const float WIDTH = 0.18; // half the band's width, as a fraction of the sprite

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    if (color.a < 0.01)
        discard;

    // x + y spans 0..2 corner to corner, halved so one band is in flight at a
    // time; the band sits where fract() reaches 0.5 and travels with u_Time.
    float diagonal = (v_TexCoord.x + v_TexCoord.y) * 0.5;
    float band = 1.0 - smoothstep(0.0, WIDTH,
        abs(fract(diagonal - u_Time * SPEED) - 0.5));

    color.rgb += RARITY * band * BEAM;
    gl_FragColor = color;
}
