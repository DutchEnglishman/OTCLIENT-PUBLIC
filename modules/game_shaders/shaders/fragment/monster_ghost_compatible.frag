uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec4 base = texture2D(u_Tex0, v_TexCoord);
    vec4 blur = vec4(0.0);

    blur += texture2D(u_Tex0, v_TexCoord + vec2( 0.012,  0.000));
    blur += texture2D(u_Tex0, v_TexCoord + vec2(-0.012,  0.000));
    blur += texture2D(u_Tex0, v_TexCoord + vec2( 0.000,  0.012));
    blur += texture2D(u_Tex0, v_TexCoord + vec2( 0.000, -0.012));
    blur *= 0.25;

    vec4 color = mix(base, blur, 0.45);
    color.rgb = mix(color.rgb, vec3(0.65, 0.85, 1.0), 0.32);
    color.a *= 0.72 + sin(u_Time * 3.0) * 0.08;

    if (color.a < 0.01)
        discard;

    gl_FragColor = color;
}
