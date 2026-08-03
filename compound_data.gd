class_name CompoundData
## Shared reference data for materials: display names, category buckets, and category
## presentation (order / labels / colours).  Used by the planet Info tab (crust composition
## names) and the Inventory tab (categorised stockpile listing) so there's one source of truth.

## Formula → human-readable name.
const NAMES: Dictionary = {
	# ── Ores / raw minerals ───────────────────────────────────────────────────
	"SiO2":    "Silicon Dioxide",
	"Al2O3":   "Aluminium Oxide",
	"Fe2O3":   "Hematite",
	"MgO":     "Periclase",
	"CaO":     "Calcium Oxide",
	"Na2O":    "Sodium Oxide",
	"K2O":     "Potassium Oxide",
	"TiO2":    "Titanium Dioxide",
	"CaCO3":   "Calcite",
	"FeS2":    "Pyrite",
	"FeO":     "Wüstite",
	"CuFeS2":  "Chalcopyrite",
	"Na2S":    "Sodium Sulfide",
	"H2O":     "Water",
	"NaCl":    "Halite",
	"P2O5":    "Phosphorus Pentoxide",
	"UO2":     "Uraninite",
	"ThO2":    "Thorianite",
	"Coal":    "Coal",
	"Oil":     "Petroleum",
	"CaSO4":   "Gypsum",
	"MgSO4":   "Epsomite",
	"N2":      "Nitrogen",
	"O2":      "Oxygen",
	"CO2":     "Carbon Dioxide",
	"Ni":      "Nickel",
	"FeS":     "Troilite",
	"MgS":     "Niningerite",
	"MgSiO3":  "Enstatite",
	"Mg2SiO4": "Forsterite",
	"CaSiO3":  "Wollastonite",
	"C":       "Carbon",
	# ── Refined metals ────────────────────────────────────────────────────────
	"Fe":      "Iron",
	"Si":      "Silicon",
	"Al":      "Aluminium",
	"Ti":      "Titanium",
	"Mg":      "Magnesium",
	"Ca":      "Calcium",
	"Na":      "Sodium",
	"K":       "Potassium",
	"Cu":      "Copper",
	"Steel":   "Steel",
	# ── Chemicals / components ────────────────────────────────────────────────
	"H2SO4":           "Sulfuric Acid",
	"NH3":             "Ammonia",
	"Plastic":         "Plastic",
	"Graphene":        "Graphene",
	"Ceramic":         "Ceramic",
	"CarbonComposite": "Carbon Composite",
	# ── Manufactured goods ────────────────────────────────────────────────────
	"Concrete":      "Concrete",
	"Glass":         "Glass",
	"SolarPanel":    "Solar Panel",
	"SolarSatellite":"Solar Satellite",
	"Microchip":     "Microchip",
	"Battery":       "Battery",
	"Superconductor":"Superconductor",
	"Propellant":    "Rocket Propellant",
	"FusionFuel":    "Fusion Fuel",
	"Rocket":        "Rocket",
	"H2":            "Hydrogen",
	"Aerogel":       "Aerogel",
	"CarbonNanotube":"Carbon Nanotube",
	"Metamaterial":  "Metamaterial",
	"SelfHealingComposite": "Self-Healing Composite",
	"QuantumProcessor":     "Quantum Processor",
	"Antimatter":    "Antimatter",
	"Missile":       "Relativistic Missile",
	"Berserker":     "Berserker Seed",
}

## Formula → category bucket (anything not listed defaults to "raw").
const CATEGORIES: Dictionary = {
	# Raw ores and crustal compounds
	"Coal":    "raw",  "Oil":     "raw",
	"SiO2":   "raw",  "Al2O3":  "raw",  "Fe2O3":  "raw",  "MgO":    "raw",
	"CaO":    "raw",  "Na2O":   "raw",  "K2O":    "raw",  "TiO2":   "raw",
	"CaCO3":  "raw",  "FeS2":   "raw",  "H2O":    "raw",  "NaCl":   "raw",
	"P2O5":   "raw",  "UO2":    "raw",  "ThO2":   "raw",
	"CuFeS2": "raw",  "Na2S":   "raw",  "C":      "raw",  "FeO":    "raw",
	"CaSO4":  "raw",  "MgSO4":  "raw",  "N2":     "raw",
	"Ni":     "raw",  "FeS":    "raw",  "MgS":    "raw",
	# Refined metals (outputs of smelting / electrolysis recipes)
	"Fe":     "refined",
	"Si":     "refined",
	"Al":     "refined",
	"Ti":     "refined",
	"Mg":     "refined",
	"Ca":     "refined",
	"Na":     "refined",
	"K":      "refined",
	"Cu":     "refined",
	"Steel":  "refined",   # primary structural alloy
	"O2":     "refined",   # electrolytic oxygen — useful industrial gas
	"H2":     "refined",
	# Processed feedstock components
	"Plastic":         "components",
	"Graphene":        "components",
	"Ceramic":         "components",
	"CarbonComposite": "components",
	"H2SO4":           "components",   # industrial chemical feedstock
	"NH3":             "components",
	# Manufactured goods (assembled from refined inputs)
	"Concrete":      "manufactured",
	"Glass":         "manufactured",
	"SolarPanel":    "manufactured",
	"SolarSatellite":"manufactured",
	"Microchip":     "manufactured",
	"Battery":       "manufactured",
	"Superconductor":"manufactured",
	"Propellant":    "manufactured",
	"FusionFuel":    "manufactured",
	"Rocket":        "manufactured",
	"Aerogel":       "manufactured",
	"CarbonNanotube":"manufactured",
	"Metamaterial":  "manufactured",
	"SelfHealingComposite": "manufactured",
	"QuantumProcessor":     "manufactured",
	"Antimatter":    "manufactured",
	"Missile":       "manufactured",
	"Berserker":     "manufactured",
}

const CATEGORY_ORDER: Array[String] = ["raw", "refined", "components", "manufactured"]

const CATEGORY_LABELS: Dictionary = {
	"raw":          "Raw Materials",
	"refined":      "Refined Materials",
	"components":   "Components",
	"manufactured": "Manufactured Goods",
}

const CATEGORY_COLORS: Dictionary = {
	"raw":          Color(0.80, 0.70, 0.50),
	"refined":      Color(0.50, 0.80, 0.65),
	"components":   Color(0.50, 0.70, 1.00),
	"manufactured": Color(0.85, 0.55, 0.90),
}
