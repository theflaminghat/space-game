extends RefCounted
class_name EvolutionTreeData

## upkeep: continuous per-individual resource drain (per second).
##
##   Chemical keys are compound formulas that match planet_data.gd / compound_inventory.
##   All rates are per individual per second.  The game multiplies by total population
##   of each lineage to get the civilisation-wide drain.
##
##   Biological needs calibrated to a 2 000 kcal/day adult:
##     H2O  ─ ~2 500 mL/day ≈ 2.9e-2 g/s         water
##     C    ─ carbohydrate/fat carbon ≈ 1.7e-4 g/s as refined carbon substrate
##     O2   ─ resting metabolism ≈ 250 mL/min at 1.4 g/L ≈ 5.8e-3 g/s
##     NaCl ─ dietary sodium ~2 g/day ≈ 2.3e-5 g/s
##     CaO  ─ calcium requirement ~1 g/day (bones, signalling) ≈ 1.2e-5 g/s
##     P2O5 ─ phosphorus (ATP, DNA, bones) ~1.5 g/day ≈ 1.7e-5 g/s
##     energy (Watts) ─ metabolic heat + habitat infrastructure power draw
##
##   Off-world / mechanical upkeep adds:
##     Fe   ─ structural wear, moving parts, steel mass loss
##     SiO2 ─ semiconductor substrate, optical glass, insulation (digital/cyber)
##     Al2O3─ radiation shielding, hull insulation, thermal tiles
##
##   compute (FLOP/s): total cognitive output of the lineage per individual.
##     Biological brains ≈ 1e17 FLOP/s (rough neocortex estimate).
##     Cybernetic/digital variants retain the same floor with augmentation headroom.
##
## Calibration note:
##   Mine        → 50 g/s minerals    supports ~10 baseline humans (total mineral weight)
##   Solar Farm  → 200 W              powers ~2.5 baseline humans
##   Fusion Reactor → 80 000 W        powers the energy needs of ~1 000 baseline humans

