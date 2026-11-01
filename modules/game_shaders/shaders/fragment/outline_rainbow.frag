// outline_solid.frag cycling through the hues; the draw colour is ignored.
uniform sampler2D u_Tex0;
uniform vec4 u_Color;
uniform float u_Opacity;
uniform float u_Time;
varying vec2 v_TexCoord;

vec3 hue(float h)
{
    return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

void main()
{
    if (texture2D(u_Tex0, v_TexCoord).a < 0.5)
        discard;
    gl_FragColor = vec4(hue(fract(u_Time * 0.25)), u_Color.a * u_Opacity);
}
