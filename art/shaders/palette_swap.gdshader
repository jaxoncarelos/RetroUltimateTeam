shader_type canvas_item;
// Swaps the template's key colors for team colors. One sprite sheet serves every team.
// Keys (see tools/gen_player_sprites.gd): full-intensity keys are the base color, the
// half-intensity twin (e.g. 800000) is its shade; 8080FF is the helmet shine, 00FFFF the
// helmet stripe, 808080 the facemask and FF80FF the eye line behind it (skin, tinted by a visor).

uniform vec4 primary : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec4 secondary : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 helmet : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec4 pants : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 skin : source_color = vec4(0.55, 0.36, 0.24, 1.0);
uniform vec4 stripe : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 mask : source_color = vec4(0.72, 0.73, 0.76, 1.0);
// Visor over the eye line: alpha 0 = none, ~0.4 = clear, 1 = tinted.
uniform vec4 visor : source_color = vec4(0.1, 0.1, 0.12, 0.0);
uniform vec4 flash : source_color = vec4(1.0, 1.0, 1.0, 0.0);

bool is_key(vec3 c, vec3 key) {
	return distance(c, key) < 0.08;
}

vec3 shade(vec3 c) {
	// Darker and slightly cooler; keeps near-black colors distinguishable.
	return c * vec3(0.66, 0.66, 0.74) + vec3(0.02, 0.02, 0.05);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 rgb = c.rgb;
	if (is_key(rgb, vec3(1.0, 0.0, 0.0))) rgb = primary.rgb;
	else if (is_key(rgb, vec3(0.5, 0.0, 0.0))) rgb = shade(primary.rgb);
	else if (is_key(rgb, vec3(0.0, 1.0, 0.0))) rgb = secondary.rgb;
	else if (is_key(rgb, vec3(0.0, 0.5, 0.0))) rgb = shade(secondary.rgb);
	else if (is_key(rgb, vec3(0.0, 0.0, 1.0))) rgb = helmet.rgb;
	else if (is_key(rgb, vec3(0.0, 0.0, 0.5))) rgb = shade(helmet.rgb);
	else if (is_key(rgb, vec3(0.5, 0.5, 1.0))) rgb = mix(helmet.rgb, vec3(1.0), 0.55);
	else if (is_key(rgb, vec3(0.0, 1.0, 1.0))) rgb = stripe.rgb;
	else if (is_key(rgb, vec3(1.0, 1.0, 0.0))) rgb = pants.rgb;
	else if (is_key(rgb, vec3(0.5, 0.5, 0.0))) rgb = shade(pants.rgb);
	else if (is_key(rgb, vec3(1.0, 0.5, 1.0))) rgb = mix(skin.rgb, visor.rgb, visor.a);
	else if (is_key(rgb, vec3(1.0, 0.0, 1.0))) rgb = skin.rgb;
	else if (is_key(rgb, vec3(0.5, 0.0, 0.5))) rgb = shade(skin.rgb);
	else if (is_key(rgb, vec3(0.5, 0.5, 0.5))) rgb = mask.rgb;
	rgb = mix(rgb, flash.rgb, flash.a);
	COLOR = vec4(rgb, c.a);
}