static func build() -> Dictionary:
	return {
		# ── Root ─────────────────────────────────────────────────────────────────
		# Unmodified 20th–21st century humans on a planetary surface with breathable
		# atmosphere and biosphere food chain.  Infrastructure overhead is minimal:
		# basic electrical grid (~80 W/person), water treatment, waste recycling.
		"homo_sapiens": {
			"name": "Homo sapiens",
			"subtitle": "Baseline humans",
			"description": "Unmodified planetary humans living within a natural biosphere.",
			"parents": [],
			"pos": Vector2(80, 260),
			"upkeep": {
				"H2O":   2.9e-2,   # drinking + sanitation water
				"O2":    5.8e-3,   # resting respiratory oxygen
				"C":     1.7e-4,   # dietary carbon (carbohydrate / fat substrate)
				"NaCl":  2.3e-5,   # dietary sodium chloride
				"CaO":   1.2e-5,   # calcium (bone and cellular signalling)
				"P2O5":  1.7e-5,   # phosphorus (ATP, DNA, bone mineral)
				"energy": 80.0,    # grid electricity + heating per person
			},
			"compute": 1.0e17,     # ~10^17 FLOP/s (neocortex equivalent)
		},

		# ── Tier 1 ───────────────────────────────────────────────────────────────

		# Orbital populations in closed-loop ECLSS habitats.  All O₂ is
		# electrolytically regenerated from H₂O; water is fully recycled.
		# Food is delivered from Earth or hydroponically grown.  Station power
		# draw per person ≈ 2.5 kW (ISS reference), amortised at ~150 W/person.
		# Structural Al₂O₃ tiles and radiation shielding add mineral wear.
		"homo_sapiens_orbitalis": {
			"name": "H. sapiens orbitalis",
			"subtitle": "Orbital population",
			"description": "Humans adapted culturally and medically to orbital habitats — reliant on closed-loop life support.",
			"parents": ["homo_sapiens"],
			"pos": Vector2(340, 140),
			"upkeep": {
				"H2O":    3.5e-2,   # higher loss due to EVA suit cooling and electrolysis
				"O2":     5.8e-3,   # same metabolic rate; regenerated in-station
				"C":      2.0e-4,   # slightly higher: limited hydroponics, packaged food
				"NaCl":   2.3e-5,
				"CaO":    1.4e-5,   # increased calcium loss in microgravity
				"P2O5":   1.7e-5,
				"Al2O3":  8.0e-6,   # radiation-shielding tile abrasion + hull wear
				"energy": 150.0,    # ECLSS, lighting, thermal control, comms
			},
			"compute": 1.0e17,
		},

		# Mars colonists benefit from partial ISRU (water ice mining, CO₂→O₂
		# via Sabatier/MOXIE), reducing water and oxygen import costs.  Dome
		# pressurisation and electric heating in the −60 °C mean surface
		# temperature raise power demand; UV / radiation shielding needs Fe panels.
		"homo_sapiens_martis": {
			"name": "H. sapiens martis",
			"subtitle": "Mars branch",
			"description": "Early permanently-established Martian populations living in pressurised domes with ISRU support.",
			"parents": ["homo_sapiens"],
			"pos": Vector2(340, 260),
			"upkeep": {
				"H2O":    1.8e-2,   # partially sourced from subsurface ice
				"O2":     3.0e-3,   # partially produced by MOXIE-class ISRU
				"C":      1.9e-4,   # greenhouses supplement packaged food
				"NaCl":   2.3e-5,
				"CaO":    1.2e-5,
				"P2O5":   1.7e-5,
				"Fe":     5.0e-6,   # structural iron for dome frameworks and rad panels
				"energy": 120.0,    # dome heating, lighting, ISRU plant power
			},
			"compute": 1.0e17,
		},

		# High-gravity industrial worlds (super-Earth, Jovian moons).  Denser
		# musculoskeletal loading raises caloric needs; thick atmospheres may ease
		# radiation shielding but pressurisation of habitats costs more energy.
		# Structural steel wear from heavy-industry operations is significant.
		"homo_sapiens_gravitus": {
			"name": "H. sapiens gravitus",
			"subtitle": "High-g branch",
			"description": "Humans adapted for high-gravity industrial worlds through selective pressure and pharmaceutical support.",
			"parents": ["homo_sapiens"],
			"pos": Vector2(340, 380),
			"upkeep": {
				"H2O":    3.2e-2,   # higher metabolic water loss (exertion)
				"O2":     7.5e-3,   # higher O₂ consumption under load
				"C":      2.4e-4,   # higher caloric load (muscle maintenance)
				"NaCl":   3.0e-5,   # elevated electrolyte loss through sweat
				"CaO":    2.0e-5,   # musculoskeletal calcium demand
				"P2O5":   2.2e-5,
				"Fe":     8.0e-6,   # heavy-industry infrastructure wear
				"energy": 110.0,    # habitat pressurisation + industrial lighting
			},
			"compute": 1.0e17,
		},

		# ── Tier 2 ───────────────────────────────────────────────────────────────

		# Fully space-native species — no planetary biosphere backup.  Closed-loop
		# life support is near-perfect but relies entirely on processed feedstocks.
		# Long-term micro-G adaptation has reshaped bone density and circulatory
		# system; pharmaceutical metabolic regulators are permanently integrated.
		"homo_astralis": {
			"name": "Homo astralis",
			"subtitle": "Space-adapted species",
			"description": "A distinctly space-adapted descendant lineage — born and living entirely in orbital and deep-space habitats.",
			"parents": ["homo_sapiens_orbitalis"],
			"pos": Vector2(620, 140),
			"upkeep": {
				"H2O":    4.0e-2,   # entirely processed; higher recycling losses
				"O2":     5.0e-3,   # electrolytic; efficient but non-zero
				"C":      1.5e-4,   # vat-grown protein + algae base diet
				"NaCl":   2.0e-5,
				"CaO":    2.0e-5,   # pharmacological bone density maintenance
				"P2O5":   1.8e-5,
				"Al2O3":  1.5e-5,   # hull and module wear at interstellar speeds
				"SiO2":   5.0e-6,   # optical and electronic component replacement
				"energy": 250.0,    # full ECLSS + spin-gravity drive + comms
			},
			"compute": 1.0e17,
		},

		# Engineered for aquatic worlds: gills for dissolved-O₂ extraction,
		# reinforced sinuses for pressure, bioluminescent signalling.  Ocean
		# biospheres locally provide food and oxygen (lower chemical imports),
		# but thermoregulation in cold deep water requires metabolic energy.
		"homo_pelagicus": {
			"name": "Homo pelagicus",
			"subtitle": "Oceanic branch",
			"description": "Engineered humans adapted for aquatic or ocean-world colonisation — with gill-augmented respiration and pressure-resistant physiology.",
			"parents": ["homo_sapiens_martis"],
			"pos": Vector2(620, 260),
			"upkeep": {
				"H2O":    0.0,      # immersed in environment; ambient supply
				"O2":     2.0e-3,   # partial gill extraction; less O₂ infrastructure
				"C":      1.2e-4,   # local aquatic food chain supplement
				"NaCl":   1.0e-5,   # salt filtered from seawater
				"CaO":    1.3e-5,
				"P2O5":   1.5e-5,
				"energy": 130.0,    # thermoregulation + bioluminescence + depth suits
			},
			"compute": 1.0e17,
		},

		# Biological core (brain + viscera) still requires full nutrition; limb
		# replacement with myoelectric prosthetics adds ~200 W per person; neural
		# lace and internal sensors add another ~200 W.  SiO₂ for chip substrates;
		# Fe for mechanical joint and exo-musculature wear.
		"homo_cyberneticus": {
			"name": "Homo cyberneticus",
			"subtitle": "Cybernetic lineage",
			"description": "Humans with pervasive neural and bodily augmentation — part biological, part machine.",
			"parents": ["homo_sapiens_orbitalis", "homo_sapiens_gravitus"],
			"pos": Vector2(620, 380),
			"upkeep": {
				"H2O":    2.5e-2,   # biological core still requires full hydration
				"O2":     5.8e-3,
				"C":      1.6e-4,   # biological food intake unchanged
				"NaCl":   2.3e-5,
				"CaO":    1.2e-5,
				"P2O5":   1.7e-5,
				"Fe":     3.0e-5,   # exo-musculature joint wear (steel alloy)
				"SiO2":   1.5e-5,   # neural-lace chip substrate replacement
				"energy": 600.0,    # metabolic + neural lace + exo-musculature + sensors
			},
			"compute": 1.0e17,
		},

		# ── Tier 3 ───────────────────────────────────────────────────────────────

		# Post-biological: no biological body.  Hardware wear and coolant cycling
		# consume SiO₂ (chip substrate) and Al₂O₃ (thermal tiles, ICs).  Server
		# infrastructure runs at ~2 kW/mind (equivalent to a small GPU cluster).
		# Trace iron for chassis and magnetic storage components.
		"homo_digitalis": {
			"name": "Homo digitalis",
			"subtitle": "Uploaded minds",
			"description": "A digital post-biological lineage — human-derived minds running on distributed computational substrates.",
			"parents": ["homo_cyberneticus"],
			"pos": Vector2(900, 320),
			"upkeep": {
				"H2O":    5.0e-4,   # server coolant loop losses
				"SiO2":   8.0e-5,   # chip substrate replacement (IC fabrication)
				"Al2O3":  3.0e-5,   # ceramic IC packaging + thermal tiles
				"Fe":     1.0e-5,   # chassis / magnetic storage components
				"energy": 2000.0,   # ~2 kW per substrate node (GPU-cluster equivalent)
			},
			"compute": 1.0e17,
		},

		# ── Tier 4 ───────────────────────────────────────────────────────────────

		# A single distributed unit spans multiple stellar platforms.  Material
		# throughput for self-replication and repair dominates: Fe for structural
		# frames, SiO₂ for optical-computing substrates, Al₂O₃ for radiation-
		# hard ceramic shielding, and MgO for refractory structural alloys.
		# Onboard fusion supplies ~20 kW; peak compute vastly exceeds biological limits.
		"homo_mechanicus_galacticus": {
			"name": "H. mechanicus galacticus",
			"subtitle": "Galactic machine civilization",
			"description": "Machine-descended civilization distributed across galactic scales — each unit a self-replicating, fusion-powered node.",
			"parents": ["homo_digitalis"],
			"pos": Vector2(1180, 320),
			"upkeep": {
				"SiO2":   5.0e-3,   # optical compute substrates + solar panel glass
				"Fe":     4.0e-3,   # structural frames, magnetic confinement coils
				"Al2O3":  2.0e-3,   # radiation-hard shielding + ceramic heat exchangers
				"MgO":    1.0e-3,   # refractory alloy for fusion chamber lining
				"TiO2":   5.0e-4,   # corrosion-resistant hull coating
				"energy": 20000.0,  # onboard fusion drive + computation + replication
			},
			"compute": 1.0e17,
		},
	}
