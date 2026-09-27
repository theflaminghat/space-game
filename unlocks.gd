class_name BuildingUnlocks

const BUILDING_UNLOCK_REQUIREMENTS := {
	"Solar Farm":      "",
	"Mine":            "",
	# Agriculture is older than the game's start date -- a 1945 civilisation is already farming.
	"Farm":            "",
	"Ranch":           "",
	# Growing food without soil or sunlight is not.
	"Hydroponics Bay": "space_habitation_systems",
	# Terraforming is "modification of a world's atmosphere, temperature and surface chemistry
	# to support life" — a field held at its own climate is that, one envelope at a time.
	"Climate-Controlled Farm": "terraforming",
	# Cryogenic air separation needs vessels that survive the thermal stress of liquefaction.
	"Atmospheric Condenser": "high_performance_materials",
	"Workshop":          "",
	"Factory":           "mass_production_systems",
	"Automated Factory": "autonomous_factories",
	# Gas turbines are a post-war technology, unlike the coal and oil fleet already standing.
	"Natural Gas Burner": "industrial_mechanization",
	"Nuclear Plant":   "nuclear_power",
	# Civil defence becomes a live concern the moment the bomb does.
	"Bunker":          "nuclear_power",
	"Research Lab":    "",
	"Observatory":     "radio_astronomy",
	"Radio Telescope Array": "radio_astronomy",
	"Space Telescope": "space_habitation_systems",
	"Automated Mine":  "industrial_robotics",
	"Data Center":     "microprocessors",
	"Colony Dome":     "space_habitation_systems",
	# A spun cylinder needs the same habitation engineering as a surface dome.
	"Orbital Habitat": "space_habitation_systems",
	"Fusion Reactor":  "fusion_engineering",
	"AI Research Hub": "machine_learning_systems",
	"Orbital Laser":   "space_power_infrastructure",
	"Thermal Radiator": "space_power_infrastructure",
	# Beaming power is the other half of building a swarm -- the same node that unlocks the
	# collectors unlocks the ground link that lands their output.
	"Ground Rectenna":  "space_power_infrastructure",
	"Microwave Uplink": "space_power_infrastructure",
	# Orbital apertures need the routing techniques that come with Stellar Power.
	"Orbital Rectenna": "stellar_energy_harvesting",
	"Power Relay Satellite": "stellar_energy_harvesting",
	# The orbital rung between planetary hardware and swarm-class megastructures.
	"Orbital Radiator Array": "stellar_energy_harvesting",
	"Orbital Power Grid":     "stellar_energy_harvesting",
	# Stellar-scale counterparts to the swarm itself — nothing smaller can service it.
	"Radiator Swarm":        "megastructure_materials",
	"Stellar Rectenna Grid": "megastructure_materials",
	"Swarm Relay Network":   "megastructure_materials",
	"Orbital Ring Store":    "megastructure_materials",
	# Taking Sol apart needs its own breakthrough — the swarm only supplies the power for it.
	# Building in orbit at all is what this node is for; a shipyard is its largest expression.
	"Orbital Construction Station": "precision_orbital_construction",
	"Star Lifter":           "star_lifting",
	"Sunshade Constellation": "solar_shading",
	"Core Mixing Array":     "stellar_husbandry",
	"Shkadov Mirror":        "stellar_propulsion",
	"Space Elevator":  "nanostructured_materials",
	"Matter Depot":    "",
	"Battery Bank":    "",
	"Flywheel Array":  "",
	"Pumped Hydro Storage": "",
	"Orbital Vault":   "automated_logistics",
	"Orbital Battery": "automated_logistics",
	"Superconducting Storage Ring": "superconducting_systems",
}
