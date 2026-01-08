shader_type particles;

uniform float cell_radius = 20.0;
uniform float cell_length = 40.0;
uniform float layer_offset = 0.0; // 0 for inner, +something for outer if we did 2 layers

float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void start() {
	uint seed = uint(INDEX);
	
	// Distribute on Capsule Surface
	// Simplified: Cylinder + Caps
	// We use rejection sampling on a bounding box for simplicity of code vs parametric complexity
	
	vec3 pos = vec3(0.0);
	vec3 normal = vec3(0,1,0);
	
	for(int i=0; i<10; i++) {
		// Random point on box surface approx
		// Actually, let's use parametric for Cylinder part and Sphere part based on ratio
		
		float r1 = rand(vec2(float(seed), 1.0 + float(i)));
		float r2 = rand(vec2(float(seed), 2.0 + float(i)));
		
		float h_total = cell_length + (2.0 * cell_radius * 3.14159); // Area weighting approx
		float h_cyl = cell_length;
		
		// This is tricky to get perfect uniformity without complex math.
		// Let's stick to the Physics Rejection method:
		// Spawn in box, normalize to surface.
		
		vec3 p = vec3(
			rand(vec2(float(seed), 3.0 + float(i))) - 0.5,
			rand(vec2(float(seed), 4.0 + float(i))) - 0.5,
			rand(vec2(float(seed), 5.0 + float(i))) - 0.5
		);
		p.y *= (cell_length + cell_radius*2.0) / (cell_radius*2.0); // Stretch Y
		
		// Project to Capsule Surface
		float half_len = cell_length * 0.5;
		vec3 a = vec3(0, -half_len, 0);
		vec3 b = vec3(0, half_len, 0);
		
		vec3 pa = p - a, ba = b - a;
		float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
		vec3 axis_point = a + ba*h;
		
		normal = normalize(p - axis_point);
		pos = axis_point + normal * (cell_radius + layer_offset);
		break; 
	}
	
	TRANSFORM[3].xyz = pos;
	
	// Orient so Up (Y) = Normal
	vec3 up = normal;
	vec3 ref_right = vec3(1,0,0);
	if (abs(dot(up, ref_right)) > 0.9) ref_right = vec3(0,0,1);
	
	vec3 forward = normalize(cross(ref_right, up));
	vec3 right = cross(up, forward);
	
	TRANSFORM[0].xyz = right;
	TRANSFORM[1].xyz = up;
	TRANSFORM[2].xyz = forward;
	
	VELOCITY = vec3(0.0);
}

void process() {
	// Static membrane, maybe slight jitter?
	// TRANSFORM[3].xyz += ...
}
