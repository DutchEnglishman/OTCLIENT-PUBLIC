uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    if (color.a < 0.01)
        discard;

    float diagonal = v_TexCoord.x + v_TexCoord.y;
    float beam = 1.0 - smoothstep(0.0, 0.10,
        abs(fract(diagonal - u_Time * 0.55) - 0.5));

    color.rgb += vec3(1.0, 0.95, 0.75) * beam * 0.75;
    gl_FragColor = color;
}
