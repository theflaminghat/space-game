extends RefCounted
class_name EvolutionTreeData

static func build() -> Dictionary:
	return {
		"homo_sapiens": {
			"name": "Homo sapiens",
			"subtitle": "Baseline humans",
			"description": "Unmodified planetary humans.",
			"parents": [],
			"pos": Vector2(80, 260)
		},

		"homo_sapiens_orbitalis": {
			"name": "H. sapiens orbitalis",
			"subtitle": "Orbital population",
			"description": "Humans adapted culturally and medically to orbital habitats.",
			"parents": ["homo_sapiens"],
			"pos": Vector2(340, 140)
		},

		"homo_sapiens_martis": {
			"name": "H. sapiens martis",
			"subtitle": "Mars branch",
			"description": "Early human populations permanently established on Mars.",
			"parents": ["homo_sapiens"],
			"pos": Vector2(340, 260)
		},

		"homo_sapiens_gravitus": {
			"name": "H. sapiens gravitus",
			"subtitle": "High-g branch",
			"description": "Humans adapted for high-gravity industrial worlds.",
			"parents": ["homo_sapiens"],
			"pos": Vector2(340, 380)
		},

		"homo_astralis": {
			"name": "Homo astralis",
			"subtitle": "Space-adapted species",
			"description": "A distinctly space-adapted descendant lineage.",
			"parents": ["homo_sapiens_orbitalis"],
			"pos": Vector2(620, 140)
		},

		"homo_pelagicus": {
			"name": "Homo pelagicus",
			"subtitle": "Oceanic branch",
			"description": "Engineered humans adapted for aquatic or ocean worlds.",
			"parents": ["homo_sapiens_martis"],
			"pos": Vector2(620, 260)
		},

		"homo_cyberneticus": {
			"name": "Homo cyberneticus",
			"subtitle": "Cybernetic lineage",
			"description": "Humans with pervasive neural and bodily augmentation.",
			"parents": ["homo_sapiens_orbitalis", "homo_sapiens_gravitus"],
			"pos": Vector2(620, 380)
		},

		"homo_digitalis": {
			"name": "Homo digitalis",
			"subtitle": "Uploaded minds",
			"description": "A digital post-biological lineage derived from human minds.",
			"parents": ["homo_cyberneticus"],
			"pos": Vector2(900, 320)
		},

		"homo_mechanicus_galacticus": {
			"name": "H. mechanicus galacticus",
			"subtitle": "Galactic machine civilization",
			"description": "Machine-descended civilization distributed across galactic scales.",
			"parents": ["homo_digitalis"],
			"pos": Vector2(1180, 320)
		}
	}
