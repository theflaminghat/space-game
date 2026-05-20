class_name ResearchTreeData

static func lane_pos(
	col: int,
	lane: float,
	x_spacing: float,
	y_spacing: float,
	offset: Vector2 = Vector2.ZERO
) -> Vector2:
	return Vector2(col * x_spacing, lane * y_spacing) + offset


static func build() -> Array:
	const X_SPACING: float = 430.0
	const Y_SPACING: float = 100.0

	# Lane layout:
	# 0.0  Computation / information
	# 1.0  Theory / mathematics / physics
	# 2.0  Energy / power systems
	# 3.0  Materials / manufacturing
	# 4.0  Automation / industry
	# 5.0  Space infrastructure
	# 6.0  Biology / life support
	# 7.0  Civilization / post-biological systems

	const COMPUTE: float = 0.0
	const THEORY: float = 1.0
	const ENERGY: float = 2.0
	const MATERIALS: float = 3.0
	const INDUSTRY: float = 4.0
	const SPACE: float = 5.0
	const BIO: float = 6.0
	const CIV: float = 7.0

	var make = func(
		id: String,
		name: String,
		desc: String,
		prereqs: Array,
		cost: Dictionary,
		time: float,
		pos: Vector2
	) -> ResearchNode:
		var n: ResearchNode = ResearchNode.new()
		n.id = id
		n.display_name = name
		n.description = desc
		n.prerequisites = prereqs
		n.cost = cost
		n.research_time = time
		n.position = pos
		return n

	var nodes: Array = []

	# --------------------------------------------------------------------
	# Column 0 - Foundations
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"transistors",
		"Transistors",
		"Solid-state electronics enabling modern digital systems.",
		[],
		{"science": 0, "energy": 0},
		5.0,
		lane_pos(0, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"numerical_methods",
		"Numerical Methods",
		"Practical computational mathematics for simulation, approximation, and engineering analysis.",
		[],
		{"science": 0, "energy": 0},
		5.0,
		lane_pos(0, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"nuclear_power",
		"Nuclear Power",
		"Controlled fission for industrial-scale power generation.",
		[],
		{"science": 0, "energy": 0},
		5.0,
		lane_pos(0, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"metallurgy",
		"Metallurgy",
		"Industrial knowledge of metals, alloys, and structural engineering.",
		[],
		{"science": 0, "energy": 0},
		5.0,
		lane_pos(0, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"industrial_mechanization",
		"Industrial Mechanization",
		"Mass production through powered tools, standardization, and mechanized workflows.",
		[],
		{"science": 0, "energy": 0},
		5.0,
		lane_pos(0, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"early_rocketry",
		"Early Rocketry",
		"Liquid-fuel launch systems capable of reaching space.",
		[],
		{"science": 0, "energy": 0},
		5.0,
		lane_pos(0, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"modern_medicine",
		"Modern Medicine",
		"Evidence-based medicine, sterile procedures, antibiotics, vaccines, and imaging.",
		[],
		{"science": 0, "energy": 0},
		5.0,
		lane_pos(0, BIO, X_SPACING, Y_SPACING)
	))

	# --------------------------------------------------------------------
	# Column 1 - Early systems
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"integrated_circuits",
		"Integrated Circuits",
		"Miniaturized electronics fabricated onto single chips.",
		["transistors"],
		{"science": 25, "energy": 5},
		8.0,
		lane_pos(1, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"control_theory",
		"Control Theory",
		"Mathematical methods for stable feedback, guidance, automation, and regulation.",
		["numerical_methods"],
		{"science": 25, "energy": 5},
		8.0,
		lane_pos(1, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"advanced_reactor_systems",
		"Advanced Reactor Systems",
		"Improved reactor designs with safer control and better fuel utilization.",
		["nuclear_power"],
		{"science": 30, "energy": 8},
		8.0,
		lane_pos(1, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"advanced_alloys",
		"Advanced Alloys",
		"Specialized alloys for heat, stress, and corrosion resistance.",
		["metallurgy"],
		{"science": 30, "energy": 8},
		8.0,
		lane_pos(1, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"mass_production_systems",
		"Mass Production Systems",
		"Scalable manufacturing with quality control, interchangeable parts, and throughput optimization.",
		["industrial_mechanization"],
		{"science": 30, "energy": 8},
		8.0,
		lane_pos(1, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"orbital_mechanics",
		"Orbital Mechanics",
		"Predictive modeling of trajectories, transfer windows, and stable orbital operations.",
		["early_rocketry", "numerical_methods"],
		{"science": 30, "energy": 8},
		8.0,
		lane_pos(1, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"advanced_biomedical_engineering",
		"Advanced Biomedical Engineering",
		"Medical devices, prosthetics, organ support systems, and diagnostic instrumentation.",
		["modern_medicine"],
		{"science": 30, "energy": 8},
		8.0,
		lane_pos(1, BIO, X_SPACING, Y_SPACING)
	))

	# --------------------------------------------------------------------
	# Column 2 - Computing and industrialization
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"semiconductor_manufacturing",
		"Semiconductor Manufacturing",
		"Precision fabrication of increasingly dense and reliable microelectronic systems.",
		["integrated_circuits"],
		{"science": 45, "energy": 10},
		10.0,
		lane_pos(2, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"information_theory",
		"Information Theory",
		"Formal treatment of communication, encoding, signal efficiency, and information limits.",
		["numerical_methods", "integrated_circuits"],
		{"science": 40, "energy": 10},
		10.0,
		lane_pos(2, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"grid_infrastructure",
		"Grid Infrastructure",
		"Large-scale power transmission, distribution, and load balancing.",
		["advanced_reactor_systems"],
		{"science": 45, "energy": 12},
		10.0,
		lane_pos(2, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"high_performance_materials",
		"High Performance Materials",
		"Composites, ceramics, and structural materials for high stress and high temperature use.",
		["advanced_alloys"],
		{"science": 45, "energy": 10},
		10.0,
		lane_pos(2, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"industrial_robotics",
		"Industrial Robotics",
		"Programmable machines for repeatable, high-precision manufacturing.",
		["mass_production_systems", "control_theory"],
		{"science": 50, "energy": 12},
		10.0,
		lane_pos(2, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"satellite_systems",
		"Satellite Systems",
		"Communication, navigation, and remote sensing infrastructure in orbit.",
		["orbital_mechanics"],
		{"science": 45, "energy": 12},
		10.0,
		lane_pos(2, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"medical_informatics",
		"Medical Informatics",
		"Digitized diagnostics, records, modeling, and data-driven clinical systems.",
		["advanced_biomedical_engineering", "semiconductor_manufacturing"],
		{"science": 45, "energy": 10},
		10.0,
		lane_pos(2, BIO, X_SPACING, Y_SPACING)
	))

	# --------------------------------------------------------------------
	# Column 3 - Networked civilization
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"microprocessors",
		"Microprocessors",
		"General-purpose programmable processors enabling widespread digital control and computation.",
		["semiconductor_manufacturing"],
		{"science": 60, "energy": 12},
		11.0,
		lane_pos(3, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"statistical_modeling",
		"Statistical Modeling",
		"Probabilistic inference, estimation, forecasting, and data-driven decision frameworks.",
		["information_theory", "numerical_methods"],
		{"science": 55, "energy": 10},
		11.0,
		lane_pos(3, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"superconducting_systems",
		"Superconducting Systems",
		"High-field and low-loss electrical systems for advanced energy and scientific infrastructure.",
		["grid_infrastructure", "high_performance_materials"],
		{"science": 65, "energy": 16},
		12.0,
		lane_pos(3, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"precision_manufacturing",
		"Precision Manufacturing",
		"Fine-tolerance fabrication required for high-performance electronics, optics, and machinery.",
		["high_performance_materials", "industrial_robotics"],
		{"science": 60, "energy": 14},
		11.0,
		lane_pos(3, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"automated_logistics",
		"Automated Logistics",
		"Machine-coordinated transport, routing, warehousing, and industrial supply systems.",
		["industrial_robotics", "microprocessors"],
		{"science": 60, "energy": 14},
		11.0,
		lane_pos(3, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"reusable_launch_systems",
		"Reusable Launch Systems",
		"Recovery-oriented space launch infrastructure that lowers the cost of access to orbit.",
		["satellite_systems", "precision_manufacturing"],
		{"science": 65, "energy": 18},
		12.0,
		lane_pos(3, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"bioinformatics",
		"Bioinformatics",
		"Computational analysis of genomes, proteins, and biological networks.",
		["medical_informatics", "statistical_modeling"],
		{"science": 60, "energy": 12},
		11.0,
		lane_pos(3, BIO, X_SPACING, Y_SPACING)
	))

	# --------------------------------------------------------------------
	# Column 4 - Advanced capability growth
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"networked_computing",
		"Networked Computing",
		"Distributed information systems linking computation, communication, and remote services.",
		["microprocessors", "information_theory"],
		{"science": 80, "energy": 18},
		13.0,
		lane_pos(4, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"materials_physics",
		"Materials Physics",
		"Advanced physical understanding of materials behavior under extreme conditions.",
		["statistical_modeling", "high_performance_materials"],
		{"science": 75, "energy": 16},
		13.0,
		lane_pos(4, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"high_energy_density_power",
		"High Energy Density Power",
		"Power architectures suitable for large industrial systems, dense storage, and advanced transport.",
		["superconducting_systems"],
		{"science": 85, "energy": 24},
		14.0,
		lane_pos(4, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"extreme_environment_materials",
		"Extreme Environment Materials",
		"Materials capable of surviving radiation, vacuum, large thermal gradients, and high energy flux.",
		["materials_physics", "precision_manufacturing"],
		{"science": 85, "energy": 18},
		14.0,
		lane_pos(4, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"autonomous_industrial_control",
		"Autonomous Industrial Control",
		"Software-directed, adaptive, partially autonomous industrial operation and fault handling.",
		["automated_logistics", "networked_computing", "control_theory"],
		{"science": 85, "energy": 20},
		14.0,
		lane_pos(4, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"space_habitation_systems",
		"Space Habitation Systems",
		"Environmental control, shielding, rotation, and support systems for long-duration living in space.",
		["reusable_launch_systems", "advanced_biomedical_engineering"],
		{"science": 85, "energy": 20},
		14.0,
		lane_pos(4, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"genome_engineering",
		"Genome Engineering",
		"Deliberate editing and design of biological systems for medicine and adaptation.",
		["bioinformatics"],
		{"science": 80, "energy": 16},
		13.0,
		lane_pos(4, BIO, X_SPACING, Y_SPACING)
	))

	# --------------------------------------------------------------------
	# Column 5 - Infrastructure civilization
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"high_performance_computing",
		"High Performance Computing",
		"Large-scale compute infrastructure for simulation, optimization, and scientific modeling.",
		["networked_computing"],
		{"science": 100, "energy": 26},
		15.0,
		lane_pos(5, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"plasma_physics",
		"Plasma Physics",
		"Applied understanding of high-energy ionized matter for fusion and advanced propulsion research.",
		["materials_physics", "high_energy_density_power"],
		{"science": 95, "energy": 24},
		15.0,
		lane_pos(5, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"fusion_engineering",
		"Fusion Engineering",
		"Engineering capability for practical high-output fusion systems.",
		["high_energy_density_power", "plasma_physics", "superconducting_systems"],
		{"science": 110, "energy": 35},
		16.0,
		lane_pos(5, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"nanostructured_materials",
		"Nanostructured Materials",
		"Fine-structure engineering of matter for tailored thermal, electrical, and mechanical properties.",
		["extreme_environment_materials", "materials_physics"],
		{"science": 100, "energy": 22},
		15.0,
		lane_pos(5, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"autonomous_factories",
		"Autonomous Factories",
		"Largely self-coordinating production systems with minimal human intervention.",
		["autonomous_industrial_control", "high_performance_computing"],
		{"science": 105, "energy": 24},
		15.0,
		lane_pos(5, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"orbital_construction",
		"Orbital Construction",
		"Assembly, maintenance, and heavy construction techniques for persistent infrastructure in orbit.",
		["space_habitation_systems", "reusable_launch_systems", "autonomous_factories"],
		{"science": 110, "energy": 28},
		16.0,
		lane_pos(5, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"synthetic_biology",
		"Synthetic Biology",
		"Engineering of cells, tissues, and biological pathways for designed functions.",
		["genome_engineering"],
		{"science": 100, "energy": 18},
		15.0,
		lane_pos(5, BIO, X_SPACING, Y_SPACING)
	))

	# --------------------------------------------------------------------
	# Column 6 - Sci-fi enabling capabilities
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"machine_learning_systems",
		"Machine Learning Systems",
		"Data-driven adaptive systems for prediction, perception, optimization, and control.",
		["high_performance_computing", "statistical_modeling"],
		{"science": 125, "energy": 28},
		17.0,
		lane_pos(6, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"quantum_information_theory",
		"Quantum Information Theory",
		"Operational understanding of quantum systems for computation, sensing, and communication.",
		["information_theory", "materials_physics"],
		{"science": 120, "energy": 24},
		17.0,
		lane_pos(6, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"space_power_infrastructure",
		"Space Power Infrastructure",
		"Large-scale orbital or off-world energy generation, storage, and transmission systems.",
		["fusion_engineering", "orbital_construction", "high_energy_density_power"],
		{"science": 130, "energy": 40},
		18.0,
		lane_pos(6, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"radiation_hardened_systems",
		"Radiation Hardened Systems",
		"Hardware and structures designed for sustained operation in intense radiation environments.",
		["nanostructured_materials", "extreme_environment_materials"],
		{"science": 120, "energy": 24},
		17.0,
		lane_pos(6, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"autonomous_industrial_coordination",
		"Autonomous Industrial Coordination",
		"Planetary and orbital coordination of production, extraction, and logistics by intelligent systems.",
		["autonomous_factories", "machine_learning_systems"],
		{"science": 130, "energy": 28},
		18.0,
		lane_pos(6, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"in_situ_resource_utilization",
		"In-Situ Resource Utilization",
		"Extraction and processing of local extraterrestrial materials for construction and support.",
		["orbital_construction", "autonomous_factories", "radiation_hardened_systems"],
		{"science": 130, "energy": 30},
		18.0,
		lane_pos(6, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"closed_loop_ecosystems",
		"Closed-Loop Ecosystems",
		"Recycling of air, water, nutrients, and waste for sustained independent habitats.",
		["synthetic_biology", "space_habitation_systems"],
		{"science": 125, "energy": 22},
		17.0,
		lane_pos(6, BIO, X_SPACING, Y_SPACING)
	))

	# --------------------------------------------------------------------
	# Column 7 - Deep capability layer
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"general_ai_assistance",
		"General AI Assistance",
		"Flexible AI systems capable of broad engineering, scientific, and industrial support.",
		["machine_learning_systems", "autonomous_industrial_coordination"],
		{"science": 150, "energy": 32},
		19.0,
		lane_pos(7, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"high_energy_physics",
		"High Energy Physics",
		"Experimental and theoretical capability for extreme-energy particles, fields, and interactions.",
		["quantum_information_theory", "fusion_engineering"],
		{"science": 145, "energy": 34},
		19.0,
		lane_pos(7, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"high_energy_particle_engineering",
		"High Energy Particle Engineering",
		"Engineering control of high-energy particle systems for manufacturing, science, and power applications.",
		["high_energy_physics", "space_power_infrastructure"],
		{"science": 155, "energy": 42},
		20.0,
		lane_pos(7, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"field_stabilized_materials",
		"Field-Stabilized Materials",
		"Advanced materials designed to operate with extreme electromagnetic, thermal, and radiation loads.",
		["radiation_hardened_systems", "high_energy_physics"],
		{"science": 150, "energy": 28},
		19.0,
		lane_pos(7, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"self_replicating_industry",
		"Self-Replicating Industry",
		"Industrial systems able to reproduce large parts of their own production base from available resources.",
		["autonomous_industrial_coordination", "in_situ_resource_utilization", "field_stabilized_materials"],
		{"science": 165, "energy": 34},
		21.0,
		lane_pos(7, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"precision_orbital_construction",
		"Precision Orbital Construction",
		"High-accuracy assembly of large, delicate, or tightly toleranced orbital structures.",
		["orbital_construction", "field_stabilized_materials", "autonomous_industrial_coordination"],
		{"science": 160, "energy": 34},
		20.0,
		lane_pos(7, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"human_adaptation_systems",
		"Human Adaptation Systems",
		"Biological and medical systems for long-duration survival in altered, artificial, or hostile environments.",
		["closed_loop_ecosystems", "genome_engineering", "advanced_biomedical_engineering"],
		{"science": 150, "energy": 24},
		19.0,
		lane_pos(7, BIO, X_SPACING, Y_SPACING)
	))

	# --------------------------------------------------------------------
	# Column 8 - Civilization transition technologies
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"planetary_simulation",
		"Planetary Simulation",
		"Integrated simulation of climate, economy, infrastructure, logistics, and biosystems at planetary scale.",
		["general_ai_assistance", "high_performance_computing"],
		{"science": 180, "energy": 36},
		22.0,
		lane_pos(8, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"relativistic_physics",
		"Relativistic Physics",
		"Applied understanding of high-velocity systems, time dilation, and extreme-energy trajectories.",
		["high_energy_physics"],
		{"science": 170, "energy": 30},
		21.0,
		lane_pos(8, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"antimatter_handling",
		"Antimatter Handling",
		"Containment, transfer, and controlled use of antimatter at nontrivial engineering scales.",
		["high_energy_particle_engineering", "field_stabilized_materials"],
		{"science": 185, "energy": 50},
		22.0,
		lane_pos(8, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"molecular_manufacturing",
		"Molecular Manufacturing",
		"Fine-grained construction of matter at extremely small scales for ultra-precise products and systems.",
		["field_stabilized_materials", "nanostructured_materials", "precision_manufacturing"],
		{"science": 180, "energy": 32},
		22.0,
		lane_pos(8, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"distributed_autonomous_economy",
		"Distributed Autonomous Economy",
		"Large-scale economic coordination among autonomous industrial and logistical systems across many sites.",
		["self_replicating_industry", "planetary_simulation"],
		{"science": 185, "energy": 36},
		22.0,
		lane_pos(8, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"deep_space_logistics",
		"Deep Space Logistics",
		"Sustained movement of materials, equipment, and habitats between distant off-world industrial zones.",
		["precision_orbital_construction", "in_situ_resource_utilization", "space_power_infrastructure"],
		{"science": 180, "energy": 38},
		22.0,
		lane_pos(8, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"longevity_engineering",
		"Longevity Engineering",
		"Medical control of aging, degeneration, and long-term health maintenance.",
		["human_adaptation_systems", "synthetic_biology"],
		{"science": 175, "energy": 24},
		21.0,
		lane_pos(8, BIO, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"brain_computer_interfaces",
		"Brain-Computer Interfaces",
		"High-bandwidth links between nervous systems and digital systems.",
		["human_adaptation_systems", "general_ai_assistance"],
		{"science": 175, "energy": 26},
		21.0,
		lane_pos(8, CIV, X_SPACING, Y_SPACING)
	))

	# --------------------------------------------------------------------
	# Column 9 - Endgame enablers
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"automated_science_systems",
		"Automated Science Systems",
		"AI-driven experimental design, theory generation, simulation, and discovery workflows.",
		["planetary_simulation", "general_ai_assistance"],
		{"science": 210, "energy": 40},
		24.0,
		lane_pos(9, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"relativistic_navigation",
		"Relativistic Navigation",
		"Trajectory design, guidance, and error correction for extreme-velocity interplanetary and interstellar travel.",
		["relativistic_physics", "deep_space_logistics"],
		{"science": 205, "energy": 36},
		24.0,
		lane_pos(9, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"stellar_energy_harvesting",
		"Stellar Energy Harvesting",
		"Engineering capability for capturing and routing energy at massive orbital scales.",
		["space_power_infrastructure", "precision_orbital_construction", "distributed_autonomous_economy"],
		{"science": 220, "energy": 55},
		25.0,
		lane_pos(9, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"megastructure_materials",
		"Megastructure Materials",
		"Materials and structural systems suitable for immense orbital and stellar engineering projects.",
		["molecular_manufacturing", "field_stabilized_materials"],
		{"science": 215, "energy": 38},
		24.0,
		lane_pos(9, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"megastructure_fabrication",
		"Megastructure Fabrication",
		"Industrial methods for assembling structures on scales far beyond ordinary spacecraft or stations.",
		["distributed_autonomous_economy", "megastructure_materials", "precision_orbital_construction"],
		{"science": 225, "energy": 42},
		25.0,
		lane_pos(9, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"interstellar_preparation",
		"Interstellar Preparation",
		"Capability for building systems robust enough for precursor interstellar missions and settlement infrastructure.",
		["deep_space_logistics", "relativistic_navigation", "closed_loop_ecosystems"],
		{"science": 220, "energy": 40},
		25.0,
		lane_pos(9, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"synthetic_biosphere_engineering",
		"Synthetic Biosphere Engineering",
		"Design and long-term stabilization of complex artificial ecologies for habitats and colonies.",
		["closed_loop_ecosystems", "longevity_engineering", "planetary_simulation"],
		{"science": 210, "energy": 28},
		24.0,
		lane_pos(9, BIO, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"digital_consciousness_frameworks",
		"Digital Consciousness Frameworks",
		"Technical and philosophical basis for stable digital persons, cognition transfer, or equivalent mind emulation.",
		["brain_computer_interfaces", "automated_science_systems"],
		{"science": 215, "energy": 34},
		24.0,
		lane_pos(9, CIV, X_SPACING, Y_SPACING)
	))

	# --------------------------------------------------------------------
	# Column 10 - Final civilization capabilities
	# --------------------------------------------------------------------
	nodes.append(make.call(
		"stellar_scale_computation",
		"Stellar-Scale Computation",
		"Computation sustained by massive off-world energy and industrial infrastructure.",
		["stellar_energy_harvesting", "automated_science_systems"],
		{"science": 300, "energy": 85},
		32.0,
		lane_pos(10, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"post_relativistic_mission_design",
		"Post-Relativistic Mission Design",
		"Integrated design of ultra-long-duration missions, settlement packages, and autonomous expansion architectures.",
		["relativistic_navigation", "interstellar_preparation"],
		{"science": 280, "energy": 55},
		30.0,
		lane_pos(10, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"exotic_energy_management",
		"Exotic Energy Management",
		"Ultra-high-energy storage, routing, and containment for civilization-scale engineering.",
		["antimatter_handling", "stellar_energy_harvesting"],
		{"science": 290, "energy": 90},
		31.0,
		lane_pos(10, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"self_healing_megastructures",
		"Self-Healing Megastructures",
		"Large engineered systems able to monitor damage, repair themselves, and maintain structural integrity over long timescales.",
		["megastructure_materials", "self_replicating_industry"],
		{"science": 285, "energy": 50},
		30.0,
		lane_pos(10, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"civilization_scale_coordination",
		"Civilization-Scale Coordination",
		"Management and optimization of industry, logistics, habitats, energy, and computation across vast distributed systems.",
		["megastructure_fabrication", "stellar_scale_computation", "distributed_autonomous_economy"],
		{"science": 300, "energy": 60},
		32.0,
		lane_pos(10, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"multi_habitat_support_architecture",
		"Multi-Habitat Support Architecture",
		"Integrated life support, logistics, and industrial support for many large habitats and colonies.",
		["synthetic_biosphere_engineering", "deep_space_logistics", "civilization_scale_coordination"],
		{"science": 290, "energy": 55},
		31.0,
		lane_pos(10, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"post_biological_transition",
		"Post-Biological Transition",
		"Stable coexistence or migration between biological, augmented, and digital forms of personhood.",
		["digital_consciousness_frameworks", "longevity_engineering", "brain_computer_interfaces"],
		{"science": 295, "energy": 45},
		31.0,
		lane_pos(10, BIO, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"distributed_civilization_models",
		"Distributed Civilization Models",
		"Governance, coordination, and social architecture for civilizations spread across habitats, worlds, and substrates.",
		["post_biological_transition", "civilization_scale_coordination"],
		{"science": 295, "energy": 42},
		31.0,
		lane_pos(10, CIV, X_SPACING, Y_SPACING)
	))

	return nodes
