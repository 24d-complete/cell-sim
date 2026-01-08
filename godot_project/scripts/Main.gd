extends Node3D

@onready var camera = $Camera3D

# UI Nodes
@onready var loading_layer = $LoadingLayer
@onready var status_label = $LoadingLayer/CenterContainer/VBox/StatusLabel
@onready var progress_bar = $LoadingLayer/CenterContainer/VBox/ProgressBar
@onready var log_label = $LoadingLayer/CenterContainer/VBox/LogLabel

# Preload LOD classes (workaround for class_name registration timing)
const MoleculeLODScript = preload("res://scripts/MoleculeLOD.gd")
const LODConfigScript = preload("res://scripts/LODConfig.gd")

# LOD System
var lod_shader: Shader = null

# Chunked DNA storage
# chunks[chunk_idx] = {center: Vector3, instances: Array[4 MeshInstance3D], current_lod: int}
var dna_chunks: Array = []
var dna_container: Node3D = null

var cam_distance = 45.0 # View Further out
var cam_rot_x = 0.0
var cam_rot_y = 0.0
var cam_offset = Vector3.ZERO
var is_ready = false

# Configuration
const BASE_PAIRS = 3000
const CHUNK_SIZE = BioScale.CHUNK_BP_SIZE # 100 bp per chunk
var NUM_CHUNKS: int

# LOD thresholds (distance in nm)
var lod_thresholds = [50.0, 150.0, 500.0] # 3 thresholds for 4 LODs

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Keep visible during load
	lod_shader = preload("res://shaders/lod_transition.gdshader")
	NUM_CHUNKS = ceili(float(BASE_PAIRS) / float(CHUNK_SIZE))
	_async_init()

func _async_init():
	var molecules = AtomicDefinitions.get_molecules()
	
	_log("Initializing Atomic Database...")
	await get_tree().process_frame
	
	# Create container for all DNA chunks
	dna_container = Node3D.new()
	dna_container.name = "DNAChunks"
	add_child(dna_container)
	
	# Generate chunked DNA with LOD
	_log("Synthesizing Chunked Plasmid (%d bp, %d chunks)..." % [BASE_PAIRS, NUM_CHUNKS])
	await _generate_chunked_dna(molecules["Nucleotide"])
	
	_log("[color=green]Initialization Complete.[/color]")
	status_label.text = "Simulation Ready"
	progress_bar.value = 100
	await get_tree().create_timer(0.5).timeout
	
	# Fade out UI
	var tween = create_tween()
	tween.tween_property(loading_layer, "modulate:a", 0.0, 1.0)
	tween.tween_callback(loading_layer.queue_free)
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	is_ready = true

