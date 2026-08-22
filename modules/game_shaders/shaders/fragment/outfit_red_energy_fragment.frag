uniform float u_Depth;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

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

    vec4 effectColor = texture2D(u_Tex1, v_TexCoord3);
	vec4 c = vec4(effectColor.rgb, gl_FragColor.a);
	c.rgb *= vec3(3.0, 0.0, 0.0);
    gl_FragColor.rgb = mix(gl_FragColor.rgb, c.rgb, c.rgb);
	if(gl_FragColor.a < 0.01) discard;
}