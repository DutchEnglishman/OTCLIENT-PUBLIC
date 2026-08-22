uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    if (color.a < 0.01)
        discard;

    float pulse = 0.55 + 0.45 * sin(u_Time * 6.0);
    float bands = 0.5 + 0.5 *
        sin(v_TexCoord.y * 32.0 - u_Time * 8.0 + sin(v_TexCoord.x * 15.0));

    vec3 energy = vec3(1.0, 0.03, 0.01);
    color.rgb = mix(color.rgb, energy, 0.38 + pulse * 0.22);
    color.rgb += energy * bands * 0.38;

    gl_FragColor = color;
}
