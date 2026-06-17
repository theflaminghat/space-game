class_name PlanetData
extends Node

# ─────────────────────────────────────────────────────────────────────────────
# Planetary physical, orbital, and chemical data
# ─────────────────────────────────────────────────────────────────────────────
#
# All orbital elements are referenced to the J2000.0 epoch
#   (Julian Date 2 451 545.0 = January 1.5, 2000 TT).
#
# Sources:
#   Orbital elements & secular rates — NASA JPL Keplerian Elements for
#     Approximate Planet Positions (Standish 1992 / Table 1)
#     https://ssd.jpl.nasa.gov/planets/approx_pos.html
#   Planet masses & mean radii — NASA Planetary Fact Sheets / IAU 2015
#
#   Elemental composition (bulk mass fractions):
#     Mercury — Morgan & Anders (1980); Nittler et al. (2011) MESSENGER
#     Venus   — Assumed Earth-like bulk (Morgan & Anders 1980)
#     Earth   — McDonough & Sun (1995); Allegre et al. (2001)
#     Mars    — Wänke & Dreibus (1988); Taylor (2013)
#     Jupiter — Guillot & Havel (2011); Atreya et al. (2003)
#     Saturn  — Guillot (2005); Flasar et al. (2005)
#     Uranus  — Nettelmann et al. (2013); Podolak et al. (1995)
#     Neptune — Hubbard et al. (1995); Fortney & Nettelmann (2010)
#
# Dictionary keys per planet
# ──────────────────────────
#   Physical
#     mass_kg           kg        Planet mass
#     radius_km         km        Mean volumetric radius
#
#   Orbital elements at J2000.0
#     semi_major_axis_au  AU      Semi-major axis a
#     eccentricity        –       Orbital eccentricity e
#     inclination_deg     °       Inclination to the ecliptic i
#     lan_deg             °       Longitude of ascending node Ω
#     long_periapsis_deg  °       Longitude of periapsis ω̄  = Ω + ω
#     mean_longitude_deg  °       Mean longitude L₀  (= M₀ + ω̄)
#
#   Secular rates (per Julian century = 36 525 days)
#     da_au_per_cy        AU/cy   ȧ
#     de_per_cy           /cy     ė
#     di_deg_per_cy       °/cy    İ
#     dlan_deg_per_cy     °/cy    Ω̇
#     dlong_peri_deg_per_cy °/cy  ω̄̇   (rate of longitude of periapsis)
#     dmL_deg_per_cy      °/cy    L̇   (mean longitude rate ≈ mean motion)
#
#   Chemical composition
#     composition_g       Dictionary  layer → { compound formula → mass in grams }
#                         Nested two-level dictionary.  Outer key = layer name,
#                         inner key = compound formula, value = mass in grams.
#
#                         Rocky planet layers
#                           "core"       — metallic Fe-Ni alloy + FeS sulfide melt
#                           "mantle"     — bridgmanite (MgSiO3) lower + forsterite
#                                          (Mg2SiO4) upper + oxide phases
#                           "crust"      — silicate / carbonate / sulfate / ice
#                                          surface minerals incl. H₂O, UO₂, ThO₂
#                           "atmosphere" — atmospheric gas inventory by mass
#
#                         Gas giant layers
#                           "core"       — rocky/icy dense inner region (~10–20 M⊕)
#                                          includes UO₂/ThO₂ radiogenic sources
#                           "atmosphere" — H₂ + He fluid + dissolved volatiles
#                                          (metallic inner zone + molecular outer)
#
#                         Ice giant layers
#                           "core"       — rocky silicate + iron (~3–4 M⊕)
#                                          includes UO₂/ThO₂ radiogenic sources
#                           "mantle"     — superionic H₂O + CH₄ + NH₃ ices
#                           "atmosphere" — thin H₂ + He outer gas shell
#
#                         Fissile / fertile materials present in all rocky-body crusts
#                         and gas-/ice-giant rocky cores:
#                           UO₂  (uraninite)   — fissile U-238 / U-235 source
#                           ThO₂ (thorianite)  — fertile Th-232 → U-233 source
#
#                         Compound masses derived from published elemental fractions
#                         via stoichiometric phase assignment (see comments per planet).
#                         Traces (< 0.05 % of layer mass) are omitted.
#
# Derived quantities used at runtime (NOT stored here – computed in planet.gd)
#   Mean anomaly at epoch:  M₀ = L₀ − ω̄
#   Orbital period (days):  T  = 365.25 × a^1.5
#   Mean motion (rad/day):  n  = 2π / T
# ─────────────────────────────────────────────────────────────────────────────

