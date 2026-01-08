class_name LODConfig
extends Resource

## Configuration resource for molecule LOD settings
## Allows per-molecule-type customization of LOD behavior

@export var molecule_type: String = "Generic"
@export var description: String = ""

# Distance thresholds for LOD switching (in nanometers / Godot units)
@export var lod_thresholds: Array = [50.0, 150.0, 500.0]

# Transition settings
@export var transition_duration: float = 0.2 # Seconds for cross-fade
@export var use_blur_transition: bool = true
@export var use_fade_transition: bool = true

# Chunking settings (for mega-molecules)
@export var use_chunking: bool = false
@export var chunk_size: int = 1000 # Units per chunk (base pairs for DNA)

# LOD level configurations
@export var lod_level_configs: Array[Dictionary] = [
	{
		"sphere_segments": 6,
		"sphere_rings": 4,
		"bond_segments": 4,
		"skip_hydrogens": false,
		"blur_amount": 0.0
	},
	{
		"sphere_segments": 4,
		"sphere_rings": 3,
		"bond_segments": 3,
		"skip_hydrogens": true,
		"blur_amount": 0.0
	},
	{
		"sphere_segments": 2,
		"sphere_rings": 2,
		"bond_segments": 2,
		"skip_hydrogens": true,
		"blur_amount": 0.3
	},
	{
		"sphere_segments": 1,
		"sphere_rings": 1,
		"bond_segments": 0,
		"skip_hydrogens": true,
		"blur_amount": 0.6
	}
]


## Create a DNA-optimized LOD config
static func create_dna_config(base_pairs: int) -> LODConfig:
	var config = LODConfig.new()
	config.molecule_type = "DNA"
	config.description = "LOD config for %d bp DNA molecule" % base_pairs
	
	# Adjust thresholds based on molecule size
	var size_factor = sqrt(float(base_pairs) / 3000.0)
	config.lod_thresholds = [50.0 * size_factor, 150.0 * size_factor, 500.0 * size_factor]
	
	# Enable chunking for large DNA
	if base_pairs > 10000:
		config.use_chunking = true
		config.chunk_size = 5000
	
	return config


## Create a protein-optimized LOD config
static func create_protein_config(amino_acids: int) -> LODConfig:
	var config = LODConfig.new()
	config.molecule_type = "Protein"
	config.description = "LOD config for %d AA protein" % amino_acids
	
	# Proteins are generally smaller and denser
	var size_factor = sqrt(float(amino_acids) / 300.0)
	config.lod_thresholds = [30.0 * size_factor, 100.0 * size_factor, 300.0 * size_factor]
	
	# Enable chunking for very large proteins
	if amino_acids > 5000:
		config.use_chunking = true
		config.chunk_size = 1000
	
	return config


## Create nucleoid DNA config (E. coli ~4.6M bp)
static func create_nucleoid_config() -> LODConfig:
	var config = LODConfig.new()
	config.molecule_type = "Nucleoid"
	config.description = "LOD config for E. coli nucleoid (~4.6M bp)"
	
	# Large scale thresholds
	config.lod_thresholds = [200.0, 600.0, 2000.0]
	
	# Must use chunking
	config.use_chunking = true
	config.chunk_size = 10000
	
	return config


## Get LOD level config as Dictionary
func get_lod_level(index: int) -> Dictionary:
	if index >= 0 and index < lod_level_configs.size():
		return lod_level_configs[index]
	return {}


## Get appropriate LOD index for a distance
func get_lod_for_distance(distance: float) -> int:
	for i in range(lod_thresholds.size()):
		if distance < lod_thresholds[i]:
			return i
	return lod_thresholds.size()
