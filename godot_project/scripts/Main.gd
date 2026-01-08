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
var dna_lod = null # MoleculeLOD instance
var lod_shader: Shader = null

var cam_distance = 45.0 # View Further out
var cam_rot_x = 0.0
var cam_rot_y = 0.0
var cam_offset = Vector3.ZERO
var is_ready = false

# Configuration
const BASE_PAIRS = 3000

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Keep visible during load
	lod_shader = preload("res://shaders/lod_transition.gdshader")
	_async_init()

func _async_init():
	var molecules = AtomicDefinitions.get_molecules()
	
	_log("Initializing Atomic Database...")
	await get_tree().process_frame
	
	# 1. DNA with LOD System
	_log("Synthesizing Plasmid (%d bp) with LOD..." % BASE_PAIRS)
	
	# Create LOD-enabled DNA node
	dna_lod = MoleculeLODScript.new()
	dna_lod.set_camera(camera)
	
	# Configure LOD thresholds based on molecule size
	var dna_config = LODConfigScript.create_dna_config(BASE_PAIRS)
	dna_lod.lod_thresholds = dna_config.lod_thresholds
	
	# Create LOD material template
	var lod_material = ShaderMaterial.new()
	lod_material.shader = lod_shader
	dna_lod.material_template = lod_material
	
	# Connect LOD change signal for logging
	dna_lod.lod_changed.connect(_on_dna_lod_changed)
	
	add_child(dna_lod)
	
	# Generate meshes for each LOD level
	_log("Generating LOD meshes...")
	await _generate_dna_lod_meshes(molecules["Nucleotide"])
	
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

func _generate_dna_lod_meshes(nucleotide_atoms: Array) -> void:
	# Clear existing LOD meshes
	for child in dna_lod.get_children():
		child.queue_free()
	dna_lod.lod_meshes.clear()
	dna_lod.lod_instances.clear()
	
	# LOD level configurations
	var lod_configs = [
		{"segments": 6, "rings": 4, "bond_segs": 4, "skip_h": false, "blur": 0.0}, # Full
		{"segments": 4, "rings": 3, "bond_segs": 3, "skip_h": true, "blur": 0.0}, # Medium
		{"segments": 2, "rings": 2, "bond_segs": 2, "skip_h": true, "blur": 0.3}, # Low
		{"segments": 1, "rings": 1, "bond_segs": 0, "skip_h": true, "blur": 0.6}, # Ultra-low
	]
	
	# Ensure cache directory exists (using res:// to keep as project assets)
	var cache_dir = "res://lod_cache"
	if not DirAccess.dir_exists_absolute(cache_dir):
		var err = DirAccess.make_dir_absolute(cache_dir)
		if err != OK:
			print("Error creating cache dir: ", err)
		
	for lod_idx in range(lod_configs.size()):
		var config = lod_configs[lod_idx]
		var cache_file = "dna_v3_%d_lod%d.res" % [BASE_PAIRS, lod_idx]
		var cache_path = cache_dir + "/" + cache_file
		var mesh: ArrayMesh
		
		# Check if file exists
		if FileAccess.file_exists(cache_path):
			print("Cache Hit: ", cache_path)
			_log("Loading LOD %d from cache..." % lod_idx)
			status_label.text = "Loading LOD %d / %d (Cached)" % [lod_idx + 1, lod_configs.size()]
			await get_tree().process_frame
			mesh = ResourceLoader.load(cache_path)
		else:
			print("Cache Miss: ", cache_path)
			# Not in cache, generate it
			_log("Generating LOD %d mesh..." % lod_idx)
			status_label.text = "Generating LOD %d / %d" % [lod_idx + 1, lod_configs.size()]
			await get_tree().process_frame
			
			mesh = await _create_dna_helix_lod(
				nucleotide_atoms,
				config["segments"],
				config["rings"],
				config["bond_segs"],
				config["skip_h"]
			)
			
			# Save to cache
			_log("Saving LOD %d to cache..." % lod_idx)
			var err = ResourceSaver.save(mesh, cache_path)
			if err != OK:
				print("Failed to save mesh to cache: ", err)

		
		dna_lod.lod_meshes.append(mesh)
		
		# Create instance
		var instance = MeshInstance3D.new()
		instance.mesh = mesh
		instance.visible = (lod_idx == 0)
		
		# Apply material
		if lod_idx == 0:
			# LOD 0: Use Original StandardMaterial3D for AAA look
			var mat = StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
			mat.roughness = 0.3
			mat.rim_enabled = true
			mat.rim = 0.5
			instance.material_override = mat
		else:
			# LOD 1+: Use Shader for Blur/Fade transitions
			var mat = ShaderMaterial.new()
			mat.shader = lod_shader
			mat.set_shader_parameter("blur_amount", config["blur"])
			mat.set_shader_parameter("blur_start", dna_lod.lod_thresholds[0] if lod_idx > 0 else 1000.0)
			mat.set_shader_parameter("blur_end", dna_lod.lod_thresholds[lod_idx] if lod_idx < dna_lod.lod_thresholds.size() else 1000.0)
			instance.material_override = mat
		
		dna_lod.add_child(instance)
		dna_lod.lod_instances.append(instance)
	
	dna_lod.current_lod = 0

