uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    if (color.a < 0.01)
        discard;

    float frost =
        0.5 + 0.5 * sin(v_TexCoord.x * 34.0 + v_TexCoord.y * 22.0 + u_Time);

    vec3 ice = vec3(0.45, 0.82, 1.0);
    color.rgb = mix(color.rgb, ice, 0.48);
    color.rgb += vec3(0.25, 0.55, 0.75) * frost * 0.22;

    gl_FragColor = color;
}
