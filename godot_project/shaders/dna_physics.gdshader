shader_type particles;

uniform float cell_radius = 20.0;
uniform float cell_length = 40.0;

// DNA is huge, we don't move it much, just wobble.
// POSITION is passed from the Mesh (the starting Helix).
// We update VELOCITY to 0 but add some noise to vertex?
// GPUParticles3D replaces TRANSFORM every frame if we don't be careful?
// No, Standard behavior is Start then Process.

float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void start() {
	// We are emitting particles at 0,0,0 usually.
	// BUT we want them to form a helix.
	// Particle Shaders control the emission transform.
	// Recreating a specific 10,000 atom helix purely in shader index math is hard.
	
	// APPROACH:
	// We will use "Emit from Mesh" approach provided by Main.gd?
	// If Main.gd generates the mesh into draw_pass_1, effectively we are drawing ONE giant mesh.
	// In that case, we are not using Particles to position them. We are using Particles to *render* them?
	
	// Wait, for Water/Glucose we used 1 Particle = 1 Molecule Mesh.
	// For DNA, it is ONE giant molecule.
	// So we should just emit 1 Particle.
	// And that 1 Particle draws the huge DNA Mesh.
	
	TRANSFORM[3].xyz = vec3(0.0);
	TRANSFORM[0].xyz = vec3(1.0, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, 1.0, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, 1.0);
	VELOCITY = vec3(0.0);
}

void process() {
	// SLight Rotation/Wobble of the whole nucleoid?
	float theta = sin(TIME * 0.5) * 0.05;
	float c = cos(theta);
	float s = sin(theta);
	
	// Apply rotation around Y
	mat3 rot = mat3(
		vec3(c, 0, -s),
		vec3(0, 1, 0),
		vec3(s, 0, c)
	);
	
	// TRANSFORM[0].xyz = rot[0];
	// TRANSFORM[1].xyz = rot[1];
	// TRANSFORM[2].xyz = rot[2];
	
	// Or just do nothing, let it sit there.
}
