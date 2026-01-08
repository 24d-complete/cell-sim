class_name AtomicDefinitions extends RefCounted

# Radius in Angstroms (Visual Scale)
# Color in CPK Standard
# Radius in Angstroms (Visual Scale)
# Color in CPK Standard
# Note: accessed via get_atoms() to allow dynamic scale reference
static func get_atoms() -> Dictionary:
	return {
		"H": {"color": Color(0.95, 0.95, 0.95), "radius": BioScale.R_HYDROGEN}, # H: White
		"C": {"color": Color(0.2, 0.2, 0.2), "radius": BioScale.R_CARBON}, # C: Dark Grey/Black
		"N": {"color": Color(0.1, 0.2, 0.9), "radius": BioScale.R_NITROGEN}, # N: Blue
		"O": {"color": Color(0.9, 0.1, 0.1), "radius": BioScale.R_OXYGEN}, # O: Red
		"P": {"color": Color(1.0, 0.6, 0.0), "radius": BioScale.R_PHOSPHORUS}, # P: Orange
		"S": {"color": Color(0.9, 0.9, 0.2), "radius": BioScale.R_SULFUR} # S: Yellow
	}

# Blueprints are defined in Local Coordinate Space (roughly 1 unit = 1 Angstrom for convenience)
# We will scale these by BioScale.ANGSTROM when generating meshes.
static func get_molecules() -> Dictionary:
	return {
		"Water": [
			{"type": "O", "pos": Vector3(0, 0, 0)},
			{"type": "H", "pos": Vector3(0.96, -0.24, 0)}, # 0.96 A bond length approx
			{"type": "H", "pos": Vector3(-0.96, -0.24, 0)}
		],
		"Glucose": _generate_glucose_ring(),
		"AminoAcid": [
			{"type": "N", "pos": Vector3(-1.4, 0, 0)},
			{"type": "H", "pos": Vector3(-1.4, 1.0, 0)},
			{"type": "C", "pos": Vector3(0, 0, 0)}, # Alpha
			{"type": "H", "pos": Vector3(0, 1.0, 0)},
			{"type": "C", "pos": Vector3(1.4, 0, 0)}, # Carboxyl
			{"type": "O", "pos": Vector3(1.4, 1.2, 0)}, # Double bond
			{"type": "O", "pos": Vector3(2.4, -0.6, 0)}
		],
		"Nucleotide": [
			# Phosphate
			{"type": "P", "pos": Vector3(-2, 0, 0)},
			{"type": "O", "pos": Vector3(-2, 1.2, 0)},
			{"type": "O", "pos": Vector3(-3, -0.5, 0.5)},
			# Sugar (Ribose-like ring simplified)
			{"type": "C", "pos": Vector3(0, 0, 0)},
			{"type": "C", "pos": Vector3(1, 0.5, 0)},
			{"type": "O", "pos": Vector3(0.5, -0.5, 0)},
			# Base (Generic Purine/Pyrimidine blob)
			{"type": "N", "pos": Vector3(1.5, 1.5, 0)},
			{"type": "C", "pos": Vector3(2.5, 2.0, 0)},
			{"type": "N", "pos": Vector3(3.0, 1.0, 0)}
		],
		"Phospholipid": [
			# Hydrophilic Head (Polar)
			{"type": "P", "pos": Vector3(0, 0, 0)},
			{"type": "O", "pos": Vector3(0, 1.0, 0)},
			{"type": "O", "pos": Vector3(1.0, -0.5, 0)},
			{"type": "N", "pos": Vector3(-1.0, -0.5, 0)}, # Choline bit
			# Hydrophobic Tails (Non-polar Carbon Chains)
			# Tail 1
			{"type": "C", "pos": Vector3(0.5, -1.5, 0)},
			{"type": "C", "pos": Vector3(0.8, -2.5, 0.2)},
			{"type": "C", "pos": Vector3(0.5, -3.5, 0)},
			{"type": "C", "pos": Vector3(0.8, -4.5, 0.2)},
			{"type": "C", "pos": Vector3(0.5, -5.5, 0)},
			# Tail 2
			{"type": "C", "pos": Vector3(-0.5, -1.5, 0)},
			{"type": "C", "pos": Vector3(-0.8, -2.5, -0.2)},
			{"type": "C", "pos": Vector3(-0.5, -3.5, 0)},
			{"type": "C", "pos": Vector3(-0.8, -4.5, -0.2)},
			{"type": "C", "pos": Vector3(-0.5, -5.5, 0)}
		]
	}

static func _generate_glucose_ring() -> Array:
	var atoms = []
	for i in range(6):
		var angle = i * PI / 3.0
		var x = cos(angle) * 1.5
		var z = sin(angle) * 1.5
		# Carbon Ring
		atoms.append({"type": "C", "pos": Vector3(x, 0, z)})
		# Hydroxyls / Hydrogens (simplified visual layout)
		atoms.append({"type": "O", "pos": Vector3(x * 1.4, (i % 2) * 0.5, z * 1.4)})
		atoms.append({"type": "H", "pos": Vector3(x * 1.6, (i % 2) * 0.5, z * 1.6)})
	return atoms
