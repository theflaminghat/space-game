class_name RecipeData

## Manufacturing recipes: convert input resources/chemicals into outputs.
##
## Keys per recipe:
##   name        – display name
##   category    – "metals" | "materials" | "electronics" | "aerospace"
##                  | "chemicals" | "fuels" | "biologics"
##                  (groups the recipe in the Production panel's category dropdown)
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
	# ── Agriculture ──────────────────────────────────────────────────
	# What a Farm actually grows is chosen HERE, not by the building: one Farm is arable
	# capacity, and these recipes decide what that capacity is turned into.  "work" is set
	# explicitly rather than derived from inputs, because what limits a field is land and
	# season, not the tonnage of water pumped onto it.
	#
	# Water figures are NET irrigation draw — the share that has to be supplied rather than
	# fallen out of the sky — which is why they are small next to a crop's real thirst.
	#
	# ENERGY IS IN WATT-DAYS, NOT SI JOULES — one unit is 86 400 real joules (see units.gd).
	# So 0.030 here is 2 592 real J per gram of wheat, which is industrial cereal's true cost
	# of 2-4 GJ per tonne.  Writing the SI figure directly asked for 6 000x the planet's entire
	# output and starved everyone; divide real joules by 86 400 before putting them here.
	#
	# Grain holds ~14 000 real J/g of food energy, so a field returns roughly five joules for
	# each one spent — farming with machines, not a free lunch.  The whole slate comes to ~7 %
	# of the energy budget, which is what agriculture costs an industrial society.
	#
	# The gap between a field and a lamp is the reason living off Earth is hard.  Photosynthesis
	# runs at 1-2 %, so a gram of biomass needs on the order of a MILLION real joules of light.
	# On a planet with a sky the Sun donates it; under LEDs you buy it, which is why Algae
	# Culture costs 200x what wheat does.
	{
		"name":        "Wheat Cultivation",
		"category":    "agriculture",
		"description": "Sow, irrigate and harvest cereal grain — the cheapest calories per unit of land ever found.",
		"requires":    "",
		"work":        1.0,
		"inputs":  {"H2O": 0.02, "energy": 0.030},
		"outputs": {"Wheat": 1.0},
	},
	{
		"name":        "Rice Cultivation",
		"category":    "agriculture",
		"description": "Flooded-paddy cultivation. Feeds more people per hectare than any other grain, and drinks accordingly.",
		"requires":    "",
		"work":        1.0,
		"inputs":  {"H2O": 0.06, "energy": 0.048},
		"outputs": {"Rice": 1.0},
	},
	{
		"name":        "Vegetable Cultivation",
		"category":    "agriculture",
		"description": "Mixed truck farming — more edible mass off the same ground than grain, and none of it keeps.",
		"requires":    "",
		"work":        0.8,
		"inputs":  {"H2O": 0.04, "energy": 0.018},
		"outputs": {"Vegetables": 1.0},
	},
	{
		"name":        "Algae Culture",
		"category":    "agriculture",
		"description": "Photobioreactor cultivation of edible algae — the only crop that needs neither soil nor season.",
		"requires":    "",
		"work":        1.2,
		"inputs":  {"H2O": 0.03, "CO2": 0.02, "energy": 6.0},
		"outputs": {"Algae": 1.0},
	},

	# ── Livestock ────────────────────────────────────────────────────
	# A Ranch is pens, pasture and handling — which animal stands in it is chosen here.  Every
	# one of them is a converter that runs at a loss: you are spending grain you could have
	# eaten to get back a smaller mass of something else.  The feed ratios are the real ones,
	# and they are the whole decision — poultry returns a gram for every two spent, cattle
	# wants ten.
	{
		"name":        "Poultry Farming",
		"category":    "livestock",
		"description": "Broiler flocks. The most efficient animal ever domesticated: roughly two grams of feed per gram of meat.",
		"requires":    "",
		"work":        2.0,
		"inputs":  {"Wheat": 2.0, "H2O": 0.12, "energy": 0.096},
		"outputs": {"Chicken": 1.0},
	},
	{
		"name":        "Aquaculture",
		"category":    "livestock",
		"description": "Netted pens and raceways. Fish are cold-blooded and weightless in water, so almost nothing is spent holding them up.",
		"requires":    "",
		"work":        1.5,
		"inputs":  {"Wheat": 1.5, "H2O": 0.20, "energy": 0.072},
		"outputs": {"Fish": 1.0},
	},
	{
		"name":        "Swine Husbandry",
		"category":    "livestock",
		"description": "Pig lots. Four grams of feed per gram of pork — twice a bird's cost, half a steer's.",
		"requires":    "",
		"work":        4.0,
		"inputs":  {"Wheat": 4.0, "H2O": 0.25, "energy": 0.120},
		"outputs": {"Pork": 1.0},
	},
	{
		"name":        "Cattle Raising",
		"category":    "livestock",
		"description": "Beef herds. Ten grams of grain walked through an animal to yield one — the most expensive food a civilisation can choose to make.",
		"requires":    "",
		"work":        10.0,
		"inputs":  {"Wheat": 10.0, "H2O": 0.50, "energy": 0.180},
		"outputs": {"Beef": 1.0},
	},

	# ── Iron ─────────────────────────────────────────────────────────────────────

	# Hematite route (Earth / Mars): blast-furnace reduction of Fe2O3 with coke.
	{
		"name":        "Iron Smelting",
		"category":    "metals",
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
		"category":    "metals",
		"description": "Roast pyrite to iron oxide, then carbothermically reduce to metallic iron.",
		"requires":    "",
		"inputs":  {"FeS2": 8.0, "Coal": 2.0, "energy": 60.0},
		"outputs": {"Fe": 3.5},
	},
	# Wüstite route (Venus): direct carbothermic reduction of iron(II) oxide.
	# Venus crust carries ~9 % FeO by mass — an abundant, easily reduced feedstock.
	{
		"name":        "Wüstite Reduction",
		"category":    "metals",
		"description": "Carbothermic reduction of wüstite (FeO) — the dominant iron ore in Venus' basaltic crust.",
		"requires":    "metallurgy",
		"inputs":  {"FeO": 8.0, "Coal": 1.5, "energy": 40.0},
		"outputs": {"Fe": 6.0},
	},

	# ── Silicon ───────────────────────────────────────────────────────────────────

	# Carbothermic reduction of quartz (all rocky planets).
	{
		"name":        "Silicon Refining",
		"category":    "metals",
		"description": "Carbothermic reduction of quartz sand to metallurgical-grade silicon.",
		"requires":    "",
		"inputs":  {"SiO2": 8.0, "Coal": 4.0, "energy": 120.0},
		"outputs": {"Si": 4.0},
	},

	# ── Aluminium ─────────────────────────────────────────────────────────────────

	# Hall–Héroult electrolysis of alumina (all rocky planets).
	{
		"name":        "Aluminium Smelting",
		"category":    "metals",
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
		"category":    "metals",
		"description": "Thermal reduction of periclase (MgO) to produce primary magnesium metal.",
		"requires":    "metallurgy",
		"inputs":  {"MgO": 6.0, "energy": 150.0},
		"outputs": {"Mg": 3.5},
	},
	# MgSO4 route (Mars): thermal decomposition of epsomite sulfate evaporites.
	# Abundant in Martian evaporite deposits; lower Mg yield than oxide route.
	{
		"name":        "Magnesium from Sulfate",
		"category":    "metals",
		"description": "Thermal decomposition of Martian epsomite (MgSO₄) to recover magnesium metal.",
		"requires":    "metallurgy",
		"inputs":  {"MgSO4": 8.0, "Coal": 2.0, "energy": 180.0},
		"outputs": {"Mg": 1.5},
	},

	# ── Calcium ───────────────────────────────────────────────────────────────────

	# Intermediate — convert calcite to quicklime (CaO) for use downstream.
	{
		"name":        "Lime Production",
		"category":    "chemicals",
		"description": "Thermal decomposition of calcite to quicklime (CaO) and CO₂.",
		"requires":    "",
		"inputs":  {"CaCO3": 8.0, "energy": 40.0},
		"outputs": {"CaO": 4.5},
	},
	# Ca metal: electrolytic reduction of molten CaO (Fused-salt electrolysis).
	{
		"name":        "Calcium Electrolysis",
		"category":    "metals",
		"description": "Fused-salt electrolysis of calcium oxide to produce reactive calcium metal.",
		"requires":    "advanced_alloys",
		"inputs":  {"CaO": 5.0, "energy": 120.0},
		"outputs": {"Ca": 3.5},
	},

	# ── Titanium ─────────────────────────────────────────────────────────────────

	# Kroll process (all rocky planets with TiO2 in crust).
	{
		"name":        "Titanium Extraction",
		"category":    "metals",
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
		"category":    "metals",
		"description": "Downs-cell electrolysis of molten sodium chloride to produce sodium metal.",
		"requires":    "metallurgy",
		"inputs":  {"NaCl": 6.0, "energy": 80.0},
		"outputs": {"Na": 2.0},
	},
	# Sulfide electrolysis: process Mercury's sodium sulfide ore.
	# Na2S → 2Na + S  (electrolytic, molten-salt bath).
	{
		"name":        "Sodium from Sulfide",
		"category":    "metals",
		"description": "Electrolysis of molten sodium sulfide — the primary sodium ore in Mercury's reducing crust.",
		"requires":    "metallurgy",
		"inputs":  {"Na2S": 5.0, "energy": 100.0},
		"outputs": {"Na": 2.5},
	},

	# ── Potassium ────────────────────────────────────────────────────────────────

	# Electrolytic reduction of K2O (Earth crust — 1.8 % K2O by mass).
	{
		"name":        "Potassium Reduction",
		"category":    "metals",
		"description": "Electrolytic or metalothermic reduction of potassium oxide to produce potassium metal.",
		"requires":    "metallurgy",
		"inputs":  {"K2O": 5.0, "energy": 90.0},
		"outputs": {"K": 4.0},
	},

	# ── Copper ───────────────────────────────────────────────────────────────────

	# Pyrometallurgical smelting of chalcopyrite (Earth).
	{
		"name":        "Copper Smelting",
		"category":    "metals",
		"description": "Roast and smelt chalcopyrite ore through matte smelting and converting to produce blister copper.",
		"requires":    "",
		"inputs":  {"CuFeS2": 5.0, "energy": 90.0},
		"outputs": {"Cu": 2.0},
	},

	# ── Refined materials ─────────────────────────────────────────────────────────

	# Phosphate: wet-process digestion of P2O5 ore.
	{
		"name":        "Phosphate Processing",
		"category":    "chemicals",
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
		"category":    "electronics",
		"description": "Laminate silicon wafers between toughened glass sheets in an aluminium frame to produce photovoltaic solar panel modules.",
		"requires":    "metallurgy",
		"inputs":  {"Si": 12.0, "Glass": 35.0, "Al": 3.0, "energy": 2_000.0},
		"outputs": {"SolarPanel": 50.0},
	},
	# Plastic: polymerise petroleum fractions into bulk thermoplastic.
	{
		"name":        "Plastic Synthesis",
		"category":    "materials",
		"description": "Steam-crack and polymerise naphtha into bulk thermoplastic resin.",
		"requires":    "industrial_mechanization",
		"inputs":  {"Naphtha": 6.0, "energy": 60.0},
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
		"category":    "electronics",
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
		"requires":    "",
		"inputs":  {"Fe": 8.0, "Coal": 2.0, "energy": 100.0},
		"outputs": {"Steel": 7.0},
	},
	# Ceramic: sinter alumina and silicon into a hard, heat-resistant ceramic.
	{
		"name":        "Ceramic Sintering",
		"category":    "materials",
		"description": "Sinter alumina and silicon carbide into hard, heat- and radiation-resistant technical ceramics.",
		"requires":    "",
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
		"category":    "electronics",
		"description": "Assemble sodium-ion cells with graphene anodes for grid-scale electrical storage.",
		"requires":    "high_energy_density_power",
		"inputs":  {"Na": 4.0, "Graphene": 2.0, "energy": 150.0},
		"outputs": {"Battery": 3.0},
	},
	# Superconductor: copper-oxide ceramic cuprate for magnets and lossless transmission.
	{
		"name":        "Superconductor Fabrication",
		"category":    "electronics",
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
		"category":    "aerospace",
		"description": "Integrate an aluminium-alloy airframe, steel engines, and microchip avionics into a complete launch vehicle.",
		"requires":    "early_rocketry",
		"inputs":  {"Al": 8.0, "Steel": 4.0, "Microchip": 1.0, "energy": 800.0},
		"outputs": {"Rocket": 1.0},
	},

	# Industrial Robot — an actuated frame with enough onboard processing to work unsupervised.
	# It does not appear in any bill of materials: what it consumes is the LABOUR SHORTAGE.
	# A civilisation's manufacturing is capped by how much of its built capacity its people can
	# actually staff (see Game._mc_staffing), and every robot is another pair of hands that does
	# not need feeding, sleeping or housing — which is the only way industry keeps growing once
	# population stops.
	{
		"name":        "Robot Assembly",
		"category":    "electronics",
		"description": "Assemble an actuated industrial frame — servos, structure and onboard processing — able to work a shift without a person in it.",
		"requires":    "industrial_robotics",
		"inputs":  {"Steel": 6.0, "Al": 3.0, "Microchip": 0.8, "Cu": 1.2, "energy": 1_400.0},
		"outputs": {"Robot": 1.0},
	},
	# Solar collector satellite: a free-flying photovoltaic collector on an aluminium
	# bus with microchip avionics.  Launched to the Sun (Solar Deployment mission) to
	# occupy a slot in the Dyson swarm — the more you build and loft, the larger the
	# swarm and the more power it beams back.
	{
		"name":        "Solar Satellite Assembly",
		"category":    "aerospace",
		"description": "Integrate photovoltaic collectors, an aluminium spacecraft bus, and microchip avionics into a free-flying solar collector satellite for deployment to a solar-power swarm.",
		"requires":    "space_power_infrastructure",
		"inputs":  {"SolarPanel": 40.0, "Al": 12.0, "Microchip": 1.0, "energy": 1_500.0},
		"outputs": {"SolarSatellite": 1.0},
	},
	# Relativistic kinetic missile: a dense penetrator, superconducting shielding, and
	# microchip guidance.  Crafted here, then fired at a star system from the star map.
	{
		"name":        "Relativistic Missile Assembly",
		"category":    "aerospace",
		"description": "Integrate a dense kinetic penetrator, superconducting magnetic shielding, and microchip guidance into a relativistic kinetic missile.",
		"requires":    "relativistic_navigation",
		"inputs":  {"Steel": 200.0, "Superconductor": 4.0, "Microchip": 2.0, "energy": 5_000.0},
		"outputs": {"Missile": 1.0},
	},
	# Von Neumann berserker seed: a self-replicating industrial probe that consumes a target
	# system on arrival.  Crafted here, then launched at a star system from the star map.
	{
		"name":        "Berserker Assembly",
		"category":    "aerospace",
		"description": "Integrate a self-replicating industrial core, microchip control, and superconducting systems into a von Neumann berserker seed.",
		"requires":    "self_replicating_industry",
		"inputs":  {"Steel": 60.0, "Superconductor": 6.0, "Microchip": 4.0, "energy": 4_000.0},
		"outputs": {"Berserker": 1.0},
	},

	# von Neumann Probe — a colony seed that builds copies of itself out of whatever it finds.
	# One probe reaching one star becomes two probes leaving it, which is why a single launch
	# eventually reaches everything: the fleet is not something you build, it is something you
	# start.  That is also the danger, and why it needs Self-Replicating Industry to make.
	{
		"name":        "von Neumann Probe Assembly",
		"category":    "aerospace",
		"description": "Integrate a self-replicating colony seed: fabricators, a mining head, avionics and a starship, able to rebuild all of it from raw asteroid.",
		"requires":    "self_replicating_industry",
		"inputs":  {"Al": 1_200.0, "Steel": 800.0, "Microchip": 240.0, "Superconductor": 120.0,
			"SelfHealingComposite": 60.0, "energy": 9_000.0},
		"outputs": {"VNProbe": 1.0},
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
		"name":        "Oil Refining",
		"category":    "fuels",
		"description": "Fractional distillation of crude oil. The still splits the barrel into heavy fuel oil for power generation, naphtha for the petrochemical industry, and kerosene for aviation and rocketry. Nothing is burned here — this is where crude becomes usable.",
		"requires":    "",
		# Mass balance mirrors a real barrel: ~45 % heavy fuel oil, ~35 % naphtha, ~10 % kerosene,
		# with the last ~10 % leaving as refinery gas, coke and residue.
		"inputs":  {"Oil": 10.0, "energy": 45.0},
		"outputs": {"FuelOil": 4.5, "Naphtha": 3.5, "Kerosene": 1.0},
	},
	{
		"name":        "Uranium Enrichment",
		"category":    "fuels",
		"description": "Gas-centrifuge enrichment of uranium hexafluoride to reactor-grade fuel. Natural uranium is only 0.72 % U-235; a cascade concentrates it to about 4 %, which is what a reactor core actually runs on. No power is generated here — this is what a Nuclear Plant burns.",
		"requires":    "nuclear_power",
		# ~8 kg of natural uranium per kg of 4 % enriched product (0.25 % tails), and the
		# cascade is enormously energy-hungry — far more per gram than any other refining step.
		"inputs":  {"UO2": 8.0, "energy": 900.0},
		"outputs": {"EnrichedU": 1.0},
	},
	{
		"name":        "Thorium Activation",
		"category":    "fuels",
		"description": "Neutron capture in a molten-salt blanket converts fertile Th-232 into fissile U-233, which is chemically separated and loaded as reactor fuel. Thorium is 3.5× more abundant than uranium and needs no isotope separation, so this route yields far more fuel per gram of ore for a fraction of the energy — but only once the reactor technology exists to breed it.",
		"requires":    "advanced_reactor_systems",
		# 6:1 feed after breeding and reprocessing losses, at ~250 J per gram of product —
		# well under the 900 J/g the uranium centrifuge cascade demands, because no isotope
		# separation is involved.  The bred U-233 is uranium, so it fuels the same reactors.
		"inputs":  {"ThO2": 6.0, "energy": 1500.0},
		"outputs": {"EnrichedU": 1.0},
	},
	# Rocket propellant: refine kerosene from oil and combine with liquid oxygen.
	{
		"name":        "Propellant Refining",
		"category":    "fuels",
		"description": "Refine kerosene from crude oil and pair it with liquid oxygen to produce storable launch propellant.",
		"requires":    "early_rocketry",
		"inputs":  {"Kerosene": 5.0, "O2": 8.0, "energy": 200.0},
		"outputs": {"Propellant": 6.0},
	},
	# NOTE: there is no recipe for fusion fuel.  Helium-3 cannot be manufactured — it is mined,
	# from lunar regolith where the solar wind implanted it, or condensed out of a gas giant's
	# envelope.  Reaching it is the point; that is what fusion propulsion actually costs.

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

	# ── Advanced craftables ───────────────────────────────────────────────────────
	# Each is built from existing crafted goods (all inputs are mineable or already
	# producible), and gated on a deep-tech research node, giving several otherwise
	# unused late-tree nodes a payload.

	# Hydrogen — the other half of water electrolysis; a feedstock and propellant, and
	# the input to antimatter synthesis.
	{
		"name":        "Hydrogen Electrolysis",
		"category":    "chemicals",
		"description": "Electrolyse water to recover hydrogen gas — a clean feedstock and propellant.",
		"requires":    "",
		"inputs":  {"H2O": 10.0, "energy": 70.0},
		"outputs": {"H2": 6.0},
	},
	# Aerogel — ultralight silica solid for insulation and habitat shielding.
	{
		"name":        "Aerogel Synthesis",
		"category":    "materials",
		"description": "Supercritically dry a silica gel into aerogel — a near-weightless, near-transparent insulator for habitats and cryogenics.",
		"requires":    "nanostructured_materials",
		"inputs":  {"SiO2": 6.0, "energy": 300.0},
		"outputs": {"Aerogel": 3.0},
	},
	# Carbon nanotube — the strongest tether material; the proper basis for elevators
	# and megastructures.
	{
		"name":        "Carbon Nanotube Spinning",
		"category":    "materials",
		"description": "Spin single-walled carbon nanotubes from graphene feedstock — stronger and lighter than any composite.",
		"requires":    "molecular_manufacturing",
		"inputs":  {"Graphene": 4.0, "energy": 800.0},
		"outputs": {"CarbonNanotube": 2.0},
	},
	# Metamaterial — engineered electromagnetic response: radiation shielding and
	# low-observability skins (going quiet in the dark forest).
	{
		"name":        "Metamaterial Fabrication",
		"category":    "materials",
		"description": "Pattern sub-wavelength structures into a ceramic-metal matrix to steer electromagnetic radiation around what it shields.",
		"requires":    "field_stabilized_materials",
		"inputs":  {"Ceramic": 4.0, "Cu": 2.0, "Si": 2.0, "energy": 600.0},
		"outputs": {"Metamaterial": 2.0},
	},
	# Self-healing composite — structures that reseal damage, keeping megastructures
	# intact under bombardment.
	{
		"name":        "Self-Healing Composite Layup",
		"category":    "materials",
		"description": "Embed microvascular healing agents in a carbon-composite matrix so structural damage seals itself.",
		"requires":    "self_healing_megastructures",
		"inputs":  {"CarbonComposite": 3.0, "Plastic": 3.0, "energy": 500.0},
		"outputs": {"SelfHealingComposite": 2.0},
	},
	# Quantum processor — superconducting qubit arrays; computation beyond classical chips.
	{
		"name":        "Quantum Processor Fabrication",
		"category":    "electronics",
		"description": "Fabricate superconducting qubit arrays in a cryogenic substrate for quantum computation far beyond any classical chip.",
		"requires":    "quantum_computing",
		"inputs":  {"Microchip": 3.0, "Superconductor": 2.0, "energy": 3_000.0},
		"outputs": {"QuantumProcessor": 1.0},
	},
	# Antimatter — the densest fuel possible, at a staggering energy cost; fuels the
	# highest-acceleration relativistic drives.
	{
		"name":        "Antimatter Synthesis",
		"category":    "fuels",
		"description": "Forge and magnetically bottle antiprotons — the most energy-dense fuel there is, made at enormous power cost.",
		"requires":    "antimatter_handling",
		"inputs":  {"H2": 4.0, "energy": 50_000.0},
		"outputs": {"Antimatter": 0.5},
	},
]

