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
## Accessible crust compounds by planet:
##   Earth   – SiO2, Al2O3, Fe2O3, MgO, CaO, Na2O, K2O, TiO2, CaCO3, FeS2,
##             H2O, NaCl, P2O5, UO2, ThO2, Coal, Oil, CuFeS2
##   Mercury – SiO2, Al2O3, CaO, Na2S, FeS2, TiO2, UO2, ThO2
##   Venus   – SiO2, Al2O3, MgO, FeO, CaO, Na2O, TiO2, UO2, ThO2
##   Mars    – SiO2, Fe2O3, MgO, Al2O3, CaO, Na2O, CaSO4, MgSO4, H2O, NaCl, UO2, ThO2
##
## Main resources (ResearchTree.resources):
##   minerals, energy, science

const RECIPES: Array = [
	# ── Iron ─────────────────────────────────────────────────────────────────────

	# Hematite route (Earth / Mars): blast-furnace reduction of Fe2O3 with coke.
	{
		"name":        "Iron Smelting",
		"category":    "materials",
		"description": "Blast-furnace reduction of hematite ore with coke to produce pig iron.",
		"requires":    "",
		"inputs":  {"Fe2O3": 10.0, "Coal": 3.0, "energy": 50.0},
		"outputs": {"Fe": 6.0},
	},
	# Pyrite route (Earth / Mercury): roast iron-sulfide ore, then reduce.
	# FeS2 → Fe2O3 (roast) → Fe (reduce).  Lower yield than hematite but useful
	# on planets where pyrite is the primary iron source.
	{
		"name":        "Pyrite Smelting",
		"category":    "materials",
		"description": "Roast pyrite to iron oxide, then carbothermically reduce to metallic iron.",
		"requires":    "",
		"inputs":  {"FeS2": 8.0, "Coal": 2.0, "energy": 60.0},
		"outputs": {"Fe": 3.5},
	},
	# Wüstite route (Venus): direct carbothermic reduction of iron(II) oxide.
	# Venus crust carries ~9 % FeO by mass — an abundant, easily reduced feedstock.
	{
		"name":        "Wüstite Reduction",
		"category":    "materials",
		"description": "Carbothermic reduction of wüstite (FeO) — the dominant iron ore in Venus' basaltic crust.",
		"requires":    "",
		"inputs":  {"FeO": 8.0, "Coal": 1.5, "energy": 40.0},
		"outputs": {"Fe": 6.0},
	},

	# ── Silicon ───────────────────────────────────────────────────────────────────

	# Carbothermic reduction of quartz (all rocky planets).
	{
		"name":        "Silicon Refining",
		"category":    "materials",
		"description": "Carbothermic reduction of quartz sand to metallurgical-grade silicon.",
		"requires":    "metallurgy",
		"inputs":  {"SiO2": 8.0, "Coal": 4.0, "energy": 120.0},
		"outputs": {"Si": 4.0},
	},

	# ── Aluminium ─────────────────────────────────────────────────────────────────

	# Hall–Héroult electrolysis of alumina (all rocky planets).
	{
		"name":        "Aluminium Smelting",
		"category":    "materials",
		"description": "Hall–Héroult electrolysis of alumina to primary aluminium.",
		"requires":    "advanced_alloys",
		"inputs":  {"Al2O3": 12.0, "energy": 200.0},
		"outputs": {"Al": 6.5},
	},

	# ── Magnesium ─────────────────────────────────────────────────────────────────

	# MgO route (Earth / Venus / Mars): Pidgeon-process vacuum reduction.
	# 2MgO + Si → 2Mg + SiO2  (here simplified to pure electrolytic route).
	{
		"name":        "Magnesium Smelting",
		"category":    "materials",
		"description": "Thermal reduction of periclase (MgO) to produce primary magnesium metal.",
		"requires":    "metallurgy",
		"inputs":  {"MgO": 6.0, "energy": 150.0},
		"outputs": {"Mg": 3.5},
	},
	# MgSO4 route (Mars): thermal decomposition of epsomite sulfate evaporites.
	# Abundant in Martian evaporite deposits; lower Mg yield than oxide route.
	{
		"name":        "Magnesium from Sulfate",
		"category":    "materials",
		"description": "Thermal decomposition of Martian epsomite (MgSO₄) to recover magnesium metal.",
		"requires":    "metallurgy",
		"inputs":  {"MgSO4": 8.0, "Coal": 2.0, "energy": 180.0},
		"outputs": {"Mg": 1.5},
	},

	# ── Calcium ───────────────────────────────────────────────────────────────────

	# Intermediate — convert calcite to quicklime (CaO) for use downstream.
	{
		"name":        "Lime Production",
		"category":    "materials",
		"description": "Thermal decomposition of calcite to quicklime (CaO) and CO₂.",
		"requires":    "",
		"inputs":  {"CaCO3": 8.0, "energy": 40.0},
		"outputs": {"CaO": 4.5},
	},
	# Ca metal: electrolytic reduction of molten CaO (Fused-salt electrolysis).
	{
		"name":        "Calcium Electrolysis",
		"category":    "materials",
		"description": "Fused-salt electrolysis of calcium oxide to produce reactive calcium metal.",
		"requires":    "advanced_alloys",
		"inputs":  {"CaO": 5.0, "energy": 120.0},
		"outputs": {"Ca": 3.5},
	},

	# ── Titanium ─────────────────────────────────────────────────────────────────

	# Kroll process (all rocky planets with TiO2 in crust).
	{
		"name":        "Titanium Extraction",
		"category":    "materials",
		"description": "Kroll-process chlorination and magnesiothermic reduction of rutile to sponge titanium.",
		"requires":    "advanced_alloys",
		"inputs":  {"TiO2": 6.0, "Coal": 2.0, "energy": 350.0},
		"outputs": {"Ti": 3.0},
	},

	# ── Sodium ───────────────────────────────────────────────────────────────────

	# Downs process: electrolysis of molten halite (Earth / Mars).
	# 2NaCl → 2Na + Cl₂  at ~600 °C.
	{
		"name":        "Sodium Electrolysis",
		"category":    "materials",
		"description": "Downs-cell electrolysis of molten sodium chloride to produce sodium metal.",
		"requires":    "metallurgy",
		"inputs":  {"NaCl": 6.0, "energy": 80.0},
		"outputs": {"Na": 2.0},
	},
	# Sulfide electrolysis: process Mercury's sodium sulfide ore.
	# Na2S → 2Na + S  (electrolytic, molten-salt bath).
	{
		"name":        "Sodium from Sulfide",
		"category":    "materials",
		"description": "Electrolysis of molten sodium sulfide — the primary sodium ore in Mercury's reducing crust.",
		"requires":    "metallurgy",
		"inputs":  {"Na2S": 5.0, "energy": 100.0},
		"outputs": {"Na": 2.5},
	},

	# ── Potassium ────────────────────────────────────────────────────────────────

	# Electrolytic reduction of K2O (Earth crust — 1.8 % K2O by mass).
	{
		"name":        "Potassium Reduction",
		"category":    "materials",
		"description": "Electrolytic or metalothermic reduction of potassium oxide to produce potassium metal.",
		"requires":    "metallurgy",
		"inputs":  {"K2O": 5.0, "energy": 90.0},
		"outputs": {"K": 4.0},
	},

	# ── Copper ───────────────────────────────────────────────────────────────────

	# Pyrometallurgical smelting of chalcopyrite (Earth).
	{
		"name":        "Copper Smelting",
		"category":    "materials",
		"description": "Roast and smelt chalcopyrite ore through matte smelting and converting to produce blister copper.",
		"requires":    "metallurgy",
		"inputs":  {"CuFeS2": 5.0, "energy": 90.0},
		"outputs": {"Cu": 2.0},
	},

	# ── Refined materials ─────────────────────────────────────────────────────────

	# Phosphate: wet-process digestion of P2O5 ore.
	{
		"name":        "Phosphate Processing",
		"category":    "materials",
		"description": "Acid digestion of phosphate rock into concentrated phosphoric acid.",
		"requires":    "industrial_mechanization",
		"inputs":  {"P2O5": 5.0, "H2O": 3.0, "energy": 20.0},
		"outputs": {"minerals": 3.0},
	},
	# Concrete: Portland-cement clinker kiln.
	{
		"name":        "Concrete Production",
		"category":    "materials",
		"description": "Sinter lime, silica, and alumina into Portland cement clinker, then mix with aggregate to produce structural concrete.",
		"requires":    "",
		"inputs":  {"CaO": 4.0, "SiO2": 5.0, "Al2O3": 1.0, "energy": 50.0},
		"outputs": {"Concrete": 8.0},
	},
	# Glass: soda-lime fusion.
	{
		"name":        "Glass Smelting",
		"category":    "materials",
		"description": "Fuse silica sand, soda ash (Na₂O), and lime at high temperature to produce transparent soda-lime glass.",
		"requires":    "metallurgy",
		"inputs":  {"SiO2": 7.0, "Na2O": 2.0, "CaO": 1.0, "energy": 80.0},
		"outputs": {"Glass": 8.0},
	},
	# Solar Panel Assembly: laminate Si wafers between glass sheets in an Al frame.
	# Mass breakdown per 200 W panel: ~70 % glass, ~25 % silicon, ~5 % aluminium.
	# Outputs accumulate in compound_inventory as "SolarPanel" (grams of finished
	# panel mass).  A Solar Farm building consumes 5 000 g (≈ one 200 W module).
	{
		"name":        "Solar Panel Assembly",
		"category":    "materials",
		"description": "Laminate silicon wafers between toughened glass sheets in an aluminium frame to produce photovoltaic solar panel modules.",
		"requires":    "metallurgy",
		"inputs":  {"Si": 12.0, "Glass": 35.0, "Al": 3.0, "energy": 2_000.0},
		"outputs": {"SolarPanel": 50.0},
	},
	# Plastic: polymerise petroleum fractions into bulk thermoplastic.
	{
		"name":        "Plastic Synthesis",
		"category":    "materials",
		"description": "Crack and polymerise petroleum fractions into bulk thermoplastic resin.",
		"requires":    "industrial_mechanization",
		"inputs":  {"Oil": 6.0, "energy": 60.0},
		"outputs": {"Plastic": 5.0},
	},
	# Graphene: high-temperature chemical-vapour deposition of single-layer carbon.
	{
		"name":        "Graphene Synthesis",
		"category":    "materials",
		"description": "Chemical-vapour deposition of single-layer carbon sheets from a coal-derived carbon feedstock.",
		"requires":    "nanostructured_materials",
		"inputs":  {"Coal": 4.0, "energy": 500.0},
		"outputs": {"Graphene": 1.0},
	},
	# Microchips: photolithographic fabrication on silicon wafers with copper
	# interconnects and plastic packaging — the most energy-intensive recipe.
	{
		"name":        "Microchip Fabrication",
		"category":    "materials",
		"description": "Photolithographic fabrication of integrated circuits on silicon wafers with copper interconnects and plastic packaging.",
		"requires":    "microprocessors",
		"inputs":  {"Si": 5.0, "Cu": 1.0, "Plastic": 1.0, "energy": 1_500.0},
		"outputs": {"Microchip": 2.0},
	},
	# Steel: carburise molten iron with coal to make the primary structural alloy.
	{
		"name":        "Steel Making",
		"category":    "materials",
		"description": "Alloy molten iron with carbon from coal in a basic-oxygen furnace to produce structural steel.",
		"requires":    "metallurgy",
		"inputs":  {"Fe": 8.0, "Coal": 2.0, "energy": 100.0},
		"outputs": {"Steel": 7.0},
	},
	# Ceramic: sinter alumina and silicon into a hard, heat-resistant ceramic.
	{
		"name":        "Ceramic Sintering",
		"category":    "materials",
		"description": "Sinter alumina and silicon carbide into hard, heat- and radiation-resistant technical ceramics.",
		"requires":    "advanced_alloys",
		"inputs":  {"Al2O3": 6.0, "Si": 3.0, "energy": 200.0},
		"outputs": {"Ceramic": 5.0},
	},
	# Carbon composite: weave graphene and plastic into an ultra-strong fibre matrix.
	{
		"name":        "Carbon Composite Layup",
		"category":    "materials",
		"description": "Bind graphene fibre in a polymer matrix to form an ultra-high-strength, lightweight composite — the basis of orbital tethers.",
		"requires":    "nanostructured_materials",
		"inputs":  {"Graphene": 3.0, "Plastic": 4.0, "energy": 300.0},
		"outputs": {"CarbonComposite": 4.0},
	},
	# Battery: sodium-ion cells using a graphene anode — bulk grid energy storage.
	{
		"name":        "Battery Production",
		"category":    "materials",
		"description": "Assemble sodium-ion cells with graphene anodes for grid-scale electrical storage.",
		"requires":    "high_energy_density_power",
		"inputs":  {"Na": 4.0, "Graphene": 2.0, "energy": 150.0},
		"outputs": {"Battery": 3.0},
	},
	# Superconductor: copper-oxide ceramic cuprate for magnets and lossless transmission.
	{
		"name":        "Superconductor Fabrication",
		"category":    "materials",
		"description": "Sinter copper-oxide ceramic into high-temperature superconducting tape for magnets and lossless power transmission.",
		"requires":    "radiation_hardened_systems",
		"inputs":  {"Cu": 2.0, "Ceramic": 2.0, "energy": 400.0},
		"outputs": {"Superconductor": 1.0},
	},
	# Rocket: an assembled launch vehicle — aluminium-alloy airframe, steel engines,
	# and microchip avionics.  A finished good that (with propellant) puts payloads
	# into space.
	{
		"name":        "Rocket Assembly",
		"category":    "materials",
		"description": "Integrate an aluminium-alloy airframe, steel engines, and microchip avionics into a complete launch vehicle.",
		"requires":    "early_rocketry",
		"inputs":  {"Al": 8.0, "Steel": 4.0, "Microchip": 1.0, "energy": 800.0},
		"outputs": {"Rocket": 1.0},
	},
	# Solar collector satellite: a free-flying photovoltaic collector on an aluminium
	# bus with microchip avionics.  Launched to the Sun (Solar Deployment mission) to
	# occupy a slot in the Dyson swarm — the more you build and loft, the larger the
	# swarm and the more power it beams back.
	{
		"name":        "Solar Satellite Assembly",
		"category":    "materials",
		"description": "Integrate photovoltaic collectors, an aluminium spacecraft bus, and microchip avionics into a free-flying solar collector satellite for deployment to a solar-power swarm.",
		"requires":    "space_power_infrastructure",
		"inputs":  {"SolarPanel": 40.0, "Al": 12.0, "Microchip": 1.0, "energy": 1_500.0},
		"outputs": {"SolarSatellite": 1.0},
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
	# Sulphate leaching: dissolve gypsum (CaSO4) to recover CaO feedstock.
	{
		"name":        "Gypsum Processing",
		"category":    "chemicals",
		"description": "Dissolve gypsum ore to recover calcium oxide feedstock.",
		"requires":    "metallurgy",
		"inputs":  {"CaSO4": 6.0, "energy": 35.0},
		"outputs": {"CaO": 2.0},
	},
	# Sulfuric acid: roast pyrite, then hydrate the SO₃ — the industrial workhorse.
	{
		"name":        "Sulfuric Acid Production",
		"category":    "chemicals",
		"description": "Roast pyrite to sulfur trioxide and hydrate it via the contact process to produce concentrated sulfuric acid.",
		"requires":    "industrial_mechanization",
		"inputs":  {"FeS2": 5.0, "H2O": 3.0, "energy": 60.0},
		"outputs": {"H2SO4": 4.0},
	},
	# Ammonia: Haber-Bosch fixation of crustal nitrogen with hydrogen from water.
	{
		"name":        "Ammonia Synthesis",
		"category":    "chemicals",
		"description": "Haber-Bosch fixation of nitrogen and water-derived hydrogen into ammonia for fertiliser and feedstock.",
		"requires":    "industrial_mechanization",
		"inputs":  {"N2": 3.0, "H2O": 4.0, "energy": 120.0},
		"outputs": {"NH3": 4.0},
	},

	# ── Fuels ─────────────────────────────────────────────────────────────────────

	{
		"name":        "Coal Combustion",
		"category":    "fuels",
		"description": "Combustion of coal to generate thermal energy.",
		"requires":    "",
		"inputs":  {"Coal": 10.0},
		"outputs": {"energy": 80.0},
	},
	{
		"name":        "Oil Refining",
		"category":    "fuels",
		"description": "Fractional distillation and combustion of crude oil.",
		"requires":    "industrial_mechanization",
		"inputs":  {"Oil": 8.0},
		"outputs": {"energy": 120.0},
	},
	{
		"name":        "Uranium Enrichment",
		"category":    "fuels",
		"description": "Gas-centrifuge enrichment of uranium hexafluoride to reactor-grade U-235.",
		"requires":    "nuclear_power",
		"inputs":  {"UO2": 5.0, "energy": 200.0},
		"outputs": {"energy": 2000.0},
	},
	{
		"name":        "Thorium Activation",
		"category":    "fuels",
		"description": "Neutron capture converts Th-232 to fissile U-233 in a molten-salt blanket.",
		"requires":    "advanced_reactor_systems",
		"inputs":  {"ThO2": 4.0, "energy": 300.0},
		"outputs": {"energy": 3000.0},
	},
	# Rocket propellant: refine kerosene from oil and combine with liquid oxygen.
	{
		"name":        "Propellant Refining",
		"category":    "fuels",
		"description": "Refine kerosene from crude oil and pair it with liquid oxygen to produce storable launch propellant.",
		"requires":    "early_rocketry",
		"inputs":  {"Oil": 5.0, "O2": 8.0, "energy": 200.0},
		"outputs": {"Propellant": 6.0},
	},
	# Fusion fuel: distil deuterium from heavy water for fusion reactors.
	{
		"name":        "Deuterium Extraction",
		"category":    "fuels",
		"description": "Distil deuterium from heavy water by isotopic separation to fuel fusion reactors.",
		"requires":    "fusion_engineering",
		"inputs":  {"H2O": 20.0, "energy": 800.0},
		"outputs": {"FusionFuel": 1.0},
	},

	# ── Biologics ────────────────────────────────────────────────────────────────

	{
		"name":        "Water Recycling",
		"category":    "biologics",
		"description": "Closed-loop purification of grey-water back to potable quality.",
		"requires":    "space_habitation_systems",
		"inputs":  {"H2O": 8.0, "energy": 15.0},
		"outputs": {"H2O": 7.5},
	},
	{
		"name":        "Fertiliser Synthesis",
		"category":    "biologics",
		"description": "Combine phosphate and lime into concentrated hydroponics fertiliser.",
		"requires":    "synthetic_biology",
		"inputs":  {"P2O5": 3.0, "CaO": 2.0, "H2O": 4.0, "energy": 30.0},
		"outputs": {"minerals": 3.0},
	},
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
