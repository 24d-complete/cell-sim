class_name BioScale
extends RefCounted

# SYSTEM STANDARD: 1 GODOT UNIT = 1 NANOMETER (nm)

const NM: float = 1.0
const ANGSTROM: float = 0.1 * NM
const MICRON: float = 1000.0 * NM

# ATOMIC VdW RADII (in Nanometers)
const R_HYDROGEN: float = 0.12 * NM
const R_CARBON: float = 0.17 * NM
const R_NITROGEN: float = 0.155 * NM
const R_OXYGEN: float = 0.152 * NM
const R_PHOSPHORUS: float = 0.18 * NM
const R_SULFUR: float = 0.18 * NM

# STRUCTURES
const DNA_HELIX_DIAMETER: float = 2.0 * NM
const DNA_HELIX_RADIUS: float = 1.0 * NM
const DNA_RISE_PER_BP: float = 0.34 * NM
const DNA_TWIST_PER_BP: float = deg_to_rad(34.3)

const MEMBRANE_THICKNESS: float = 5.0 * NM

# E. COLI DIMENSIONS
const CELL_WIDTH: float = 500.0 * NM
const CELL_LENGTH: float = 2000.0 * NM

# LOD DISTANCE THRESHOLDS (nm)
const LOD_HIGH_THRESHOLD: float = 50.0 * NM
const LOD_MED_THRESHOLD: float = 150.0 * NM
const LOD_LOW_THRESHOLD: float = 500.0 * NM

# MEGA-MOLECULE PARAMETERS
const NUCLEOID_BP_COUNT: int = 4_600_000
const CHUNK_BP_SIZE: int = 10_000 # ~460 chunks for nucleoid