# Days from J2000.0 (Jan 1.5 2000) to the game's starting date (Jan 1, 1945).
# 1945 is BEFORE J2000.0, so this value is negative.
# Leap years in 1945–1999: 1948,52,56,60,64,68,72,76,80,84,88,92,96 → 13
# Regular years: 55 - 13 = 42  → 13×366 + 42×365 = 20 088 days
# J2000.0 is noon on Jan 1 2000, so add 0.5 day: 20 088.5 days ahead of epoch.
const DAYS_J2000_TO_GAME_EPOCH: float = -20088.5

const PLANETS: Dictionary = {

	"mercury": {
		# Physical
		"mass_kg":                  3.3011e23,
		"radius_km":                2439.7,
		# Orbital elements at J2000.0
		"semi_major_axis_au":       0.38709927,
		"eccentricity":             0.20563593,
		"inclination_deg":          7.00497902,
		"lan_deg":                  48.33076593,
		"long_periapsis_deg":       77.45779628,
		"mean_longitude_deg":       252.25032350,
		# Secular rates
		"da_au_per_cy":             0.00000037,
		"de_per_cy":                0.00001906,
		"di_deg_per_cy":           -0.00594749,
		"dlan_deg_per_cy":         -0.12534081,
		"dlong_peri_deg_per_cy":    0.16047689,
		"dmL_deg_per_cy":           149472.67411175,
		# Chemical composition by layer  (total mass: 3.3011e26 g)
		# Mercury is extremely iron-rich and oxygen-depleted (enstatite-chondrite
		# affinity confirmed by MESSENGER).  Core spans ~85 % of the radius; the
		# silicate mantle is only ~400 km thick.  Reduced conditions → Mg and Na
		# form sulfides (niningerite, Na₂S) rather than oxides.
		# Sources: Morgan & Anders (1980); Nittler et al. (2011) MESSENGER.
		"composition_g": {
			# Metallic + sulfide core  (~70 % of planet mass)
			# FeS-rich layer at the core-mantle boundary is highly conductive and
			# probably responsible for Mercury's anomalously large magnetic field.
			"core": {
				"Fe":  1.63e26,  # metallic iron (dominant)
				"Ni":  5.94e24,  # Fe-Ni inner-core alloy
				"FeS": 1.65e25,  # troilite — sulfide melt (core-mantle boundary)
				"MgS": 1.00e25,  # niningerite — reduced Mg sulfide
				"C":   2.00e24,  # graphite — dark carbon layer (MESSENGER albedo)
			},
			# Thin enstatite-pyroxene mantle  (~27 % of planet mass)
			# Predominantly lower-mantle-type enstatite; short radial distance
			# leaves little room for a distinct upper-mantle olivine layer.
			"mantle": {
				"MgSiO3":  6.24e25,  # enstatite — lower mantle dominant phase
				"Mg2SiO4": 2.67e25,  # forsterite — thin upper mantle olivine
				"MgS":     6.50e24,  # niningerite — upper mantle reduced phase
			},
			# Thin surface crust  (~3 % of planet mass)
			"crust": {
				"SiO2":  1.32e25,  # free silica (oxygen-poor surface rock)
				"Al2O3": 6.60e24,  # alumina (MESSENGER high-Al terrain)
				"CaO":   4.00e24,  # lime
				"Na2S":  3.30e24,  # sodium sulfide (MESSENGER surface Na + S)
				"FeS2":  1.50e24,  # pyrite (minor sulfide ore)
				"TiO2":  5.00e23,  # rutile / ilmenite
				"UO2":   3.40e19,  # uraninite — fissile U-238 ore
				"ThO2":  1.14e20,  # thorianite — fertile Th-232 ore
			},
			# Exosphere  (total mass ~1 × 10⁷ g — effectively none)
			# Atoms sputtered from the surface by solar wind; not a true atmosphere.
			# Pressure ~5 × 10⁻¹⁰ Pa at surface.
			"atmosphere": {
				"Na": 5.00e06,  # sodium (dominant exospheric species)
				"O2": 2.00e06,  # molecular oxygen (surface sputtering)
				"H2": 1.00e06,  # hydrogen (solar wind implanted)
				"He": 2.00e05,  # helium (solar wind capture)
			},
		},
	},

	"venus": {
		"mass_kg":                  4.8675e24,
		"radius_km":                6051.8,
		"semi_major_axis_au":       0.72333566,
		"eccentricity":             0.00677672,
		"inclination_deg":          3.39467605,
		"lan_deg":                  76.67984255,
		"long_periapsis_deg":       131.60246718,
		"mean_longitude_deg":       181.97909950,
		"da_au_per_cy":             0.00000390,
		"de_per_cy":               -0.00004107,
		"di_deg_per_cy":           -0.00078890,
		"dlan_deg_per_cy":         -0.27769418,
		"dlong_peri_deg_per_cy":    0.00268329,
		"dmL_deg_per_cy":           58517.81538729,
		# Chemical composition by layer  (total mass: 4.8675e27 g)
		# Earth-like interior inferred from mass/radius similarity (no seismic data).
		# Differentiated into metallic Fe-Ni core + MgSiO3 mantle + basaltic crust.
		# Slightly more reduced than Earth (lower FeO).  No seismological constraints.
		# Source: Morgan & Anders (1980); assumed Earth-like bulk.
		"composition_g": {
			# Metallic + sulfide core  (~32 % of planet mass)
			"core": {
				"Fe":  1.32e27,  # metallic iron
				"Ni":  8.76e25,  # Fe-Ni inner-core alloy
				"FeS": 3.36e26,  # troilite — sulfide melt
			},
			# Silicate mantle  (~66 % of planet mass)
			# Lower: bridgmanite + periclase;  upper: forsterite olivine
			"mantle": {
				"MgSiO3":  1.93e27,  # bridgmanite — lower mantle dominant phase
				"Mg2SiO4": 8.25e26,  # forsterite — upper mantle olivine
				"MgO":     1.67e26,  # periclase
				"FeO":     3.60e25,  # iron(II) oxide — mantle iron fraction
				"CaSiO3":  1.24e26,  # Ca-perovskite / wollastonite
			},
			# Basaltic crust  (~2 % of planet mass)
			# Venera 13/14 + VEGA lander wt% applied to 9.74e25 g target crust mass.
			"crust": {
				"SiO2":  4.58e25,  # silica — 47 % (basaltic surface rock)
				"Al2O3": 1.66e25,  # alumina — 17 % (feldspar-rich basalt)
				"MgO":   1.17e25,  # periclase — 12 % (high-Mg basalt)
				"FeO":   8.77e24,  # wüstite — 9 % (basaltic iron oxide)
				"CaO":   8.77e24,  # lime — 9 % (pyroxene, anorthosite)
				"Na2O":  2.34e24,  # sodium oxide — 2.4 % (plagioclase)
				"TiO2":  1.46e24,  # ilmenite / rutile — 1.5 %
				"UO2":   2.96e20,  # uraninite — fissile U-238 ore
				"ThO2":  1.06e21,  # thorianite — fertile Th-232 ore
			},
			# Dense CO₂ atmosphere  (total mass ~4.8 × 10²³ g)
			# Surface pressure ~92 bar; second-most massive planetary atmosphere
			# in the solar system.  H₂SO₄ clouds at 45–70 km altitude.
			"atmosphere": {
				"CO2":  4.63e23,  # carbon dioxide (96.5 % — runaway greenhouse)
				"N2":   1.68e22,  # nitrogen (3.5 %)
				"SO2":  7.20e19,  # sulfur dioxide (volcanic outgassing)
				"Ar":   3.36e19,  # argon
				"CO":   8.16e18,  # carbon monoxide
				"H2SO4":2.00e17,  # sulfuric acid (cloud droplets, 45–70 km)
				"HCl":  2.40e18,  # hydrogen chloride (volcanic)
			},
		},
	},

	"earth": {
		"mass_kg":                  5.9722e24,
		"radius_km":                6371.0,
		"semi_major_axis_au":       1.00000018,
		"eccentricity":             0.01671022,
		"inclination_deg":          0.00005,
		"lan_deg":                 -5.11260389,
		"long_periapsis_deg":       102.93768193,
		"mean_longitude_deg":       100.46457166,
		"da_au_per_cy":            -0.00000003,
		"de_per_cy":               -0.00003804,
		"di_deg_per_cy":           -0.01294668,
		"dlan_deg_per_cy":         -0.24123353,
		"dlong_peri_deg_per_cy":    0.32327364,
		"dmL_deg_per_cy":           35999.37244981,
		# Chemical composition by layer  (total mass: 5.9722e27 g)
		# Best-constrained planet (seismic + geochemical + sample-return data).
		# Inner core: solid Fe-Ni; outer core: liquid Fe + FeS melt (dynamo source).
		# Lower mantle: bridgmanite (MgSiO3) + periclase (MgO) at 25–135 GPa.
		# Upper mantle: forsterite olivine (Mg2SiO4) + enstatite at 0–25 GPa.
		# Crust: continental (felsic, ~60 % SiO2) + oceanic (mafic basalt).
		# Sources: McDonough & Sun (1995); Allegre et al. (2001).
		"composition_g": {
			# Metallic + sulfide core  (~32 % of planet mass)
			# Inner core solid Fe-Ni (~1220 km radius); outer core liquid Fe+FeS.
			"core": {
				"Fe":  1.30e27,  # metallic iron (inner + outer core)
				"Ni":  1.08e26,  # nickel (Fe-Ni inner core alloy, ~5 wt %)
				"FeS": 4.76e26,  # troilite — sulfide melt (outer core + CMB)
			},
			# Silicate mantle  (~67 % of planet mass)
			# Lower mantle (660–2900 km): bridgmanite + ferropericlase.
			# Upper mantle (0–660 km): olivine + pyroxene assemblage.
			"mantle": {
				"MgSiO3":  2.27e27,  # bridgmanite — dominant lower mantle phase
				"Mg2SiO4": 9.70e26,  # forsterite / olivine — upper mantle
				"MgO":     6.67e25,  # periclase (ferropericlase in lower mantle)
				"FeO":     4.05e26,  # wüstite — mantle iron oxide
				"CaSiO3":  1.53e26,  # Ca-perovskite (lower) / wollastonite (upper)
				"Cr2O3":   2.62e25,  # chromia (spinel, chromite)
				"MnO":     7.71e24,  # manganosite
				"TiO2":    1.00e24,  # ilmenite / rutile (mantle trace)
			},
			# Continental + oceanic crust  (~0.5 % of planet mass)
			# Rudnick & Gao (2003) wt% applied to 2.99e25 g target crust mass.
			# Includes the global ocean (1.335 × 10²⁴ g H₂O) as a surface layer.
			"crust": {
				"SiO2":  1.70e25,  # quartz / feldspar — 60.6 % of crust
				"Al2O3": 4.46e24,  # alumina — 15.9 % (feldspar, garnet, corundum)
				"Fe2O3": 1.88e24,  # hematite — 6.7 % (oxidised crustal iron)
				"MgO":   1.32e24,  # periclase — 4.7 % (mafic minerals, basalt)
				"CaO":   1.80e24,  # lime — 6.4 % (rest of Ca; bulk in mantle CaSiO3)
				"Na2O":  8.61e23,  # soda — 3.1 % (plagioclase feldspar)
				"K2O":   5.08e23,  # potassium oxide — 1.8 % (K-feldspar, granite)
				"TiO2":  2.02e23,  # ilmenite / rutile — 0.7 % (black sand, ore)
				"CaCO3": 3.60e23,  # calcite / limestone (sedimentary carbonate)
				"FeS2":  2.50e23,  # pyrite (fool's gold — common ore mineral)
				"H2O":   1.43e24,  # water (ocean 1.335e24 g + polar ice 9.5e22 g)
				"NaCl":  4.70e22,  # halite (dissolved ocean salt)
				"P2O5":  3.65e22,  # phosphorus pentoxide — 0.13 % (apatite)
				"UO2":   7.40e19,  # uraninite — fissile U-238 ore (~2.7 ppm crust)
				"ThO2":  2.62e20,  # thorianite — fertile Th-232 ore (~9.6 ppm crust)
				"Coal":    1.50e22,  # organic carbon in sedimentary rock (~3 ppm crust)
				"Oil":     3.00e18,  # petroleum + natural gas hydrocarbon inventory
				"CuFeS2":  5.90e21,  # chalcopyrite — primary copper ore (~68 ppm Cu)
				"N2":      6.00e20,  # fixed nitrogen in micas/feldspars (~20 ppm crust)
			},
			# Atmosphere  (total mass ~5.15 × 10²¹ g; surface pressure 1 bar)
			# Uniquely O₂-rich due to photosynthetic life; CO₂ sequestered in rock.
			"atmosphere": {
				"N2":  3.89e21,  # nitrogen (78.08 % by volume)
				"O2":  1.19e21,  # oxygen (20.95 % — biogenic)
				"Ar":  6.59e19,  # argon (0.93 %)
				"H2O": 1.30e19,  # water vapour (variable ~0.4 % avg)
				"CO2": 3.14e18,  # carbon dioxide (0.042 % — greenhouse gas)
				"CH4": 5.30e15,  # methane (1.9 ppm — biogenic + wetlands)
				"N2O": 5.00e14,  # nitrous oxide (0.3 ppm — biogenic)
			},
		},
	},

	"mars": {
		"mass_kg":                  6.4171e23,
		"radius_km":                3389.5,
		"semi_major_axis_au":       1.52371034,
		"eccentricity":             0.09339410,
		"inclination_deg":          1.84969142,
		"lan_deg":                  49.55953891,
		"long_periapsis_deg":      -23.94362959,
		"mean_longitude_deg":       -4.55343205,
		"da_au_per_cy":             0.00001847,
		"de_per_cy":                0.00007882,
		"di_deg_per_cy":           -0.00813131,
		"dlan_deg_per_cy":         -0.29257343,
		"dlong_peri_deg_per_cy":    0.44441088,
		"dmL_deg_per_cy":           19140.30268499,
		# Chemical composition by layer  (total mass: 6.4171e26 g)
		# More oxidised than Earth: higher O/Fe, smaller metallic core (~15 % radius).
		# FeO-rich mantle; Fe₂O₃ hematite + sulfate evaporites dominate the thick crust.
		# Notable FeS in core from S-enriched inner solar-system accretion region.
		# Sources: Wänke & Dreibus (1988); Taylor (2013); InSight seismology (2021).
		"composition_g": {
			# Small metallic + sulfide core  (~18 % of planet mass, ~1 800 km radius)
			# InSight confirmed a surprisingly large, possibly liquid core.
			"core": {
				"Fe":  3.00e25,  # metallic iron
				"Ni":  1.93e24,  # Fe-Ni alloy
				"FeS": 4.24e25,  # troilite — S-enriched core (liquid, InSight data)
			},
			# FeO-rich silicate mantle  (~74 % of planet mass)
			"mantle": {
				"MgSiO3":  2.68e26,  # enstatite — lower mantle silicate
				"Mg2SiO4": 1.15e26,  # forsterite / olivine — upper mantle
				"FeO":     9.09e25,  # iron(II) oxide — high FeO mantle
				"CaSiO3":  1.93e25,  # wollastonite / Ca-perovskite
			},
			# Thick oxidised basaltic crust  (~8 % of planet mass, ~50 km avg)
			# No plate tectonics — the oldest crust is preserved at the surface.
			# Mars Odyssey GRS (Taylor et al. 2006) wt% applied to 5.13e25 g target.
			"crust": {
				"SiO2":  2.33e25,  # quartz / volcanic glass — 45.4 %
				"Fe2O3": 9.34e24,  # hematite — 18.2 % (red dust and bedrock)
				"MgO":   4.67e24,  # periclase — 9.1 % (mafic basalt)
				"Al2O3": 5.28e24,  # alumina — 10.3 % (feldspar)
				"CaO":   3.13e24,  # lime — 6.1 %
				"Na2O":  1.23e24,  # sodium oxide — 2.4 % (plagioclase)
				"CaSO4": 1.54e24,  # gypsum / anhydrite — 3.0 % (Opportunity, Curiosity)
				"MgSO4": 5.13e23,  # epsomite — 1.0 % (evaporite deposits)
				"H2O":   5.00e22,  # water ice (polar caps + subsurface permafrost)
				"NaCl":  1.00e23,  # halite — 0.2 % (chloride deposits, Gale Crater)
				"UO2":   2.09e19,  # uraninite (~0.36 ppm U — Mars Odyssey GRS)
				"ThO2":  5.22e19,  # thorianite (~0.9 ppm Th — Mars Odyssey GRS)
			},
			# Thin CO₂ atmosphere  (total mass ~2.5 × 10¹⁹ g; surface pressure ~6 mbar)
			# CO₂ condenses at the winter poles, cycling ~25 % of the atmosphere
			# seasonally.  Perchlorates (ClO₄⁻) are present at ~0.5 wt % in the soil.
			"atmosphere": {
				"CO2": 2.38e19,  # carbon dioxide (95.3 %)
				"N2":  6.50e17,  # nitrogen (2.6 %)
				"Ar":  4.75e17,  # argon (1.9 % — ⁴⁰Ar from K decay, isotope marker)
				"O2":  3.25e16,  # oxygen (0.13 % — photolytic)
				"CO":  1.75e16,  # carbon monoxide (0.07 %)
			},
		},
	},

	"jupiter": {
		"mass_kg":                  1.8982e27,
		"radius_km":                69911.0,
		"semi_major_axis_au":       5.20288700,
		"eccentricity":             0.04838624,
		"inclination_deg":          1.30439695,
		"lan_deg":                  100.47390909,
		"long_periapsis_deg":       14.72847983,
		"mean_longitude_deg":       34.39644051,
		"da_au_per_cy":            -0.00011607,
		"de_per_cy":               -0.00013253,
		"di_deg_per_cy":           -0.00183714,
		"dlan_deg_per_cy":          0.20469106,
		"dlong_peri_deg_per_cy":    0.21252668,
		"dmL_deg_per_cy":           3034.74612775,
		# Chemical composition by layer  (total mass: 1.8982e30 g)
		# Gas giant: ~98 % H₂ + He by mass.  Two-layer model:
		#   Core      — rocky + icy dense inner region (~10 M⊕), radius ~0.15 R_J.
		#               Possibly a diffuse "fuzzy core" extending to ~0.5 R_J (Juno).
		#   Atmosphere— metallic H₂ (inner) merging into molecular H₂/He (outer);
		#               NH₃ ice cloud deck at ~0.7 bar; NH₄SH clouds at ~2 bar;
		#               H₂O clouds deep at ~5 bar.  Photochemistry produces C₂H₂.
		# Sources: Guillot & Havel (2011); Atreya et al. (2003); Juno (2016–2023).
		"composition_g": {
			# Rocky + icy core  (~10 Earth masses, ~0.3 % of Jupiter mass)
			# Contains chondritic radiogenic heat sources.
			"core": {
				"Fe":   1.33e27,  # iron
				"SiO2": 2.85e27,  # silica
				"MgO":  1.90e27,  # magnesia
				"UO2":  5.40e20,  # uraninite — radiogenic heating source
				"ThO2": 2.04e21,  # thorianite — radiogenic heating source
			},
			# H₂/He fluid + atmosphere  (metallic + molecular layers, ~99.7 % of mass)
			# Metallic H₂ inner zone (>1 Mbar) transitions continuously to
			# molecular envelope; no sharp phase boundary.
			"atmosphere": {
				"H2":  1.39e30,  # molecular hydrogen (dominant; metallic at depth)
				"He":  4.56e29,  # helium (depleted in outer layers — rains inward)
				"H2O": 1.64e28,  # water (deep clouds ~5 bar; icy planetesimals)
				"CH4": 1.29e28,  # methane (all carbon)
				"H2S": 3.23e27,  # hydrogen sulfide
				"NH3": 3.23e27,  # ammonia (visible cloud deck at ~0.7 bar)
				"Ne":  2.09e27,  # neon (depleted in atmosphere — dissolves in He)
				"PH3": 1.90e25,  # phosphine (~6 ppm; upwelled from deep interior)
				"CO":  1.90e24,  # carbon monoxide (deep thermochemistry)
				"C2H2":3.80e21,  # acetylene (UV photolysis of CH₄, stratosphere)
			},
		},
	},

	"saturn": {
		"mass_kg":                  5.6834e26,
		"radius_km":                58232.0,
		"semi_major_axis_au":       9.53667594,
		"eccentricity":             0.05386179,
		"inclination_deg":          2.48599187,
		"lan_deg":                  113.66242448,
		"long_periapsis_deg":       92.59887831,
		"mean_longitude_deg":       49.95424423,
		"da_au_per_cy":            -0.00125060,
		"de_per_cy":               -0.00050991,
		"di_deg_per_cy":            0.00193609,
		"dlan_deg_per_cy":         -0.28867794,
		"dlong_peri_deg_per_cy":   -0.41897216,
		"dmL_deg_per_cy":           1222.49362201,
		# Chemical composition by layer  (total mass: 5.6834e29 g)
		# Gas giant: lower He fraction than Jupiter; heavier-element enrichment ~3×.
		# Two-layer model: rocky/icy core ~20 M⊕ + H₂/He fluid atmosphere.
		# Ring system is mostly H₂O ice + silicate dust (not included in bulk mass).
		# Sources: Guillot (2005); Flasar et al. (2005); Cassini CIRS.
		"composition_g": {
			# Rocky + icy core  (~20 Earth masses, ~3.4 % of Saturn mass)
			"core": {
				"Fe":   2.27e26,  # iron
				"SiO2": 6.09e26,  # silica
				"MgO":  2.85e26,  # magnesia
				"UO2":  1.08e21,  # uraninite — radiogenic heating source
				"ThO2": 4.07e21,  # thorianite — radiogenic heating source
			},
			# H₂/He fluid + atmosphere  (metallic + molecular layers, ~96.6 % of mass)
			# Metallic H₂ zone thinner than Jupiter's; rapid rotation creates
			# strong zonal winds (up to 500 m/s).
			"atmosphere": {
				"H2":  4.28e29,  # molecular hydrogen (dominant)
				"He":  1.22e29,  # helium
				"H2O": 6.03e27,  # water (deep clouds)
				"CH4": 5.39e27,  # methane
				"H2S": 1.33e27,  # hydrogen sulfide
				"NH3": 1.31e27,  # ammonia (visible cloud deck)
				"Ne":  3.98e26,  # neon
				"PH3": 2.84e24,  # phosphine (~5 ppm; Cassini CIRS detection)
				"C2H6":1.14e21,  # ethane (UV photolysis product, stratosphere)
				"CO":  5.68e20,  # carbon monoxide (trace deep thermochemistry)
			},
		},
	},

	"uranus": {
		"mass_kg":                  8.6810e25,
		"radius_km":                25362.0,
		"semi_major_axis_au":       19.18916464,
		"eccentricity":             0.04725744,
		"inclination_deg":          0.77263783,
		"lan_deg":                  74.01692503,
		"long_periapsis_deg":       170.95427630,
		"mean_longitude_deg":       313.23810451,
		"da_au_per_cy":            -0.00196176,
		"de_per_cy":               -0.00004397,
		"di_deg_per_cy":           -0.00242939,
		"dlan_deg_per_cy":          0.04240589,
		"dlong_peri_deg_per_cy":    0.40805281,
		"dmL_deg_per_cy":           428.48202785,
		# Chemical composition by layer  (total mass: 8.6810e28 g)
		# Ice giant: three-layer structure.
		#   Core      — rocky silicate + iron inner region (~3.7 M⊕, ~20 % of mass).
		#   Mantle    — superionic / ionic fluid of H₂O, CH₄, NH₃ (~60 % of mass);
		#               electrically conducting; drives the tilted magnetic field.
		#   Atmosphere— thin outer H₂ + He gas shell (~20 % of mass);
		#               CH₄ absorbs red light → blue-green colour.
		# Sources: Nettelmann et al. (2013); Podolak et al. (1995).
		"composition_g": {
			# Rocky + partially oxidised iron core  (~20 % of planet mass)
			"core": {
				"Fe":   3.78e27,  # metallic iron
				"FeO":  4.85e27,  # iron(II) oxide (partially oxidised)
				"SiO2": 1.26e28,  # silica
				"MgO":  7.38e27,  # magnesia
				"UO2":  2.01e20,  # uraninite — radiogenic heat (no internal heat excess)
				"ThO2": 7.55e20,  # thorianite — radiogenic heat source
			},
			# Superionic "ice" mantle  (~60 % of planet mass)
			# Ionic fluid at 10–100 GPa: H₂O protons conduct electricity.
			# Carbonic and ammoniacal phases also present at these pressures.
			"mantle": {
				"H2O": 2.54e28,  # water — dominant superionic phase
				"CH4": 1.61e28,  # methane (may decompose to diamond at depth)
				"NH3": 4.84e27,  # ammonia
			},
			# H₂/He outer atmosphere  (~20 % of planet mass)
			# Upper troposphere: CH₄ ice clouds at ~1.3 bar;
			# H₂S ice clouds at ~3–6 bar (green-tinted, not H₂O).
			"atmosphere": {
				"H2":  4.61e27,  # molecular hydrogen
				"He":  4.95e27,  # helium
				"H2S": 1.30e27,  # hydrogen sulfide (H₂S ice clouds)
				"Ne":  8.68e26,  # neon
				"CO":  2.60e24,  # carbon monoxide (external infall + photochemistry)
				"C2H6":8.68e22,  # ethane (UV photolysis of CH₄)
			},
		},
	},

	"neptune": {
		"mass_kg":                  1.0243e26,
		"radius_km":                24622.0,
		"semi_major_axis_au":       30.06992276,
		"eccentricity":             0.00859048,
		"inclination_deg":          1.77004347,
		"lan_deg":                  131.78422574,
		"long_periapsis_deg":       44.96476227,
		"mean_longitude_deg":      -55.12002969,
		"da_au_per_cy":             0.00026291,
		"de_per_cy":                0.00005105,
		"di_deg_per_cy":            0.00035372,
		"dlan_deg_per_cy":         -0.00508664,
		"dlong_peri_deg_per_cy":   -0.32241464,
		"dmL_deg_per_cy":           218.45945325,
		# Chemical composition by layer  (total mass: 1.0243e29 g)
		# Ice giant: heavier-element enriched vs. Uranus; strong internal heat flux
		# (~2.6 W/m² vs. Uranus' near-zero excess — origin debated).
		# Same three-layer structure; core ~4 M⊕; mantle proportionally thicker.
		# CO and N₂ detected at higher abundances than Uranus (cometary enrichment).
		# Sources: Hubbard et al. (1995); Fortney & Nettelmann (2010); Voyager 2.
		"composition_g": {
			# Rocky + partially oxidised iron core  (~20 % of planet mass)
			"core": {
				"Fe":   3.28e27,  # metallic iron
				"FeO":  6.32e27,  # iron(II) oxide (more oxidised than Uranus core)
				"SiO2": 1.43e28,  # silica
				"MgO":  8.53e27,  # magnesia
				"UO2":  2.17e20,  # uraninite — radiogenic heat (contributes to excess)
				"ThO2": 8.16e20,  # thorianite — radiogenic heat source
			},
			# Superionic "ice" mantle  (~62 % of planet mass)
			# Richer in heavy molecules than Uranus; strong convection drives
			# heat flux and the complex multipolar magnetic field.
			"mantle": {
				"H2O": 3.23e28,  # water — dominant superionic phase
				"CH4": 1.84e28,  # methane (diamond precipitation possible at depth)
				"NH3": 5.84e27,  # ammonia
			},
			# H₂/He outer atmosphere  (~18 % of planet mass)
			# Triton-captured nitrogen inventory contributes trace N₂.
			# Vivid blue colour from CH₄ absorption of red light.
			"atmosphere": {
				"H2":  4.68e27,  # molecular hydrogen
				"He":  5.63e27,  # helium
				"H2S": 1.64e27,  # hydrogen sulfide (H₂S ice clouds)
				"Ne":  1.02e27,  # neon
				"Ar":  5.12e26,  # argon
				"N2":  1.02e25,  # nitrogen (cometary origin; Triton source)
				"CO":  1.02e23,  # carbon monoxide (higher abundance than Uranus)
			},
		},
	},
}