## Normalisation factor that makes a rate of 1× mean ONE UNIT of primary output per game-day:
## one gram for a recipe that yields matter, or one Joule for the fuel recipes that yield only
## energy.  The stoichiometric ratios in the table are preserved — every input and output is
## simply scaled together — so "3× Iron Smelting" reads directly as 3 g of iron per day.
## "Work" one unit of rate demands from a world's capacity pool — the currency both the
## Production panel and the simulation throttle against.  An explicit "work" key wins (used by
## agriculture, where land and season set the limit rather than tonnage); otherwise it is the
## mass of everything non-energy that has to be handled.
##
## Lives here rather than in Game.gd so the panel showing the number and the simulation
## enforcing it cannot drift apart.
static func work(recipe: Dictionary) -> float:
	if recipe.has("work"):
		return maxf(1.0, float(recipe["work"]))
	var w: float = 0.0
	var inputs: Dictionary = recipe.get("inputs", {})
	for key: String in inputs:
		if key == "energy" or key == "science":
			continue
		w += float(inputs[key])
	return maxf(1.0, w)

## Work per unit of the panel's normalised rate (1x = 1 g of product/day).
static func work_per_rate(recipe: Dictionary) -> float:
	return scale(recipe) * work(recipe)

static func scale(recipe: Dictionary) -> float:
	var outputs: Dictionary = recipe.get("outputs", {})
	var mass: float = 0.0
	for key: String in outputs:
		if key == "energy" or key == "science":
			continue
		mass += float(outputs[key])
	if mass > 0.0:
		return 1.0 / mass
	# Energy-only recipes (coal/oil combustion, enrichment): 1× = 1 Joule per day.
	var e: float = float(outputs.get("energy", 0.0))
	return 1.0 / e if e > 0.0 else 1.0

## Returns all recipes that are unlocked given a set of completed research node ids.
static func available(completed_research: Dictionary) -> Array:
	var result: Array = []
	for r in RECIPES:
		var req: String = r.get("requires", "")
		if req == "" or completed_research.get(req, false):
			result.append(r)
	return result
