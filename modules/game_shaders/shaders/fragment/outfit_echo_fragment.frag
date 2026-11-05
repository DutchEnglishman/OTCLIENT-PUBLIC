uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_Position;
uniform sampler2D u_Tex0;
uniform float u_Time;

// CONFIG
float desaturate = 0.4;
vec3 tint = vec3(0.70, 0.85, 0.95);
float tintAmount = 0.18;
float alphaBase = 0.72;
float alphaPulse = 0.06;
float pulseSpeed = 1.6;
float rippleSpacing = 22.0;
float rippleSpeed = 9.0;
float rippleStrength = 0.10;
// CONFIG END

void main()
{
    gl_FragColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    if(texcolor.r > 0.9) {
        gl_FragColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        gl_FragColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        gl_FragColor *= u_Color[3];
    }
    if(gl_FragColor.a < 0.01) discard;

    float grey = dot(gl_FragColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 rgb = mix(gl_FragColor.rgb, vec3(grey), desaturate);
    rgb = mix(rgb, tint * max(grey, 0.25), tintAmount);

    float band = mod(v_Position.y + u_Time * rippleSpeed, rippleSpacing) / rippleSpacing;
    rgb *= 1.0 + rippleStrength * smoothstep(0.0, 0.15, band) * (1.0 - smoothstep(0.15, 0.3, band));

    gl_FragColor.rgb = rgb;
    gl_FragColor.a *= alphaBase + alphaPulse * sin(u_Time * pulseSpeed);
}
