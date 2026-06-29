class_name ResearchTreeData

# ── Cost scaling (match production magnitudes) ───────────────────────────────
# The hand-authored per-node costs below carry the *relative* curve (≈1.43×
# science per column).  Their raw magnitudes (science 18–4525, energy 2–2798)
# were trivially affordable: science income is uncapped at ~population × 10^17
# FLOP/s (≈2.3e26 FLOP/s at the 1945 start), and energy refills its storage tank
# almost instantly.  These multipliers lift the magnitudes onto the same scale as
# actual production so research becomes a real, time-gated sink:
#
#   • Science is uncapped, so its cost is scaled to the FLOP economy.  An early
#     node (science 30) now costs 3e27 ≈ a dozen game-days of starting output;
#     late nodes (science ~4500) cost ~4.5e29 ≈ centuries, while production only
#     grows ~4× (population 2.3e9 → ~1e10), so research escalates meaningfully.
#   • Energy is storage-capped (base 1e5, +1e6 per Storage Depot), so its cost is
#     scaled to that pool: early nodes fit the base tank, advanced nodes require
#     building dedicated storage first.
const SCIENCE_COST_SCALE: float = 1.0e26
const ENERGY_COST_SCALE:  float = 1.0e3

# ── Cost philosophy ─────────────────────────────────────────────────────────
# Science grows ~1.43× per column; energy is weighted by research infrastructure:
#   Theory/math          → energy × 0.1–0.3
#   Materials/chemistry  → energy × 0.8–1.2
#   Computing/robotics   → energy × 0.6–1.0
#   Nuclear/power        → energy × 1.5–2.5
#   Space launch         → energy × 1.2–1.8
#   Plasma/fusion        → energy × 3.0–4.5
#   Particle physics     → energy × 5–8      (LHC ≈ 200 MW·yr)
#   Antimatter           → energy × 12+

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

	# Lane Y positions
	# 0.0  Computation / information
	# 0.5  Quantum hardware  (sub-lane)
	# 1.0  Theory / mathematics / physics
	# 1.5  Applied forecasting  (sub-lane)
	# 2.0  Energy / power systems
	# 2.5  Energy storage  (sub-lane)
	# 3.0  Materials / manufacturing
	# 3.5  Additive / digital fabrication  (sub-lane)
	# 4.0  Automation / industry
	# 5.0  Space infrastructure
	# 5.5  Propulsion / terraforming  (sub-lane)
	# 6.0  Biology / life support
	# 7.0  Civilization / governance / post-biological

	const COMPUTE:   float = 0.0
	const QCOMP:     float = 0.5   # quantum hardware sub-lane
	const THEORY:    float = 1.0
	const FORECAST:  float = 1.5   # predictive / applied math sub-lane
	const ENERGY:    float = 2.0
	const ESTORAGE:  float = 2.5   # energy storage sub-lane
	const MATERIALS: float = 3.0
	const ADDITIVE:  float = 3.5   # additive manufacturing sub-lane
	const INDUSTRY:  float = 4.0
	const SPACE:     float = 5.0
	const PROPULSION: float = 5.5  # advanced propulsion / terraforming sub-lane
	const BIO:       float = 6.0
	const CIV:       float = 7.0

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

	# ════════════════════════════════════════════════════════════════════════
	# Column 0 — Foundations  (starting knowledge, always free)
	# ════════════════════════════════════════════════════════════════════════
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
		"Computational mathematics for simulation, approximation, and engineering analysis.",
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
		"Industrialization",
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

	# ════════════════════════════════════════════════════════════════════════
	# Column 1 — Early post-war R&D  (science ~18–35, energy ~2–18)
	# ════════════════════════════════════════════════════════════════════════
	nodes.append(make.call(
		"integrated_circuits",
		"Integrated Circuits",
		"Miniaturized electronics fabricated onto single chips.",
		["transistors"],
		{"science": 30, "energy": 8},
		8.0,
		lane_pos(1, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"control_theory",
		"Control Theory",
		"Mathematical methods for stable feedback, guidance, automation, and regulation.",
		["numerical_methods"],
		{"science": 18, "energy": 2},
		7.0,
		lane_pos(1, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"advanced_reactor_systems",
		"Advanced Reactors",
		"Improved reactor designs with safer control and better fuel utilization.",
		["nuclear_power"],
		{"science": 35, "energy": 18},
		9.0,
		lane_pos(1, ENERGY, X_SPACING, Y_SPACING)
	))

	# NEW — Energy Storage
	# Lead-acid → NiMH → Li-ion progression; essential bridge between nuclear
	# power and a flexible grid.  Unlocks Power Grid and Dense Power Systems.
	nodes.append(make.call(
		"energy_storage",
		"Energy Storage",
		"Scalable electrochemical and physical systems for storing and releasing energy on demand — from portable batteries to grid-scale reservoirs.",
		["metallurgy", "nuclear_power"],
		{"science": 28, "energy": 14},
		8.5,
		lane_pos(1, ESTORAGE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"advanced_alloys",
		"Advanced Alloys",
		"Specialized alloys for heat, stress, and corrosion resistance.",
		["metallurgy"],
		{"science": 25, "energy": 10},
		8.0,
		lane_pos(1, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"mass_production_systems",
		"Mass Production",
		"Scalable manufacturing with quality control, interchangeable parts, and throughput optimization.",
		["industrial_mechanization"],
		{"science": 22, "energy": 7},
		7.0,
		lane_pos(1, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"orbital_mechanics",
		"Orbital Mechanics",
		"Predictive modeling of trajectories, transfer windows, and stable orbital operations.",
		["early_rocketry", "numerical_methods"],
		{"science": 28, "energy": 3},
		8.0,
		lane_pos(1, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"advanced_biomedical_engineering",
		"Biomedical Engineering",
		"Medical devices, prosthetics, organ support systems, and diagnostic instrumentation.",
		["modern_medicine"],
		{"science": 25, "energy": 5},
		8.0,
		lane_pos(1, BIO, X_SPACING, Y_SPACING)
	))

	# ════════════════════════════════════════════════════════════════════════
	# Column 2 — Big-science era  (science ~45–78, energy ~3–38)
	# ════════════════════════════════════════════════════════════════════════
	nodes.append(make.call(
		"semiconductor_manufacturing",
		"Semiconductor Manufacturing",
		"Precision fabrication of increasingly dense and reliable microelectronic systems.",
		["integrated_circuits"],
		{"science": 65, "energy": 28},
		10.0,
		lane_pos(2, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"information_theory",
		"Information Theory",
		"Formal treatment of communication, encoding, signal efficiency, and information limits.",
		["numerical_methods", "integrated_circuits"],
		{"science": 45, "energy": 4},
		9.0,
		lane_pos(2, THEORY, X_SPACING, Y_SPACING)
	))

	# MODIFIED — added energy_storage as prerequisite
	nodes.append(make.call(
		"grid_infrastructure",
		"Power Grid",
		"Large-scale power transmission, distribution, and load balancing.",
		["advanced_reactor_systems", "energy_storage"],
		{"science": 60, "energy": 35},
		10.0,
		lane_pos(2, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"high_performance_materials",
		"High-Perf Materials",
		"Composites, ceramics, and structural materials for high stress and high temperature use.",
		["advanced_alloys"],
		{"science": 55, "energy": 18},
		10.0,
		lane_pos(2, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"industrial_robotics",
		"Industrial Robotics",
		"Programmable machines for repeatable, high-precision manufacturing.",
		["mass_production_systems", "control_theory"],
		{"science": 72, "energy": 22},
		11.0,
		lane_pos(2, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"satellite_systems",
		"Satellite Systems",
		"Communication, navigation, and remote sensing infrastructure in orbit.",
		["orbital_mechanics"],
		{"science": 78, "energy": 32},
		11.0,
		lane_pos(2, SPACE, X_SPACING, Y_SPACING)
	))

	# NEW — Advanced Propulsion
	# Nuclear thermal (Nerva program, 1960s) and ion drives (DS1, 1998) enable
	# practical deep-space transit and dramatically reduce in-space travel times.
	# Required for Reusable Launch (engine reuse tech) and Deep Space Logistics.
	nodes.append(make.call(
		"advanced_propulsion",
		"Advanced Propulsion",
		"High-efficiency in-space drives including nuclear thermal rockets and electric ion systems, enabling practical deep-space transit.",
		["orbital_mechanics", "advanced_reactor_systems"],
		{"science": 58, "energy": 38},
		10.5,
		lane_pos(2, PROPULSION, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"medical_informatics",
		"Medical Informatics",
		"Digitized diagnostics, records, modeling, and data-driven clinical systems.",
		["advanced_biomedical_engineering", "semiconductor_manufacturing"],
		{"science": 55, "energy": 10},
		10.0,
		lane_pos(2, BIO, X_SPACING, Y_SPACING)
	))

	# ════════════════════════════════════════════════════════════════════════
	# Column 3 — Late 20th century  (science ~78–128, energy ~7–55)
	# ════════════════════════════════════════════════════════════════════════
	nodes.append(make.call(
		"microprocessors",
		"Microprocessors",
		"General-purpose programmable processors enabling widespread digital control and computation.",
		["semiconductor_manufacturing"],
		{"science": 100, "energy": 35},
		12.0,
		lane_pos(3, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"statistical_modeling",
		"Statistical Modeling",
		"Probabilistic inference, estimation, forecasting, and data-driven decision frameworks.",
		["information_theory", "numerical_methods"],
		{"science": 78, "energy": 7},
		11.0,
		lane_pos(3, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"superconducting_systems",
		"Superconductors",
		"High-field and low-loss electrical systems for advanced energy and scientific infrastructure.",
		["grid_infrastructure", "high_performance_materials"],
		{"science": 125, "energy": 55},
		13.0,
		lane_pos(3, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"precision_manufacturing",
		"Precision Manufacturing",
		"Fine-tolerance fabrication required for high-performance electronics, optics, and machinery.",
		["high_performance_materials", "industrial_robotics"],
		{"science": 95, "energy": 28},
		12.0,
		lane_pos(3, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"automated_logistics",
		"Automated Logistics",
		"Machine-coordinated transport, routing, warehousing, and industrial supply systems.",
		["industrial_robotics", "microprocessors"],
		{"science": 88, "energy": 22},
		12.0,
		lane_pos(3, INDUSTRY, X_SPACING, Y_SPACING)
	))

	# MODIFIED — added advanced_propulsion as prerequisite
	nodes.append(make.call(
		"reusable_launch_systems",
		"Reusable Launch",
		"Recovery-oriented space launch infrastructure that lowers the cost of access to orbit.",
		["satellite_systems", "precision_manufacturing", "advanced_propulsion"],
		{"science": 128, "energy": 50},
		13.0,
		lane_pos(3, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"bioinformatics",
		"Bioinformatics",
		"Computational analysis of genomes, proteins, and biological networks.",
		["medical_informatics", "statistical_modeling"],
		{"science": 82, "energy": 14},
		11.0,
		lane_pos(3, BIO, X_SPACING, Y_SPACING)
	))

	# ════════════════════════════════════════════════════════════════════════
	# Column 4 — Early 21st century  (science ~125–165, energy ~12–88)
	# ════════════════════════════════════════════════════════════════════════
	nodes.append(make.call(
		"networked_computing",
		"Networked Computing",
		"Distributed information systems linking computation, communication, and remote services.",
		["microprocessors", "information_theory"],
		{"science": 145, "energy": 42},
		14.0,
		lane_pos(4, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"materials_physics",
		"Materials Physics",
		"Advanced physical understanding of materials behaviour under extreme conditions.",
		["statistical_modeling", "high_performance_materials"],
		{"science": 132, "energy": 48},
		14.0,
		lane_pos(4, THEORY, X_SPACING, Y_SPACING)
	))

	# NEW — Predictive Modeling
	# Bridges statistical modeling and materials physics; enables rigorous
	# engineering forecasting from climate models to structural failure analysis.
	# Boosts science production and feeds into Planetary Simulation.
	nodes.append(make.call(
		"predictive_modeling",
		"Predictive Modeling",
		"Rigorous mathematical forecasting of complex system behavior — from climate and economics to engineering failure modes and logistics optimization.",
		["statistical_modeling", "information_theory"],
		{"science": 128, "energy": 12},
		13.5,
		lane_pos(4, FORECAST, X_SPACING, Y_SPACING)
	))

	# MODIFIED — added energy_storage as prerequisite (dense storage needs
	# advanced battery chemistry to validate high charge/discharge rates)
	nodes.append(make.call(
		"high_energy_density_power",
		"Dense Power Systems",
		"Power architectures suitable for large industrial systems, dense storage, and advanced transport.",
		["superconducting_systems", "energy_storage"],
		{"science": 162, "energy": 88},
		15.0,
		lane_pos(4, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"extreme_environment_materials",
		"Extreme Materials",
		"Materials capable of surviving radiation, vacuum, large thermal gradients, and high energy flux.",
		["materials_physics", "precision_manufacturing"],
		{"science": 148, "energy": 52},
		15.0,
		lane_pos(4, MATERIALS, X_SPACING, Y_SPACING)
	))

	# NEW — Additive Manufacturing
	# 3-D printing from powders, wires, and polymers; bridges precision
	# manufacturing and molecular manufacturing.  Dramatically reduces
	# waste and enables on-demand spare parts on orbital stations.
	nodes.append(make.call(
		"additive_manufacturing",
		"Additive Manufacturing",
		"Layer-by-layer construction from digital models, enabling complex geometries, rapid prototyping, and on-demand part production with minimal waste.",
		["precision_manufacturing", "industrial_robotics"],
		{"science": 142, "energy": 42},
		14.5,
		lane_pos(4, ADDITIVE, X_SPACING, Y_SPACING)
	))

	# MODIFIED — removed control_theory prereq (covered transitively via
	# industrial_robotics → mass_production → industrial_mechanization chain)
	nodes.append(make.call(
		"autonomous_industrial_control",
		"Industrial AI",
		"Software that plans and runs industry on its own — adaptive scheduling, fault handling, and standing-order execution. Unlocks the Automation panel, where you delegate building and launches to be carried out without you.",
		["automated_logistics", "networked_computing"],
		{"science": 155, "energy": 45},
		15.0,
		lane_pos(4, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"space_habitation_systems",
		"Space Habitation",
		"Environmental control, shielding, rotation, and support systems for long-duration living in space.",
		["reusable_launch_systems", "advanced_biomedical_engineering"],
		{"science": 162, "energy": 58},
		15.0,
		lane_pos(4, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"genome_engineering",
		"Genome Engineering",
		"Deliberate editing and design of biological systems for medicine and adaptation.",
		["bioinformatics"],
		{"science": 138, "energy": 30},
		14.0,
		lane_pos(4, BIO, X_SPACING, Y_SPACING)
	))

	# ════════════════════════════════════════════════════════════════════════
	# Column 5 — Near-future  (science ~188–262, energy ~45–215)
	# ════════════════════════════════════════════════════════════════════════
	nodes.append(make.call(
		"high_performance_computing",
		"High-Performance Computing",
		"Large-scale compute infrastructure for simulation, optimization, and scientific modeling.",
		["networked_computing"],
		{"science": 205, "energy": 70},
		16.0,
		lane_pos(5, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"plasma_physics",
		"Plasma Physics",
		"Applied understanding of high-energy ionized matter for fusion and advanced propulsion research.",
		["materials_physics", "high_energy_density_power"],
		{"science": 228, "energy": 178},
		17.0,
		lane_pos(5, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"fusion_engineering",
		"Fusion Engineering",
		"Engineering capability for practical high-output fusion systems.",
		["high_energy_density_power", "plasma_physics", "superconducting_systems"],
		{"science": 262, "energy": 215},
		18.0,
		lane_pos(5, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"nanostructured_materials",
		"Nanomaterials",
		"Fine-structure engineering of matter for tailored thermal, electrical, and mechanical properties.",
		["extreme_environment_materials", "materials_physics"],
		{"science": 198, "energy": 62},
		16.0,
		lane_pos(5, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"autonomous_factories",
		"Autonomous Factories",
		"Largely self-coordinating production systems with minimal human intervention.",
		["autonomous_industrial_control", "high_performance_computing"],
		{"science": 215, "energy": 72},
		17.0,
		lane_pos(5, INDUSTRY, X_SPACING, Y_SPACING)
	))

	# MODIFIED — removed reusable_launch prereq (reusable_launch is already
	# required by space_habitation, so it is covered transitively)
	nodes.append(make.call(
		"orbital_construction",
		"Orbital Construction",
		"Assembly, maintenance, and heavy construction techniques for persistent infrastructure in orbit.",
		["space_habitation_systems", "autonomous_factories"],
		{"science": 245, "energy": 105},
		17.0,
		lane_pos(5, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"synthetic_biology",
		"Synthetic Biology",
		"Engineering of cells, tissues, and biological pathways for designed functions.",
		["genome_engineering"],
		{"science": 192, "energy": 48},
		16.0,
		lane_pos(5, BIO, X_SPACING, Y_SPACING)
	))

	# NEW — Institutional Science
	# Formalised peer review, international consortia, coordinated funding
	# bodies (NSF, CERN, ESA-style organisations).  Historically the single
	# biggest multiplier on research output per dollar spent.
	nodes.append(make.call(
		"institutional_science",
		"Institutional Science",
		"Formal research institutions, peer review, international collaboration frameworks, and coordinated funding that multiply collective discovery rates.",
		["networked_computing", "statistical_modeling"],
		{"science": 208, "energy": 52},
		17.0,
		lane_pos(5, CIV, X_SPACING, Y_SPACING)
	))

	# ════════════════════════════════════════════════════════════════════════
	# Column 6 — Advanced civilisation  (science ~305–425, energy ~62–240)
	# ════════════════════════════════════════════════════════════════════════
	nodes.append(make.call(
		"machine_learning_systems",
		"Machine Learning",
		"Data-driven adaptive systems for prediction, perception, optimization, and control.",
		["high_performance_computing", "statistical_modeling"],
		{"science": 305, "energy": 115},
		18.0,
		lane_pos(6, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"quantum_information_theory",
		"Quantum Information",
		"Operational understanding of quantum systems for computation, sensing, and communication.",
		["information_theory", "materials_physics"],
		{"science": 348, "energy": 132},
		19.0,
		lane_pos(6, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"space_power_infrastructure",
		"Space Power Grid",
		"Large-scale orbital or off-world energy generation, storage, and transmission systems.",
		["fusion_engineering", "orbital_construction", "high_energy_density_power"],
		{"science": 418, "energy": 238},
		20.0,
		lane_pos(6, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"radiation_hardened_systems",
		"Radiation Hardening",
		"Hardware and structures designed for sustained operation in intense radiation environments.",
		["nanostructured_materials", "extreme_environment_materials"],
		{"science": 312, "energy": 88},
		18.0,
		lane_pos(6, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"autonomous_industrial_coordination",
		"Industrial AI",
		"Planetary and orbital coordination of production, extraction, and logistics by intelligent systems.",
		["autonomous_factories", "machine_learning_systems"],
		{"science": 375, "energy": 130},
		19.0,
		lane_pos(6, INDUSTRY, X_SPACING, Y_SPACING)
	))

	# MODIFIED — removed autonomous_factories prereq (orbital_construction
	# already requires autonomous_factories, covering it transitively)
	nodes.append(make.call(
		"in_situ_resource_utilization",
		"ISRU",
		"Extraction and processing of local extraterrestrial materials for construction and support.",
		["orbital_construction", "radiation_hardened_systems"],
		{"science": 425, "energy": 165},
		20.0,
		lane_pos(6, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"closed_loop_ecosystems",
		"Closed-Loop Life Support",
		"Recycling of air, water, nutrients, and waste for sustained independent habitats.",
		["synthetic_biology", "space_habitation_systems"],
		{"science": 355, "energy": 98},
		19.0,
		lane_pos(6, BIO, X_SPACING, Y_SPACING)
	))

	# NEW — Global Governance
	# Planetary coordination frameworks for shared resource management and
	# long-horizon planning; prerequisite for civilisation-scale projects.
	# Historically: UN, WTO, IPCC, ISS partnership treaties.
	nodes.append(make.call(
		"global_governance",
		"Global Governance",
		"Planetary coordination frameworks for shared resource allocation, conflict resolution, and long-horizon civilizational planning.",
		["institutional_science"],
		{"science": 318, "energy": 78},
		19.5,
		lane_pos(6, CIV, X_SPACING, Y_SPACING)
	))

	# ════════════════════════════════════════════════════════════════════════
	# Column 7 — Deep capability  (science ~520–770, energy ~95–595)
	# ════════════════════════════════════════════════════════════════════════

	# NEW — Quantum Computing (hardware)
	# Physical quantum processors exploiting superposition and entanglement.
	# Distinct from Quantum Information Theory (which is the formalism);
	# this node represents the engineering of reliable qubit hardware.
	# Boosts research speed and is required for Automated Science.
	nodes.append(make.call(
		"quantum_computing",
		"Quantum Computing",
		"Physical quantum processors that exploit superposition and entanglement to solve problems intractable for classical hardware.",
		["quantum_information_theory", "high_performance_computing"],
		{"science": 542, "energy": 248},
		22.5,
		lane_pos(7, QCOMP, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"general_ai_assistance",
		"General AI",
		"Flexible AI systems capable of broad engineering, scientific, and industrial support.",
		["machine_learning_systems", "autonomous_industrial_coordination"],
		{"science": 520, "energy": 195},
		21.0,
		lane_pos(7, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"high_energy_physics",
		"High Energy Physics",
		"Experimental and theoretical capability for extreme-energy particles, fields, and interactions.",
		["quantum_information_theory", "fusion_engineering"],
		{"science": 648, "energy": 525},
		23.0,
		lane_pos(7, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"high_energy_particle_engineering",
		"Particle Engineering",
		"Engineering control of high-energy particle systems for manufacturing, science, and power applications.",
		["high_energy_physics", "space_power_infrastructure"],
		{"science": 718, "energy": 592},
		24.0,
		lane_pos(7, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"field_stabilized_materials",
		"Field Materials",
		"Advanced materials designed to operate with extreme electromagnetic, thermal, and radiation loads.",
		["radiation_hardened_systems", "high_energy_physics"],
		{"science": 568, "energy": 218},
		21.0,
		lane_pos(7, MATERIALS, X_SPACING, Y_SPACING)
	))

	# MODIFIED — removed field_stabilized_materials prereq; field materials
	# is reached via industrial_ai → radiation_hardening path.
	nodes.append(make.call(
		"self_replicating_industry",
		"Self-Replication",
		"Industrial systems able to reproduce large parts of their own production base from available resources.",
		["autonomous_industrial_coordination", "in_situ_resource_utilization"],
		{"science": 768, "energy": 258},
		24.0,
		lane_pos(7, INDUSTRY, X_SPACING, Y_SPACING)
	))

	# MODIFIED — removed autonomous_industrial_coordination prereq;
	# industrial AI is reached via multiple other paths in the tree.
	nodes.append(make.call(
		"precision_orbital_construction",
		"Precision Orbital Assembly",
		"High-accuracy assembly of large, delicate, or tightly toleranced orbital structures.",
		["orbital_construction", "field_stabilized_materials"],
		{"science": 662, "energy": 235},
		22.0,
		lane_pos(7, SPACE, X_SPACING, Y_SPACING)
	))

	# MODIFIED — removed advanced_biomedical_engineering prereq; it is
	# covered transitively through genome_engineering → bioinformatics →
	# medical_informatics → advanced_biomedical_engineering.
	nodes.append(make.call(
		"human_adaptation_systems",
		"Human Adaptation",
		"Biological and medical systems for long-duration survival in altered, artificial, or hostile environments.",
		["closed_loop_ecosystems", "genome_engineering"],
		{"science": 595, "energy": 142},
		21.0,
		lane_pos(7, BIO, X_SPACING, Y_SPACING)
	))

	# ════════════════════════════════════════════════════════════════════════
	# Column 8 — Civilisation transition  (science ~920–1252, energy ~150–885)
	# ════════════════════════════════════════════════════════════════════════

	# MODIFIED — added predictive_modeling as prerequisite (planetary-scale
	# simulation requires advanced forecasting frameworks as its foundation)
	nodes.append(make.call(
		"planetary_simulation",
		"Planetary Simulation",
		"Integrated simulation of climate, economy, infrastructure, logistics, and biosystems at planetary scale.",
		["general_ai_assistance", "high_performance_computing", "predictive_modeling"],
		{"science": 925, "energy": 295},
		25.0,
		lane_pos(8, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"relativistic_physics",
		"Relativistic Physics",
		"Applied understanding of high-velocity systems, time dilation, and extreme-energy trajectories.",
		["high_energy_physics"],
		{"science": 1085, "energy": 458},
		26.0,
		lane_pos(8, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"antimatter_handling",
		"Antimatter Handling",
		"Containment, transfer, and controlled use of antimatter at nontrivial engineering scales.",
		["high_energy_particle_engineering", "field_stabilized_materials"],
		{"science": 1252, "energy": 885},
		28.0,
		lane_pos(8, ENERGY, X_SPACING, Y_SPACING)
	))

	# MODIFIED — replaced precision_manufacturing with additive_manufacturing
	# (additive manufacturing is the direct predecessor to molecular assembly)
	nodes.append(make.call(
		"molecular_manufacturing",
		"Molecular Manufacturing",
		"Fine-grained construction of matter at extremely small scales for ultra-precise products and systems.",
		["field_stabilized_materials", "nanostructured_materials", "additive_manufacturing"],
		{"science": 968, "energy": 315},
		25.0,
		lane_pos(8, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"distributed_autonomous_economy",
		"Autonomous Economy",
		"Large-scale economic coordination among autonomous industrial and logistical systems across many sites.",
		["self_replicating_industry", "planetary_simulation"],
		{"science": 1125, "energy": 338},
		27.0,
		lane_pos(8, INDUSTRY, X_SPACING, Y_SPACING)
	))

	# MODIFIED — replaced space_power_infrastructure with advanced_propulsion
	# (deep-space transit is more directly gated on propulsion than on power grids;
	# space power is reached transitively via precision_orbital_assembly)
	nodes.append(make.call(
		"deep_space_logistics",
		"Deep Space Logistics",
		"Sustained movement of materials, equipment, and habitats between distant off-world industrial zones.",
		["precision_orbital_construction", "in_situ_resource_utilization", "advanced_propulsion"],
		{"science": 1068, "energy": 392},
		26.0,
		lane_pos(8, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"longevity_engineering",
		"Longevity Engineering",
		"Medical control of aging, degeneration, and long-term health maintenance.",
		["human_adaptation_systems", "synthetic_biology"],
		{"science": 1012, "energy": 282},
		25.0,
		lane_pos(8, BIO, X_SPACING, Y_SPACING)
	))

	# MODIFIED — added global_governance as prerequisite (society must have
	# regulatory and ethical frameworks before widespread BCI deployment)
	nodes.append(make.call(
		"brain_computer_interfaces",
		"Brain-Computer Interface",
		"High-bandwidth links between nervous systems and digital systems.",
		["human_adaptation_systems", "general_ai_assistance", "global_governance"],
		{"science": 1125, "energy": 318},
		26.0,
		lane_pos(8, CIV, X_SPACING, Y_SPACING)
	))

	# ════════════════════════════════════════════════════════════════════════
	# Column 9 — Endgame enablers  (science ~1500–2245, energy ~282–1295)
	# ════════════════════════════════════════════════════════════════════════

	# MODIFIED — added quantum_computing as prerequisite (automated science
	# requires quantum-speed hypothesis evaluation and experiment design)
	nodes.append(make.call(
		"automated_science_systems",
		"Automated Science",
		"AI-driven experimental design, theory generation, simulation, and discovery workflows.",
		["planetary_simulation", "general_ai_assistance", "quantum_computing"],
		{"science": 1598, "energy": 532},
		29.0,
		lane_pos(9, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"relativistic_navigation",
		"Relativistic Navigation",
		"Trajectory design, guidance, and error correction for extreme-velocity interplanetary and interstellar travel.",
		["relativistic_physics", "deep_space_logistics"],
		{"science": 1905, "energy": 648},
		31.0,
		lane_pos(9, THEORY, X_SPACING, Y_SPACING)
	))

	# MODIFIED — removed distributed_autonomous_economy prereq; economy
	# systems are reached transitively via orbital_construction → ISRU paths.
	nodes.append(make.call(
		"stellar_energy_harvesting",
		"Stellar Power",
		"Engineering capability for capturing and routing energy at massive orbital scales.",
		["space_power_infrastructure", "precision_orbital_construction"],
		{"science": 2198, "energy": 1295},
		33.0,
		lane_pos(9, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"megastructure_materials",
		"Megastructure Materials",
		"Materials and structural systems suitable for immense orbital and stellar engineering projects.",
		["molecular_manufacturing", "field_stabilized_materials"],
		{"science": 2085, "energy": 745},
		32.0,
		lane_pos(9, MATERIALS, X_SPACING, Y_SPACING)
	))

	# MODIFIED — removed precision_orbital_construction prereq; it is
	# covered transitively through megastructure_materials → field_materials →
	# radiation_hardening → … chain.
	nodes.append(make.call(
		"megastructure_fabrication",
		"Megastructure Fabrication",
		"Industrial methods for assembling structures on scales far beyond ordinary spacecraft or stations.",
		["distributed_autonomous_economy", "megastructure_materials"],
		{"science": 2245, "energy": 848},
		33.0,
		lane_pos(9, INDUSTRY, X_SPACING, Y_SPACING)
	))

	# MODIFIED — removed closed_loop_ecosystems prereq; it is covered
	# transitively through deep_space_logistics → space_habitation → … path.
	nodes.append(make.call(
		"interstellar_preparation",
		"Interstellar Readiness",
		"Capability for building systems robust enough for precursor interstellar missions and settlement infrastructure.",
		["deep_space_logistics", "relativistic_navigation"],
		{"science": 2085, "energy": 748},
		32.0,
		lane_pos(9, SPACE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"synthetic_biosphere_engineering",
		"Biosphere Engineering",
		"Design and long-term stabilisation of complex artificial ecologies for habitats and colonies.",
		["closed_loop_ecosystems", "longevity_engineering", "planetary_simulation"],
		{"science": 1898, "energy": 582},
		31.0,
		lane_pos(9, BIO, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"digital_consciousness_frameworks",
		"Digital Consciousness",
		"Technical and philosophical basis for stable digital persons, cognition transfer, or equivalent mind emulation.",
		["brain_computer_interfaces", "automated_science_systems"],
		{"science": 2085, "energy": 642},
		32.0,
		lane_pos(9, CIV, X_SPACING, Y_SPACING)
	))

	# ════════════════════════════════════════════════════════════════════════
	# Column 10 — Final civilisation capabilities
	# Extrapolated exponential growth; each node represents a Kardashev
	# Type-II level of organisational and energetic complexity.
	# ════════════════════════════════════════════════════════════════════════
	nodes.append(make.call(
		"stellar_scale_computation",
		"Stellar Computation",
		"Computation sustained by massive off-world energy and industrial infrastructure.",
		["stellar_energy_harvesting", "automated_science_systems"],
		{"science": 4185, "energy": 2198},
		42.0,
		lane_pos(10, COMPUTE, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"post_relativistic_mission_design",
		"Interstellar Mission Design",
		"Integrated design of ultra-long-duration missions, settlement packages, and autonomous expansion architectures.",
		["relativistic_navigation", "interstellar_preparation"],
		{"science": 3598, "energy": 1298},
		39.0,
		lane_pos(10, THEORY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"exotic_energy_management",
		"Exotic Energy",
		"Ultra-high-energy storage, routing, and containment for civilisation-scale engineering.",
		["antimatter_handling", "stellar_energy_harvesting"],
		{"science": 4525, "energy": 2798},
		43.0,
		lane_pos(10, ENERGY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"self_healing_megastructures",
		"Self-Healing Megastructures",
		"Large engineered systems able to monitor damage, repair themselves, and maintain structural integrity over long timescales.",
		["megastructure_materials", "self_replicating_industry"],
		{"science": 3798, "energy": 1498},
		40.0,
		lane_pos(10, MATERIALS, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"civilization_scale_coordination",
		"Macro Coordination",
		"Management and optimisation of industry, logistics, habitats, energy, and computation across vast distributed systems.",
		["megastructure_fabrication", "stellar_scale_computation", "distributed_autonomous_economy"],
		{"science": 4198, "energy": 1895},
		42.0,
		lane_pos(10, INDUSTRY, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"multi_habitat_support_architecture",
		"Multi-Habitat Support",
		"Integrated life support, logistics, and industrial support for many large habitats and colonies.",
		["synthetic_biosphere_engineering", "deep_space_logistics", "civilization_scale_coordination"],
		{"science": 3698, "energy": 1495},
		40.0,
		lane_pos(10, SPACE, X_SPACING, Y_SPACING)
	))

	# NEW — Terraforming
	# Deliberate long-term modification of a world's atmosphere, temperature,
	# and hydrosphere.  Requires biosphere engineering (to seed life), ISRU
	# (to source raw materials), and stellar power (to run planetary-scale
	# industrial processes over centuries).
	nodes.append(make.call(
		"terraforming",
		"Terraforming",
		"Deliberate and sustained modification of a world's atmosphere, temperature, and surface chemistry to support life or large-scale industry.",
		["synthetic_biosphere_engineering", "in_situ_resource_utilization", "stellar_energy_harvesting"],
		{"science": 2848, "energy": 1648},
		40.0,
		lane_pos(10, PROPULSION, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"post_biological_transition",
		"Post-Biological",
		"Stable coexistence or migration between biological, augmented, and digital forms of personhood.",
		["digital_consciousness_frameworks", "longevity_engineering", "brain_computer_interfaces"],
		{"science": 4398, "energy": 1398},
		42.0,
		lane_pos(10, BIO, X_SPACING, Y_SPACING)
	))

	nodes.append(make.call(
		"distributed_civilization_models",
		"Civilization Architecture",
		"Governance, coordination, and social architecture for civilisations spread across habitats, worlds, and substrates.",
		["post_biological_transition", "civilization_scale_coordination"],
		{"science": 3995, "energy": 1095},
		40.0,
		lane_pos(10, CIV, X_SPACING, Y_SPACING)
	))

	# ── Boost assignments ────────────────────────────────────────────────────
	var boost_map: Dictionary = {
		# Compute lane → research speed
		"integrated_circuits":        {"research_speed": 0.10},
		"semiconductor_manufacturing":{"research_speed": 0.15},
		"microprocessors":            {"research_speed": 0.15},
		"high_performance_computing": {"research_speed": 0.20},
		"machine_learning_systems":   {"research_speed": 0.25},
		"automated_science_systems":  {"research_speed": 0.30},
		# NEW — Quantum Computing gives a large research speed jump
		"quantum_computing":          {"research_speed": 0.25},
		# Energy lane → energy production
		"advanced_reactor_systems":   {"energy_production": 0.10},
		"grid_infrastructure":        {"energy_production": 0.15},
		"superconducting_systems":    {"energy_production": 0.15},
		"fusion_engineering":         {"energy_production": 0.25},
		"space_power_infrastructure": {"energy_production": 0.35},
		# NEW — Energy Storage improves how effectively produced energy is used
		"energy_storage":             {"energy_production": 0.12},
		# Industry / materials lane → matter production AND automation.  "automation"
		# multiplies per-planet Manufacturing Capacity and lowers the labour each unit of
		# capacity needs (Game._automation_factor / _process_production); self-replicating
		# industry is the big jump that finally decouples output from population.
		"metallurgy":                 {"matter_production": 0.10},
		"mass_production_systems":    {"matter_production": 0.15, "automation": 0.5},
		"industrial_robotics":        {"matter_production": 0.20, "automation": 1.0},
		"automated_logistics":        {"matter_production": 0.20, "automation": 1.0},
		"autonomous_factories":       {"matter_production": 0.30, "automation": 2.0},
		"self_replicating_industry":  {"matter_production": 0.40, "automation": 5.0},
		# NEW — Additive Manufacturing reduces material waste → more output
		"additive_manufacturing":     {"matter_production": 0.20, "automation": 0.5},
		# NEW — Theory / forecasting lane → science production
		"predictive_modeling":        {"science_production": 0.20},
		"institutional_science":      {"research_speed":    0.12},
		"global_governance":          {"science_production": 0.15},
	}
	for n: ResearchNode in nodes:
		if boost_map.has(n.id):
			n.boosts = boost_map[n.id]

	# ── Layout correction ────────────────────────────────────────────────────
	# Push every node right until its X > all prerequisites' X + X_SPACING.
	var id_to_node: Dictionary = {}
	for n: ResearchNode in nodes:
		id_to_node[n.id] = n

	var any_changed := true
	while any_changed:
		any_changed = false
		for n: ResearchNode in nodes:
			for prereq_id_v: Variant in n.prerequisites:
				var prereq_id: String = prereq_id_v as String
				if not id_to_node.has(prereq_id):
					continue
				var prereq: ResearchNode = id_to_node[prereq_id] as ResearchNode
				var min_x: float = prereq.position.x + X_SPACING
				if n.position.x < min_x:
					n.position.x = min_x
					any_changed = true

	# Lift the hand-authored relative costs onto production-matched magnitudes.
	for n: ResearchNode in nodes:
		if n.cost.has("science"):
			n.cost["science"] = float(n.cost["science"]) * SCIENCE_COST_SCALE
		if n.cost.has("energy"):
			n.cost["energy"] = float(n.cost["energy"]) * ENERGY_COST_SCALE

	return nodes
