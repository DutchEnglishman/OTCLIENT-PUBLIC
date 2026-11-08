uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

const float GRID = 20.0;
const float BODY_ASPECT = 0.75;

vec2 q(vec2 uv, vec2 centre) {
    return (uv - centre) * vec2(BODY_ASPECT, 1.0);
}

float star(vec2 p, float r) {
    float seg = 6.2831853 / 5.0;
    float a = atan(p.x, -p.y);
    a = mod(a + seg * 0.5, seg) - seg * 0.5;
    float d = length(p);
    vec2 o = vec2(0.0, r);
    vec2 i = vec2(sin(seg * 0.5), cos(seg * 0.5)) * r * 0.382;
    vec2 w = vec2(abs(sin(a)), cos(a)) * d - o;
    vec2 e = i - o;
    return (e.x * w.y - e.y * w.x) <= 0.0 ? 1.0 : 0.0;
}
vec3 flagColor(vec2 uv) {
    if (uv.x < 1.0 / 3.0)
        return vec3(0.0, 0.57, 0.27);
    if (uv.x < 2.0 / 3.0)
        return vec3(1.0);
    return vec3(0.81, 0.17, 0.21);
}
void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a < 0.01)
        discard;

    vec2 lo = vec2(1.0);
    vec2 hi = vec2(0.0);
    for (int i = 0; i < 20; i++) {
        for (int j = 0; j < 20; j++) {
            vec2 p = (vec2(float(i), float(j)) + 0.5) / GRID;
            if (texture2D(u_Tex0, p).a > 0.5) {
                lo = min(lo, p);
                hi = max(hi, p);
            }
        }
    }
    lo -= 0.5 / GRID;
    hi += 0.5 / GRID;

    vec2 uv = (v_TexCoord - lo) / max(hi - lo, vec2(0.001));
    uv.y = 1.0 - uv.y;

    float wave = sin(uv.x * 7.0 - u_Time * 3.0 + uv.y * 2.0);
    uv.y += wave * 0.035;
    vec3 flag = flagColor(clamp(uv, 0.0, 1.0));

    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    float shade = 0.45 + 0.75 * lum + wave * 0.07;
    float sheen = smoothstep(0.93, 1.0, sin((uv.x + uv.y) * 3.0 - u_Time * 1.6)) * 0.22;

    gl_FragColor = vec4(clamp(flag * shade + sheen, 0.0, 1.0), col.a);
}