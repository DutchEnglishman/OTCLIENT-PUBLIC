uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec2 uv = v_TexCoord;
    float waveX = sin(uv.y * 28.0 + u_Time * 5.0) * 0.012;
    float waveY = cos(uv.x * 24.0 + u_Time * 4.0) * 0.008;
    uv += vec2(waveX, waveY);

    vec4 color = texture2D(u_Tex0, uv);
    if (color.a < 0.01)
        discard;

    gl_FragColor = color;
}
