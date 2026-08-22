uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

float rand(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    if (color.a < 0.01)
        discard;

    vec2 grid = floor(v_TexCoord * 18.0);
    float star = step(0.94, rand(grid));
    float twinkle = 0.45 + 0.55 * sin(u_Time * 7.0 + rand(grid) * 6.28318);
    star *= max(twinkle, 0.0);

    color.rgb += vec3(0.75, 0.85, 1.0) * star * 1.4;
    color.rgb = mix(color.rgb, vec3(0.25, 0.18, 0.55) * color.rgb, 0.16);

    gl_FragColor = color;
}
