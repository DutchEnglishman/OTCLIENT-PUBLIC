uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    if (color.a < 0.01)
        discard;

    float veins =
        sin((v_TexCoord.x * 19.0 + v_TexCoord.y * 31.0) + u_Time * 2.0) *
        sin((v_TexCoord.x * 37.0 - v_TexCoord.y * 13.0) - u_Time * 1.4);

    veins = smoothstep(0.35, 0.9, veins);
    color.rgb = mix(color.rgb, vec3(0.32, 0.0, 0.0), 0.48);
    color.rgb += vec3(0.75, 0.0, 0.0) * veins * 0.45;

    gl_FragColor = color;
}
