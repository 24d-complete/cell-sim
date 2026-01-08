class_name MoleculeLOD
extends Node3D

## Generalizable LOD system for large molecules (DNA, proteins, etc.)
## Provides distance-based mesh resolution switching with blur/fade transitions.

signal lod_changed(new_lod: int, old_lod: int)

# LOD Configuration
@export var lod_thresholds: Array = [50.0, 150.0, 500.0] # nm distances
@export var transition_range: float = 10.0 # Blend zone width in nm
@export var use_chunking: bool = false
@export var chunk_size: int = 1000 # Base pairs per chunk (for DNA)

# Internal state
var lod_meshes: Array[ArrayMesh] = []
var lod_instances: Array[MeshInstance3D] = []
var current_lod: int = 0
var camera_ref: Camera3D = null
var molecule_center: Vector3 = Vector3.ZERO

# Chunk management for mega-molecules
var chunks: Dictionary = {} # chunk_id -> {meshes: [], active_lod: int}
var visible_chunk_ids: Array[int] = []

# LOD level definitions
class LODLevel:
	var sphere_segments: int = 6
	var sphere_rings: int = 4
	var bond_segments: int = 4
	var skip_hydrogens: bool = false
	var use_billboard: bool = false
	var blur_amount: float = 0.0
	
	func _init(segs: int = 6, rings: int = 4, bond_segs: int = 4, skip_h: bool = false, billboard: bool = false, blur: float = 0.0):
		sphere_segments = segs
		sphere_rings = rings
		bond_segments = bond_segs
		skip_hydrogens = skip_h
		use_billboard = billboard
		blur_amount = blur

# Default LOD configurations
static var DEFAULT_LOD_LEVELS: Array[LODLevel] = [
	LODLevel.new(6, 4, 4, false, false, 0.0), # LOD 0: Full detail
	LODLevel.new(4, 3, 3, true, false, 0.0), # LOD 1: Medium (no hydrogens)
	LODLevel.new(2, 2, 2, true, false, 0.3), # LOD 2: Low + slight blur
	LODLevel.new(1, 1, 0, true, true, 0.6), # LOD 3: Billboard/blob + blur
]

var lod_levels: Array[LODLevel] = []
var material_template: ShaderMaterial = null


func _ready() -> void:
	# Initialize with default LOD levels if not set
	if lod_levels.is_empty():
		lod_levels = DEFAULT_LOD_LEVELS.duplicate()


func _process(_delta: float) -> void:
	if camera_ref == null or lod_meshes.is_empty():
		return
	
	update_lod(camera_ref.global_position)


## Set the camera reference for distance calculations
func set_camera(cam: Camera3D) -> void:
	camera_ref = cam


## Generate LOD meshes from molecule data
## molecule_data: Array of atom dictionaries from AtomicDefinitions
## base_pairs: Number of base pairs (for DNA) or units (for proteins)
func generate_lod_meshes(molecule_data: Array, base_pairs: int = 1, generate_func: Callable = Callable()) -> void:
	# Clear existing
	for inst in lod_instances:
		inst.queue_free()
	lod_instances.clear()
	lod_meshes.clear()
	
	# Generate mesh for each LOD level
	for i in range(lod_levels.size()):
		var lod = lod_levels[i]
		var mesh: ArrayMesh
		
		if generate_func.is_valid():
			# Use custom generation function (assumes it returns ArrayMesh directly)
			mesh = generate_func.call(molecule_data, base_pairs, lod)
			if mesh is ArrayMesh:
				pass # Already have the mesh
		else:
			# Default: use internal DNA generation
			mesh = _generate_default_mesh(molecule_data, base_pairs, lod)
		
		lod_meshes.append(mesh)
		
		# Create MeshInstance3D for this LOD
		var instance = MeshInstance3D.new()
		instance.mesh = mesh
		instance.visible = (i == 0) # Only show LOD 0 initially
		
		# Apply material with blur support
		if material_template != null:
			var mat = material_template.duplicate()
			mat.set_shader_parameter("blur_amount", lod.blur_amount)
			instance.material_override = mat
		else:
			# Fallback to vertex color material
			var mat = StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.roughness = 0.3
			instance.material_override = mat
		
		add_child(instance)
		lod_instances.append(instance)
	
	current_lod = 0


## Update LOD based on camera distance
func update_lod(camera_pos: Vector3) -> void:
	var distance = camera_pos.distance_to(global_position + molecule_center)
	var new_lod = _get_lod_for_distance(distance)
	
	if new_lod != current_lod:
		_switch_lod(new_lod)


## Calculate appropriate LOD level for distance
func _get_lod_for_distance(distance: float) -> int:
	for i in range(lod_thresholds.size()):
		if distance < lod_thresholds[i]:
			return i
	return lod_thresholds.size() # Furthest LOD


## Switch between LOD levels
func _switch_lod(new_lod: int) -> void:
	var old_lod = current_lod
	
	# Hide old, show new
	if old_lod < lod_instances.size():
		lod_instances[old_lod].visible = false
	
	if new_lod < lod_instances.size():
		lod_instances[new_lod].visible = true
	
	current_lod = new_lod
	lod_changed.emit(new_lod, old_lod)


