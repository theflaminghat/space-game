class_name BuildingUnlocks

const BUILDING_UNLOCK_REQUIREMENTS := {
	"Solar Farm":      "",
	"Mine":            "",
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
	"Fusion Reactor":  "fusion_engineering",
	"AI Research Hub": "machine_learning_systems",
	"Orbital Laser":   "space_power_infrastructure",
	"Thermal Radiator": "space_power_infrastructure",
	"Space Elevator":  "nanostructured_materials",
	"Matter Depot":    "",
	"Battery Bank":    "",
	"Flywheel Array":  "",
	"Pumped Hydro Storage": "",
	"Orbital Vault":   "automated_logistics",
	"Orbital Battery": "automated_logistics",
	"Superconducting Storage Ring": "superconducting_systems",
}
