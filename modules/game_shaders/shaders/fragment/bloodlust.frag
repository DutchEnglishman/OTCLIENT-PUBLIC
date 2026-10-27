uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

// Madareth's Bloodlust. A blink, not a repaint: the mix sits low and dips in
// and out about a second and a half apart, so he still reads as himself with
// blood coming up under the skin. Compare monster_corrupted.frag next door,
// which holds 0.55 and turns the whole sprite red -- that is a permanent state
// worn by a variant, this is a few seconds of a boss winding up.
void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);

    if (color.a < 0.01)
        discard;

    float pulse = 0.18 + 0.22 * (0.5 + 0.5 * sin(u_Time * 9.0));
    vec3 tint = vec3(0.95, 0.05, 0.05);

    color.rgb = mix(color.rgb, tint, pulse);
    gl_FragColor = color;
}
