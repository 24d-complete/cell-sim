shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// LOD Transition Shader
// Provides blur and fade effects based on camera distance

uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;
uniform float fade_amount : hint_range(0.0, 1.0) = 0.0;
uniform float camera_distance = 0.0;

// Distance-based parameters (set by MoleculeLOD.gd)
uniform float blur_start = 100.0;
uniform float blur_end = 300.0;
uniform float fade_start = 400.0;
uniform float fade_end = 600.0;

// Visual adjustments
uniform float roughness_boost : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	// Pass world position to fragment shader
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	
	// Optional: Slight vertex displacement for blur effect at distance
	if (blur_amount > 0.0) {
		// Add subtle noise-based displacement for organic blur feel
		float noise = sin(VERTEX.x * 10.0 + TIME) * cos(VERTEX.y * 10.0 + TIME * 0.7);
		VERTEX += NORMAL * noise * blur_amount * 0.02;
	}
}

void fragment() {
	// Base color from vertex colors
	vec3 base_color = COLOR.rgb * tint_color.rgb;
	
	// Calculate distance-based effects
	float dist = length(world_position - CAMERA_POSITION_WORLD);
	
	// Dynamic blur calculation (if not using uniform blur_amount)
	float dynamic_blur = clamp((dist - blur_start) / (blur_end - blur_start), 0.0, 1.0);
	float effective_blur = max(blur_amount, dynamic_blur);
	
	// Dynamic fade calculation
	float dynamic_fade = clamp((dist - fade_start) / (fade_end - fade_start), 0.0, 1.0);
	float effective_fade = max(fade_amount, dynamic_fade);
	
	// Apply blur effect
	// Technique: Increase roughness and add slight color averaging
	float final_roughness = mix(0.3, 0.9, effective_blur + roughness_boost);
	
	// Color desaturation for distance (mimics atmospheric perspective)
	vec3 gray = vec3(dot(base_color, vec3(0.299, 0.587, 0.114)));
	vec3 blurred_color = mix(base_color, gray, effective_blur * 0.5);
	
	// Rim lighting for depth perception at distance
	float rim = 1.0 - max(dot(world_normal, normalize(CAMERA_POSITION_WORLD - world_position)), 0.0);
	rim = pow(rim, 2.0) * effective_blur;
	blurred_color += vec3(0.1, 0.15, 0.2) * rim;
	
	ALBEDO = blurred_color;
	ROUGHNESS = final_roughness;
	METALLIC = 0.0;
	
	// Emission for glow effect
	// Boost emission based on color brightness (make lighter atoms glow more like P and N)
	float brightness = max(base_color.r, max(base_color.g, base_color.b));
	EMISSION = base_color * brightness * 1.5 * (1.0 - effective_blur * 0.5);
	
	// Alpha for fade effect
	ALPHA = 1.0 - effective_fade;
	
	// Discard fully faded pixels
	if (ALPHA < 0.01) {
		discard;
	}
}
