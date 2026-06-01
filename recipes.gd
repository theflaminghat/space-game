class_name RecipeData

## Manufacturing recipes: convert input resources/chemicals into outputs.
##
## Keys per recipe:
##   name        – display name
##   category    – "materials" | "chemicals" | "fuels" | "energy" | "biologics"
##   inputs      – Dictionary { resource_or_compound → grams-per-second at rate 1× }
##   outputs     – Dictionary { resource_or_compound → grams-per-second at rate 1× }
##   requires    – research node id that must be completed (empty = always available)
##   description – short flavour text
##
## All input compounds must exist in at least one planet's CRUST composition in
## planet_data.gd so they can actually accumulate from mining.  Check before
## adding new recipes.
##
## Earth crust compounds (from planet_data.gd / McDonough & Sun 1995):
##   SiO2, Al2O3, Fe2O3, MgO, CaO, Na2O, K2O, TiO2, CaCO3, FeS2,
##   H2O, NaCl, P2O5, UO2, ThO2, Coal, Oil
##
## Main resources (ResearchTree.resources):
##   minerals, energy, science

const RECIPES: Array = [
	# ── Materials ────────────────────────────────────────────────────────────────

	# Iron: smelt hematite (Fe2O3) from Earth's crust; Coal provides the carbon.
	{
		"name":        "Iron Smelting",
		"category":    "materials",
		"description": "Reduce hematite ore to metallic iron using coal as a reductant.",
		"requires":    "",
		"inputs":  {"Fe2O3": 10.0, "Coal": 3.0, "energy": 50.0},
		"outputs": {"Fe": 6.0},
	},
	# Silicon: carbothermic reduction of quartz using Coal.
	{
		"name":        "Silicon Refining",
		"category":    "materials",
		"description": "Carbothermic reduction of quartz sand to metallurgical-grade silicon.",
		"requires":    "metallurgy",
		"inputs":  {"SiO2": 8.0, "Coal": 4.0, "energy": 120.0},
		"outputs": {"minerals": 4.0},
	},
	# Aluminium: Hall–Héroult electrolysis of crustal alumina.
	{
		"name":        "Aluminium Smelting",
		"category":    "materials",
		"description": "Hall–Héroult electrolysis of alumina to primary aluminium.",
		"requires":    "advanced_alloys",
		"inputs":  {"Al2O3": 12.0, "energy": 200.0},
		"outputs": {"minerals": 8.0},
	},
	# Lime: roast calcium carbonate (calcite / limestone) from the crust.
	{
		"name":        "Lime Production",
		"category":    "materials",
		"description": "Thermal decomposition of calcite to quicklime (CaO) and CO₂.",
		"requires":    "",
		"inputs":  {"CaCO3": 8.0, "energy": 40.0},
		"outputs": {"CaO": 4.5},
	},
	# Titanium: Kroll process – TiO2 reduced with Coal/coke.
	{
		"name":        "Titanium Extraction",
		"category":    "materials",
		"description": "Kroll-process reduction of rutile to sponge titanium.",
		"requires":    "advanced_alloys",
		"inputs":  {"TiO2": 6.0, "Coal": 2.0, "energy": 350.0},
		"outputs": {"minerals": 3.0},
	},
	# Phosphate: wet-process digestion of P2O5 ore.
	{
		"name":        "Phosphate Processing",
		"category":    "materials",
		"description": "Acid digestion of phosphate rock into concentrated phosphoric acid.",
		"requires":    "industrial_mechanization",
		"inputs":  {"P2O5": 5.0, "H2O": 3.0, "energy": 20.0},
		"outputs": {"minerals": 3.0},
	},

	# ── Chemicals ────────────────────────────────────────────────────────────────

	# Water electrolysis: split abundant crustal H2O into O2.
	{
		"name":        "Water Electrolysis",
		"category":    "chemicals",
		"description": "Split water into hydrogen and oxygen using electrical current.",
		"requires":    "",
		"inputs":  {"H2O": 10.0, "energy": 60.0},
		"outputs": {"O2": 8.0},
	},
	# Brine desalination: recover water from NaCl brine.
	{
		"name":        "Brine Desalination",
		"category":    "chemicals",
		"description": "Reverse-osmosis separation of potable water from seawater.",
		"requires":    "",
		"inputs":  {"NaCl": 5.0, "energy": 25.0},
		"outputs": {"H2O": 4.0},
	},
	# Sulphate leaching: dissolve gypsum (CaSO4) to recover CaO and H2SO4 feedstock.
	{
		"name":        "Gypsum Processing",
		"category":    "chemicals",
		"description": "Dissolve gypsum ore to recover calcium oxide feedstock.",
		"requires":    "metallurgy",
		"inputs":  {"CaSO4": 6.0, "energy": 35.0},
		"outputs": {"CaO": 2.0},
	},

	# ── Fuels ─────────────────────────────────────────────────────────────────────

	# Coal → energy: gasification / combustion of crustal coal.
	{
		"name":        "Coal Combustion",
		"category":    "fuels",
		"description": "Combustion of coal to generate thermal energy.",
		"requires":    "",
		"inputs":  {"Coal": 10.0},
		"outputs": {"energy": 80.0},
	},
	# Oil → energy: refinery + combustion of crustal petroleum.
	{
		"name":        "Oil Refining",
		"category":    "fuels",
		"description": "Fractional distillation and combustion of crude oil.",
		"requires":    "industrial_mechanization",
		"inputs":  {"Oil": 8.0},
		"outputs": {"energy": 120.0},
	},
	# Uranium enrichment: concentrate UO2 into reactor fuel.
	{
		"name":        "Uranium Enrichment",
		"category":    "fuels",
		"description": "Gas-centrifuge enrichment of uranium hexafluoride to reactor-grade U-235.",
		"requires":    "nuclear_power",
		"inputs":  {"UO2": 5.0, "energy": 200.0},
		"outputs": {"energy": 2000.0},
	},
	# Thorium breeding: activate Th-232 from crust into fissile U-233.
	{
		"name":        "Thorium Activation",
		"category":    "fuels",
		"description": "Neutron capture converts Th-232 to fissile U-233 in a molten-salt blanket.",
		"requires":    "advanced_reactor_systems",
		"inputs":  {"ThO2": 4.0, "energy": 300.0},
		"outputs": {"energy": 3000.0},
	},

	# ── Biologics ────────────────────────────────────────────────────────────────

	# Water recycling: clean water from mined H2O using minimal energy.
	{
		"name":        "Water Recycling",
		"category":    "biologics",
		"description": "Closed-loop purification of grey-water back to potable quality.",
		"requires":    "space_habitation_systems",
		"inputs":  {"H2O": 8.0, "energy": 15.0},
		"outputs": {"H2O": 7.5},   # small net loss; better than consuming fresh stock
	},
	# Phosphate fertiliser: use P2O5 + CaO (from lime) for hydroponics.
	{
		"name":        "Fertiliser Synthesis",
		"category":    "biologics",
		"description": "Combine phosphate and lime into concentrated hydroponics fertiliser.",
		"requires":    "synthetic_biology",
		"inputs":  {"P2O5": 3.0, "CaO": 2.0, "H2O": 4.0, "energy": 30.0},
		"outputs": {"minerals": 3.0},
	},
	# Bone mineral synthesis: produce hydroxyapatite from crustal minerals.
	{
		"name":        "Bone Mineral Synthesis",
		"category":    "biologics",
		"description": "Synthetic hydroxyapatite (Ca₅(PO₄)₃OH) for skeletal augments and implants.",
		"requires":    "advanced_biomedical_engineering",
		"inputs":  {"CaO": 3.0, "P2O5": 2.0, "H2O": 1.0, "energy": 40.0},
		"outputs": {"minerals": 2.0},
	},
]

## Returns all recipes that are unlocked given a set of completed research node ids.
static func available(completed_research: Dictionary) -> Array:
	var result: Array = []
	for r in RECIPES:
		var req: String = r.get("requires", "")
		if req == "" or completed_research.get(req, false):
			result.append(r)
	return result
