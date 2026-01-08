shader_type particles;

uniform float cell_radius = 20.0;
uniform float cell_length = 40.0;
uniform float speed_scale = 1.0;
uniform bool use_cyclosis = false; // Add flow

float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// SDF Capsule
float sdCapsule( vec3 p, vec3 a, vec3 b, float r ) {
	vec3 pa = p - a, ba = b - a;
	float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
	return length( pa - ba*h ) - r;
}

void start() {
	uint seed = uint(INDEX);
	// Start ANYWHERE in the capsule volume
	// Rejection sampling (simple)
	vec3 pos = vec3(0.0);
	for(int i=0; i<5; i++) {
		vec3 p = vec3(
			rand(vec2(float(seed), 1.0 + float(i))) - 0.5,
			rand(vec2(float(seed), 2.0 + float(i))) - 0.5,
			rand(vec2(float(seed), 3.0 + float(i))) - 0.5
		) * vec3(cell_radius * 2.2, cell_length * 1.2, cell_radius * 2.2);
		
		float half_len = cell_length * 0.5;
		if (sdCapsule(p, vec3(0,-half_len,0), vec3(0,half_len,0), cell_radius-0.5) < 0.0) {
			pos = p;
			break;
		}
	}
	TRANSFORM[3].xyz = pos;
	
	// Random Rotation
	vec3 axis = normalize(vec3(rand(vec2(float(seed),4.0)), rand(vec2(float(seed),5.0)), rand(vec2(float(seed),6.0))) - 0.5);
	float angle = rand(vec2(float(seed), 7.0)) * 6.28;
	float c = cos(angle);
	float s = sin(angle);
	float t = 1.0 - c;
	
	mat3 rot = mat3(
		vec3(t*axis.x*axis.x + c, t*axis.x*axis.y - s*axis.z, t*axis.x*axis.z + s*axis.y),
		vec3(t*axis.x*axis.y + s*axis.z, t*axis.y*axis.y + c, t*axis.y*axis.z - s*axis.x),
		vec3(t*axis.x*axis.z - s*axis.y, t*axis.y*axis.z + s*axis.x, t*axis.z*axis.z + c)
	);
	
	TRANSFORM[0].xyz = rot[0];
	TRANSFORM[1].xyz = rot[1];
	TRANSFORM[2].xyz = rot[2];
	
	VELOCITY = vec3(0.0);
}

void process() {
	uint seed = uint(INDEX) + uint(TIME * 60.0);
	vec3 pos = TRANSFORM[3].xyz;
	
	// Brownian
	vec3 noise = vec3(
		rand(vec2(float(seed), 10.0)) - 0.5,
		rand(vec2(float(seed), 11.0)) - 0.5,
		rand(vec2(float(seed), 12.0)) - 0.5
	);
	vec3 force = noise * 50.0 * speed_scale;
	
	// Cyclosis / Streaming (Simple Vortex along Y)
	if (use_cyclosis) {
		vec3 flow = cross(normalize(pos), vec3(0,1,0)) * 20.0;
		force += flow * speed_scale;
	}
	
	vec3 drag = -VELOCITY * 5.0;
	force += drag;
	
	// Boundary
	float half_len = cell_length * 0.5;
	vec3 cap_a = vec3(0, -half_len, 0);
	vec3 cap_b = vec3(0, half_len, 0);
	float dist = sdCapsule(pos, cap_a, cap_b, cell_radius - 0.5);
	
	if (dist > 0.0) {
		force -= normalize(pos) * (dist * 1000.0);
	}
	
	VELOCITY += force * DELTA;
	TRANSFORM[3].xyz += VELOCITY * DELTA;
}