func _generate_chunked_dna(nucleotide_atoms: Array) -> void:
	# LOD level configurations - 4 levels
	var lod_configs = [
		{"segments": 6, "rings": 4, "bond_segs": 4, "skip_h": false, "blur": 0.0}, # LOD 0: High
		{"segments": 4, "rings": 3, "bond_segs": 3, "skip_h": true, "blur": 0.0}, # LOD 1: Medium
		{"segments": 2, "rings": 2, "bond_segs": 2, "skip_h": true, "blur": 0.3}, # LOD 2: Low
		{"segments": 1, "rings": 1, "bond_segs": 0, "skip_h": true, "blur": 0.6}, # LOD 3: Ultra-Low
	]
	
	# Ensure cache directory exists
	var cache_dir = "res://lod_cache"
	if not DirAccess.dir_exists_absolute(cache_dir):
		var err = DirAccess.make_dir_absolute(cache_dir)
		if err != OK:
			print("Error creating cache dir: ", err)
	
	# Precompute shared geometry templates
	var geometry_templates = _create_geometry_templates(lod_configs)
	
	# Supercoiled Plasmid Parameters
	var major_radius = 40.0 * BioScale.NM
	var minor_radius = 8.0 * BioScale.NM
	var coils = 16.0
	
	# Generate each chunk
	for chunk_idx in range(NUM_CHUNKS):
		var start_bp = chunk_idx * CHUNK_SIZE
		var end_bp = min(start_bp + CHUNK_SIZE, BASE_PAIRS)
		
		# Calculate chunk center position (midpoint of segment)
		var mid_bp = (start_bp + end_bp) / 2.0
		var mid_t = mid_bp / float(BASE_PAIRS) * TAU
		var mid_coil = mid_t * coils
		var mid_cx = (major_radius + minor_radius * cos(mid_coil)) * cos(mid_t)
		var mid_cz = (major_radius + minor_radius * cos(mid_coil)) * sin(mid_t)
		var mid_cy = minor_radius * sin(mid_coil)
		var chunk_center = Vector3(mid_cx, mid_cy, mid_cz)
		
		# Create chunk data structure
		var chunk_data = {
			"center": chunk_center,
			"instances": [],
			"current_lod": 0
		}
		
		# Create container for this chunk's LOD meshes
		var chunk_node = Node3D.new()
		chunk_node.name = "Chunk_%d" % chunk_idx
		dna_container.add_child(chunk_node)
		
		# Generate/load meshes for each LOD level
		for lod_idx in range(lod_configs.size()):
			var config = lod_configs[lod_idx]
			var cache_file = "dna_v6_chunk%d_lod%d.res" % [chunk_idx, lod_idx]
			var cache_path = cache_dir + "/" + cache_file
			var mesh: ArrayMesh
			
			# Update progress
			var total_items = NUM_CHUNKS * lod_configs.size()
			var current_item = chunk_idx * lod_configs.size() + lod_idx
			var progress = float(current_item) / float(total_items) * 100.0
			progress_bar.value = progress
			status_label.text = "Chunk %d/%d, LOD %d" % [chunk_idx + 1, NUM_CHUNKS, lod_idx]
			
			# Check cache
			if FileAccess.file_exists(cache_path):
				mesh = ResourceLoader.load(cache_path)
			else:
				# Generate mesh for this chunk and LOD
				await get_tree().process_frame
				mesh = await _create_chunk_mesh(
					nucleotide_atoms,
					start_bp, end_bp,
					config,
					geometry_templates[lod_idx],
					major_radius, minor_radius, coils
				)
				
				# Save to cache
				var err = ResourceSaver.save(mesh, cache_path)
				if err != OK:
					print("Failed to save mesh to cache: ", err)
			
			# Create MeshInstance3D for this LOD
			var instance = MeshInstance3D.new()
			instance.mesh = mesh
			instance.visible = (lod_idx == 0) # Only LOD 0 visible initially
			
			# Apply material
			if lod_idx == 0:
				var mat = StandardMaterial3D.new()
				mat.vertex_color_use_as_albedo = true
				mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
				mat.roughness = 0.3
				mat.rim_enabled = true
				mat.rim = 0.5
				instance.material_override = mat
			else:
				var mat = ShaderMaterial.new()
				mat.shader = lod_shader
				mat.set_shader_parameter("blur_amount", config["blur"])
				mat.set_shader_parameter("blur_start", lod_thresholds[0])
				mat.set_shader_parameter("blur_end", lod_thresholds[lod_idx - 1] if lod_idx > 0 else 1000.0)
				instance.material_override = mat
			
			chunk_node.add_child(instance)
			chunk_data["instances"].append(instance)
		
		dna_chunks.append(chunk_data)
		
		# Yield periodically to prevent freezing
		if chunk_idx % 5 == 0:
			await get_tree().process_frame

func _create_geometry_templates(lod_configs: Array) -> Array:
	# Pre-generate sphere and bond mesh arrays for each LOD level
	var templates = []
	for config in lod_configs:
		var sphere = SphereMesh.new()
		sphere.radial_segments = config["segments"]
		sphere.rings = config["rings"]
		var s_arrays = sphere.get_mesh_arrays()
		
		var bond = CylinderMesh.new()
		bond.top_radius = 1.0
		bond.bottom_radius = 1.0
		bond.height = 1.0
		bond.radial_segments = max(config["bond_segs"], 2)
		bond.rings = 1
		var b_arrays = bond.get_mesh_arrays()
		
		templates.append({
			"s_verts": s_arrays[Mesh.ARRAY_VERTEX],
			"s_norms": s_arrays[Mesh.ARRAY_NORMAL],
			"s_inds": s_arrays[Mesh.ARRAY_INDEX],
			"b_verts": b_arrays[Mesh.ARRAY_VERTEX],
			"b_norms": b_arrays[Mesh.ARRAY_NORMAL],
			"b_inds": b_arrays[Mesh.ARRAY_INDEX],
			"skip_h": config["skip_h"],
			"bond_segs": config["bond_segs"]
		})
	return templates

