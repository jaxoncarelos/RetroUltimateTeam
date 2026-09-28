shader_type canvas_item;
// Swaps the template's key colors for team colors. One sprite sheet serves every team.

uniform vec4 primary : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec4 secondary : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 helmet : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec4 pants : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 skin : source_color = vec4(0.55, 0.36, 0.24, 1.0);
uniform vec4 flash : source_color = vec4(1.0, 1.0, 1.0, 0.0);

bool is_key(vec3 c, vec3 key) {
	return distance(c, key) < 0.08;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 rgb = c.rgb;
	if (is_key(rgb, vec3(1.0, 0.0, 0.0))) rgb = primary.rgb;
	else if (is_key(rgb, vec3(0.0, 1.0, 0.0))) rgb = secondary.rgb;
	else if (is_key(rgb, vec3(0.0, 0.0, 1.0))) rgb = helmet.rgb;
	else if (is_key(rgb, vec3(1.0, 1.0, 0.0))) rgb = pants.rgb;
	else if (is_key(rgb, vec3(1.0, 0.0, 1.0))) rgb = skin.rgb;
	rgb = mix(rgb, flash.rgb, flash.a);
	COLOR = vec4(rgb, c.a);
}