func _create_dna_helix_lod(nucleotide_atoms: Array, sphere_segs: int, sphere_rings: int, bond_segs: int, skip_h: bool) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Geometry caching with LOD-appropriate detail
	var sphere = SphereMesh.new()
	sphere.radial_segments = sphere_segs
	sphere.rings = sphere_rings
	var s_arrays = sphere.get_mesh_arrays()
	var s_verts = s_arrays[Mesh.ARRAY_VERTEX]
	var s_norms = s_arrays[Mesh.ARRAY_NORMAL]
	var s_inds = s_arrays[Mesh.ARRAY_INDEX]
	
	var bond_mesh = CylinderMesh.new()
	bond_mesh.top_radius = 1.0
	bond_mesh.bottom_radius = 1.0
	bond_mesh.height = 1.0
	bond_mesh.radial_segments = max(bond_segs, 2)
	bond_mesh.rings = 1
	var b_arrays = bond_mesh.get_mesh_arrays()
	var b_verts = b_arrays[Mesh.ARRAY_VERTEX]
	var b_norms = b_arrays[Mesh.ARRAY_NORMAL]
	var b_inds = b_arrays[Mesh.ARRAY_INDEX]
	
	var current_verts = 0
	
	# Supercoiled Plasmid Parameters (Using BioScale)
	var major_radius = 40.0 * BioScale.NM
	var minor_radius = 8.0 * BioScale.NM
	var coils = 16.0
	
	# Filter atoms based on LOD
	var filtered_atoms = nucleotide_atoms
	if skip_h:
		filtered_atoms = nucleotide_atoms.filter(func(a): return a["type"] != "H")
	
	for i in range(BASE_PAIRS):
		# Yield every 30 bases to let UI update
		if i % 30 == 0:
			var progress = float(i) / float(BASE_PAIRS)
			progress_bar.value = progress * 100.0
			await get_tree().process_frame
			
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
	
	status_label.text = "Optimizing Buffer..."
	await get_tree().process_frame
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

func _on_dna_lod_changed(new_lod: int, old_lod: int):
	print("DNA LOD changed: %d -> %d" % [old_lod, new_lod])

func _input(event):
	if not is_ready:
		return
	
	# Visibility Toggles
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_4 and dna_lod:
			dna_lod.visible = !dna_lod.visible
		# Debug: Show current LOD
		if event.keycode == KEY_L and dna_lod:
			print("Current LOD: %d, Distance: %.1f" % [dna_lod.get_current_lod(), cam_distance])

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

func _process(_delta):
	var rot_pos = Vector3(0, 0, cam_distance).rotated(Vector3.RIGHT, cam_rot_x).rotated(Vector3.UP, cam_rot_y)
	if camera:
		camera.position = rot_pos + cam_offset
		camera.look_at(cam_offset)
	
	# Update LOD based on camera position
	if dna_lod and is_ready:
		dna_lod.update_lod(camera.global_position)