## Generate default mesh (simple sphere blobs for now)
func _generate_default_mesh(molecule_data: Array, _base_pairs: int, lod: LODLevel) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Create sphere template with LOD-appropriate detail
	var sphere = SphereMesh.new()
	sphere.radial_segments = lod.sphere_segments
	sphere.rings = lod.sphere_rings
	var s_arrays = sphere.get_mesh_arrays()
	var s_verts = s_arrays[Mesh.ARRAY_VERTEX]
	var s_norms = s_arrays[Mesh.ARRAY_NORMAL]
	var s_inds = s_arrays[Mesh.ARRAY_INDEX]
	
	var atom_db = AtomicDefinitions.get_atoms()
	var v_offset = 0
	
	for atom in molecule_data:
		# Skip hydrogens at low LOD
		if lod.skip_hydrogens and atom["type"] == "H":
			continue
		
		var local_pos = atom["pos"] * BioScale.ANGSTROM
		var info = atom_db[atom["type"]]
		var col = info["color"]
		var rad = info["radius"]
		
		var start = v_offset
		for k in range(s_verts.size()):
			st.set_normal(s_norms[k])
			st.set_color(col)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(s_verts[k] * rad + local_pos)
			v_offset += 1
		
		for idx in s_inds:
			st.add_index(start + idx)
	
	st.generate_normals()
	return st.commit()


# ============================================================================
# CHUNKING SYSTEM FOR MEGA-MOLECULES
# ============================================================================

## Initialize chunked molecule (for nucleoid DNA, large proteins, etc.)
func init_chunked_molecule(total_units: int, _chunk_gen_func: Callable) -> void:
	use_chunking = true
	chunks.clear()
	
	var num_chunks = ceili(float(total_units) / float(chunk_size))
	
	for chunk_id in range(num_chunks):
		var start_unit = chunk_id * chunk_size
		var end_unit = mini(start_unit + chunk_size, total_units)
		
		chunks[chunk_id] = {
			"start": start_unit,
			"end": end_unit,
			"meshes": [], # Populated on demand
			"instances": [],
			"active_lod": - 1, # Not loaded
			"loaded": false
		}


## Update chunks based on camera position (frustum culling + LOD)
func update_chunks(camera_pos: Vector3, viewport: Viewport) -> void:
	if not use_chunking:
		return
	
	var cam = viewport.get_camera_3d()
	if cam == null:
		return
	
	# Simple distance-based chunk loading for now
	# TODO: Add proper frustum culling
	for chunk_id in chunks:
		var chunk = chunks[chunk_id]
		var chunk_center = _get_chunk_center(chunk_id)
		var distance = camera_pos.distance_to(chunk_center)
		
		var target_lod = _get_lod_for_distance(distance)
		
		# Load/unload based on distance
		if distance < lod_thresholds[lod_thresholds.size() - 1] * 2.0:
			if not chunk["loaded"]:
				_load_chunk(chunk_id)
			if chunk["active_lod"] != target_lod:
				_set_chunk_lod(chunk_id, target_lod)
		else:
			if chunk["loaded"]:
				_unload_chunk(chunk_id)


## Get estimated center position of a chunk
func _get_chunk_center(chunk_id: int) -> Vector3:
	# Override this for specific molecule types
	# Default: evenly distribute along Y axis
	var chunk = chunks[chunk_id]
	var t = float(chunk["start"] + chunk["end"]) / 2.0
	return global_position + Vector3(0, t * 0.1, 0)


## Load chunk meshes into memory
func _load_chunk(chunk_id: int) -> void:
	var chunk = chunks[chunk_id]
	chunk["loaded"] = true
	# Actual mesh generation would be triggered here
	# Using a callback or deferred generation


## Unload chunk to free memory
func _unload_chunk(chunk_id: int) -> void:
	var chunk = chunks[chunk_id]
	for inst in chunk["instances"]:
		inst.queue_free()
	chunk["instances"].clear()
	chunk["meshes"].clear()
	chunk["loaded"] = false
	chunk["active_lod"] = -1


## Set LOD level for a specific chunk
func _set_chunk_lod(chunk_id: int, lod_level: int) -> void:
	var chunk = chunks[chunk_id]
	
	# Hide current LOD
	if chunk["active_lod"] >= 0 and chunk["active_lod"] < chunk["instances"].size():
		chunk["instances"][chunk["active_lod"]].visible = false
	
	# Show new LOD
	if lod_level < chunk["instances"].size():
		chunk["instances"][lod_level].visible = true
	
	chunk["active_lod"] = lod_level


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

## Get current LOD level
func get_current_lod() -> int:
	return current_lod


## Get total number of LOD levels
func get_lod_count() -> int:
	return lod_levels.size()


## Check if using chunked mode
func is_chunked() -> bool:
	return use_chunking


## Get loaded chunk count (for debugging)
func get_loaded_chunk_count() -> int:
	var count = 0
	for chunk_id in chunks:
		if chunks[chunk_id]["loaded"]:
			count += 1
	return count
