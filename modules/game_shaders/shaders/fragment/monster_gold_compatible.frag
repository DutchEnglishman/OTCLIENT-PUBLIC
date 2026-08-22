uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    if (color.a < 0.01)
        discard;

    float sweep = 0.5 + 0.5 *
        sin((v_TexCoord.x + v_TexCoord.y) * 18.0 - u_Time * 4.0);

    vec3 goldDark = vec3(0.55, 0.30, 0.02);
    vec3 goldLight = vec3(1.00, 0.82, 0.22);
    vec3 gold = mix(goldDark, goldLight, sweep);

    float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, gold * (0.55 + luminance), 0.68);

    gl_FragColor = color;
}
