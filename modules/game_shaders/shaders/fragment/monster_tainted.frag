uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);

    if (color.a < 0.01)
        discard;

    float pulse = 0.55 + 0.15 * sin(u_Time * 5.0);
    vec3 tint = vec3(0.72, 0.12, 0.95);

    color.rgb = mix(color.rgb, tint, pulse);
    gl_FragColor = color;
}
