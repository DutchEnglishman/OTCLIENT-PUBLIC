uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

float rand(vec2 p)
{
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
    vec2 uv = v_TexCoord;
    float row = floor(uv.y * 18.0);
    float noise = rand(vec2(row, floor(u_Time * 8.0)));

    if (noise > 0.72) {
        uv.x += (noise - 0.72) * 0.12;
    }

    vec4 color = texture2D(u_Tex0, uv);
    if (color.a < 0.01)
        discard;

    gl_FragColor = color;
}
