// outline_solid.frag, breathing: the rim fades between 35% and full once a second or so.
uniform sampler2D u_Tex0;
uniform vec4 u_Color;
uniform float u_Opacity;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    if (texture2D(u_Tex0, v_TexCoord).a < 0.5)
        discard;
    float pulse = 0.675 + 0.325 * sin(u_Time * 5.0);
    gl_FragColor = vec4(u_Color.rgb, u_Color.a * u_Opacity * pulse);
}