func _create_chunk_mesh(nucleotide_atoms: Array, start_bp: int, end_bp: int, config: Dictionary, geom: Dictionary, major_radius: float, minor_radius: float, coils: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var s_verts = geom["s_verts"]
	var s_norms = geom["s_norms"]
	var s_inds = geom["s_inds"]
	var b_verts = geom["b_verts"]
	var b_norms = geom["b_norms"]
	var b_inds = geom["b_inds"]
	var skip_h = geom["skip_h"]
	var bond_segs = geom["bond_segs"]
	
	var current_verts = 0
	
	# Filter atoms based on LOD
	var filtered_atoms = nucleotide_atoms
	if skip_h:
		filtered_atoms = nucleotide_atoms.filter(func(a): return a["type"] != "H")
	
	for i in range(start_bp, end_bp):
		var t = float(i) / float(BASE_PAIRS) * TAU
		var coil_angle = t * coils
		var u = t
		var v = coil_angle
		
		# Torus pos
		var cx = (major_radius + minor_radius * cos(v)) * cos(u)
		var cz = (major_radius + minor_radius * cos(v)) * sin(u)
		var cy = minor_radius * sin(v)
		var center_pos = Vector3(cx, cy, cz)
		
		# Orientation (Tangent)
		var next_u = u + 0.01
		var next_v = v + (0.01 * coils)
		var nx = (major_radius + minor_radius * cos(next_v)) * cos(next_u)
		var nz = (major_radius + minor_radius * cos(next_v)) * sin(next_u)
		var ny = minor_radius * sin(next_v)
		var forward = (Vector3(nx, ny, nz) - center_pos).normalized()
		var right = forward.cross(Vector3.UP).normalized()
		var up_vec = right.cross(forward).normalized()
		var orientation = Basis(right, up_vec, forward)
		
		# Helix Properties
		var helix_angle = i * BioScale.DNA_TWIST_PER_BP
		var helix_rot = Basis(Vector3(0, 0, 1), helix_angle)
		var helix_radius = BioScale.DNA_HELIX_RADIUS
		
		var pos1 = center_pos + (orientation * (helix_rot * Vector3(helix_radius, 0, 0)))
		var pos2 = center_pos + (orientation * (helix_rot * Vector3(-helix_radius, 0, 0)))
		
		# Nucleotides with LOD consideration
		if bond_segs > 0:
			current_verts = _add_atoms_plus_bonds_lod(st, filtered_atoms, pos1, orientation * helix_rot, s_verts, s_norms, s_inds, b_verts, b_norms, b_inds, current_verts)
			current_verts = _add_atoms_plus_bonds_lod(st, filtered_atoms, pos2, orientation * helix_rot * Basis(Vector3(0, 0, 1), PI), s_verts, s_norms, s_inds, b_verts, b_norms, b_inds, current_verts)
		else:
			# Ultra-low LOD: just atoms, no bonds
			current_verts = _add_atoms_only(st, filtered_atoms, pos1, orientation * helix_rot, s_verts, s_norms, s_inds, current_verts)
			current_verts = _add_atoms_only(st, filtered_atoms, pos2, orientation * helix_rot * Basis(Vector3(0, 0, 1), PI), s_verts, s_norms, s_inds, current_verts)
	
	st.generate_normals()
	return st.commit()

func _add_atoms_plus_bonds_lod(st, atoms, center, orient, sv, sn, si, bv, bn, bi, v_off):
	var atom_db = AtomicDefinitions.get_atoms()
	var atom_positions = []
	
	for atom in atoms:
		var local_pos_nm = atom["pos"] * BioScale.ANGSTROM
		var final_pos = center + (orient * local_pos_nm)
		atom_positions.append(final_pos)
		
		var info = atom_db[atom["type"]]
		var col = info["color"]
		var rad = info["radius"]
		
		var start = v_off
		for k in range(sv.size()):
			st.set_normal(sn[k])
			st.set_color(col)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(sv[k] * rad + final_pos)
			v_off += 1
		for idx in si:
			st.add_index(start + idx)
	
	for i in range(atoms.size()):
		for j in range(i + 1, atoms.size()):
			var dist = atom_positions[i].distance_to(atom_positions[j])
			if dist < 0.6:
				var mid = (atom_positions[i] + atom_positions[j]) * 0.5
				var look = atom_positions[j] - atom_positions[i]
				var rot = Basis(Vector3(0, 1, 0).cross(look).normalized(), Vector3(0, 1, 0).angle_to(look)) if not look.is_normalized() else Basis()
				if look.length() < 0.001:
					rot = Basis()
				var start = v_off
				for k in range(bv.size()):
					var vert = bv[k]
					vert.x *= 0.05
					vert.z *= 0.05
					vert.y *= dist
					st.set_normal(rot * bn[k])
					st.set_color(Color(0.5, 0.5, 0.5))
					st.set_uv(Vector2.ZERO)
					st.add_vertex(mid + (rot * vert))
					v_off += 1
				for idx in bi:
					st.add_index(start + idx)
	return v_off

func _add_atoms_only(st, atoms, center, orient, sv, sn, si, v_off):
	var atom_db = AtomicDefinitions.get_atoms()
	
	for atom in atoms:
		var local_pos_nm = atom["pos"] * BioScale.ANGSTROM
		var final_pos = center + (orient * local_pos_nm)
		
		var info = atom_db[atom["type"]]
		var col = info["color"]
		var rad = info["radius"]
		
		var start = v_off
		for k in range(sv.size()):
			st.set_normal(sn[k])
			st.set_color(col)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(sv[k] * rad + final_pos)
			v_off += 1
		for idx in si:
			st.add_index(start + idx)
	return v_off

func _log(msg: String):
	log_label.append_text("[center]" + msg + "[/center]\n")

func _input(event):
	if not is_ready:
		return
	
	# Visibility Toggles
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_4 and dna_container:
			dna_container.visible = !dna_container.visible
		# Debug: Show chunk LOD info
		if event.keycode == KEY_L:
			_print_chunk_lod_info()

	# Mouse Controls
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_distance -= 2.0
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_distance += 2.0
		cam_distance = clamp(cam_distance, 5.0, 150.0)

	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			cam_rot_x -= event.relative.y * 0.005
			cam_rot_y -= event.relative.x * 0.005
			cam_rot_x = clamp(cam_rot_x, -1.5, 1.5)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			var pan_speed = cam_distance * 0.001
			var forward = Vector3(0, 0, -1).rotated(Vector3.RIGHT, cam_rot_x).rotated(Vector3.UP, cam_rot_y)
			var right = Vector3(1, 0, 0).rotated(Vector3.RIGHT, cam_rot_x).rotated(Vector3.UP, cam_rot_y)
			var up = right.cross(forward)
			cam_offset += (-right * event.relative.x + up * event.relative.y) * pan_speed

func _print_chunk_lod_info():
	var lod_counts = [0, 0, 0, 0]
	for chunk in dna_chunks:
		lod_counts[chunk["current_lod"]] += 1
	print("Chunk LOD Distribution: LOD0=%d, LOD1=%d, LOD2=%d, LOD3=%d" % lod_counts)

func _process(_delta):
	var rot_pos = Vector3(0, 0, cam_distance).rotated(Vector3.RIGHT, cam_rot_x).rotated(Vector3.UP, cam_rot_y)
	if camera:
		camera.position = rot_pos + cam_offset
		camera.look_at(cam_offset)
	
	# Update per-chunk LOD based on camera position
	if is_ready and dna_chunks.size() > 0:
		_update_chunk_lods(camera.global_position)

func _update_chunk_lods(camera_pos: Vector3):
	for chunk in dna_chunks:
		var dist = camera_pos.distance_to(chunk["center"])
		
		# Determine new LOD level based on distance thresholds
		var new_lod = 0
		for i in range(lod_thresholds.size()):
			if dist > lod_thresholds[i]:
				new_lod = i + 1
			else:
				break
		
		# Update visibility if LOD changed
		if new_lod != chunk["current_lod"]:
			var instances = chunk["instances"]
			instances[chunk["current_lod"]].visible = false
			instances[new_lod].visible = true
			chunk["current_lod"] = new_lod
