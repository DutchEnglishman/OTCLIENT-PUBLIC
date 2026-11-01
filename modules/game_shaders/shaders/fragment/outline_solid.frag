// An outfit's silhouette in one flat colour: Creature::internalDraw draws it eight times, one
// art pixel out each way, behind the body, so only the rim shows. The colour is the draw colour.
uniform sampler2D u_Tex0;
uniform vec4 u_Color;
uniform float u_Opacity;
varying vec2 v_TexCoord;

void main()
{
    // Half-transparent pixels are left out, so the rim stays one crisp pixel like the art.
    if (texture2D(u_Tex0, v_TexCoord).a < 0.5)
        discard;
    gl_FragColor = vec4(u_Color.rgb, u_Color.a * u_Opacity);
}
